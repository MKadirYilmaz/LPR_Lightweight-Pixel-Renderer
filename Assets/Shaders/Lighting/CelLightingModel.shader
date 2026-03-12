Shader "Custom/CelLightingModel"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _ShadowLight ("Shadow Light", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            half _ShadowLight;
            #define SHADOW_LIGHT _ShadowLight
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : NORMAL;
                half3 diffuse : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            float4 _BaseMap_ST;

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                
                float3 lightDir = GetMainLight().direction;
                float3 normal = OUT.normalWS;
                float3 objectWorldPos = UNITY_MATRIX_M._m03_m13_m23;
                float3 vertPos = TransformObjectToWorld(IN.positionOS.xyz);
                
                OUT.diffuse = ShadowlessCelLighting(normal, objectWorldPos, vertPos, GetMainLight());
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * half4(IN.diffuse, 1.0);
                
                return color;
            }
            ENDHLSL
        }
    }
}
