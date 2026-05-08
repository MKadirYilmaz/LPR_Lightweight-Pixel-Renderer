using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Experimental.Rendering;

public class LprDefaultDeferredRF : ScriptableRendererFeature
{
    [System.Serializable]
    public class LprSettings
    {
        [Tooltip("Opaque Decoder Post Process Material")]
        public Material opaquePostProcessMaterial;
        
        [Tooltip("Global Post Process Material")]
        public Material globalPostProcessMaterial;
        
        [Tooltip("Skybox Material")]
        public Material skyboxMaterial;
        
        [Range(5f, 100f), Tooltip("Target DPI")]
        public float DPI = 40f;
    }

    public LprSettings settings = new LprSettings();

    private LprOpaquePass mOpaquePass;
    private LprOpaquePostProcessPass mOpaquePostProcessPass;
    private LprSkyboxPass mSkyboxPass;
    private LprTransparencyPass mTransparencyPass;
    private LprBlitPass mBlitPass;
    

    private class LprPassData : ContextItem
    {
        public TextureHandle ColorTarget;
        public TextureHandle GBuffer0Target;
        public TextureHandle DepthTarget;

        public override void Reset()
        {
            ColorTarget = TextureHandle.nullHandle;
            DepthTarget = TextureHandle.nullHandle;
            GBuffer0Target = TextureHandle.nullHandle;
        }
    }

    public override void Create()
    {
        if (settings.opaquePostProcessMaterial == null || 
            settings.globalPostProcessMaterial == null ||
            settings.skyboxMaterial == null) return;

        mOpaquePass = new LprOpaquePass(settings.DPI);
        mOpaquePostProcessPass = new LprOpaquePostProcessPass(settings.opaquePostProcessMaterial);
        mSkyboxPass = new LprSkyboxPass(settings.skyboxMaterial);
        mTransparencyPass = new LprTransparencyPass();
        mBlitPass = new LprBlitPass(settings.globalPostProcessMaterial);

    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.opaquePostProcessMaterial == null || 
            settings.globalPostProcessMaterial == null ||
            settings.skyboxMaterial == null) return;

