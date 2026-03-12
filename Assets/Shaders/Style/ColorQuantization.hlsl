float3 RGBtoHSV(half3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

half3 HSVtoRGB(float3 c) {
    half4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

half3 SmartQuantize(half3 RGB, half steps, half darkProtection, half3 colorWeight) {
    
    // Convert the original color to HSV space
    float3 hsv = RGBtoHSV(RGB);

    // Calculate weights based on the original HUE value
    half distRed = min(abs(hsv.x - 0.0), abs(1.0 - abs(hsv.x - 0.0)));
    half distGreen = min(abs(hsv.x - 0.3333), abs(1.0 - abs(hsv.x - 0.3333)));
    half distBlue = min(abs(hsv.x - 0.6666), abs(1.0 - abs(hsv.x - 0.6666)));

    half weightRed = saturate(1.0 - (distRed / 0.3333));
    half weightGreen = saturate(1.0 - (distGreen / 0.3333));
    half weightBlue = saturate(1.0 - (distBlue / 0.3333));

    // This is the step value that will be used for the TONES (Saturation and Value) of that pixel
    half ToneSteps = (weightRed * colorWeight.r * steps) + 
                     (weightGreen * colorWeight.g * steps) + 
                     (weightBlue * colorWeight.b * steps);
    ToneSteps = max(ToneSteps, 1.0); // Ensure we don't divide by zero later

    // Quantize HUE with its own FIXED step value
    hsv.x = round(hsv.x * steps) / steps; 

    // Quantize TONES (Sat and Val) with the dynamically calculated step!
    hsv.y = round(hsv.y * ToneSteps) / ToneSteps;

    // Dark-Protecting Quantization (Value)
    // If darkProtection is 0.0, it behaves normally.
    // If you give it a value like 0.5, it will allocate more steps to the darks.
    half safeProtection = clamp(darkProtection, 0.0, 0.99); // Clamp to avoid division by zero or negative values
    hsv.z = pow(hsv.z, 1 - safeProtection);          // Expand the darks
    hsv.z = round(hsv.z * ToneSteps) / ToneSteps; // Dynamic step comes into play here!
    hsv.z = pow(hsv.z, 1.0 / (1 - safeProtection));    // Then shrink it back down to put it in its original place

    // Convert back to RGB safely
    return HSVtoRGB(hsv);
}