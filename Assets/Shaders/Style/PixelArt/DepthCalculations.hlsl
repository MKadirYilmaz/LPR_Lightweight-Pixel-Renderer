#include "Assets/Shaders/Style/ColorQuantization.hlsl"

#ifndef DEPTH_POW
    #define DEPTH_POW 1.5
#endif

half GetDepthValue(float zEye, float near, float far)
{
    return pow(saturate((zEye - near) / (far - near)), DEPTH_POW);
}
static const uint BITS_H = 6;  // Hue
static const uint BITS_S = 4;  // Saturation
static const uint BITS_V = 5;  // Value
static const uint BITS_F = 1;  // Outline Flag

static const uint BITS_NX = 8; 
static const uint BITS_NY = 8;

static const uint BITS_D = 32 - BITS_H - BITS_S - BITS_V - BITS_F; // Depth (remaining bits after allocating for H, S, V, and the outline flag)

static const uint MAX_H = (1u << BITS_H) - 1u; // Max integer value for Hue based on the number of bits allocated (e.g., 63 for 6 bits)
static const uint MAX_S = (1u << BITS_S) - 1u; // Max integer value for Saturation based on the number of bits allocated (e.g., 15 for 4 bits)
static const uint MAX_V = (1u << BITS_V) - 1u; // Max integer value for Value based on the number of bits allocated (e.g., 31 for 5 bits)
static const uint MAX_D = (1u << BITS_D) - 1u; // Max integer value for Depth based on the number of bits allocated (e.g., 1023 for 10 bits)

static const uint MAX_NX = (1u << BITS_NX) - 1u; // 255
static const uint MAX_NY = (1u << BITS_NY) - 1u; // 255

static const uint SHIFT_S = BITS_H;                            
static const uint SHIFT_V = BITS_H + BITS_S;                   
static const uint SHIFT_F = BITS_H + BITS_S + BITS_V;          
static const uint SHIFT_D = BITS_H + BITS_S + BITS_V + BITS_F;

static const uint SHIFT_NX = BITS_H + BITS_S + BITS_V + BITS_F;
static const uint SHIFT_NY = BITS_H + BITS_S + BITS_V + BITS_F + BITS_NX;

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

// --- PAKETLEME (ENCODE) ---
uint PackRGBNormal(half3 rgb, half3 normal, uint outlineFlag)
{
    float3 hsv = RGBtoHSV(rgb);
    
    // Optimizasyon: clamp yerine max kullanmak daha ucuzdur (Dark protection negatif olamayacağı için)
    float safeProtection = max(DARK_PROTECTION, 0.0);
    float adjustedValue = pow(hsv.z, 1.0 - safeProtection);
    
    // HSV ve Flag'i uint'e çevir
    uint h = (uint)(saturate(hsv.x) * (float)MAX_H + 0.5);
    uint s = (uint)(saturate(hsv.y) * (float)MAX_S + 0.5);
    uint v = (uint)(saturate(adjustedValue) * (float)MAX_V + 0.5);
    uint f = outlineFlag & 1u;
    
    // DÜZELTME 1: Normali -1..1 aralığından 0..1 aralığına GÜVENLİ taşı (Negative Uint Underflow engeli)
    // normal.xy * 0.5 + 0.5 işlemi -1'i 0 yapar, 1'i 1 yapar.
    float2 normUV = normal.xy * 0.5 + 0.5;
    
    // 0..1 aralığını 0..255 (MAX_NX) aralığına genişlet
    uint nX = (uint)(saturate(normUV.x) * (float)MAX_NX + 0.5);
    uint nY = (uint)(saturate(normUV.y) * (float)MAX_NY + 0.5);
    
    // DÜZELTME 2: Ayrı bit kaydırmalarıyla temiz paketleme
    uint packedData = (nY << SHIFT_NY) | (nX << SHIFT_NX) | (f << SHIFT_F) | (v << SHIFT_V) | (s << SHIFT_S) | h;
    
    return packedData;
}

