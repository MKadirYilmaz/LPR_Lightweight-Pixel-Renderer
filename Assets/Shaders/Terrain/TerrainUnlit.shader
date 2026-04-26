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

            half4 fragmentCalculation(Varyings IN)
            {
                half4 control = SAMPLE_TEXTURE2D(_Control, sampler_Control, IN.uvControl); // R = Splat0, G = Splat1, B = Splat2, A = Splat3
                
                half4 splat0 = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, IN.uvSplat0_1.xy);
                half4 splat1 = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat1, IN.uvSplat0_1.zw);
                half4 splat2 = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat2, IN.uvSplat2_3.xy);
                half4 splat3 = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat3, IN.uvSplat2_3.zw);
                
                half4 terrainColor = control.r * splat0 + control.g * splat1 + control.b * splat2 + control.a * splat3;
                return terrainColor;
            }
        
        ENDHLSL

        Pass
        {
            Name "LPRForward"
            Tags { "LightMode" = "LPRForward" }
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _USE_UNITY_PBR_LIT

            half4 frag(Varyings IN) : SV_Target
            {
                #if defined(_USE_UNITY_PBR_LIT)
                    
                    SurfaceData surfaceData = (SurfaceData)0;
                
                    half4 control = SAMPLE_TEXTURE2D(_Control, sampler_Control, IN.uvControl); // R = Splat0, G = Splat1, B = Splat2, A = Splat3
                
                    half4 splat0 = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, IN.uvSplat0_1.xy);
                    half4 splat1 = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat1, IN.uvSplat0_1.zw);
                    half4 splat2 = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat2, IN.uvSplat2_3.xy);
                    half4 splat3 = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat3, IN.uvSplat2_3.zw);
                    
                    half4 texColor = control.r * splat0 + control.g * splat1 + control.b * splat2 + control.a * splat3;
                
                    surfaceData.albedo = texColor.rgb;
                    surfaceData.alpha = texColor.a;
                    surfaceData.metallic = 0.0;     
                    surfaceData.smoothness = 0.0;   
                    surfaceData.normalTS = float3(0, 0, 1);
                    surfaceData.emission = 0;
                    surfaceData.occlusion = 1;
                
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.worldPos.xyz;
                    inputData.normalWS = length(IN.normalWS) > 0.001 ? normalize(IN.normalWS) : float3(0, 1, 0);
                    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.worldPos.xyz);
                    inputData.shadowCoord = TransformWorldToShadowCoord(IN.worldPos.xyz);
                    inputData.bakedGI = SampleSH(inputData.normalWS);
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
                    inputData.shadowMask = half4(1, 1, 1, 1);
                
                    return UniversalFragmentPBR(inputData, surfaceData);
                #else
                    return fragmentCalculation(IN);
                #endif
            }
            ENDHLSL
        }

        Pass
        {
            Name "LPRPackedForward"
            Tags { "LightMode" = "LPRPackedForward" }
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            uint frag(Varyings IN) : SV_Target
            {
                half4 terrainColor = fragmentCalculation(IN);
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 fragPos = IN.worldPos.xyz;
                half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                return PackRGBNormal(terrainColor.rgb, modifiedNormal, 1);
            }
            ENDHLSL
        }
    }
}
