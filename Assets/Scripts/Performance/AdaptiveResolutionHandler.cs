using System.Collections;
using UnityEngine;

public class AdaptiveResolutionHandler : MonoBehaviour
{
    [SerializeField] private Camera lowResCamera;
    [SerializeField] private RenderTexture rt;
    [Range(0.01f, 1.0f)]
    [SerializeField] private float resolutionScale = 0.15f;

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

    private void ResizeRT()
    {
        int width  = Mathf.Max(1, Mathf.RoundToInt(Screen.width  * resolutionScale));
        int height = Mathf.Max(1, Mathf.RoundToInt(Screen.height * resolutionScale));
        
        rt.Release();
        rt.width  = width;
        rt.height = height;
        rt.Create();
        
        lowResCamera.targetTexture = rt;
        lowResCamera.aspect = (float)width / (float)height;

        lastScreenWidth  = Screen.width;
        lastScreenHeight = Screen.height;

        Debug.Log($"RT resized: {width}x{height}");
    }
}
