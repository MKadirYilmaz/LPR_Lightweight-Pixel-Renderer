Shader "Custom/DownscalerPostProcess"
{
    Properties
    {
        _PixelScale ("Pixel Scale Factor", Range(1, 20)) = 4.0
        _NormalOutlineThreshold ("Outline Threshold", Range(0.0001, 0.01)) = 0.001
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)
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
            
            #pragma multi_compile _ _RENDER_NORMALS _RENDER_DEPTH

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            
            #define FOG_FALLOFF half(5.0)
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            
            float _PixelScale;
            float _NormalOutlineThreshold;
            half4 _OutlineColor;

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                float2 targetResolution = _ScreenParams.xy / max(_PixelScale, 1.0);
                float2 texelSize = 1.0 / targetResolution; 
                float2 pixelatedUV = (floor(uv * targetResolution) + 0.5) / targetResolution;
                
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, pixelatedUV);
                color.rgb = SmartQuantize(color.rgb, 32.0, 0.3, half3(1.0, 1.0, 1.0));
                
                float depthCenter = SampleSceneDepth(pixelatedUV);
                float pDepthCenter = Linear01Depth(depthCenter, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - depthCenter, unity_OrthoParams.w);
                depthCenter = pow(uDepthCenter, DEPTH_POW);
                #if defined(_RENDER_DEPTH)
                    return half4(depthCenter, depthCenter, depthCenter, 1.0);
                #endif
                
                float depthUp     = SampleSceneDepth(pixelatedUV + float2(0.0, texelSize.y));
                float depthDown   = SampleSceneDepth(pixelatedUV + float2(0.0, -texelSize.y));
                float depthLeft   = SampleSceneDepth(pixelatedUV + float2(-texelSize.x, 0.0));
                float depthRight  = SampleSceneDepth(pixelatedUV + float2(texelSize.x, 0.0));
                
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
                
                half4 finalColor = lerp(color, _OutlineColor, isInnerEdge);
                
                finalColor.rgb = ApplyFog(finalColor, depthCenter);
                
                return finalColor;
                return half4(depthCenter, depthCenter, depthCenter, 1.0);
            }
            ENDHLSL
        }
    }
}
