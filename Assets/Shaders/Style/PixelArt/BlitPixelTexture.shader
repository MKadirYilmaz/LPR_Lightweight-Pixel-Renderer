Shader "Custom/PixelPerfectBlit"
{
    Properties
    {
        _SourceTexture ("Source Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/Style/ColorQuantization.hlsl"

            TEXTURE2D(_SourceTexture);
            SAMPLER(sampler_point_clamp);

            CBUFFER_START(UnityPerMaterial)
                float4 _SourceTexture_ST;
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.uv = float2((IN.vertexID << 1) & 2, IN.vertexID & 2);
                OUT.positionHCS = float4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    OUT.uv.y = 1.0 - OUT.uv.y;
                #endif
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv);
                color.rgb = SmartQuantize(color, 32, 0.25, half3(0.85, 0.9, 0.75));
                return color;
            }

            ENDHLSL
        }
    }
}