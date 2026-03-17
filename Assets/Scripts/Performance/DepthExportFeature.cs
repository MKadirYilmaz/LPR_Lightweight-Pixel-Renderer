using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class SimpleDepthCopyFeature : ScriptableRendererFeature
{
    public Material depthCatcherMaterial;
    public RenderTexture targetTexture; 

    class CopyPass : ScriptableRenderPass
    {
        public Material mat;
        public RenderTexture rt;
        private RTHandle rtHandle;

        class PassData { }

        public CopyPass()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (mat == null || rt == null) return;

            // Work only with game camera for editor optimization
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            if (cameraData.cameraType != CameraType.Game) return;

            // Allocate RTHandle if not allocated or if size/format changed
            if (rtHandle == null || rtHandle.rt != rt) rtHandle = RTHandles.Alloc(rt);
            TextureHandle destination = renderGraph.ImportTexture(rtHandle);
            
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Copy Depth to File", out var passData))
            {
                // Point render target as destination (write)
                builder.SetRenderAttachment(destination, 0);
                
                builder.AllowPassCulling(false);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    // Paint the render texture with our material (which samples depth)
                    Blitter.BlitTexture(context.cmd, new Vector4(1, 1, 0, 0), mat, 0);
                });
            }
        }
    }

    CopyPass m_Pass;

    public override void Create()
    {
        m_Pass = new CopyPass { mat = depthCatcherMaterial, rt = targetTexture };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData data)
    {
        renderer.EnqueuePass(m_Pass);
    }
}
