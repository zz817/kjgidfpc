#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> residualVectorFiner;
Texture2D<float3> correctionVectorCoarser;

RWTexture2D<float3> residualVectorFinerUpdated;

cbuffer shaderConsts : register(b0)
{
    uint2 dimension;
    float coefficient;
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 finerPixelIndex = dispatchThreadId;
    int2 coarserPixelIndex = finerPixelIndex / 2;
    float2 correctionalVector = correctionVectorCoarser[coarserPixelIndex];
    float2 residualVector = residualVectorFiner[finerPixelIndex];
    
    {
        bool bIsValidhistoryPixel = all(uint2(finerPixelIndex) < dimension);
        if (bIsValidhistoryPixel)
        {
            residualVectorFinerUpdated[finerPixelIndex] = residualVector + correctionalVector;
        }
    }
}