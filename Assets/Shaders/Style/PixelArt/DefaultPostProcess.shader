Shader "Custom/DefaultPostProcess"
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
            #pragma multi_compile _ _RENDER_NORMALS _RENDER_DEPTH

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };
            
            Texture2D<half4> _BlitTexture;
            Texture2D<half> _LPR_DepthTexture;
            float _NormalOutlineThreshold;
            

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                OUT.positionHCS = GetFullScreenTriangleVertexPosition(IN.vertexID);
                OUT.uv  = GetFullScreenTriangleTexCoord(IN.vertexID);
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
                
                half4 color = _BlitTexture.Load(int3(pixelCoord, 0));
                color.rgb = SmartQuantize(color.rgb, 32.0, 0.3, half3(1.0, 1.0, 1.0));
                
                float depthCenter = _LPR_DepthTexture.Load(int3(pixelCoord, 0));
                float pDepthCenter = Linear01Depth(depthCenter, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - depthCenter, unity_OrthoParams.w);
                depthCenter = pow(uDepthCenter, DEPTH_POW);
                #if defined(_RENDER_DEPTH)
                    return half4(depthCenter, depthCenter, depthCenter, 1.0);
                #endif
                
                if (pixelCoord.x <= 0 || pixelCoord.x >= rtWidth - 1 || pixelCoord.y <= 0 || pixelCoord.y >= rtHeight - 1)
                {
                    // Skip edge pixels to avoid out-of-bounds access
                    return half4(ApplyFog(color.rgb, depthCenter), 1.0);
                }
                
                float depthUp     = _LPR_DepthTexture.Load(int3(float2(pixelCoord.x ,clamp(pixelCoord.y + 1.0, 0.0, rtHeight)), 0));
                float depthDown   = _LPR_DepthTexture.Load(int3(float2(pixelCoord.x ,clamp(pixelCoord.y - 1.0, 0.0, rtHeight)), 0));
                float depthLeft   = _LPR_DepthTexture.Load(int3(float2(clamp(pixelCoord.x - 1.0, 0.0, rtWidth), pixelCoord.y), 0));
                float depthRight  = _LPR_DepthTexture.Load(int3(float2(clamp(pixelCoord.x + 1.0, 0.0, rtWidth), pixelCoord.y), 0));
                
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
                
                #if defined(_RENDER_NORMALS)
                        // Calculate the normal using central differences
                        float dzdx = depthRight - depthLeft;
                        float dzdy = depthUp - depthDown;
                        // We can calculate normal texture here by with no additional texture fetches, using the depth values we already have.
                        half3 normal = normalize(float3(dzdx, dzdy, 0.01));
                        return half4(normal, 1.0); // Normal visualization for testing
                    #endif
                
                float curveX = (depthLeft + depthRight) - (2.0 * depthCenter);
                float curveY = (depthUp + depthDown) - (2.0 * depthCenter);

                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, 0.0), isInnerEdge);
                
                finalColor.rgb = ApplyFog(finalColor, depthCenter);
                
                return finalColor;
            }
            ENDHLSL
        }
    }
}
