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

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"
            #include "Assets/Shaders/Misc/FoliageVertexManipulation.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;   // Object Space pozisyon
                float2 uv         : TEXCOORD0;
                float4 vertexColor : COLOR;     // Vertex paint maskesi
                float3 normalOS   : NORMAL;    // Object Space normal
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION; // Clip Space (GPU'nun beklediği)
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;    // World Space normal
                float3 worldPos    : TEXCOORD2;    // World Space pozisyon
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
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uvMain = IN.uv * _MainTexture_ST.xy + _MainTexture_ST.zw;
                float4 mainTex = SAMPLE_TEXTURE2D(_MainTexture, sampler_MainTexture, uvMain);

                // Alpha clip — yaprağın kenarı
                clip(mainTex.a - _Cutoff);

                float2 uvEmission = IN.uv * _Emission_ST.xy + _Emission_ST.zw;
                float4 emission = SAMPLE_TEXTURE2D(_Emission, sampler_Emission, uvEmission);

                float4 finalColor = mainTex * _ColorTint + emission * _EmissionColor;
                finalColor.a = 1.0;
                
                half3 diffuse = ShadowlessCelLighting(IN.normalWS, UNITY_MATRIX_M._m03_m13_m23, 
                    IN.worldPos, GetMainLight());
                finalColor.rgb *= diffuse;
                return finalColor;
            }
            ENDHLSL
        }
    }
}
