using System.Collections;
using UnityEngine;
using UnityEngine.UI;

public class AdaptiveResolutionHandler : MonoBehaviour
{
    [SerializeField] private Camera lowResCamera;
    [Range(0.01f, 1.0f)]
    [SerializeField] private float resolutionScale = 0.15f;
    [SerializeField] private RenderTexture depthTexture;
    [SerializeField] private Slider resolutionSlider;
    
    [SerializeField] private Material fullscreenPassMaterial;

    private int lastScreenWidth;
    private int lastScreenHeight;

    private IEnumerator Start()
    {
        yield return null;
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
        int width  = Mathf.Max(1, Mathf.RoundToInt(Screen.width  * resolutionScale));
        int height = Mathf.Max(1, Mathf.RoundToInt(Screen.height * resolutionScale));
        
        lowResCamera.aspect = (float)width / (float)height;
        
        RenderTexture rt = lowResCamera.targetTexture;
        
        rt.Release();
        rt.width  = width;
        rt.height = height;
        rt.Create();
        
        depthTexture.Release();
        depthTexture.width  = width;
        depthTexture.height  = height;
        depthTexture.Create();
        
        lowResCamera.targetTexture = rt;

        lastScreenWidth  = Screen.width;
        lastScreenHeight = Screen.height;

        Debug.Log($"RT resized: {width}x{height}");
    }

    public void UpdateResolutionScale()
    {
        resolutionScale = resolutionSlider.value;
        fullscreenPassMaterial.SetFloat("_PixelScale",  1.0f / resolutionScale);
        ResizeRT();
    }
}
