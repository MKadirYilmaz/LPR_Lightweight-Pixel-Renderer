#ifndef DEPTH_POW
    #define DEPTH_POW 1.5
#endif

#include "Assets/Shaders/Style/ColorQuantization.hlsl"

half GetDepthValue(float zEye, float near, float far)
{
    return pow(saturate((zEye - near) / (far - near)), DEPTH_POW);
}
static const uint BITS_H = 6;  // Hue
static const uint BITS_S = 4;  // Saturation
static const uint BITS_V = 5;  // Value
static const uint BITS_F = 1;  // Outline Flag

static const uint BITS_D = 32 - BITS_H - BITS_S - BITS_V - BITS_F; // Depth (remaining bits after allocating for H, S, V, and the outline flag)

static const uint MAX_H = (1u << BITS_H) - 1u; // Max integer value for Hue based on the number of bits allocated (e.g., 63 for 6 bits)
static const uint MAX_S = (1u << BITS_S) - 1u; // Max integer value for Saturation based on the number of bits allocated (e.g., 15 for 4 bits)
static const uint MAX_V = (1u << BITS_V) - 1u; // Max integer value for Value based on the number of bits allocated (e.g., 31 for 5 bits)
static const uint MAX_D = (1u << BITS_D) - 1u; // Max integer value for Depth based on the number of bits allocated (e.g., 1023 for 10 bits)

static const uint SHIFT_S = BITS_H;                            
static const uint SHIFT_V = BITS_H + BITS_S;                   
static const uint SHIFT_F = BITS_H + BITS_S + BITS_V;          
static const uint SHIFT_D = BITS_H + BITS_S + BITS_V + BITS_F;

static const float DARK_PROTECTION = 0.3; 

uint PackRGBA(half4 rgba, uint outlineFlag)
{
    float3 hsv = RGBtoHSV(rgba.rgb);
    
    float safeProtection = clamp(DARK_PROTECTION, 0.0, 0.99);
    float adjustedValue = pow(hsv.z, 1.0 - safeProtection);
    
    uint h = (uint)(saturate(hsv.x) * (float)MAX_H + 0.5);
    uint s = (uint)(saturate(hsv.y) * (float)MAX_S + 0.5);
    uint v = (uint)(saturate(adjustedValue) * (float)MAX_V + 0.5);
    
    uint f = outlineFlag & 1u; 
    uint d = (uint)(saturate(rgba.a) * (float)MAX_D + 0.5);
    
    uint packedData = (d << SHIFT_D) | (f << SHIFT_F) | (v << SHIFT_V) | (s << SHIFT_S) | h;
    return packedData;
}

float4 UnpackRGBA(uint packedData, out uint outlineFlag)
{
    uint h = packedData & MAX_H;
    uint s = (packedData >> SHIFT_S) & MAX_S;
    uint v = (packedData >> SHIFT_V) & MAX_V;
    
    outlineFlag = (packedData >> SHIFT_F) & 1u;
    uint d = (packedData >> SHIFT_D) & MAX_D;
    
    float3 hsv;
    hsv.x = (float)h / (float)MAX_H;
    hsv.y = (float)s / (float)MAX_S;
    float adjustedValue = (float)v / (float)MAX_V;
    
    float safeProtection = clamp(DARK_PROTECTION, 0.0, 0.99);
    hsv.z = pow(adjustedValue, 1.0 / (1.0 - safeProtection));
    
    float4 rgba;
    rgba.rgb = HSVtoRGB(hsv);
    rgba.a = (float)d / (float)MAX_D;
    
    return rgba;
}