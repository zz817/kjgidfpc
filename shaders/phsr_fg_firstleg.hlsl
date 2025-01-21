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
    
    float2 selectedVector = motionVectorRaw[currentPixelIndex];
    float selectedDepth = depthTextureRaw[currentPixelIndex];
    uint selectedCAT = motionRawCAT[currentPixelIndex];
    
    float2 filteredVector = float2(0.0f, 0.0f);
    float filteredDepth = 0.0f;
    int validSampleCount = 0;
    {
        for (int i = 0; i < subsampleCount9PointPatch; ++i)
        {
            int2 elementIndex = currentPixelIndex + subsamplePixelOffset9PointPatch[i];
            float2 elementVector = motionVectorRaw[elementIndex];
            float elementDepth = depthTextureRaw[elementIndex];
            float elementCAT = motionRawCAT[elementIndex];
            
            if (elementCAT == ReprojCAT0ValidSamp)
            {
                filteredVector += elementVector;
                filteredDepth += elementDepth;
                validSampleCount++;
            }
        }
    }
    if (validSampleCount > 0)
    {
        filteredVector /= float(validSampleCount);
        filteredDepth /= float(validSampleCount);
    }
    if (selectedCAT == ReprojCAT0ValidSamp)
    {
        if (validSampleCount <= 3)
        {
            selectedVector = float2(0.0f, 0.0f);
            selectedDepth = 0.0f;
            selectedCAT = ReprojCAT2Unwritten;
        }
    }
    else
    {
        if (validSampleCount > 5)
        {
            selectedVector = filteredVector;
            selectedDepth = filteredDepth;
            selectedCAT = ReprojCAT0ValidSamp;
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            motionVectorFiltered[currentPixelIndex] = selectedVector;
            depthTextureFiltered[currentPixelIndex] = selectedDepth;
            motionFilteredCAT[currentPixelIndex] = selectedCAT;
        }
    }
}
