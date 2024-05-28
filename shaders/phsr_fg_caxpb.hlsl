#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> inputrAr;
Texture2D<float3> inputApMAp;
Texture2D<float3> inputX;
Texture2D<float3> inputB;

RWTexture2D<float3> outputAxPb;

cbuffer shaderConsts : register(b0)
{
    uint2 dimension;
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
    
    float3 outputVector = inputrAr[groupId] * SafeRcp3(inputApMAp[groupId]) * inputX[pixelIndex] + inputB[pixelIndex];
    
    {
        bool bIsValidhistoryPixel = all(uint2(pixelIndex) < dimension);
        if (bIsValidhistoryPixel)
        {
            outputAxPb[pixelIndex] = outputVector;
        }
    }
}