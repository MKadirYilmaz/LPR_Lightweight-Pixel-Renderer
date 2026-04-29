using UnityEngine;
using System.IO;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class TerrainColorBake : MonoBehaviour
{
    public Terrain terrain;
    public int textureSize = 1024;
    public string savePath = "Assets/Textures/TerrainColorBaked.png";

    [ContextMenu("Bake Terrain Color")]
    public void Bake()
    {
        Material terrainMat = terrain.materialTemplate;
        TerrainData td = terrain.terrainData;

        // Terrain'in splat texture'larını material'a manuel aktar
        TerrainLayer[] layers = td.terrainLayers;
        
        if (layers.Length > 0) terrainMat.SetTexture("_Splat0", layers[0].diffuseTexture);
        if (layers.Length > 1) terrainMat.SetTexture("_Splat1", layers[1].diffuseTexture);
        if (layers.Length > 2) terrainMat.SetTexture("_Splat2", layers[2].diffuseTexture);
        if (layers.Length > 3) terrainMat.SetTexture("_Splat3", layers[3].diffuseTexture);

        // Control map (splat map) — terrain'in ilk alphamap'i
        Texture2D[] alphaMaps = td.alphamapTextures;
        if (alphaMaps.Length > 0) terrainMat.SetTexture("_Control", alphaMaps[0]);

        // Tiling değerlerini de aktar
        if (layers.Length > 0) terrainMat.SetVector("_Splat0_ST", new Vector4(
            td.size.x / layers[0].tileSize.x,
            td.size.z / layers[0].tileSize.y,
            0, 0));
        if (layers.Length > 1) terrainMat.SetVector("_Splat1_ST", new Vector4(
            td.size.x / layers[1].tileSize.x,
            td.size.z / layers[1].tileSize.y,
            0, 0));
        if (layers.Length > 2) terrainMat.SetVector("_Splat2_ST", new Vector4(
            td.size.x / layers[2].tileSize.x,
            td.size.z / layers[2].tileSize.y,
            0, 0));
        if (layers.Length > 3) terrainMat.SetVector("_Splat3_ST", new Vector4(
            td.size.x / layers[3].tileSize.x,
            td.size.z / layers[3].tileSize.y,
            0, 0));

        // Render et
        RenderTexture rt = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.ARGB32);
        Graphics.Blit(null, rt, terrainMat, 0);

        // RT'yi PNG'ye kaydet
        RenderTexture.active = rt;
        Texture2D tex = new Texture2D(textureSize, textureSize, TextureFormat.RGBA32, false);
        tex.ReadPixels(new Rect(0, 0, textureSize, textureSize), 0, 0);
        tex.Apply();
        RenderTexture.active = null;

        byte[] bytes = tex.EncodeToPNG();
        File.WriteAllBytes(savePath, bytes);

        DestroyImmediate(tex);
        rt.Release();

        Debug.Log($"Bake tamamlandı: {savePath}");

        #if UNITY_EDITOR
            AssetDatabase.Refresh();
        #endif
    }
}