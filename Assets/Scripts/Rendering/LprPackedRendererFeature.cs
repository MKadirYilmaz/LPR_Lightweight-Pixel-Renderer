namespace Rendering
{
    using UnityEngine;
    using UnityEngine.Rendering;
    using UnityEngine.Rendering.Universal;
    using UnityEngine.Rendering.RenderGraphModule;
    using UnityEngine.Experimental.Rendering;

    public class LprPackedRendererFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class LprSettings
        {
            [Tooltip("Opaque Decoder Post Process Material")]
            public Material opaqueDecodeMaterial;
            
            [Tooltip("Global Post Process Material")]
            public Material globalPostProcessMaterial;
            
            [Range(0.01f, 1f), Tooltip("Render scale for the LPR pass.")]
            public float renderScale = 1.0f;
        }

        public LprSettings settings = new LprSettings();

        private LprOpaquePass mOpaquePass;
        private LprOpaquePostProcessPass mOpaquePostProcessPass;
        private LprTransparencyPass mTransparencyPass;
        private LprBlitPass mBlitPass;
        

        private class LprPassData : ContextItem
        {
            public TextureHandle ColorTarget;
            public TextureHandle GBufferTarget;
            public TextureHandle DepthTarget;

            public override void Reset()
            {
                ColorTarget = TextureHandle.nullHandle;
                DepthTarget = TextureHandle.nullHandle;
                GBufferTarget = TextureHandle.nullHandle;
            }
        }

        public override void Create()
        {
            if (settings.opaqueDecodeMaterial == null || settings.globalPostProcessMaterial == null) return;

            mOpaquePass = new LprOpaquePass(settings.renderScale);
            mOpaquePostProcessPass = new LprOpaquePostProcessPass(settings.opaqueDecodeMaterial);
            mTransparencyPass = new LprTransparencyPass();
            mBlitPass = new LprBlitPass(settings.globalPostProcessMaterial);

        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (settings.opaqueDecodeMaterial == null || settings.globalPostProcessMaterial == null) return;

            renderer.EnqueuePass(mOpaquePass);
            renderer.EnqueuePass(mOpaquePostProcessPass);
            renderer.EnqueuePass(mTransparencyPass);
            renderer.EnqueuePass(mBlitPass);
        }

        // Stage 1: Render opaque objects to a uint buffer with a custom shader pass
        class LprOpaquePass : ScriptableRenderPass
        {
            private float mScale;
            private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRDeferredPacked");

            public LprOpaquePass(float scale)
            {
                mScale = scale;
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
                
                int width = Mathf.Max(1, Mathf.RoundToInt(cameraData.cameraTargetDescriptor.width * mScale));
                int height = Mathf.Max(1, Mathf.RoundToInt(cameraData.cameraTargetDescriptor.height * mScale));

                TextureDesc uintDesc = new TextureDesc(width, height)
                {
                    colorFormat = GraphicsFormat.R32_UInt,
                    depthBufferBits = DepthBits.None,
                    msaaSamples = MSAASamples.None,
                    name = "LPR_uColorBuffer",
                    clearBuffer = true,
                    clearColor = Color.black
                };
                TextureDesc gBuffer0Desc = new TextureDesc(width, height)
                {
                    colorFormat = GraphicsFormat.R32_UInt,
                    depthBufferBits = DepthBits.None,
                    msaaSamples = MSAASamples.None,
                    name = "LPR_uGBuffer0",
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
                lprData.GBufferTarget = gBuffer0Texture;
                
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
                public Material Material;
            }

            public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
            {
                UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
                LprPassData lprData = frameData.Get<LprPassData>();

                if (lprData == null || !lprData.ColorTarget.IsValid()) return;
                TextureDesc uintDesc = lprData.ColorTarget.GetDescriptor(renderGraph);
                TextureDesc colorTexDesc = new TextureDesc(uintDesc.width, uintDesc.height)
                {
                    colorFormat = GraphicsFormat.R8G8B8A8_UNorm,
                    depthBufferBits = DepthBits.None,
                    msaaSamples = MSAASamples.None,
                    name = "LPR_ColorBuffer",
                    clearBuffer = true,
                    clearColor = Color.black
                };
                TextureHandle uintTexture = lprData.ColorTarget;
                TextureHandle gBuffer0 = lprData.GBufferTarget;
                TextureHandle colorTexture = renderGraph.CreateTexture(colorTexDesc);
                
                lprData.ColorTarget =  colorTexture;
                

                using (var builder = renderGraph.AddRasterRenderPass<OpaquePPData>("LPR Opaque PP Pass", out var passData))
                {
                    passData.SourceHandle = uintTexture;
                    passData.GBuffer0Handle = gBuffer0;
                    passData.Material = mDecodeMaterial;
                    
                    builder.SetInputAttachment(passData.SourceHandle, 0);
                    builder.SetInputAttachment(passData.GBuffer0Handle, 1);
                    
                    builder.SetRenderAttachment(colorTexture, 0);

                    builder.SetRenderFunc((OpaquePPData data, RasterGraphContext context) =>
                    {
                        context.cmd.DrawProcedural(Matrix4x4.identity, data.Material, 0, MeshTopology.Triangles, 3, 1, null);
                    });
                }
            }
        }

        class LprTransparencyPass : ScriptableRenderPass
        {
            private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRForward");
            
            public LprTransparencyPass()
            {
                renderPassEvent = (RenderPassEvent)260;
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
                
                // Set up drawing and filtering settings to render only opaque objects with our custom shader pass
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
                    builder.SetRenderAttachmentDepth(passData.DepthHandle);

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
                    passData.GBuffer0Handle = lprData.GBufferTarget;
                    passData.Material = mBlitPostProcessMaterial;

                    builder.UseTexture(passData.SourceHandle);
                    builder.UseTexture(passData.GBuffer0Handle);
                    
                    builder.SetRenderAttachment(destinationTarget, 0);

                    builder.SetRenderFunc((BlitPassData data, RasterGraphContext context) =>
                    {
                        data.Material.SetTexture("_GBuffer0", data.GBuffer0Handle);
                        Blitter.BlitTexture(context.cmd, data.SourceHandle, new Vector4(1, 1, 0, 0), data.Material, 0);
                    });
                }
            }
        }
    }
}