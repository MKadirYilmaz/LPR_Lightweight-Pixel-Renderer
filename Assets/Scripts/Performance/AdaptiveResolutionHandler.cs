using System.Collections;
using TMPro;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

public class AdaptiveResolutionHandler : MonoBehaviour
{
    [SerializeField] private Camera mainCamera;
    [Range(5f, 100f)]
    [SerializeField] private float targetDPI = 40f;
    [SerializeField] private Slider resolutionSlider;
    [SerializeField] private TextMeshProUGUI resolutionText;
    [SerializeField] private Material downscalerMaterial;

    private int lastScreenWidth;
    private int lastScreenHeight;

    private IEnumerator Start()
    {
        yield return null;
        UpdateMaterialDPISettings();
        ResizeRT();
    }

    private void Update()
    {
        if (Screen.width != lastScreenWidth || Screen.height != lastScreenHeight)
        {
            ResizeRT();
        }
    }

    public void ResizeRT()
    {
        UpdateMaterialDPISettings();
        float dpi = Screen.dpi;
        if (dpi <= 0) dpi = 96;

        Vector2 physicalSize = new Vector2(Screen.width / dpi, Screen.height / dpi);
            
        int width  = Mathf.RoundToInt(physicalSize.x * targetDPI);
        int height = Mathf.RoundToInt(physicalSize.y * targetDPI);
        
        resolutionText.text = $"{width}x{height}";
        
        mainCamera.aspect = (float)width / (float)height;

        lastScreenWidth  = Screen.width;
        lastScreenHeight = Screen.height;

        Debug.Log($"RT resized: {width}x{height}");
    }

    public void UpdateResolutionScale()
    {
        ResizeRT();
    }

    [ContextMenu("Update Material DPI Settings")]
    public void UpdateMaterialDPISettings()
    {
        downscalerMaterial.SetVector("_ScreenDPI", new Vector4(Screen.dpi, targetDPI, 0, 0));
    }
}
