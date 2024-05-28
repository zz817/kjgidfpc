#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> residualVectorFiner;
RWTexture2D<float3> residualVectorCoarser;

cbuffer shaderConsts : register(b0)
{
    uint2 dimension;
    float coefficient;
    float duplicated;
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 coarserPixelIndex = dispatchThreadId;
    
    int2 finerPixelUpperLeft = 2 * coarserPixelIndex;
    float3 filteredVector = 0.0f;
    {
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float3 finerVector = residualVectorFiner[finerIndex];
            filteredVector += finerVector;
        }
    }
    filteredVector *= SafeRcp(float(subsampleCount4PointTian));
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < dimension);
        if (bIsValidhistoryPixel)
        {
            residualVectorCoarser[coarserPixelIndex] = filteredVector;
        }
    }
}
