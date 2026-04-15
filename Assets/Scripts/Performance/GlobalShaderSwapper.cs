using System;
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
        SwitchToCustomShader();
    }
    
    private void OnEnable()
    {
        SwitchToCustomShader();
    }
    
    void OnDisable()
    {
        SwitchToCustomShader();
    }

    private void OnApplicationQuit()
    {
        SwitchToCustomShader();
    }

    public void ToggleCustomShader()
    {
        if (bIsCustomShader)
        {
            SwitchToPBRShader();
        }
        else
        {
            SwitchToCustomShader();
        }
        // Refresh RT sizes to match current screen size after shader switch
        adaptiveResolutionHandler.ResizeRT();
    }

    [ContextMenu("Switch To PBR Shader")]
    public void SwitchToPBRShader()
    {
        if (pixelArtCamera == null)
            return;
        Shader.EnableKeyword("_USE_UNITY_PBR_LIT");
        
        pixelArtCamera.targetTexture = pbrRenderTexture;
        blitMaterial.SetTexture("_SourceTexture", pbrRenderTexture);
        blitMaterial.SetTexture("_MainCameraDepth", depthTexture);
        pixelArtCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(0);
            
        // Enable engine depth texture generation
        if (globalURPAsset != null) globalURPAsset.supportsCameraDepthTexture = true;
        pixelArtCamera.GetComponent<Skybox>().enabled = false;
        bIsCustomShader = false;
        
    }
    [ContextMenu("Switch To Custom Shader")]
    public void SwitchToCustomShader()
    {
        if (pixelArtCamera == null)
            return;
        Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
        
        pixelArtCamera.targetTexture = packedRenderTexture;
        blitMaterial.SetTexture("_SourceTexture", packedRenderTexture);
        blitMaterial.SetTexture("_MainCameraDepth", null);
        depthTexture.Release();
            
        pixelArtCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(1);
            
        // Disable engine depth texture generation
        if (globalURPAsset != null) globalURPAsset.supportsCameraDepthTexture = false;
        pixelArtCamera.GetComponent<Skybox>().enabled = true;
        bIsCustomShader = true;
    }
}
