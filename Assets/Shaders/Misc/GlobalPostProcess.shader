Shader "Custom/GlobalPostProcess"
{
    Properties
    {
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always
        
        Pass
        {
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            half4 frag(Varyings IN) : SV_Target
            {
                #if UNITY_UV_STARTS_AT_TOP
                if (_ProjectionParams.x > 0.0)
                {
                    IN.texcoord.y = 1.0 - IN.texcoord.y;
                }
                #endif
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, IN.texcoord);
                return color;
            }
            ENDHLSL
        }
    }
}
