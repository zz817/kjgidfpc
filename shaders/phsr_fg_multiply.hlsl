#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> inputX;
RWTexture2D<float3> outputAx;

cbuffer shaderConsts : register(b0)
{
    uint2 dimensions;
    float coefficient;
}

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 pixelIndex = dispatchThreadId;
    float3 multipliedVector = -4.0f * inputX[pixelIndex];
    for (int patchIndex = 1; patchIndex < subsampleCount5PointStencil; ++patchIndex)
    {
        int2 elementIndex = pixelIndex + subsamplePixelOffset5PointStencil[patchIndex];
        multipliedVector += inputX[elementIndex];
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(pixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            outputAx[pixelIndex] = multipliedVector;
        }
    }
}
