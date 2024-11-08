#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> scaledMotion;
RWTexture2D<float2> pushedMotion;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
	
	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < FinerDimension);
        if (bIsValidhistoryPixel)
        {
            pushedMotion[currentPixelIndex] = pushedMotion[currentPixelIndex];
        }
    }
}
