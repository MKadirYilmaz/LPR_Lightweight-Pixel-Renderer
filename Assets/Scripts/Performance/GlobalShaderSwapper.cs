using System;
using TMPro;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GlobalShaderSwapper : MonoBehaviour
{
    [SerializeField] private Camera mainCamera;

    [SerializeField] private TextMeshProUGUI lightingModelText;
    [SerializeField] private TextMeshProUGUI samplingTypeText;
    
    [SerializeField] private AdaptiveResolutionHandler adaptiveResolutionHandler;
    
    [SerializeField] private UniversalRenderPipelineAsset globalURPAsset;
    
    [SerializeField] private UniversalRendererData defualtRendererData;
    [SerializeField] private UniversalRendererData packedRendererData;
    

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
        Shader.DisableKeyword("_CUSTOM_LIGHTING");
        bIsCustomShader = false;
        lightingModelText.text = "PBR Lighting";

    }
    [ContextMenu("Switch To Custom Shader")]
    public void SwitchToCustomShader()
    {
        Shader.EnableKeyword("_CUSTOM_LIGHTING");
        bIsCustomShader = true;
        lightingModelText.text = "Custom Lighting";
    }

    [ContextMenu("Switch To Downscaling")]
    public void SwitchToDownscaling()
    {
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is FullScreenPassRendererFeature)?.SetActive(true);
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
        if(defualtRendererData != null) defualtRendererData.rendererFeatures.Find(feature => feature is FullScreenPassRendererFeature)?.SetActive(false);
        bIsDownscaling = false;
        samplingTypeText.text = "Upscaling";
        if(bIsCustomShader)
            SwitchToCustomShader();
        else
            SwitchToPBRShader();
    }

    [ContextMenu("Switch to Deferred Shading")]
    public void SwitchToDeferredShading()
    {
        Shader.EnableKeyword("_DEFERRED_SHADING");
    }

    [ContextMenu("Switch to Forward Shading")]
    public void SwitchToForwardShading()
    {
        Shader.DisableKeyword("_DEFERRED_SHADING");
    }
    
}
