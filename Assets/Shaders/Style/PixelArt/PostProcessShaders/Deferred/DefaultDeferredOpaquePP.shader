Shader "Custom/DefaultDeferredOpaquePP"
{
    Properties
    {
        _NormalOutlineThreshold ("Normal Outline Threshold", Range(0.001, 0.2)) = 0.01
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

            TEXTURE2D(_BlitTexture);
            TEXTURE2D(_GBuffer0);
            TEXTURE2D(_LPR_DepthTexture);
            
            uniform int _LightCount;
            uniform half4 _LightPositions[32];
            uniform half3 _LightColors[32];
            
            float _NormalOutlineThreshold;
            
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
            
            half3 CalculateLightPass(int shaderID, float3 worldPos, float3 normal, Light light)
            {
                switch (shaderID)
                {
                case 0:
                    return CelLighting(normal, light);
                case 1:
                    return GrassLighting(light);
                case 2: // PBR Lighting
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
            
            half3 CalculateAdditionalLights(int shaderID, float3 worldPos, float3 normal)
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

            half4 frag(Varyings IN) : SV_Target
            {
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                float2 texelSize = 1.0 / float2(rtWidth, rtHeight);
                
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, IN.uv);
                half4 gBuffer = SAMPLE_TEXTURE2D(_GBuffer0, sampler_PointClamp, IN.uv);
                
                int shaderID = round(gBuffer.a * 10);
                float3 normal = gBuffer.rgb;
                
                half rawDepth = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv).r;
                
                float3 worldPos = GetWorldPositionFromDepth(rawDepth, IN.uv);
                
                float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
                Light light = GetMainLight(shadowCoord);
                
                light.distanceAttenuation = 1.0;
                
                half3 mainLightDiffuse = CalculateLightPass(shaderID, worldPos, normal, light);
                half3 additionalLightDiffuse = CalculateAdditionalLights(shaderID, worldPos, normal);
                
                color.rgb *= mainLightDiffuse + additionalLightDiffuse;
                color.a = (shaderID == 1) ? 0.0 : 1.0; // Outline removal for grass shader
                
                float pDepthCenter = Linear01Depth(rawDepth, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - rawDepth, unity_OrthoParams.w);
                float depthCenter = pow(uDepthCenter, DEPTH_POW);
                
                float depthUp     = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(0, 1) * texelSize).r;
                float depthDown   = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(0, -1) * texelSize).r;
                float depthLeft   = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(-1, 0) * texelSize).r;
                float depthRight  = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(1, 0) * texelSize).r;
                
                float pDepthUp     = Linear01Depth(depthUp, _ZBufferParams);
                float pDepthDown   = Linear01Depth(depthDown, _ZBufferParams);
                float pDepthLeft   = Linear01Depth(depthLeft, _ZBufferParams);
                float pDepthRight  = Linear01Depth(depthRight, _ZBufferParams);
                
                float uDepthUp    = lerp(pDepthUp, 1.0 - depthUp, unity_OrthoParams.w);
                float uDepthDown  = lerp(pDepthDown, 1.0 - depthDown, unity_OrthoParams.w);
                float uDepthLeft  = lerp(pDepthLeft, 1.0 - depthLeft, unity_OrthoParams.w);
                float uDepthRight = lerp(pDepthRight, 1.0 - depthRight, unity_OrthoParams.w);
                
                depthUp     = pow(uDepthUp, DEPTH_POW);
                depthDown   = pow(uDepthDown, DEPTH_POW);
                depthLeft   = pow(uDepthLeft, DEPTH_POW);
                depthRight  = pow(uDepthRight, DEPTH_POW);
                
                float curveX = (depthLeft + depthRight) - (2.0 * depthCenter);
                float curveY = (depthUp + depthDown) - (2.0 * depthCenter);

                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                color.rgb = lerp(color.rgb, half3(0.0, 0.0, 0.0), isInnerEdge * color.a);
                
                color.rgb = ApplyFog(color.rgb, depthCenter);
                return color;
            }
            ENDHLSL
        }
    }
}
