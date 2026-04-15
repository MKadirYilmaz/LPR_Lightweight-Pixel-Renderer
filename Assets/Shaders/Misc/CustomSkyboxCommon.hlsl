#ifndef SkyColor
    #define SkyColor half3(0.5, 0.7, 1.0) // Default sky color (light blue)
#endif

half4 GetSkyboxColor(float3 rayDirection)
{
    // Simple gradient skybox based on the y component of the ray direction
    float t = saturate(rayDirection.y); // t will be 0 at the horizon (y=0) and 1 at the zenith (y=1)
    half3 skyColor = lerp(SkyColor * 0.05, SkyColor, t); // Darker at the horizon, lighter at the zenith
    return half4(skyColor, 1.0);
}