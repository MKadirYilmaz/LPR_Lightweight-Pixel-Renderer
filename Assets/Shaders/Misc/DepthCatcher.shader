Shader "Custom/DepthCatcher"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        Pass
        {
            ZWrite Off ZTest Always Blend Off Cull Off
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Engine auto generated depth texture
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes IN) {
                Varyings OUT;
                OUT.uv = float2((IN.vertexID << 1) & 2, IN.vertexID & 2);
                OUT.positionHCS = float4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                OUT.uv.y = 1.0 - OUT.uv.y;
                #endif
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target {
                // Read the depth value from the camera depth texture. The depth is stored in the red channel.
                float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, IN.uv).r;
                return half4(rawDepth, 0, 0, 1);
            }
            ENDHLSL
        }
    }
}