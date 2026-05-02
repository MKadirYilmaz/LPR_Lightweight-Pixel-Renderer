Shader "Custom/DecoderPostProcess"
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

            
            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };
            
            FRAMEBUFFER_INPUT_UINT(0);
            FRAMEBUFFER_INPUT_UINT(1);
            
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
            
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                OUT.positionHCS = GetFullScreenTriangleVertexPosition(IN.vertexID);
                OUT.uv  = GetFullScreenTriangleTexCoord(IN.vertexID);
                
                #if UNITY_UV_STARTS_AT_TOP
                    if (_ProjectionParams.x > 0.0)
                    {
                        OUT.uv.y = 1.0 - OUT.uv.y;
                    }
                #endif
                
                return OUT;
            }
            
            float3 GetSafeGBufferData(uint package, out float depth)
            {
                if (package == 0)
                {
                    discard;
                }
                return UnpackDepthNormalGBuffer(package, depth);
            }
            
            half4 frag(Varyings IN) : SV_Target
            {
                uint colorPackage = LOAD_FRAMEBUFFER_INPUT(0, IN.positionHCS.xy).x;
                uint gBufferPackage = LOAD_FRAMEBUFFER_INPUT(1, IN.positionHCS.xy).x;
                
                uint shaderID;
                half3 color = UnpackLightPassBuffer(colorPackage, shaderID);
                float depth;
                float3 normal = GetSafeGBufferData(gBufferPackage, depth);
                float rawDepth = pow(depth, 1.0 / DEPTH_POW);
                
                float zEye = rawDepth * (_ProjectionParams.z - _ProjectionParams.y) + _ProjectionParams.y;
                
                float pDepth = ((1.0 / zEye) - _ZBufferParams.w) / _ZBufferParams.z;
                float oDepth = 1.0 - rawDepth;
                float uDepth = lerp(pDepth, oDepth, unity_OrthoParams.w);
                
                float2 computeUV = IN.uv;
                computeUV.y = 1.0 - computeUV.y;
                // UV problem between perspective view and orthographic view
                computeUV = lerp(IN.uv, computeUV, unity_OrthoParams.w);
                float3 worldPos = ComputeWorldSpacePosition(computeUV, uDepth, UNITY_MATRIX_I_VP);
                half4 finalColor = half4(color, 1.0);
                #if defined(_DEFERRED_SHADING)
                    
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
                #endif
                finalColor.rgb = ApplyFog(finalColor.rgb, depth);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
