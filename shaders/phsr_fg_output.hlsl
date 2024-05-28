#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> inputX;
RWTexture2D<float4> outputAxPb;

cbuffer shaderConsts : register(b0)
{
    uint2 dimensions;
    float coefficient;
    float duplicated;
}

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 pixelIndex = dispatchThreadId;
    
    {
        bool bIsValidhistoryPixel = all(uint2(pixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            outputAxPb[pixelIndex] = float4(inputX[pixelIndex], 1.0f);
        }
    }
}
