Shader "Custom/CelLightingModel"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _ShadowLight ("Shadow Light", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}

        HLSLINCLUDE
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        half _ShadowLight;
        #define SHADOW_LIGHT _ShadowLight
        #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
        #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"

        struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; float3 normalOS : NORMAL; };
        struct Varyings { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : NORMAL; float3 worldPos : TEXCOORD1; float zEye : TEXCOORD2; };

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        float4 _BaseMap_ST;

        Varyings vert(Attributes IN)
        {
            Varyings OUT;
            OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
            OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
            OUT.worldPos = TransformObjectToWorld(IN.positionOS.xyz);
            OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
            VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.zEye = -vertexInputs.positionVS.z;
            return OUT;
        }
        
        half4 CalculateSurfaceColor(Varyings IN)
        {
            half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
            
            float3 normal = IN.normalWS;
            float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
            float3 fragPos = IN.worldPos;
            float4 shadowCoord = TransformWorldToShadowCoord(IN.worldPos);
            
            half3 diffuse = CelLighting(normal, objectWorldPos, fragPos, GetMainLight(shadowCoord));
            color.rgb *= diffuse;
            color.a = GetDepthValue(IN.zEye, _ProjectionParams.y, _ProjectionParams.z);
            
            return color;
        }
        ENDHLSL
        
        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragEditor
            #pragma multi_compile _ _USE_UNITY_PBR_LIT

            half4 fragEditor(Varyings IN) : SV_Target
            {
                #if defined(_USE_UNITY_PBR_LIT)
                    
                    SurfaceData surfaceData = (SurfaceData)0;
                    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                    surfaceData.albedo = texColor.rgb;
                    surfaceData.alpha = texColor.a;
                    surfaceData.metallic = 0.0;     
                    surfaceData.smoothness = 0.0;   
                    surfaceData.normalTS = float3(0, 0, 1);
                    surfaceData.emission = 0;
                    surfaceData.occlusion = 1;
                
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.worldPos;
                    inputData.normalWS = normalize(IN.normalWS);
                    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.worldPos);
                    inputData.shadowCoord = TransformWorldToShadowCoord(IN.worldPos);
                    inputData.bakedGI = half3(0, 0, 0);
                    inputData.normalizedScreenSpaceUV = 0;
                    inputData.shadowMask = half4(1, 1, 1, 1);
                
                    return UniversalFragmentPBR(inputData, surfaceData);
                #else
                    return CalculateSurfaceColor(IN);
                #endif
                
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "PackedRenderingPass"
            Tags { "LightMode" = "PackedRenderingPass" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragGame

            uint fragGame(Varyings IN) : SV_Target0
            {
                half4 color = CalculateSurfaceColor(IN);
                
                return PackRGBA(color, 1); 
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
