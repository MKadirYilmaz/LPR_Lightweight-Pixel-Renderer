Shader "Custom/UnlitTransparencyShader"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 0.5)
        _MainTex("Base Map (RGB) Alpha (A)", 2D) = "white" {}
    }

    SubShader
    {
        
        Tags 
        { 
            "RenderType" = "Transparent" 
            "Queue" = "Transparent" 
            "RenderPipeline" = "UniversalPipeline" 
        }

        Pass
        {
            Name "LPRForward"
            Tags { "LightMode" = "LPRForward" }
            
            // Depth write off
            ZWrite Off 
            
            // Blending
            Blend SrcAlpha OneMinusSrcAlpha, Zero OneMinusSrcAlpha
            
            // Do not write to the alpha channel of the render target, since we're only interested in RGB for this shader.
            //ColorMask RGB 
            

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS  : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _MainTex_ST;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                half4 finalColor = texColor * _BaseColor;
                
                return finalColor;
            }
            ENDHLSL
        }
    }
}