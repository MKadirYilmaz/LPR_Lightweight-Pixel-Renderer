Shader "Custom/DefaultDeferredGlobalPP"
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

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            
            TEXTURE2D(_BlitTexture);
            TEXTURE2D(_GBuffer0);
            TEXTURE2D(_LPR_DepthTexture);
            
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
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                float2 texelSize = 1.0 / float2(rtWidth, rtHeight);
                
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, IN.uv);
                half4 gBuffer = SAMPLE_TEXTURE2D(_GBuffer0, sampler_PointClamp, IN.uv);
                
                int shaderID = round(gBuffer.a * 10);
                float3 normal = gBuffer.rgb;
                
                half depthCenter = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv).r;
                
                float pDepthCenter = Linear01Depth(depthCenter, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - depthCenter, unity_OrthoParams.w);
                depthCenter = pow(uDepthCenter, DEPTH_POW);
                
                return half4(color.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
