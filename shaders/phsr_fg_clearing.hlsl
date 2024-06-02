#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<uint> motionAdvectHalfTipX;
RWTexture2D<uint> motionAdvectHalfTipY;
RWTexture2D<uint> motionReprojHalfTopX;
RWTexture2D<uint> motionReprojHalfTopY;
RWTexture2D<uint> motionReprojFullTopX;
RWTexture2D<uint> motionReprojFullTopY;

cbuffer shaderConsts : register(b0)
{
    uint2 dimensions;
    float2 distance;
    float2 viewportSize;
    float2 viewportInv;
}

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    
    bool bIsValidPixel = all(uint2(currentPixelIndex) < dimensions);
    if (bIsValidPixel)
    {
        motionAdvectHalfTipX[currentPixelIndex] = UnwrittenPackedClearValue;
        motionAdvectHalfTipY[currentPixelIndex] = UnwrittenPackedClearValue;
        motionReprojHalfTopX[currentPixelIndex] = UnwrittenPackedClearValue;
        motionReprojHalfTopY[currentPixelIndex] = UnwrittenPackedClearValue;
        motionReprojFullTopX[currentPixelIndex] = UnwrittenPackedClearValue;
        motionReprojFullTopY[currentPixelIndex] = UnwrittenPackedClearValue;
    }
}
