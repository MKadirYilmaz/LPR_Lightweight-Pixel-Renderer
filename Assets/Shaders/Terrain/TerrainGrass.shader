Shader "Custom/TerrainGrass"
{
    Properties
    {
        [HideInInspector] _MainTex("", 2D) = "white" {} // URP Terrain Shader requires a _MainTex property, but we won't use it.
        _TerrainColorMap("Terrain Color Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing  // GPU Instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Shaders/Misc/FoliageVertexManipulation.hlsl"
            
            #include "Assets/Shaders/Style/PixelArt/DepthCalculations.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos    : TEXCOORD0;
                float ambientLight : TEXCOORD1;
                float zEye         : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            TEXTURE2D(_TerrainColorMap);
            SAMPLER(sampler_TerrainColorMap);
            
            #define TERRAIN_COORD half2(-25.0, -25.0) // Set these based on your terrain's position in the world. It is defined as macro to avoid unnecessary memory fetches in the shader.
            #define TERRAIN_SIZE half2(50.0, 50.0) // Set these based on your terrain's size in world units. It is defined as macro to avoid unnecessary memory fetches in the shader.
            
            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4,  _TerrainColorMap_ST)
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                float3 posOS = IN.positionOS.xyz;
                posOS.xz += GrassFoliageWindOffset(posOS, half3(1.5, 0.3, 0.5)); // Apply wind offset to vertex position
                
                OUT.ambientLight = saturate(posOS.y + 0.9); // Use vertex height as ambient light factor (you can replace this with a more complex calculation if needed)
                
                OUT.positionHCS = TransformObjectToHClip(posOS);
                OUT.worldPos = TransformObjectToWorld(posOS);
                
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.zEye = -vertexInputs.positionVS.z;
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float2 diff = IN.worldPos.xz - TERRAIN_COORD;
                float2 uv = float2(diff.x / TERRAIN_SIZE.x, diff.y / TERRAIN_SIZE.y);

                half4 tColor = SAMPLE_TEXTURE2D(_TerrainColorMap, sampler_TerrainColorMap, uv);
                tColor.rgb *= GetMainLight().color; // Apply main directional light color
                //tColor.rgb *= IN.ambientLight; // Apply ambient light factor
                
                tColor.a = GetDepthValue(IN.zEye, _ProjectionParams.y, _ProjectionParams.z); // Write depth to alpha channel for proper sorting
                
                return tColor;
            }

            ENDHLSL
        }
    }
}