Shader "Custom/PackedForwardOpaquePP"
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

            Texture2D<uint> _BlitTexture;
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
            
            float SafeUnpackDepth(uint package)
            {
                if (package == 0)
                    return 1.0;
                
                return UnpackDepth(package);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                uint rtWidth, rtHeight;
                _BlitTexture.GetDimensions(rtWidth, rtHeight);
                int2 pixelCoord = int2(IN.uv * float2(rtWidth, rtHeight));
                
                uint package = _BlitTexture.Load(int3(pixelCoord, 0));
                
                uint outline;
                float4 color = UnpackRGBA(package, outline);
                float depthCenter = (package == 0) ? 1.0 : color.a;
                
                
                float depthUp     = SafeUnpackDepth(_BlitTexture.Load(int3(pixelCoord + int2(0, 1), 0)));
                float depthDown   = SafeUnpackDepth(_BlitTexture.Load(int3(pixelCoord + int2(0, -1), 0)));
                float depthLeft   = SafeUnpackDepth(_BlitTexture.Load(int3(pixelCoord + int2(-1, 0), 0)));
                float depthRight  = SafeUnpackDepth(_BlitTexture.Load(int3(pixelCoord + int2(1, 0), 0)));
                
                float curveX = (depthLeft + depthRight) - (2.0 * depthCenter);
                float curveY = (depthUp + depthDown) - (2.0 * depthCenter);

                half isInnerEdge = 0;
                isInnerEdge += step(_NormalOutlineThreshold, curveX);
                isInnerEdge += step(_NormalOutlineThreshold, curveY);
                isInnerEdge = saturate(isInnerEdge);
                
                half3 finalColor = lerp(color.rgb, half3(0.0, 0.0, 0.0), isInnerEdge * outline);
                
                finalColor = ApplyFog(finalColor, depthCenter);
                return half4(finalColor, (half)outline);
            }
            ENDHLSL
        }
    }
}
