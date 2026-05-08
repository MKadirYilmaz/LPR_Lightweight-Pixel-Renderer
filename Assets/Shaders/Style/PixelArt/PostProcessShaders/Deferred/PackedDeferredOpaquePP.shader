Shader "Custom/PackedDeferredOpaquePP"
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

            
            Texture2D<uint> _BlitTexture;
            Texture2D<uint> _GBuffer0;
            
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
            
            float3 GetSafeNextGBufferData(uint package, out float depth)
            {
                if (package == 0u)
                {
                    depth = 1.0;
                    return float3(0.0, 1.0, 0.0);
                }
                return UnpackDepthNormalGBuffer(package, depth);
            }
            
            half4 frag(Varyings IN) : SV_Target
            {
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
                
                uint colorPackage = _BlitTexture.Load(int3(pixelCoord, 0));
                uint gBufferPackage = _GBuffer0.Load(int3(pixelCoord, 0));
                
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
                
                
                if (pixelCoord.x <= 0 || pixelCoord.x >= rtWidth - 1 || pixelCoord.y <= 0 || pixelCoord.y >= rtHeight - 1)
                {
                    return half4(ApplyFog(color.rgb, depth), 1.0);
                }
                
                float depthUp;
                float depthDown;
                float depthLeft;
                float depthRight;
                
                float3 normalUp     = GetSafeNextGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(0, 1), 0)), depthUp);
                float3 normalDown   = GetSafeNextGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(0, -1), 0)), depthDown);
                float3 normalLeft   = GetSafeNextGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(-1, 0), 0)), depthLeft);
                float3 normalRight  = GetSafeNextGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(1, 0), 0)), depthRight);
                
                // Calculate curvature using the second derivative (Laplacian) of the depth
                float curveX = (depthLeft + depthRight) - (2.0 * depth);
                float curveY = (depthUp + depthDown) - (2.0 * depth);
                
                // Determine if the pixel is an inner edge based on curvature thresholds
                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                half outline = (shaderID == 1u) ? 0.0 : 1.0; // Outline removal for grass shader
                color.rgb = lerp(color.rgb, half3(0.0, 0.0, 0.0), isInnerEdge * outline);
                
                color = ApplyFog(color, depth);
                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
}
