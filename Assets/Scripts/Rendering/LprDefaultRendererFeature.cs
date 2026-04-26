using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class LprDefaultRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class LprDefaultSettings
    {
        [Tooltip("Opaque Post Process Material")]
        public Material opaquePostProcessMaterial;

        [Range(0.01f, 1f), Tooltip("Render scale for the LPR pass")]
        public float renderScale = 1.0f;
    }
    
    public LprDefaultSettings lprDefaultSettings = new LprDefaultSettings();
    
    private LprOpaquePass mOpaquePass;
    private LprBlitPass mBlitPass;

    private class LprPassData : ContextItem
    {
        public TextureHandle colorTarget;
        public TextureHandle depthTarget;

        public override void Reset()
        {
            colorTarget = TextureHandle.nullHandle;
            depthTarget = TextureHandle.nullHandle;
        }
    }

    public override void Create()
    {
        if(lprDefaultSettings.opaquePostProcessMaterial == null) return;

        mOpaquePass = new LprOpaquePass(lprDefaultSettings.renderScale);
        mBlitPass = new LprBlitPass(lprDefaultSettings.opaquePostProcessMaterial);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (lprDefaultSettings.opaquePostProcessMaterial == null) return;
        
        renderer.EnqueuePass(mOpaquePass);
        renderer.EnqueuePass(mBlitPass);
    }
    
    class LprOpaquePass : ScriptableRenderPass
    {
        private float mScale;
        private static readonly ShaderTagId SShaderTagId = new ShaderTagId("LPRForward");

        public LprOpaquePass(float scale)
        {
            mScale = scale;
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
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
            lprData.colorTarget = colorTarget;
            lprData.depthTarget = hardwareDepthTarget;
            
            SortingSettings sortingSettings = new SortingSettings(cameraData.camera)
            {
                criteria = cameraData.defaultOpaqueSortFlags
            };

            DrawingSettings drawingSettings = new DrawingSettings(SShaderTagId, sortingSettings)
            {
                perObjectData = PerObjectData.Lightmaps | 
                                PerObjectData.LightProbe | 
                                PerObjectData.LightData | 
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

    class LprBlitPass : ScriptableRenderPass
    {
        private Material mOpaquePostProcessMaterial;

        public LprBlitPass(Material material)
        {
            mOpaquePostProcessMaterial = material;
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
            
            if(lprData == null || !lprData.colorTarget.IsValid()) return;

            TextureHandle destinationTarget = resourceData.activeColorTexture;
            if (!destinationTarget.IsValid()) return;

            using (var builder = renderGraph.AddRasterRenderPass<BlitPassData>("LPR Post Process Blit", out var passData))
            {
                passData.SourceHandle = lprData.colorTarget;
                passData.DepthHandle = lprData.depthTarget;
                
                passData.Material = mOpaquePostProcessMaterial;
                
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
