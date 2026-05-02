Shader "Custom/GlobalPostProcess"
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

            #pragma vertex Vert
            #pragma fragment frag
            #pragma multi_compile _ _RENDER_NORMALS _RENDER_DEPTH
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            
            float _NormalOutlineThreshold;
            Texture2D<uint> _GBuffer0;
            
            float3 GetSafeGBufferData(uint package, out float depth)
            {
                if (package == 0)
                {
                    depth = 1.0;
                    return float3(0.0, -1.0, 0.0);
                }
                return UnpackDepthNormalGBuffer(package, depth);
            }
            
            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord;
                #if UNITY_UV_STARTS_AT_TOP
                    if (_ProjectionParams.x > 0.0)
                    {
                        uv.y = 1.0 - uv.y;
                    }
                #endif
                
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, uv);
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                int2 pixelCoord = int2(uv * float2(rtWidth, rtHeight));
                
                float depthCenter;
                float3 normalCenter = GetSafeGBufferData(_GBuffer0.Load(int3(pixelCoord, 0)), depthCenter);
                
                #if defined(_RENDER_NORMALS)
                    return half4(normalCenter, 1.0);
                #endif
                
                #if defined(_RENDER_DEPTH)
                    return half4(depthCenter, depthCenter, depthCenter, 1.0);
                #endif
                
                if (pixelCoord.x <= 0 || pixelCoord.x >= rtWidth - 1 || pixelCoord.y <= 0 || pixelCoord.y >= rtHeight - 1)
                {
                    // Skip edge pixels to avoid out-of-bounds access
                    return color;
                }
                float depthUp;
                float depthDown;
                float depthLeft;
                float depthRight;
                
                float3 normalUp     = GetSafeGBufferData(_GBuffer0.Load(int3(float2(pixelCoord.x ,clamp(pixelCoord.y + 1.0, 0.0, rtHeight)), 0)), depthUp);
                float3 normalDown   = GetSafeGBufferData(_GBuffer0.Load(int3(float2(pixelCoord.x ,clamp(pixelCoord.y - 1.0, 0.0, rtHeight)), 0)), depthDown);
                float3 normalLeft   = GetSafeGBufferData(_GBuffer0.Load(int3(float2(clamp(pixelCoord.x - 1.0, 0.0, rtWidth), pixelCoord.y), 0)), depthLeft);
                float3 normalRight  = GetSafeGBufferData(_GBuffer0.Load(int3(float2(clamp(pixelCoord.x + 1.0, 0.0, rtWidth), pixelCoord.y), 0)), depthRight);
                
                // Calculate curvature using the second derivative (Laplacian) of the depth
                float curveX = (depthLeft + depthRight) - (2.0 * depthCenter);
                float curveY = (depthUp + depthDown) - (2.0 * depthCenter);
                
                // Determine if the pixel is an inner edge based on curvature thresholds
                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                // Outline will be suitable with transparency
                half3 finalColor = lerp(color.rgb, ApplyFog(half3(0.0, 0.0, 0.0), depthCenter), isInnerEdge * color.a);
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
