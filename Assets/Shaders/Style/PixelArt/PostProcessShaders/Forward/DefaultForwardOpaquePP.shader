Shader "Custom/DefaultForwardOpaquePP"
{
    Properties
    {
        _NormalOutlineThreshold ("Normal Outline Threshold", Range(0.001, 0.2)) = 0.01
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
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            
            TEXTURE2D_X(_BlitTexture);
            TEXTURE2D(_LPR_DepthTexture);
            float _NormalOutlineThreshold;

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
                _LPR_DepthTexture.GetDimensions(rtWidth, rtHeight);
                float2 texelSize = 1.0 / float2(rtWidth, rtHeight);
                
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, IN.uv);
                color.rgb = SmartQuantize(color.rgb, 32.0, 0.3, half3(1.0, 1.0, 1.0));
                
                float depthCenter = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv);
                float pDepthCenter = Linear01Depth(depthCenter, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - depthCenter, unity_OrthoParams.w);
                depthCenter = pow(uDepthCenter, DEPTH_POW);
                
                float depthUp     = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(0, 1) * texelSize).r;
                float depthDown   = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(0, -1) * texelSize).r;
                float depthLeft   = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(-1, 0) * texelSize).r;
                float depthRight  = SAMPLE_TEXTURE2D(_LPR_DepthTexture, sampler_PointClamp, IN.uv + int2(1, 0) * texelSize).r;
                
                float pDepthUp     = Linear01Depth(depthUp, _ZBufferParams);
                float pDepthDown   = Linear01Depth(depthDown, _ZBufferParams);
                float pDepthLeft   = Linear01Depth(depthLeft, _ZBufferParams);
                float pDepthRight  = Linear01Depth(depthRight, _ZBufferParams);
                
                float uDepthUp    = lerp(pDepthUp, 1.0 - depthUp, unity_OrthoParams.w);
                float uDepthDown  = lerp(pDepthDown, 1.0 - depthDown, unity_OrthoParams.w);
                float uDepthLeft  = lerp(pDepthLeft, 1.0 - depthLeft, unity_OrthoParams.w);
                float uDepthRight = lerp(pDepthRight, 1.0 - depthRight, unity_OrthoParams.w);
                
                depthUp     = pow(uDepthUp, DEPTH_POW);
                depthDown   = pow(uDepthDown, DEPTH_POW);
                depthLeft   = pow(uDepthLeft, DEPTH_POW);
                depthRight  = pow(uDepthRight, DEPTH_POW);
                
                float curveX = (depthLeft + depthRight) - (2.0 * depthCenter);
                float curveY = (depthUp + depthDown) - (2.0 * depthCenter);

                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, 1.0), isInnerEdge * color.a);
                
                finalColor.rgb = ApplyFog(finalColor, depthCenter);
                
                return finalColor;
            }
            ENDHLSL
        }
    }
}
