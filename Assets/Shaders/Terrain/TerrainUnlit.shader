Shader "Terrain/TerrainUnlit"
{
    Properties
    {
        _Control ("Control Map", 2D) = "white" {}
        _Splat0 ("Splat 0", 2D) = "white" {}
        _Splat1 ("Splat 1", 2D) = "white" {}
        _Splat2 ("Splat 2", 2D) = "white" {}
        _Splat3 ("Splat 3", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "TerrainCompatible" = "True" }

        HLSLINCLUDE
        
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _DEFERRED_SHADING
            #pragma multi_compile _ _CUSTOM_LIGHTING

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uvControl : TEXCOORD0;
                float4 uvSplat0_1 : TEXCOORD1;
                float4 uvSplat2_3 : TEXCOORD2;
                float4 worldPos : TEXCOORD3;
                float3 normalWS : TEXCOORD4;
            };

            TEXTURE2D(_Control); SAMPLER(sampler_Control);
            TEXTURE2D(_Splat0);  SAMPLER(sampler_Splat0);
            TEXTURE2D(_Splat1);  SAMPLER(sampler_Splat1);
            TEXTURE2D(_Splat2);  SAMPLER(sampler_Splat2);
            TEXTURE2D(_Splat3);  SAMPLER(sampler_Splat3);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _Control_ST;
                float4 _Splat0_ST;
                float4 _Splat1_ST;
                float4 _Splat2_ST;
                float4 _Splat3_ST;
            CBUFFER_END
            

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.worldPos.xyz = TransformObjectToWorld(IN.positionOS.xyz);
                
                OUT.uvControl = TRANSFORM_TEX(IN.uv, _Control);
                
                OUT.uvSplat0_1 = float4(TRANSFORM_TEX(IN.uv, _Splat0), TRANSFORM_TEX(IN.uv, _Splat1));
                OUT.uvSplat2_3 = float4(TRANSFORM_TEX(IN.uv, _Splat2), TRANSFORM_TEX(IN.uv, _Splat3));
                
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.worldPos.w = -vertexInputs.positionVS.z;
                
                return OUT;
            }

            half4 TerrainColor(Varyings IN)
            {
                half4 control = SAMPLE_TEXTURE2D(_Control, sampler_Control, IN.uvControl); // R = Splat0, G = Splat1, B = Splat2, A = Splat3
                
                half4 splat0 = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, IN.uvSplat0_1.xy);
                half4 splat1 = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat1, IN.uvSplat0_1.zw);
                half4 splat2 = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat2, IN.uvSplat2_3.xy);
                half4 splat3 = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat3, IN.uvSplat2_3.zw);
                
                half4 terrainColor = control.r * splat0 + control.g * splat1 + control.b * splat2 + control.a * splat3;
                return terrainColor;
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
            float4 color = TerrainColor(IN);
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
                OUT.color0 = TerrainColor(IN);
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
                half4 color = TerrainColor(IN);
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
    }
}
