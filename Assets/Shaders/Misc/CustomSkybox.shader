Shader "Custom/CustomSkybox"
{
    Properties { }

    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        
        ZWrite Off
        Cull Off
        ZTest LEqual
        
        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Shaders/Misc/CustomSkyboxCommon.hlsl"
            #include "Assets/Shaders/Misc/FogSystem.hlsl"
            
            struct Attributes { uint vertexID : SV_VertexID; };
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 viewDirWS  : TEXCOORD0;
            };

            Varyings vert(Attributes input)
            {
                Varyings OUT;
                
                float x = -1.0 + float((input.vertexID & 1) << 2);
                float y = -1.0 + float((input.vertexID & 2) << 1);
                
                OUT.positionCS = float4(x, y, UNITY_RAW_FAR_CLIP_VALUE, 1.0);

                if (unity_OrthoParams.w > 0.0) 
                {
                    float3 fakeViewSpaceRay = float3(x, y, 10.0); 
                    
                    OUT.viewDirWS = mul((float3x3)UNITY_MATRIX_I_V, fakeViewSpaceRay);
                }
                else 
                {
                    float4 clipPos = float4(x, y, 1.0, 1.0);
                    float4 worldPos = mul(UNITY_MATRIX_I_VP, clipPos);
                    OUT.viewDirWS = worldPos.xyz / worldPos.w - _WorldSpaceCameraPos;
                }

                return OUT;
            }
            
            half4 frag(Varyings IN) : SV_Target0
            {
                float3 viewDir = normalize(IN.viewDirWS);
                half4 skyColor = GetSkyboxColor(viewDir);
                
                skyColor.rgb = lerp(ApplyFog(skyColor.rgb, 1 - pow(saturate(viewDir.y), 2)), skyColor.rgb, saturate(viewDir.y));
                
                skyColor.a = 0.0;
                return skyColor;
            }
            ENDHLSL
        }
    }
}