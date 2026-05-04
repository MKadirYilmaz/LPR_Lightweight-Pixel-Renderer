Shader "Custom/PackedDeferredOpaquePP"
{
    Properties
    {
            
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _DEFERRED_SHADING
            #pragma multi_compile _ _CUSTOM_LIGHTING

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"

            
            FRAMEBUFFER_INPUT_UINT(0);
            FRAMEBUFFER_INPUT_UINT(1);
            
            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv   : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv  = GetFullScreenTriangleTexCoord(input.vertexID);

                return output;
            }
            
            half4 CalculateLightPass(uint shaderID, float3 worldPos, float3 normal, half3 color)
            {
                float4 shadowCoord = TransformWorldToShadowCoord(worldPos); 
                Light light = GetMainLight(shadowCoord);
                switch (shaderID)
                {
                case 0u:
                    return half4(color * CelLighting(normal, light), 1.0);
                case 1u:
                    return half4(color * GrassLighting(light), 0.0);
                default:
                    return half4(0.0, 0.0, 0.0, 0.0);
                }
            }
            
            float3 GetSafeGBufferData(uint package, out float depth)
            {
                if (package == 0u)
                {
                    discard;
                }
                return UnpackDepthNormalGBuffer(package, depth);
            }
            
            half4 frag(Varyings IN) : SV_Target
            {
                uint colorPackage = LOAD_FRAMEBUFFER_INPUT(0, IN.positionCS.xy).x;
                uint gBufferPackage = LOAD_FRAMEBUFFER_INPUT(1, IN.positionCS.xy).x;
                
                uint shaderID;
                half3 color = UnpackLightPassBuffer(colorPackage, shaderID);
                float depth;
                float3 normal = GetSafeGBufferData(gBufferPackage, depth);
                
                float rawDeviceDepth = ConvertCustomDepthToRawDepth(depth);
                
                float3 worldPos = GetWorldPositionFromDepth(rawDeviceDepth, IN.uv);
                half4 finalColor = half4(color, 1.0);
                #if defined(_CUSTOM_LIGHTING)
                    finalColor = CalculateLightPass(shaderID, worldPos, normal, color);
                #else
                    half3 albedo = finalColor.rgb;
                    half metallic = 0.0;
                    half smoothness = 0.0;
                    half alpha = 1.0;
            
                    BRDFData brdfData;
                    InitializeBRDFData(albedo, metallic, 0, smoothness, alpha, brdfData);
            
                    half3 viewDirectionWS = GetWorldSpaceNormalizeViewDir(worldPos);
                    half3 normalWS = normalize(normal);
            
                    float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
                    Light light = GetMainLight(shadowCoord);
                    light.distanceAttenuation = 1.0; // Somehow the distance attenuation is not working correctly in this context, so we set it to 1.0 to avoid darkening the result.
            
                    half3 pbrLighting = LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
                    half3 bakedGI = SampleSH(normalWS);
                    half3 ambientLighting = GlobalIllumination(brdfData, bakedGI, 1.0, normalWS, viewDirectionWS);
            
                    finalColor.rgb = pbrLighting + ambientLighting;
                #endif
                
                finalColor.rgb = ApplyFog(finalColor.rgb, depth);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
