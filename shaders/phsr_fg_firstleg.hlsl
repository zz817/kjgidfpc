#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorRaw;
Texture2D<float> depthTextureRaw;
Texture2D<uint> motionRawCAT;

RWTexture2D<float2> motionVectorFiltered;
RWTexture2D<float> depthTextureFiltered;
RWTexture2D<uint> motionFilteredCAT;

cbuffer shaderConsts : register(b0)
{
    float4x4 prevClipToClip;
    float4x4 clipToPrevClip;
    
    uint2 dimensions;
    float2 tipTopDistance;
    float2 viewportSize;
    float2 viewportInv;
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
    
    float2 rawVector = motionVectorRaw[currentPixelIndex];
    float rawDepth = depthTextureRaw[currentPixelIndex];
    uint rawCAT = motionRawCAT[currentPixelIndex];
    
    {
        for (int i = 0; i < subsampleCount9PointPatch; ++i)
        {
            
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            motionVectorFiltered[currentPixelIndex] = rawVector;
            depthTextureFiltered[currentPixelIndex] = rawDepth;
            motionFilteredCAT[currentPixelIndex] = rawCAT;
        }
    }
}
