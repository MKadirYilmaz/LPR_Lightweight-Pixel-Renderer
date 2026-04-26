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
        }

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
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1; 
                float4 worldPos    : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
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
                
                UNITY_SETUP_INSTANCE_ID(IN); 
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                
                float offset = VertexColorWindOffset(IN.positionOS, IN.vertexColor, half3(_Small_WindSpeed, _Small_WindAmount, _Small_Frequency), 
                    half3(_Big_WindSpeed, _Big_WindAmount, _Big_Frequency));
                
                IN.positionOS.x += offset;

                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.worldPos.xyz = TransformObjectToWorld(IN.positionOS.xyz);
                
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.worldPos.w = -vertexInputs.positionVS.z;
                
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
                return finalColor;
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
                UNITY_SETUP_INSTANCE_ID(IN);
                #if defined(_USE_UNITY_PBR_LIT)
                    
                    SurfaceData surfaceData = (SurfaceData)0;
                    float2 uvMain = IN.uv * _MainTexture_ST.xy + _MainTexture_ST.zw;
                    float4 mainTex = SAMPLE_TEXTURE2D(_MainTexture, sampler_MainTexture, uvMain);

                    // Apply alpha cutoff
                    clip(mainTex.a - _Cutoff);

                    float2 uvEmission = IN.uv * _Emission_ST.xy + _Emission_ST.zw;
                    float4 emission = SAMPLE_TEXTURE2D(_Emission, sampler_Emission, uvEmission);

                    float4 texColor = mainTex * _ColorTint + emission * _EmissionColor;
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
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 finalColor = fragmentCalculation(IN);
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 fragPos = IN.worldPos.xyz;
                half3 modifiedNormal = NormalSpherelize(IN.normalWS, objectWorldPos, fragPos);
                return PackRGBNormal(finalColor.rgb, modifiedNormal, 1);
                
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
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct VaryingsShadow {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            float3 _LightDirection;

            VaryingsShadow vertShadow(AttributesShadow IN) {
                VaryingsShadow OUT;
                
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                float offset = VertexColorWindOffset(IN.positionOS, IN.vertexColor, half3(_Small_WindSpeed, _Small_WindAmount, _Small_Frequency), 
                    half3(_Big_WindSpeed, _Big_WindAmount, _Big_Frequency));
                
                IN.positionOS.x += offset;
                
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                // Apply shadow bias to world position to prevent shadow acne and peter-panning
                OUT.positionHCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, _LightDirection)
                );
                OUT.uv = IN.uv;
                // Depth clamp
                #if UNITY_REVERSED_Z
                    OUT.positionHCS.z = min(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    OUT.positionHCS.z = max(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                return OUT;
            }

            half4 fragShadow(VaryingsShadow IN) : SV_Target {
                UNITY_SETUP_INSTANCE_ID(IN);
                float2 uvMain = IN.uv * _MainTexture_ST.xy + _MainTexture_ST.zw;
                float alpha = SAMPLE_TEXTURE2D(_MainTexture, sampler_MainTexture, uvMain).a;
                clip(alpha - _Cutoff);
                
                return 0;
            }

            ENDHLSL
        }
    }
}
