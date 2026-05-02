Shader "Custom/UnlitTransparencyShader"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 0.5)
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
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS  : SV_POSITION;
                float zEye          : TEXCOORD0;
            };
            
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.zEye = -vertexInputs.positionVS.z;
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = _BaseColor;
                
                color.rgb = ApplyFog(color.rgb, GetDepthValue(IN.zEye, _ProjectionParams.y, _ProjectionParams.z));
                
                return color;
            }
            ENDHLSL
        }
    }
}