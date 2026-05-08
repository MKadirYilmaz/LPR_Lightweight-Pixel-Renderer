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
            #pragma multi_compile _ _CUSTOM_LIGHTING

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"

            
            FRAMEBUFFER_INPUT_UINT(0);
            FRAMEBUFFER_INPUT_UINT(1);
            
            uniform int _LightCount;
            uniform half4 _LightPositions[32];
            uniform half3 _LightColors[32];
            
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
            
            half3 CalculateLightPass(uint shaderID, float3 worldPos, float3 normal, Light light)
            {
                switch (shaderID)
                {
                case 0u:
                    return CelLighting(normal, light);
                case 1u:
                    return GrassLighting(light);
                case 2u: // PBR Lighting
                    half3 albedo = half3(1.0, 1.0, 1.0);
                    half metallic = 0.0;
                    half smoothness = 0.3;
                    half alpha = 1.0;
            
                    BRDFData brdfData = (BRDFData)0;
                    InitializeBRDFData(albedo, metallic, 0, smoothness, alpha, brdfData);
            
                    half3 viewDirectionWS = GetWorldSpaceNormalizeViewDir(worldPos);
                    half3 normalWS = normalize(normal);
            
                    half3 pbrLighting = LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
                    half3 bakedGI = SampleSH(normalWS);
                    half3 ambientLighting = GlobalIllumination(brdfData, bakedGI, 1.0, normalWS, viewDirectionWS);
                    return half3(pbrLighting + ambientLighting);
                default:
                    return half3(0.0, 0.0, 0.0);
                }
            }
            
            half3 CalculateAdditionalLights(uint shaderID, float3 worldPos, float3 normal)
            {
                half3 totalAdditionalLight = half3(0.0, 0.0, 0.0);
                
                for (int i = 0; i < _LightCount; i++)
                {
                    float3 lightPos = _LightPositions[i].xyz;
                    float lightRange = _LightPositions[i].w;
                    half3 lightColor = _LightColors[i].rgb;

                    float3 lightDir = lightPos - worldPos;
                    float distance = length(lightDir);

                    float attenuation = 1.0 - max(distance, 0.001) / lightRange;
                    if (attenuation <= 0.0) continue;
                    
                    attenuation *= attenuation;
                    
                    lightDir = normalize(lightDir);
                    
                    Light light;
                    light.direction = lightDir;
                    light.color = lightColor * attenuation;
                    light.distanceAttenuation = attenuation;
                    light.shadowAttenuation = 1.0;
                    light.layerMask = 0xFF;
                    
                    totalAdditionalLight += CalculateLightPass(shaderID, worldPos, normal, light);
                    
                }

                return totalAdditionalLight;
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
                
                float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
                Light light = GetMainLight(shadowCoord);
                
                light.distanceAttenuation = 1.0;
                
                half3 mainLightDiffuse = CalculateLightPass(shaderID, worldPos, normal, light);
                half3 additionalLightDiffuse = CalculateAdditionalLights(shaderID, worldPos, normal);
                
                color.rgb *= mainLightDiffuse + additionalLightDiffuse;
                half alpha = (shaderID == 1u) ? 0.0 : 1.0; // Outline removal for grass shader
                
                
                color.rgb = ApplyFog(color.rgb, depth);
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
}
