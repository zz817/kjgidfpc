#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<float3> innerProductRARPartial;
RWTexture2D<float3> innerProductAPMAPPartial;

Texture2D<float3> innerProductRAR;
Texture2D<float3> innerProductAPMAP;

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
    int2 threadIndex = dispatchThreadId;
    int2 finerPixelIndex = threadIndex * 2;
    
    float3 rArSum = float3(0.0f, 0.0f, 0.0f);
    float3 apMapSum = float3(0.0f, 0.0f, 0.0f);
    
    for (int patchIndex = 0; patchIndex < subsampleCount4PointTian; ++patchIndex)
    {
        int2 elementIndex = finerPixelIndex + subsamplePixelOffset5PointStencil[patchIndex];
        if (any(elementIndex > dimension))
        {
            continue;
        }
        float3 vectorRAR = innerProductRARPartial[elementIndex];
        float3 vectorAPMAP = innerProductAPMAPPartial[elementIndex];
       
        rArSum += vectorRAR;
        apMapSum += vectorAPMAP;
    }
    
    groupshared float3 sharedRarSum[TILE_SIZE * TILE_SIZE];
    groupshared float3 sharedApMapSum[TILE_SIZE * TILE_SIZE];
    sharedRarSum[localId.y * TILE_SIZE + localId.x] = rArSum;
    sharedApMapSum[localId.y * TILE_SIZE + localId.x] = apMapSum;
    GroupMemoryBarrierWithGroupSync();
    
    for (int stride = TILE_SIZE * TILE_SIZE / 2; stride > 0; stride /= 2)
    {
        if (localId.y * TILE_SIZE + localId.x < stride)
        {
            sharedRarSum[localId.y * TILE_SIZE + localId.x] += sharedRarSum[localId.y * TILE_SIZE + localId.x + stride];
            sharedApMapSum[localId.y * TILE_SIZE + localId.x] += sharedApMapSum[localId.y * TILE_SIZE + localId.x + stride];
        }
        GroupMemoryBarrierWithGroupSync();
    }
    
    {
        bool bIsValidhistoryPixel = (localId.y * TILE_SIZE + localId.x == 0);
        if (bIsValidhistoryPixel)
        {
            innerProductRAR[groupId] = sharedRarSum[0];
            innerProductAPMAP[groupId] = sharedApMapSum[0];
        }
    }
}
