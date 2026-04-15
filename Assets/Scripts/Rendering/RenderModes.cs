using System;
using UnityEngine;

public class RenderModes : MonoBehaviour
{
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        SwitchToBaseRendering();
    }

    private void OnEnable()
    {
        SwitchToBaseRendering();
    }

    private void OnDisable()
    {
        SwitchToBaseRendering();
    }

    private void OnApplicationQuit()
    {
        SwitchToBaseRendering();
    }

    [ContextMenu("Switch To Depth Rendering")]
    public void SwitchToDepthRendering()
    {
        Shader.EnableKeyword("_RENDER_DEPTH");
        Shader.DisableKeyword("_RENDER_NORMALS");
    }

    [ContextMenu("Switch To Normals Rendering")]
    public void SwitchToNormalsRendering()
    {
        Shader.EnableKeyword("_RENDER_NORMALS");
        Shader.DisableKeyword("_RENDER_DEPTH");
    }

    [ContextMenu("Switch To Base Rendering")]
    public void SwitchToBaseRendering()
    {
        Shader.DisableKeyword("_RENDER_NORMALS");
        Shader.DisableKeyword("_RENDER_DEPTH");
    }
}
