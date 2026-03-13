half GetDepthValue(float zEye, float near, float far)
{
    return pow(saturate((zEye - near) / (far - near)), 1.5);
}