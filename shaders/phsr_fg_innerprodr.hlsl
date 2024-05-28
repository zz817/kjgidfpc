#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> inputVectorR;
Texture2D<float3> inputVectorAR;
Texture2D<float3> inputVectorAP;
Texture2D<float3> inputVectorMAP;

RWTexture2D<float3> innerProductRARPartial;
RWTexture2D<float3> innerProductAPMAPPartial;

cbuffer shaderConsts : register(b0)
{
    uint2 dimension;
    float coefficient;
    float duplicated;
}

#define TILE_SIZE 8

groupshared float3 sharedRarSum[TILE_SIZE * TILE_SIZE];
groupshared float3 sharedApMapSum[TILE_SIZE * TILE_SIZE];

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
        float3 vectorR = inputVectorR[elementIndex];
        float3 vectorAR = inputVectorAR[elementIndex];
        float3 vectorAP = inputVectorAP[elementIndex];
        float3 vectorMAP = inputVectorMAP[elementIndex];
        float3 innerProductRARValue = vectorR * vectorAR;
        float3 innerProductAPMAPValue = vectorAP * vectorMAP;
        
        rArSum += innerProductRARValue;
        apMapSum += innerProductAPMAPValue;
    }
    
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
        int flatIndex = localId.y * TILE_SIZE + localId.x;
        bool bIsValidhistoryPixel = (flatIndex == 0) ? true : false;
        if (bIsValidhistoryPixel)
        {
            innerProductRARPartial[groupId] = sharedRarSum[0];
            innerProductAPMAPPartial[groupId] = sharedApMapSum[0];
        }
    }
}
