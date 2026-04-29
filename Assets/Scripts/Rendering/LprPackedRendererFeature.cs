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
            [Tooltip("Decoder Post Process Material")]
            public Material decodeMaterial;
            
            [Range(0.01f, 1f), Tooltip("Render scale for the LPR pass.")]
            public float renderScale = 1.0f;
        }

        public LprSettings settings = new LprSettings();

        private LprOpaquePass mOpaquePass;
        private LprBlitPass mBlitPass;

        private class LprPassData : ContextItem
        {
            public TextureHandle UintColorTarget;
            public TextureHandle DepthTarget;

            public override void Reset()
            {
                UintColorTarget = TextureHandle.nullHandle;
                DepthTarget = TextureHandle.nullHandle;
            }
        }

        public override void Create()
        {
            if (settings.decodeMaterial == null) return;

            mOpaquePass = new LprOpaquePass(settings.renderScale);
            mBlitPass = new LprBlitPass(settings.decodeMaterial);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (settings.decodeMaterial == null) return;

            renderer.EnqueuePass(mOpaquePass);
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
                    name = "LPR_UintBuffer",
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
                TextureHandle hardwareDepthTexture = renderGraph.CreateTexture(hardwareDepthDesc);

                LprPassData lprData = frameData.GetOrCreate<LprPassData>();
                lprData.UintColorTarget = uintTexture;
                lprData.DepthTarget = hardwareDepthTexture;
                
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
                    builder.SetRenderAttachmentDepth(hardwareDepthTexture);

                    builder.SetRenderFunc((OpaquePassData data, RasterGraphContext context) =>
                    {
                        context.cmd.DrawRendererList(data.RendererList);
                    });
                }
            }
        }

        // Stage 2: Blit the uint buffer to the camera's color target using a post-process material that decodes the data
        class LprBlitPass : ScriptableRenderPass
        {
            private Material mDecodeMaterial;

            public LprBlitPass(Material material)
            {
                mDecodeMaterial = material;
                renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
            }

            private class BlitPassData
            {
                public TextureHandle SourceHandle;
                public TextureHandle DepthHandle;
                public Material Material;
            }

            public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
            {
                UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
                LprPassData lprData = frameData.Get<LprPassData>();

                if (lprData == null || !lprData.UintColorTarget.IsValid()) return;
                
                TextureHandle destinationTarget = resourceData.activeColorTexture;
                if (!destinationTarget.IsValid()) return;

                using (var builder = renderGraph.AddRasterRenderPass<BlitPassData>("LPR Decode Blit", out var passData))
                {
                    passData.SourceHandle = lprData.UintColorTarget;
                    passData.DepthHandle = lprData.DepthTarget;
                    passData.Material = mDecodeMaterial;

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
}