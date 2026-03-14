Shader "Custom/PixelPerfectBlit"
{
    Properties
    {
        _SourceTexture ("Source Texture", 2D) = "white" {}
        _DepthOutlineThreshold ("Depth Outline Threshold", Range(0.001, 0.2)) = 0.01
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
            #include "Assets/Shaders/Style/ColorQuantization.hlsl"

            TEXTURE2D(_SourceTexture);
            SAMPLER(sampler_point_clamp);

            CBUFFER_START(UnityPerMaterial)
                float4 _SourceTexture_ST;
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
                half4 color = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv);
                color.rgb = SmartQuantize(color, 32.0, 0.25, half3(0.85, 0.9, 0.75));
                
                //color.rgb = color.a; // Depth visualization for testing
                
                float2 texelSize = 1.0 / float2(480, 300); // Assuming a 480x300 render target for pixel art
                half depth = color.a;
                
                half depthUp    = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv + float2(0, texelSize.y)).a;
                half depthDown  = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv + float2(0, -texelSize.y)).a;
                half depthLeft  = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv + float2(-texelSize.x, 0)).a;
                half depthRight = SAMPLE_TEXTURE2D(_SourceTexture, sampler_point_clamp, IN.uv + float2(texelSize.x, 0)).a;
                
                half centerLin = pow(depth, 1.0 / 1.5);
                half upLin = pow(depthUp, 1.0 / 1.5);
                half downLin = pow(depthDown, 1.0 / 1.5);
                half leftLin = pow(depthLeft, 1.0 / 1.5);
                half rightLin = pow(depthRight, 1.0 / 1.5);
                
                // Calculate the normal using central differences
                half dzdx = rightLin - leftLin;
                half dzdy = upLin - downLin;
                // We can calculate normal texture here by with no additional texture fetches, using the depth values we already have.
                half3 normal = normalize(float3(dzdx, dzdy, 0.01)); 
                
                // Calculate curvature using the second derivative (Laplacian) of the depth
                float curveX = (leftLin + rightLin) - (2.0 * centerLin);
                float curveY = (upLin + downLin) - (2.0 * centerLin);
                
                // Determine if the pixel is an inner edge based on curvature thresholds
                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                // Determine if the pixel is an edge based on depth differences
                /*
                half isEdge = 0;
                isEdge += step(depthUp + _DepthOutlineThreshold, depth);
                isEdge += step(depthDown + _DepthOutlineThreshold, depth);
                isEdge += step(depthLeft + _DepthOutlineThreshold, depth);
                isEdge += step(depthRight + _DepthOutlineThreshold, depth);
                
                isEdge = saturate(isEdge);
                */
                half4 finalColor = lerp(color, half4(0.0, 0.0, 0.0, color.a), isInnerEdge);
                
                return finalColor;
                color.rgb = normal; // Normal visualization for testing
                return color;
            }

            ENDHLSL
        }
    }
}