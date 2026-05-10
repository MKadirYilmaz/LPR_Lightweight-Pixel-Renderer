using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class LprDefaultForwardRF : ScriptableRendererFeature
{
    [System.Serializable]
    public class LprSettings
    {
        [Tooltip("Opaque Post Process Material")]
        public Material opaquePostProcessMaterial;
        
        [Tooltip("Global Post Process Material")]
        public Material globalPostProcessMaterial;
        
        [Tooltip("Skybox Material")]
        public Material skyboxMaterial;

        [Range(5f, 100f), Tooltip("Target DPI")]
        public float DPI = 40f;
    }
    
    public LprSettings lprSettings = new LprSettings();
    
    private LprOpaquePass mOpaquePass;
    private LprOpaquePostProcessPass mOpaquePostProcessPass;
    private LprSkyboxPass mSkyboxPass;
    private LprTransparencyPass mTransparencyPass;
    private LprBlitPass mBlitPass;

    private class LprPassData : ContextItem
    {
        public TextureHandle ColorTarget;
        public TextureHandle DepthTarget;

        public override void Reset()
        {
            ColorTarget = TextureHandle.nullHandle;
            DepthTarget = TextureHandle.nullHandle;
        }
    }

    public override void Create()
    {
        if(lprSettings.opaquePostProcessMaterial == null ||
           lprSettings.globalPostProcessMaterial == null ||
           lprSettings.skyboxMaterial == null) return;

        mOpaquePass = new LprOpaquePass(lprSettings.DPI);
        mOpaquePostProcessPass = new LprOpaquePostProcessPass(lprSettings.opaquePostProcessMaterial);
        mSkyboxPass = new LprSkyboxPass(lprSettings.skyboxMaterial);
        mTransparencyPass = new LprTransparencyPass();
        mBlitPass = new LprBlitPass(lprSettings.globalPostProcessMaterial);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (lprSettings.opaquePostProcessMaterial == null || 
            lprSettings.globalPostProcessMaterial == null ||
            lprSettings.skyboxMaterial == null) return;
        
        renderer.EnqueuePass(mOpaquePass);
        renderer.EnqueuePass(mOpaquePostProcessPass);
        renderer.EnqueuePass(mSkyboxPass);
        renderer.EnqueuePass(mTransparencyPass);
        renderer.EnqueuePass(mBlitPass);
    }
    
    class LprOpaquePass : ScriptableRenderPass
    {
        private float mTargetDpi;
        private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRForward");

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

            TextureDesc colorBufferDesc = new TextureDesc(width, height)
            {
                colorFormat = GraphicsFormat.R8G8B8A8_UNorm,
                depthBufferBits = DepthBits.None,
                msaaSamples = MSAASamples.None,
                name = "LPR_ColorBuffer",
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
            
            TextureHandle colorTarget = renderGraph.CreateTexture(colorBufferDesc);
            TextureHandle hardwareDepthTarget = renderGraph.CreateTexture(hardwareDepthDesc);
            
            LprPassData lprData = frameData.GetOrCreate<LprPassData>();
            lprData.ColorTarget = colorTarget;
            lprData.DepthTarget = hardwareDepthTarget;
            
            SortingSettings sortingSettings = new SortingSettings(cameraData.camera)
            {
                criteria = cameraData.defaultOpaqueSortFlags
            };

            DrawingSettings drawingSettings = new DrawingSettings(SShaderTagId, sortingSettings)
            {
                perObjectData = PerObjectData.Lightmaps | 
                                PerObjectData.LightProbe | 
                                PerObjectData.LightData | 
                                PerObjectData.LightIndices |
                                PerObjectData.ShadowMask | 
                                PerObjectData.ReflectionProbes,
                
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
                
                builder.SetRenderAttachment(colorTarget, 0);
                builder.SetRenderAttachmentDepth(hardwareDepthTarget, AccessFlags.Write);
                
                builder.SetRenderFunc((OpaquePassData data, RasterGraphContext context) =>
                {
                     context.cmd.DrawRendererList(data.RendererList);   
                });
            }
        }
    }

    class LprOpaquePostProcessPass : ScriptableRenderPass
    {
        private Material mOpaquePostProcessMaterial;

        public LprOpaquePostProcessPass(Material material)
        {
            mOpaquePostProcessMaterial = material;
            renderPassEvent = (RenderPassEvent)255;
        }

        private class OpaquePostProcessData
        {
            public TextureHandle SourceHandle;
            public TextureHandle DepthHandle;
            public Material Material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            LprPassData lprData = frameData.Get<LprPassData>();

            TextureDesc temp = lprData.ColorTarget.GetDescriptor(renderGraph);
            temp.name = "LPR_pColorBuffer";
            temp.clearBuffer = false;

            TextureHandle pColorBuffer = renderGraph.CreateTexture(temp);
            
            if(!lprData.ColorTarget.IsValid() || !lprData.DepthTarget.IsValid()) return;

            using (var builder = renderGraph.AddRasterRenderPass<OpaquePostProcessData>("LPR Opaque PP", out var passData))
            {
                passData.SourceHandle = lprData.ColorTarget;
                passData.DepthHandle = lprData.DepthTarget;
                
                passData.Material = mOpaquePostProcessMaterial;
                
                builder.UseTexture(passData.SourceHandle);
                builder.UseTexture(passData.DepthHandle);
                
                builder.SetRenderAttachment(pColorBuffer, 0);
                
                builder.SetRenderFunc((OpaquePostProcessData data, RasterGraphContext context) =>
                {
                    data.Material.SetTexture("_LPR_DepthTexture", data.DepthHandle);
                    Blitter.BlitTexture(context.cmd, data.SourceHandle, new Vector4(1, 1, 0, 0), data.Material, 0);
                });
            }
            lprData.ColorTarget = pColorBuffer;
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
                passData.Material = mBlitPostProcessMaterial;

                builder.UseTexture(passData.SourceHandle);
                builder.UseTexture(passData.DepthHandle);
                
                builder.SetRenderAttachment(destinationTarget, 0);

                builder.SetRenderFunc((BlitPassData data, RasterGraphContext context) =>
                {
                    data.Material.SetTexture("_LPR_DepthTexture", data.DepthHandle);
                    Blitter.BlitTexture(context.cmd, data.SourceHandle, new Vector4(1, 1, 0, 0), data.Material, 0);
                });
            }
        }
    }
}
