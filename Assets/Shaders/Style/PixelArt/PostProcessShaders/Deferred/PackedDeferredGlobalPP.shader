Shader "Custom/PackedDeferredGlobalPP"
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
            
            TEXTURE2D(_BlitTexture);
            Texture2D<uint> _GBuffer0;
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
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                float2 texelSize = 1.0 / float2(rtWidth, rtHeight);
                
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_PointClamp, IN.uv);
                int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
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
                    return half4(ApplyFog(color.rgb, depthCenter), 1.0);
                }
                
                float depthUp;
                float depthDown;
                float depthLeft;
                float depthRight;
                
                float3 normalUp     = GetSafeGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(0, 1), 0)), depthUp);
                float3 normalDown   = GetSafeGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(0, -1), 0)), depthDown);
                float3 normalLeft   = GetSafeGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(-1, 0), 0)), depthLeft);
                float3 normalRight  = GetSafeGBufferData(_GBuffer0.Load(int3(pixelCoord + int2(1, 0), 0)), depthRight);
                
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
