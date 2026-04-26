
#ifndef SHADOW_OFFSET
    #define SHADOW_OFFSET 3.0
#endif

#ifndef CEL_COUNT
    #define CEL_COUNT 4.0
#endif

#ifndef SHADOW_LIGHT
    #define SHADOW_LIGHT 0.1
#endif

#ifndef NORMAL_SPHERELIZE_STRENGTH
    #define NORMAL_SPHERELIZE_STRENGTH 0.4
#endif

#ifndef AMBIENT_SKY_COLOR
    #define AMBIENT_SKY_COLOR unity_AmbientSky.rgb
#endif

#ifndef AMBIENT_GROUND_COLOR
    #define AMBIENT_GROUND_COLOR unity_AmbientGround.rgb
#endif

half3 AmbientLight(float3 normal)
{
    return lerp(AMBIENT_GROUND_COLOR, AMBIENT_SKY_COLOR, (normal.y + 1) * 0.5); // Interpolate between ground and sky colors based on the normal's y component
}

float3 NormalSpherelize(float3 normal, float3 objectPosWS, float3 VF_PosWS)
{
    float3 sphereNormal = normalize(VF_PosWS - objectPosWS); // Calculate the normal vector from the object's position to the vertex position in world space, creating a spherical normal effect
    return lerp(normal, sphereNormal, NORMAL_SPHERELIZE_STRENGTH); // Blend the original normal with the spherical normal based on the spherelization strength
}

half3 ShadowlessCelLighting(float3 normal, Light light)
{
    half NdotL = dot(normal, light.direction);
    half lX = pow((NdotL + 1.0) * 0.5, SHADOW_OFFSET); // Adjust the light intensity based on the angle between the normal and the light direction, and apply a power function to create a sharper transition between light and shadow
    half lightValue = round(lX * CEL_COUNT) / CEL_COUNT; // Quantize the light value to create a cel-shaded effect
    
    lightValue += SHADOW_LIGHT; // Add a small constant to ensure that even the darkest areas receive some light
    
    half3 diffuse = saturate(lightValue + AmbientLight(normal)); // Modulate the light value with the ambient light to ensure that shadows are not completely black and to add depth to the lighting
    
    return light.color * diffuse;
}

half3 CelLighting(half3 normal, Light light)
{
    half NdotL = dot(normal, light.direction);
    half lX = pow((NdotL + 1.0) * 0.5, SHADOW_OFFSET); // Adjust the light intensity based on the angle between the normal and the light direction, and apply a power function to create a sharper transition between light and shadow
    
    lX *= light.shadowAttenuation; // Modulate the light intensity by the light color and shadow factor to create a more dynamic lighting effect
    
    half lightValue = round(lX * CEL_COUNT) / CEL_COUNT; // Quantize the light value to create a cel-shaded effect
    lightValue += SHADOW_LIGHT; // Add a small constant to ensure that even the darkest areas receive some light
    
    half3 diffuse = saturate(lightValue + AmbientLight(normal)); // Modulate the light value with the ambient light to ensure that shadows are not completely black and to add depth to the lighting
    
    return light.color * diffuse;
}

half3 GrassLighting(Light light)
{
    return light.color * (light.shadowAttenuation + SHADOW_LIGHT);
}


