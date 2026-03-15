using System;
using UnityEngine;

public class GlobalShaderSwapper : MonoBehaviour
{
    [SerializeField] private Camera pixelArtCamera;
    [SerializeField] private Camera fullScreenCamera;
    
    private bool bIsCustomShader = true;
    
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
        if (pixelArtCamera == null || fullScreenCamera == null)
            return;
        if (bIsCustomShader)
        {
            Shader.EnableKeyword("_USE_UNITY_PBR_LIT");
            pixelArtCamera.enabled = false;
            pixelArtCamera.GetComponent<AudioListener>().enabled = false;
            pixelArtCamera.GetComponentInChildren<Camera>().enabled = false;
            fullScreenCamera.enabled = true;
            fullScreenCamera.GetComponent<AudioListener>().enabled = true;
            bIsCustomShader = false;
        }
        else
        {
            Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
            pixelArtCamera.enabled = true;
            pixelArtCamera.GetComponent<AudioListener>().enabled = true;
            pixelArtCamera.GetComponentInChildren<Camera>().enabled = true;
            fullScreenCamera.enabled = false;
            fullScreenCamera.GetComponent<AudioListener>().enabled = false;
            bIsCustomShader = true;
        }
    }

    [ContextMenu("Disable PBR Shader")]
    public void DisablePBRShader()
    {
        Shader.DisableKeyword("_USE_UNITY_PBR_LIT");
    }
}
