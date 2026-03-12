float SimpleWind(float x, float time, float speed, float frequency)
{
    // Create wind noise based on 2 different frequency values
    float a = sin((x / frequency) + time * speed); // First layer of wind noise using the base frequency
    float b = sin((x / frequency * 2.3) + time * speed * 1.7) * 0.5; // Second layer of wind noise using a higher frequency and reduced amplitude to add complexity to the movement
    return (a + b) / 1.5; // Normalize between -1 and 1
}

// SmallWindSpeed(WindSpeed, WindAmount, Frequency), BigWindSpeed(WindSpeed, WindAmount, Frequency)
float VertexColorWindOffset(float3 vertexPosOS, half3 vertexColor, half3 smallWindValues, half3 bigWindValues)
{
    // Leaf movement
    float smallNoise = SimpleWind(vertexPosOS.x, _Time.y, smallWindValues.x, smallWindValues.z);
    float smallOffset = smallNoise * smallWindValues.y * (1.0 - vertexColor.r);

    // Branch movement
    float bigNoise = SimpleWind(0.0, _Time.y, bigWindValues.x, bigWindValues.z);
    float bigOffset = bigNoise * bigWindValues.y * (1.0 - vertexColor.b);
    
    return smallOffset + bigOffset;
}
// WindValues(WindSpeed, WindAmount, Frequency)
float GrassFoliageWindOffset(float3 vertexPosOS, half3 windValues)
{
    float windEffect = vertexPosOS.y * windValues.y; // Tip of the grass moves more than the base, creating a natural bending effect
    float windNoise = SimpleWind(vertexPosOS.x, _Time.y, windValues.x, windValues.z); // Generate wind noise based on the vertex's x position and time to create dynamic movement
    return windNoise * windEffect;
}