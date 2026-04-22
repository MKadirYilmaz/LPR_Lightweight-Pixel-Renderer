Shader "Custom/PixelPerfectBlit"
{
    Properties
    {
        _SourceTexture ("Source Texture", 2D) = "white" {}
        _NormalOutlineThreshold ("Normal Outline Threshold", Range(0.001, 0.2)) = 0.01
        _MainCameraDepth ("Main Camera Depth Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _SourceTexture_ST;
                float4 _SourceTexture_TexelSize;
                float _NormalOutlineThreshold;
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.uv = float2((IN.vertexID << 1) & 2, IN.vertexID & 2);
                OUT.positionHCS = float4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    OUT.uv.y = 1.0 - OUT.uv.y;
                #endif
                return OUT;
            }
        
        ENDHLSL
        
        Pass
        {
            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _USE_UNITY_PBR_LIT
            #pragma multi_compile _ _RENDER_NORMALS _RENDER_DEPTH

            #if defined(_USE_UNITY_PBR_LIT)
                TEXTURE2D(_SourceTexture);
                SAMPLER(sampler_point_clamp);
            
                TEXTURE2D(_MainCameraDepth);
                SAMPLER(sampler_MainCameraDepth);
            #else 
                Texture2D<uint> _SourceTexture;
            #endif
            
            
            half4 frag(Varyings IN) : SV_Target
            {
                #if defined(_USE_UNITY_PBR_LIT)
                
                    half4 color = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv);
                    color.rgb = SmartQuantize(color.rgb, 32.0, 0.3, half3(1.0, 1.0, 1.0));

                    
                    uint screenWidth, screenHeight;
                    _MainCameraDepth.GetDimensions(screenWidth, screenHeight);
                    // Texel size calculation for navigating to neighboring pixels in the depth texture
                    float2 texelSize = float2(1.0 / float(screenWidth), 1.0 / float(screenHeight));
                
                    float depth = 1.0 - SAMPLE_TEXTURE2D(_MainCameraDepth, sampler_MainCameraDepth, IN.uv).r;
                    
                    #if defined(_RENDER_DEPTH)
                        return half4(depth, depth, depth, 1.0); // Depth visualization for testing
                    #endif
                
                    float depthUp     = 1.0 - SAMPLE_TEXTURE2D(_MainCameraDepth, sampler_MainCameraDepth, IN.uv + float2(0.0, texelSize.y)).r;
                    float depthDown   = 1.0 - SAMPLE_TEXTURE2D(_MainCameraDepth, sampler_MainCameraDepth, IN.uv + float2(0.0, -texelSize.y)).r;
                    float depthLeft   = 1.0 - SAMPLE_TEXTURE2D(_MainCameraDepth, sampler_MainCameraDepth, IN.uv + float2(-texelSize.x, 0.0)).r;
                    float depthRight  = 1.0 - SAMPLE_TEXTURE2D(_MainCameraDepth, sampler_MainCameraDepth, IN.uv + float2(texelSize.x, 0.0)).r;
                
                    #if defined(_RENDER_NORMALS)
                        // Calculate the normal using central differences
                        float dzdx = depthRight - depthLeft;
                        float dzdy = depthUp - depthDown;
                        // We can calculate normal texture here by with no additional texture fetches, using the depth values we already have.
                        half3 normal = normalize(float3(dzdx, dzdy, 0.01));
                        return half4(normal, 1.0); // Normal visualization for testing
                    #endif
                
                    // Calculate curvature using the second derivative (Laplacian) of the depth
                    float curveX = (depthLeft + depthRight) - (2.0 * depth);
                    float curveY = (depthUp + depthDown) - (2.0 * depth);

                    half isInnerEdge = 0;
                    isInnerEdge += step(_NormalOutlineThreshold, curveX);
                    isInnerEdge += step(_NormalOutlineThreshold, curveY);
                
                    isInnerEdge = saturate(isInnerEdge);
                    
                    half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, color.a), isInnerEdge);
                    finalColor.rgb = ApplyFog(finalColor.rgb, depth);
                    return finalColor;
                #else
                    uint rtWidth, rtHeight;
                    _SourceTexture.GetDimensions(rtWidth, rtHeight);
                    
                    int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
                    
                    // Load function requires XY integer coordinates and mip level (0 for base level)
                    uint packedData = _SourceTexture.Load(int3(pixelCoord, 0));
                    uint outlineFlag;
                    float4 color = UnpackRGBA(packedData, outlineFlag);
                    
                    float depth = color.a;
                    float centerLin = pow(depth, 1.0 / DEPTH_POW);
                    #if defined(_RENDER_DEPTH)
                        return half4(centerLin, centerLin, centerLin, 1.0); // Depth visualization for testing
                    #endif
                
                    float depthUp    = UnpackDepth(_SourceTexture.Load(int3(pixelCoord + int2(0.0, 1.0), 0)));
                    float depthDown  = UnpackDepth(_SourceTexture.Load(int3(pixelCoord + int2(0.0, -1.0), 0)));
                    float depthLeft  = UnpackDepth(_SourceTexture.Load(int3(pixelCoord + int2(-1.0, 0.0), 0)));
                    float depthRight = UnpackDepth(_SourceTexture.Load(int3(pixelCoord + int2(1.0, 0.0), 0)));
                    
                    float upLin = pow(depthUp, 1.0 / DEPTH_POW);
                    float downLin = pow(depthDown, 1.0 / DEPTH_POW);
                    float leftLin = pow(depthLeft, 1.0 / DEPTH_POW);
                    float rightLin = pow(depthRight, 1.0 / DEPTH_POW);
                    
                    #if defined(_RENDER_NORMALS)
                        // Calculate the normal using central differences
                        float dzdx = rightLin - leftLin;
                        float dzdy = upLin - downLin;
                        // We can calculate normal texture here by with no additional texture fetches, using the depth values we already have.
                        half3 normal = normalize(float3(dzdx, dzdy, 0.01));
                        return half4(normal, 1.0); // Normal visualization for testing
                    #endif
                    
                    // Calculate curvature using the second derivative (Laplacian) of the depth
                    float curveX = (leftLin + rightLin) - (2.0 * centerLin);
                    float curveY = (upLin + downLin) - (2.0 * centerLin);
                    
                    // Determine if the pixel is an inner edge based on curvature thresholds
                    half isInnerEdge = 0;
                    isInnerEdge += step(_NormalOutlineThreshold, curveX);
                    isInnerEdge += step(_NormalOutlineThreshold, curveY);
                    isInnerEdge = saturate(isInnerEdge) * outlineFlag;
                    
                    half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, color.a), isInnerEdge);
                    finalColor.rgb = ApplyFog(finalColor.rgb, centerLin);  
                
                    return finalColor;
                #endif
                
            }
            ENDHLSL
        }
    }
}