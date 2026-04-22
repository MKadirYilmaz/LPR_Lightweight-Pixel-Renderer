#ifndef FOG_COLOR
    #define FOG_COLOR half3(0.7, 0.7, 0.8) // Default fog color
#endif
#ifndef FOG_FALLOFF
    #define FOG_FALLOFF half(5.0)
#endif

half3 ApplyFog(half3 diffuseColor, half depth)
{
    half fog = pow(saturate(depth), FOG_FALLOFF);
    return lerp(diffuseColor, FOG_COLOR, fog);
}