Shader "Custom/DecoderPostProcess"
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            #include "Assets/Shaders/Lighting/CustomLighting.hlsl"

            
            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };
            
            Texture2D<uint> _BlitTexture;
            Texture2D<half> _LPR_DepthTexture;
            float _NormalOutlineThreshold;
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                OUT.positionHCS = GetFullScreenTriangleVertexPosition(IN.vertexID);
                OUT.uv  = GetFullScreenTriangleTexCoord(IN.vertexID);
                
                #if UNITY_UV_STARTS_AT_TOP
                if (_ProjectionParams.x > 0.0)
                {
                    OUT.uv.y = 1.0 - OUT.uv.y;
                }
                #endif
                
                return OUT;
            }
            
            half4 frag(Varyings IN) : SV_Target
            {
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
                
                // Load function requires XY integer coordinates and mip level (0 for base level)
                uint packedData = _BlitTexture.Load(int3(pixelCoord, 0));
                uint outlineFlag;
                half3 normal;
                half3 color = UnpackRGBNormal(packedData, normal, outlineFlag);
                
                float depth = _LPR_DepthTexture.Load(int3(pixelCoord, 0));
                float pDepthCenter = Linear01Depth(depth, _ZBufferParams);
                float uDepthCenter = lerp(pDepthCenter, 1.0 - depth, unity_OrthoParams.w);
                
                // 2. DÜNYA POZİSYONU İÇİN SİHİRLİ DÜZELTME (Y-Flip Koruması)
                float2 computeUV = IN.uv;
                
                // Unity'nin kendi makrosu: Eğer API Y eksenini ters çeviriyorsa ve hedefe ters çiziliyorsa
                #if UNITY_UV_STARTS_AT_TOP
                if (_ProjectionParams.x > 0.0)
                {
                    computeUV.y = 1.0 - computeUV.y; // Y eksenini matematik için geri çevir!
                }
                #endif
                
                float3 worldPos = ComputeWorldSpacePosition(computeUV, depth, UNITY_MATRIX_I_VP);
                float4 shadowCoord = TransformWorldToShadowCoord(worldPos);
                Light light = GetMainLight(shadowCoord);
                
                color *= lerp(GrassLighting(light), CelLighting(normal, light), outlineFlag);
                
                depth = pow(uDepthCenter, DEPTH_POW);
                
                
                #if defined(_RENDER_DEPTH)
                    return half4(depth, depth, depth, 1.0);
                #endif
                
                if (pixelCoord.x <= 0 || pixelCoord.x >= rtWidth - 1 || pixelCoord.y <= 0 || pixelCoord.y >= rtHeight - 1)
                {
                    // Skip edge pixels to avoid out-of-bounds access
                    return half4(color, 1.0);
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
                    half3 ssnormal = normalize(float3(dzdx, dzdy, 0.01));
                    return half4(ssnormal, 1.0); // Normal visualization for testing
                #endif
                
                // Calculate curvature using the second derivative (Laplacian) of the depth
                float curveX = (depthLeft + depthRight) - (2.0 * depth);
                float curveY = (depthUp + depthDown) - (2.0 * depth);
                
                // Determine if the pixel is an inner edge based on curvature thresholds
                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge) * outlineFlag;
                
                half3 finalColor = lerp(color, half3(0.0, 0.0, 0.0), isInnerEdge);
                finalColor = ApplyFog(finalColor, depth);  
            
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