        renderer.EnqueuePass(mOpaquePass);
        renderer.EnqueuePass(mOpaquePostProcessPass);
        renderer.EnqueuePass(mSkyboxPass);
        renderer.EnqueuePass(mTransparencyPass);
        renderer.EnqueuePass(mBlitPass);
    }

    // Stage 1: Render opaque objects to a uint buffer with a custom shader pass
    class LprOpaquePass : ScriptableRenderPass
    {
        private float mTargetDpi;
        private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRDeferred");

        public LprOpaquePass(float targetDpi)
        {
            mTargetDpi = targetDpi;
            renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
        }

        private class OpaquePassData
        {
            public RendererListHandle RendererList;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();

            float dpi = Screen.dpi;
            if (dpi <= 0) dpi = 96;

            Vector2 physicalSize = new Vector2(Screen.width / dpi, Screen.height / dpi);
            
            int width  = Mathf.RoundToInt(physicalSize.x * mTargetDpi);
            int height = Mathf.RoundToInt(physicalSize.y * mTargetDpi);

            TextureDesc uintDesc = new TextureDesc(width, height)
            {
                colorFormat = GraphicsFormat.R8G8B8A8_UNorm,
                depthBufferBits = DepthBits.None,
                msaaSamples = MSAASamples.None,
                name = "LPR_ColorBuffer",
                clearBuffer = true,
                clearColor = Color.black
            };
            TextureDesc gBuffer0Desc = new TextureDesc(width, height)
            {
                colorFormat = GraphicsFormat.R8G8B8A8_UNorm,
                depthBufferBits = DepthBits.None,
                msaaSamples = MSAASamples.None,
                name = "LPR_GBuffer0_Normal",
                clearBuffer = true,
                clearColor = Color.black
            };
            
            TextureDesc hardwareDepthDesc = new TextureDesc(width, height)
            {
                colorFormat = GraphicsFormat.None,
                depthBufferBits = DepthBits.Depth16,
                msaaSamples = MSAASamples.None,
                name = "LPR_HardwareDepth",
                clearBuffer = true
            };

            TextureHandle uintTexture = renderGraph.CreateTexture(uintDesc);
            TextureHandle gBuffer0Texture = renderGraph.CreateTexture(gBuffer0Desc);
            TextureHandle hardwareDepthTexture = renderGraph.CreateTexture(hardwareDepthDesc);

            LprPassData lprData = frameData.GetOrCreate<LprPassData>();
            lprData.ColorTarget = uintTexture;
            lprData.DepthTarget = hardwareDepthTexture;
            lprData.GBuffer0Target = gBuffer0Texture;
            
            // Set up drawing and filtering settings to render only opaque objects with our custom shader pass
            SortingSettings sortingSettings = new SortingSettings(cameraData.camera)
            {
                criteria = cameraData.defaultOpaqueSortFlags
            };
            DrawingSettings drawingSettings = new DrawingSettings(SShaderTagId, sortingSettings)
            {
                enableInstancing = true,
                enableDynamicBatching = true
            };
            
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque, cameraData.camera.cullingMask);

            RendererListParams listParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);
            RendererListHandle rendererList = renderGraph.CreateRendererList(listParams);

            using (var builder = renderGraph.AddRasterRenderPass<OpaquePassData>("LPR Opaque Pass", out var passData))
            {
                passData.RendererList = rendererList;
                builder.UseRendererList(rendererList);
                
                builder.SetRenderAttachment(uintTexture, 0);
                builder.SetRenderAttachment(gBuffer0Texture, 1);
                // Unfortunately we can't create more gBuffer texture because of mobile hardware limitations,
                // so we need to bind the hardware depth buffer as a render attachment to be able to sample it in the post-process pass
                
                
                builder.SetRenderAttachmentDepth(hardwareDepthTexture);

                builder.SetRenderFunc((OpaquePassData data, RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(data.RendererList);
                });
            }
        }
    }

    // Stage 2: Blit the uint buffer to the camera's color target using a post-process material that decodes the data
    class LprOpaquePostProcessPass : ScriptableRenderPass
    {
        private Material mDecodeMaterial;

        public LprOpaquePostProcessPass(Material material)
        {
            mDecodeMaterial = material;
            renderPassEvent = (RenderPassEvent)255;
        }

        private class OpaquePPData
        {
            public TextureHandle SourceHandle;
            public TextureHandle GBuffer0Handle;
            public TextureHandle DepthHandle;
            public Material Material;
            public Vector4[] LightPositions;
            public Vector4[] LightColors;
            public int LightCount;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            LprPassData lprData = frameData.Get<LprPassData>();

            if (lprData == null || !lprData.ColorTarget.IsValid()) return;
            TextureDesc temp = lprData.ColorTarget.GetDescriptor(renderGraph);
            temp.name = "LPR_pColorBuffer";
            
            TextureHandle colorTexture = renderGraph.CreateTexture(temp);

            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
                
            int lightCount = 0;
            var visibleLights = renderingData.cullResults.visibleLights;
            int length = visibleLights.Length;
                
            if (visibleLights.Length > 32)
            {
                Debug.LogWarning("LPR Packed Deferred Renderer: More than 32 visible lights! Only the first 32 will be processed.");
                length = 32;
            }
            Vector4[] m_LightPositions =  new Vector4[32];
            Vector4[] m_LightColors =  new Vector4[32];

            for (int i = 0; i < length; i++)
            {
                VisibleLight vl = visibleLights[i];
                    
                if (vl.lightType == LightType.Point)
                {
                    Vector3 pos = vl.localToWorldMatrix.GetColumn(3);
                    m_LightPositions[lightCount] = new Vector4(pos.x, pos.y, pos.z, vl.range);
                        
                    m_LightColors[lightCount] = new Vector4(vl.finalColor.r, vl.finalColor.g, vl.finalColor.b, 1.0f);
                    lightCount++;
                }
            }
            
            using (var builder = renderGraph.AddRasterRenderPass<OpaquePPData>("LPR Opaque PP Pass", out var passData))
            {
                passData.SourceHandle = lprData.ColorTarget;
                passData.GBuffer0Handle = lprData.GBuffer0Target;
                passData.DepthHandle = lprData.DepthTarget;
                passData.Material = mDecodeMaterial;
                passData.LightPositions = m_LightPositions;
                passData.LightColors = m_LightColors;
                passData.LightCount = lightCount;
                
                builder.UseTexture(passData.SourceHandle);
                builder.UseTexture(passData.GBuffer0Handle);
                builder.UseTexture(passData.DepthHandle);
                
                builder.SetRenderAttachment(colorTexture, 0);

                builder.SetRenderFunc((OpaquePPData data, RasterGraphContext context) =>
                {
                    data.Material.SetVectorArray("_LightPositions", data.LightPositions);
                    data.Material.SetVectorArray("_LightColors", data.LightColors);
                    data.Material.SetInt("_LightCount", data.LightCount);
                    
                    data.Material.SetTexture("_GBuffer0", data.GBuffer0Handle);
                    data.Material.SetTexture("_LPR_DepthTexture", data.DepthHandle);
                    
                    Blitter.BlitTexture(context.cmd, data.SourceHandle, new Vector4(1, 1, 0, 0), data.Material, 0);
                });
            }
            lprData.ColorTarget =  colorTexture;
        }
    }
    
    class LprSkyboxPass : ScriptableRenderPass
    {
        private Material mSkyboxMaterial;

        public LprSkyboxPass(Material mat)
        {
            mSkyboxMaterial = mat;
            renderPassEvent = (RenderPassEvent)260;
        }

        private class SkyboxPassData
        {
            public TextureHandle ColorTarget;
            public TextureHandle DepthTarget;
            public Material Material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            LprPassData lprData = frameData.Get<LprPassData>();
            if (lprData == null || !lprData.ColorTarget.IsValid()) return;

            using (var builder = renderGraph.AddRasterRenderPass<SkyboxPassData>("LPR Skybox Pass", out var passData))
            {
                passData.ColorTarget   = lprData.ColorTarget;
                passData.DepthTarget   = lprData.DepthTarget;
                passData.Material      = mSkyboxMaterial;

                builder.SetRenderAttachment(passData.ColorTarget,   0);
                builder.SetRenderAttachmentDepth(passData.DepthTarget, AccessFlags.Read);

                builder.SetRenderFunc((SkyboxPassData data, RasterGraphContext context) =>
                {
                    context.cmd.DrawProcedural(
                        Matrix4x4.identity, data.Material, 0,
                        MeshTopology.Triangles, 3, 1, null
                    );
                });
            }
        }
    }

    class LprTransparencyPass : ScriptableRenderPass
    {
        private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRForward");
        
        public LprTransparencyPass()
        {
            renderPassEvent = (RenderPassEvent)265;
        }

        private class TransparencyPassData
        {
            public RendererListHandle RendererList;
            public TextureHandle SourceHandle;
            public TextureHandle DepthHandle;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
            LprPassData lprData = frameData.Get<LprPassData>();
            
            SortingSettings sortingSettings = new SortingSettings(cameraData.camera)
            {
                criteria = SortingCriteria.CommonTransparent
            };
            DrawingSettings drawingSettings = new DrawingSettings(SShaderTagId, sortingSettings)
            {
                enableInstancing = true,
                enableDynamicBatching = true
            };
            
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.transparent, cameraData.camera.cullingMask);

            RendererListParams listParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);
            RendererListHandle rendererList = renderGraph.CreateRendererList(listParams);
            
            using (var builder = renderGraph.AddRasterRenderPass<TransparencyPassData>("LPR Transparent Pass", out var passData))
            {
                passData.SourceHandle = lprData.ColorTarget;
                passData.DepthHandle = lprData.DepthTarget;
                
                passData.RendererList = rendererList;
                builder.UseRendererList(rendererList);
                
                builder.SetRenderAttachment(passData.SourceHandle, 0);
                builder.SetRenderAttachmentDepth(passData.DepthHandle, AccessFlags.Read);

                builder.SetRenderFunc((TransparencyPassData data, RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(data.RendererList);
                });
            }
        }
    }

    class LprBlitPass : ScriptableRenderPass
    {
        private Material mBlitPostProcessMaterial;

        public LprBlitPass(Material blitPostProcessMaterial)
        {
            mBlitPostProcessMaterial = blitPostProcessMaterial;
            renderPassEvent = (RenderPassEvent)500;
        }

        public class BlitPassData
        {
            public TextureHandle SourceHandle;
            public TextureHandle GBuffer0Handle;
            public TextureHandle DepthHandle;
            public Material Material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            LprPassData lprData = frameData.Get<LprPassData>();

            if (lprData == null || !lprData.ColorTarget.IsValid()) return;
            
            TextureHandle destinationTarget = resourceData.activeColorTexture;
            if (!destinationTarget.IsValid()) return;
            

            using (var builder = renderGraph.AddRasterRenderPass<BlitPassData>("LPR Global PP Pass", out var passData))
            {
                passData.SourceHandle = lprData.ColorTarget;
                passData.DepthHandle = lprData.DepthTarget;
                passData.GBuffer0Handle = lprData.GBuffer0Target;
                passData.Material = mBlitPostProcessMaterial;

                builder.UseTexture(passData.SourceHandle);
                builder.UseTexture(passData.DepthHandle);
                builder.UseTexture(passData.GBuffer0Handle);
                
                builder.SetRenderAttachment(destinationTarget, 0);

                builder.SetRenderFunc((BlitPassData data, RasterGraphContext context) =>
                {
                    data.Material.SetTexture("_GBuffer0", data.GBuffer0Handle);
                    data.Material.SetTexture("_LPR_DepthTexture", data.DepthHandle);
                    Blitter.BlitTexture(context.cmd, data.SourceHandle, new Vector4(1, 1, 0, 0), data.Material, 0);
                });
            }
        }
    }
}
