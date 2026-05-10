Shader "Custom/CelLightingModel"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        HLSLINCLUDE
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        #pragma multi_compile _ _ADDITIONAL_LIGHTS
        #pragma multi_compile _ _DEFERRED_SHADING
        #pragma multi_compile _ _CUSTOM_LIGHTING
        
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
        CBUFFER_END
        
        #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
        #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"

        struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; float3 normalOS : NORMAL; };
        struct Varyings { float4 positionHCS : SV_POSITION; float3 normalWS : NORMAL; float2 uv : TEXCOORD0; float4 worldPos : TEXCOORD1; };

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        Varyings vert(Attributes IN)
        {
            Varyings OUT;
            OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
            OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
            OUT.worldPos.xyz = TransformObjectToWorld(IN.positionOS.xyz);
            OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
            VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.worldPos.w = -vertexInputs.positionVS.z;
            return OUT;
        }
        
        half3 ForwardSurfaceLighting(Light light, float3 worldPos, float3 normal)
        {
            #if defined(_CUSTOM_LIGHTING)
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
            
                light.distanceAttenuation = pow(light.distanceAttenuation, 0.4);
                half3 modifiedNormal = NormalSpherelize(normal, objectWorldPos, worldPos);
            
                return CelLighting(modifiedNormal, light);
            #else
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
            #endif
        }
        
        half4 ForwardLightLoop(Varyings IN)
        {
            float4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
            half3 mainDiffuse = 0;
            half3 additionalDiffuse = 0;
            
            float4 shadowCoord = TransformWorldToShadowCoord(IN.worldPos.xyz);
            Light mainLight = GetMainLight(shadowCoord);
            mainDiffuse = ForwardSurfaceLighting(mainLight, IN.worldPos.xyz, IN.normalWS);
            
            int additionalLightCount = GetAdditionalLightsCount();
            
            for (int i = 0; i < additionalLightCount; i++)
            {
                Light additionalLight = GetAdditionalLight(i, IN.worldPos.xyz);
                additionalDiffuse += ForwardSurfaceLighting(additionalLight, IN.worldPos.xyz, IN.normalWS);
            }
            
            return half4(color.rgb * (mainDiffuse + additionalDiffuse), color.a);
            
        }
        
        ENDHLSL
        
        Pass
        {
            Name "LPRForward"
            Tags { "LightMode" = "LPRForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            half4 frag(Varyings IN) : SV_Target
            {
                return ForwardLightLoop(IN);
            }
            ENDHLSL
        }

        Pass
        {
            Name "LPRForwardPacked"
            Tags { "LightMode" = "LPRForwardPacked" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            uint frag(Varyings IN) : SV_Target
            {
                half4 color = ForwardLightLoop(IN);
                color.a = GetDepthValue(IN.worldPos.w, _ProjectionParams.y, _ProjectionParams.z);
                return PackRGBA(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "LPRDeferred"
            Tags { "LightMode" = "LPRDeferred" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct FragOutput
            {
                half4 color0 : SV_Target0;
                half4 color1 : SV_Target1;
            };
            
            FragOutput frag(Varyings IN) : SV_Target0
            {
                FragOutput OUT;
                OUT.color0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                #if defined(_CUSTOM_LIGHTING)
                    half shaderID = 0.0;
                    float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                    float3 fragPos = IN.worldPos.xyz;
                    half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                    OUT.color1 = half4(modifiedNormal, half(shaderID));
                #else
                    half shaderID = 0.2;
                    OUT.color1 = half4(IN.normalWS, shaderID);
                #endif
                
                
                return OUT;
            }
            ENDHLSL
        }

        Pass
        {
            Name "LPRDeferredPacked"
            Tags { "LightMode" = "LPRDeferredPacked" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            struct FragOutput
            {
                uint color0 : SV_Target0;
                uint color1 : SV_Target1;
            };

            FragOutput frag(Varyings IN)
            {
                FragOutput OUT;
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                #if defined(_CUSTOM_LIGHTING)
                    OUT.color0 = PackLightPassBuffer(color.rgb, 0);
                    float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                    float3 fragPos = IN.worldPos.xyz;
                    half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                    OUT.color1 = PackDepthNormalGBuffer(GetDepthValue(IN.worldPos.w, _ProjectionParams.y, _ProjectionParams.z), modifiedNormal);
                #else
                    OUT.color0 = PackLightPassBuffer(color.rgb, 2);
                    OUT.color1 = PackDepthNormalGBuffer(GetDepthValue(IN.worldPos.w, _ProjectionParams.y, _ProjectionParams.z), IN.normalWS);
                #endif
                
                return OUT;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0       // No color output, we only care about depth
            Cull Back

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            
            #pragma multi_compile_shadowcaster

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct AttributesShadow {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct VaryingsShadow {
                float4 positionHCS : SV_POSITION;
            };
            
            float3 _LightDirection;

            VaryingsShadow vertShadow(AttributesShadow IN) {
                VaryingsShadow OUT;

                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                // Apply shadow bias to world position to prevent shadow acne and peter-panning
                OUT.positionHCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, _LightDirection)
                );

                // Depth clamp
                #if UNITY_REVERSED_Z
                    OUT.positionHCS.z = min(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    OUT.positionHCS.z = max(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                return OUT;
            }

            half4 fragShadow(VaryingsShadow IN) : SV_Target {
                return 0;
            }

            ENDHLSL
        }
    }
}
