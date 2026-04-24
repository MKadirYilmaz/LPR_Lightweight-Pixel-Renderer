using System;
using TMPro;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GlobalShaderSwapper : MonoBehaviour
{
    [SerializeField] private Camera pixelArtCamera;
    [SerializeField] private Camera blitCamera;
    [SerializeField] private Camera fullResolutionCamera;
    
    [SerializeField] private Material blitMaterial;
    
    [SerializeField] private RenderTexture packedRenderTexture;
    [SerializeField] private RenderTexture pbrRenderTexture;
    [SerializeField] private RenderTexture depthTexture;

    [SerializeField] private TextMeshProUGUI lightingModelText;
    [SerializeField] private TextMeshProUGUI samplingTypeText;
    
    [SerializeField] private AdaptiveResolutionHandler adaptiveResolutionHandler;
    [SerializeField] private UniversalRendererData defualtRendererData;
    
    [SerializeField] private UniversalRenderPipelineAsset globalURPAsset;

    private bool bIsDownscaling = false;
    private bool bIsCustomShader = true;

    private void Start()
    {
        if(globalURPAsset == null)
            globalURPAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
        SwitchToCustomShader();
        SwitchToUpscaling();
    }
    
    private void OnEnable()
    {
        SwitchToCustomShader();
        SwitchToUpscaling();
    }
    
    void OnDisable()
    {
        SwitchToCustomShader();
        SwitchToUpscaling();
    }

    private void OnApplicationQuit()
    {
        SwitchToCustomShader();
        SwitchToUpscaling();
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

    public void ToggleSamplingType()
    {
        if(bIsDownscaling)
            SwitchToUpscaling();
        else
            SwitchToDownscaling();
    }

    [ContextMenu("Switch To PBR Shader")]
    public void SwitchToPBRShader()
    {
        if (bIsDownscaling)
        {
            Shader.EnableKeyword("_USE_UNITY_PBR_LIT");
        }
        else
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
        }
        bIsCustomShader = false;
        lightingModelText.text = "PBR Lighting";

    }
    [ContextMenu("Switch To Custom Shader")]
    public void SwitchToCustomShader()
    {
        if (bIsDownscaling)
        {
            Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
        }
        else
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
        }
        bIsCustomShader = true;
        lightingModelText.text = "Custom Lighting";
    }

    [ContextMenu("Switch To Downscaling")]
    public void SwitchToDownscaling()
    {
        if (pixelArtCamera == null || blitCamera == null || fullResolutionCamera == null)
        {
            Debug.LogWarning("One or more camera references are missing. Cannot switch to downscaling.");
            return;
        }
        pixelArtCamera.enabled = false;
        blitCamera.enabled = false;
        fullResolutionCamera.enabled = true;
        
        // Enable engine depth texture generation
        if (globalURPAsset != null) globalURPAsset.supportsCameraDepthTexture = true;
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is FullScreenPassRendererFeature)?.SetActive(true);
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is SimpleDepthCopyFeature)?.SetActive(false);
        bIsDownscaling = true;
        samplingTypeText.text = "Downscaling";
        if(bIsCustomShader)
            SwitchToCustomShader();
        else
            SwitchToPBRShader();
        
    }
    [ContextMenu("Switch To Upscaling")]
    public void SwitchToUpscaling()
    {
        if (pixelArtCamera == null || blitCamera == null || fullResolutionCamera == null)
        {
            Debug.LogWarning("One or more camera references are missing. Cannot switch to upscaling.");
            return;
        }
        pixelArtCamera.enabled = true;
        blitCamera.enabled = true;
        fullResolutionCamera.enabled = false;
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is FullScreenPassRendererFeature)?.SetActive(false);
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is SimpleDepthCopyFeature)?.SetActive(true);
        bIsDownscaling = false;
        samplingTypeText.text = "Upscaling";
        if(bIsCustomShader)
            SwitchToCustomShader();
        else
            SwitchToPBRShader();
    }
    
}
