using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GlobalShaderSwapper : MonoBehaviour
{
    [SerializeField] private Camera pixelArtCamera;
    [SerializeField] private Material blitMaterial;
    
    [SerializeField] private RenderTexture packedRenderTexture;
    [SerializeField] private RenderTexture pbrRenderTexture;
    [SerializeField] private RenderTexture depthTexture;
    
    [SerializeField] private AdaptiveResolutionHandler adaptiveResolutionHandler;
    
    private UniversalRenderPipelineAsset globalURPAsset;
    
    
    private bool bIsCustomShader = true;

    private void Start()
    {
        globalURPAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
    }
    
    private void OnEnable()
    {
        ToggleCustomShader();
    }

    void OnDisable()
    {
        ToggleCustomShader();
    }

    public void ToggleCustomShader()
    {
        if (pixelArtCamera == null)
            return;
        if (bIsCustomShader)
        {
            pixelArtCamera.targetTexture = pbrRenderTexture;
            blitMaterial.SetTexture("_SourceTexture", pbrRenderTexture);
            blitMaterial.SetTexture("_MainCameraDepth", depthTexture);
            pixelArtCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(0);
            
            // Enable engine depth texture generation
            if (globalURPAsset != null) globalURPAsset.supportsCameraDepthTexture = true;

            Shader.EnableKeyword("_USE_UNITY_PBR_LIT");
            
            bIsCustomShader = false;
        }
        else
        {
            pixelArtCamera.targetTexture = packedRenderTexture;
            blitMaterial.SetTexture("_SourceTexture", packedRenderTexture);
            blitMaterial.SetTexture("_MainCameraDepth", null);
            depthTexture.Release();
            
            pixelArtCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(1);
            
            // Disable engine depth texture generation
            if (globalURPAsset != null) globalURPAsset.supportsCameraDepthTexture = false;
            
            Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
            
            bIsCustomShader = true;
        }
        adaptiveResolutionHandler.ResizeRT();
    }
    
    [ContextMenu("Toggle System")]
    public void ToggleSystem()
    {
        ToggleCustomShader();
    }

    [ContextMenu("Enable PBR Shader")]
    public void EnablePBRShader()
    {
        Shader.EnableKeyword("_USE_UNITY_PBR_LIT");
    }
    [ContextMenu("Disable PBR Shader")]
    public void DisablePBRShader()
    {
        Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
    }
}
