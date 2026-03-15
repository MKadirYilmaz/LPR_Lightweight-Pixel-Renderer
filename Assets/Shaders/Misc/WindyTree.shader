Shader "Custom/WindyTree"
{
    Properties
    {
        _MainTexture("Base Material", 2D) = "white" {}
        _ColorTint("Color Tint", Color) = (1,1,1,1)
        _Cutoff("Alpha Cutoff", Float) = 0.5

        _Emission("Emissive Mask", 2D) = "white" {}
        _EmissionColor("Emission Color", Color) = (0,0,0,0)
        
        _Big_WindSpeed("Trunk Wind Speed", Float) = 0.25
        _Big_WindAmount("Trunk Wind Strength", Float) = 0.5
        _Big_Frequency("Trunk Wind Frequency", Float) = 0.1
        
        _Small_WindSpeed("Leaf Wind Speed", Float) = 0.5
        _Small_WindAmount("Leaf Wind Strength", Float) = 0.25
        _Small_Frequency("Leaf Wind Frequency", Float) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "TransparentCutout"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
            "IgnoreProjector" = "True"
            "DisableBatching" = "True"
        }
        Cull Off

        HLSLINCLUDE
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
            #include "Assets/Shaders/Misc/FoliageVertexManipulation.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float4 vertexColor : COLOR;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1; 
                float3 worldPos    : TEXCOORD2;
                float zEye         : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTexture_ST;
                float4 _ColorTint;
                float  _Cutoff;

                float4 _Emission_ST;
                float4 _EmissionColor;

                float  _Big_WindSpeed;
                float  _Big_WindAmount;
                float  _Big_Frequency;

                float  _Small_WindSpeed;
                float  _Small_WindAmount;
                float  _Small_Frequency;
            CBUFFER_END

            TEXTURE2D(_MainTexture);       SAMPLER(sampler_MainTexture);
            TEXTURE2D(_Emission);          SAMPLER(sampler_Emission);
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                float offset = VertexColorWindOffset(IN.positionOS, IN.vertexColor, half3(_Small_WindSpeed, _Small_WindAmount, _Small_Frequency), 
                    half3(_Big_WindSpeed, _Big_WindAmount, _Big_Frequency));
                
                IN.positionOS.x += offset;

                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.zEye = -vertexInputs.positionVS.z;
                
                return OUT;
            }

            half4 fragmentCalculation(Varyings IN)
            {
                float2 uvMain = IN.uv * _MainTexture_ST.xy + _MainTexture_ST.zw;
                float4 mainTex = SAMPLE_TEXTURE2D(_MainTexture, sampler_MainTexture, uvMain);

                // Apply alpha cutoff
                clip(mainTex.a - _Cutoff);

                float2 uvEmission = IN.uv * _Emission_ST.xy + _Emission_ST.zw;
                float4 emission = SAMPLE_TEXTURE2D(_Emission, sampler_Emission, uvEmission);

                float4 finalColor = mainTex * _ColorTint + emission * _EmissionColor;
                float4 shadowCoord = TransformWorldToShadowCoord(IN.worldPos);
                
                half3 diffuse = CelLighting(IN.normalWS, UNITY_MATRIX_M._m03_m13_m23, 
                    IN.worldPos, GetMainLight(shadowCoord));
                finalColor.rgb *= diffuse;
                finalColor.a = GetDepthValue(IN.zEye, _ProjectionParams.y, _ProjectionParams.z);
                return finalColor;
            }
        ENDHLSL
        
        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            half4 frag(Varyings IN) : SV_Target
            {
                return fragmentCalculation(IN);
            }
            ENDHLSL
        }

        Pass
        {
            Name "KadirPackedPass"
            Tags { "LightMode" = "KadirPackedPass" }
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            uint frag(Varyings IN) : SV_Target
            {
                half4 finalColor = fragmentCalculation(IN);
                return PackRGBA(finalColor, 1);
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
                float4 vertexColor : COLOR;
            };

            struct VaryingsShadow {
                float4 positionHCS : SV_POSITION;
            };
            
            float3 _LightDirection;

            VaryingsShadow vertShadow(AttributesShadow IN) {
                VaryingsShadow OUT;

                float offset = VertexColorWindOffset(IN.positionOS, IN.vertexColor, half3(_Small_WindSpeed, _Small_WindAmount, _Small_Frequency), 
                    half3(_Big_WindSpeed, _Big_WindAmount, _Big_Frequency));
                
                IN.positionOS.x += offset;
                
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
