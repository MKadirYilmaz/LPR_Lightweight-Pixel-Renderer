Shader "Custom/PackedForwardOpaquePP"
{
    Properties
    {
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
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"

            FRAMEBUFFER_INPUT_UINT(0);
            
            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv   : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv  = GetFullScreenTriangleTexCoord(input.vertexID);

                return output;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                uint outline;
                float4 color = UnpackRGBA(LOAD_FRAMEBUFFER_INPUT(0, IN.positionCS), outline);
                float depth = color.a;
                
                color.rgb = ApplyFog(color.rgb, depth);
                return half4(color.rgb, (half)outline);
            }
            ENDHLSL
        }
    }
}
