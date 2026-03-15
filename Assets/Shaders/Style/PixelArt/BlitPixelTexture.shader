Shader "Custom/PixelPerfectBlit"
{
    Properties
    {
        _SourceTexture ("Source Texture", 2D) = "white" {}
        _NormalOutlineThreshold ("Normal Outline Threshold", Range(0.001, 0.2)) = 0.01
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"
            
            Texture2D<uint> _SourceTexture;

            CBUFFER_START(UnityPerMaterial)
                float4 _SourceTexture_ST;
                float4 _SourceTexture_TexelSize;
                float _DepthOutlineThreshold;
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

            half4 frag(Varyings IN) : SV_Target
            {
                // For direct texture load, we need to convert UV coordinates to pixel coordinates
                int2 pixelCoord = int2(IN.uv * _SourceTexture_TexelSize.zw);
                
                // Load function requires XY integer coordinates and mip level (0 for base level)
                uint packedData = _SourceTexture.Load(int3(pixelCoord, 0));
                uint outlineFlag;
                float4 color = UnpackRGBA(packedData, outlineFlag);
                
                //color.rgb = color.a; // Depth visualization for testing
                
                float depth = color.a;
                
                uint temp;
                float depthUp    = UnpackRGBA(_SourceTexture.Load(int3(pixelCoord + int2(0.0, 1.0), 0)), temp).a;
                float depthDown  = UnpackRGBA(_SourceTexture.Load(int3(pixelCoord + int2(0.0, -1.0), 0)), temp).a;
                float depthLeft  = UnpackRGBA(_SourceTexture.Load(int3(pixelCoord + int2(-1.0, 0.0), 0)), temp).a;
                float depthRight = UnpackRGBA(_SourceTexture.Load(int3(pixelCoord + int2(1.0, 0.0), 0)), temp).a;
                
                float centerLin = pow(depth, 1.0 / DEPTH_POW);
                float upLin = pow(depthUp, 1.0 / DEPTH_POW);
                float downLin = pow(depthDown, 1.0 / DEPTH_POW);
                float leftLin = pow(depthLeft, 1.0 / DEPTH_POW);
                float rightLin = pow(depthRight, 1.0 / DEPTH_POW);
                
                // Calculate the normal using central differences
                float dzdx = rightLin - leftLin;
                float dzdy = upLin - downLin;
                // We can calculate normal texture here by with no additional texture fetches, using the depth values we already have.
                half3 normal = normalize(float3(dzdx, dzdy, 0.01)); 
                
                // Calculate curvature using the second derivative (Laplacian) of the depth
                float curveX = (leftLin + rightLin) - (2.0 * centerLin);
                float curveY = (upLin + downLin) - (2.0 * centerLin);
                
                // Determine if the pixel is an inner edge based on curvature thresholds
                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge) * outlineFlag;
                
                half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, color.a), isInnerEdge);
                
                return finalColor;
                color.rgb = depth; // Normal visualization for testing
                return color;
            }

            ENDHLSL
        }
    }
}