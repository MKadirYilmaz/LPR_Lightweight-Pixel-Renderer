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
            
            half4 ForwardSurfaceLighting(Varyings IN)
            {
                #if defined(_CUSTOM_LIGHTING)
                    half4 color = TerrainColor(IN);
                    float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                    float3 fragPos = IN.worldPos.xyz;
                    
                    half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                    
                    float4 shadowCoord = TransformWorldToShadowCoord(fragPos);
                    Light light = GetMainLight(shadowCoord);
                
                    return half4(color.rgb * CelLighting(modifiedNormal, light), color.a);
                #else
                    SurfaceData surfaceData = (SurfaceData)0;
                    half4 texColor = TerrainColor(IN);
                    surfaceData.albedo = texColor.rgb;
                    surfaceData.alpha = texColor.a;
                    surfaceData.metallic = 0.0;     
                    surfaceData.smoothness = 0.0;   
                    surfaceData.normalTS = float3(0, 0, 1);
                    surfaceData.emission = 0;
                    surfaceData.occlusion = 1;
                
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.worldPos.xyz;
                    inputData.normalWS = normalize(IN.normalWS);
                    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.worldPos.xyz);
                    inputData.shadowCoord = TransformWorldToShadowCoord(IN.worldPos.xyz);
                    inputData.bakedGI = SampleSH(inputData.normalWS);
                    inputData.shadowMask = half4(1, 1, 1, 1);

                    return UniversalFragmentPBR(inputData, surfaceData);
                #endif
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
                return ForwardSurfaceLighting(IN);
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
                half4 color = ForwardSurfaceLighting(IN);
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
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 fragPos = IN.worldPos.xyz;
                half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                
                half shaderID = 0.0;
                OUT.color1 = half4(modifiedNormal, shaderID);
                
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
                OUT.color0 = PackLightPassBuffer(color.rgb, 0);
                
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 fragPos = IN.worldPos.xyz;
                half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                OUT.color1 = PackDepthNormalGBuffer(GetDepthValue(IN.worldPos.w, _ProjectionParams.y, _ProjectionParams.z), modifiedNormal);
                return OUT;
            }
            ENDHLSL
        }
    }
}
