using System.Collections;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class AdaptiveResolutionHandler : MonoBehaviour
{
    [SerializeField] private Camera mainCamera;
    [Range(0.01f, 1.0f)]
    [SerializeField] private float resolutionScale = 0.3125f;
    [SerializeField] private Slider resolutionSlider;
    [SerializeField] private TextMeshProUGUI resolutionText;

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
        
        resolutionText.text = $"{width}x{height}";
        
        mainCamera.aspect = (float)width / (float)height;

        lastScreenWidth  = Screen.width;
        lastScreenHeight = Screen.height;

        Debug.Log($"RT resized: {width}x{height}");
    }

    public void UpdateResolutionScale()
    {
        resolutionScale = resolutionSlider.value;
        ResizeRT();
    }
}
