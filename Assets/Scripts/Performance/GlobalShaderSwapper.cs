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
    [SerializeField] private TextMeshProUGUI shadingTypeText;
    [SerializeField] private TextMeshProUGUI packingTypeText;
    
    [SerializeField] private AdaptiveResolutionHandler adaptiveResolutionHandler;
    
    [SerializeField] private UniversalRenderPipelineAsset globalURPAsset;
    

    private bool bIsDownscaling = false;
    private bool bIsCustomShader = true;
    private bool bIsDeferred = false;
    private bool bIsPacked = true;

    private void Start()
    {
        if(globalURPAsset == null)
            globalURPAsset = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
        
        if (mainCamera == null)
            return;
        SwitchToCustomShader();
        SwitchToUpscaling();
        SwitchToForwardShading();
        SwitchToPackedSystem();
    }
    
    private void OnEnable()
    {
        if (mainCamera == null)
            return;
        SwitchToCustomShader();
        SwitchToUpscaling();
        SwitchToForwardShading();
        SwitchToPackedSystem();
    }
    
    void OnDisable()
    {
        if (mainCamera == null)
            return;
        SwitchToCustomShader();
        SwitchToUpscaling();
        SwitchToForwardShading();
        SwitchToPackedSystem();
    }

    private void OnApplicationQuit()
    {
        if (mainCamera == null)
            return;
        SwitchToCustomShader();
        SwitchToUpscaling();
        SwitchToForwardShading();
        SwitchToPackedSystem();
    }

    public void ToggleLightingType()
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

    public void ToggleShadingType()
    {
        if(bIsDeferred)
            SwitchToForwardShading();
        else
            SwitchToDeferredShading();
    }

    public void TogglePackedSystem()
    {
        if(bIsPacked)
            SwitchToNormalSystem();
        else
            SwitchToPackedSystem();
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
        bIsDownscaling = true;
        samplingTypeText.text = "Downscaling";
        globalURPAsset.supportsCameraDepthTexture = true;
        mainCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(4);
        
    }
    [ContextMenu("Switch To Upscaling")]
    public void SwitchToUpscaling()
    {
        bIsDownscaling = false;
        samplingTypeText.text = "Upscaling";
        // Enable depth texture generation
        globalURPAsset.supportsCameraDepthTexture = false;
        if(bIsDeferred)
            SwitchToDeferredShading();
        else
            SwitchToForwardShading();
    }

    [ContextMenu("Switch to Deferred Shading")]
    public void SwitchToDeferredShading()
    {
        if (bIsDownscaling)
            return;
        bIsDeferred = true;
        mainCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(bIsPacked ? 3 : 2);
        shadingTypeText.text = "Deferred Shading";
    }

    [ContextMenu("Switch to Forward Shading")]
    public void SwitchToForwardShading()
    {
        if (bIsDownscaling)
            return;
        bIsDeferred = false;
        mainCamera.GetComponent<UniversalAdditionalCameraData>().SetRenderer(bIsPacked ? 1 : 0);
        shadingTypeText.text = "Forward Shading";
    }

    [ContextMenu("Switch to Packed System")]
    public void SwitchToPackedSystem()
    {
        if (bIsDownscaling)
            return;
        bIsPacked = true;
        packingTypeText.text = "Packed";
        if(bIsDeferred)
            SwitchToDeferredShading();
        else
            SwitchToForwardShading();
    }
    
    [ContextMenu("Switch to Normal System")]
    public void SwitchToNormalSystem()
    {
        if (bIsDownscaling)
            return;
        bIsPacked = false;
        packingTypeText.text = "Normal";
        if(bIsDeferred)
            SwitchToDeferredShading();
        else
            SwitchToForwardShading();
    }
    
}