half3 UnpackRGBNormal(uint packedData, out half3 normal, out uint outlineFlag)
{
    uint h = packedData & MAX_H;
    uint s = (packedData >> SHIFT_S) & MAX_S;
    uint v = (packedData >> SHIFT_V) & MAX_V;
    
    outlineFlag = (packedData >> SHIFT_F) & 1u;
    
    float3 hsv;
    hsv.x = (float)h / (float)MAX_H;
    hsv.y = (float)s / (float)MAX_S;
    float adjustedValue = (float)v / (float)MAX_V;
    
    float safeProtection = clamp(DARK_PROTECTION, 0.0, 0.99);
    hsv.z = pow(adjustedValue, 1.0 / (1.0 - safeProtection));
    
    uint nX_uint = (packedData >> SHIFT_NX) & MAX_NX;
    uint nY_uint = (packedData >> SHIFT_NY) & MAX_NY;
    
    float2 normUV;
    normUV.x = (float)nX_uint / (float)MAX_NX;
    normUV.y = (float)nY_uint / (float)MAX_NY;
    
    normal.x = normUV.x * 2.0 - 1.0;
    normal.y = normUV.y * 2.0 - 1.0;
    
    float xySqr = normal.x * normal.x + normal.y * normal.y;
    normal.z = sqrt(1.0 - saturate(xySqr));
    normal = normalize(normal);
    
    return HSVtoRGB(hsv);
}

half3 UnpackRGB(uint packedData, out uint outlineFlag)
{
    uint h = packedData & MAX_H;
    uint s = (packedData >> SHIFT_S) & MAX_S;
    uint v = (packedData >> SHIFT_V) & MAX_V;
    
    outlineFlag = (packedData >> SHIFT_F) & 1u;
    
    float3 hsv;
    hsv.x = (float)h / (float)MAX_H;
    hsv.y = (float)s / (float)MAX_S;
    float adjustedValue = (float)v / (float)MAX_V;
    
    float safeProtection = clamp(DARK_PROTECTION, 0.0, 0.99);
    hsv.z = pow(adjustedValue, 1.0 / (1.0 - safeProtection));
    
    return HSVtoRGB(hsv);
}

// --- PAKET AÇMA (DECODE) ---
half3 UnpackNormal(uint packedData)
{
    // 1. Bitleri güvenli bir şekilde maskeleyip ayıkla
    uint nX_uint = (packedData >> SHIFT_NX) & MAX_NX;
    uint nY_uint = (packedData >> SHIFT_NY) & MAX_NY;
    
    // 2. Uint'i 0.0 ile 1.0 arasına çevir
    float2 normUV;
    normUV.x = (float)nX_uint / (float)MAX_NX;
    normUV.y = (float)nY_uint / (float)MAX_NY;
    
    // 3. 0.0..1.0 aralığını gerçek normal olan -1.0..1.0 aralığına geri çevir
    half3 normal;
    normal.x = normUV.x * 2.0 - 1.0;
    normal.y = normUV.y * 2.0 - 1.0;
    
    // 4. Z'yi yeniden oluştur (X ve Y'nin kareleri toplamı 1'den büyük olamaz, ufak hataları engellemek için saturate kullanıyoruz)
    float xySqr = normal.x * normal.x + normal.y * normal.y;
    normal.z = sqrt(1.0 - saturate(xySqr));
    
    // Opsiyonel: Eğer Z'nin her zaman kameraya doğru (pozitif) baktığını varsayıyorsak bu yeterlidir.
    // Eğer geriye bakan yüzeyleri de okuyorsak Z işareti her zaman pozitif çıkacaktır (hata).
    
    return normalize(normal); // Hassasiyet kaybını gidermek için normalize et
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

float UnpackDepth(uint packedData)
{
    uint d = (packedData >> SHIFT_D) & MAX_D;
    return (float)d / (float)MAX_D;
}