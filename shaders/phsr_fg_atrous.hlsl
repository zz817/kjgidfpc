#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorRaw;
Texture2D<float> depthTextureRaw;
Texture2D<uint> motionCATRaw;

RWTexture2D<float2> motionVectorFilled;
RWTexture2D<float> depthTextureFilled;
RWTexture2D<uint> motionCATFilled;

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
	
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        uint currentCAT = motionCATRaw[currentPixelIndex];
        if (bIsValidhistoryPixel && currentCAT == ReprojCAT0ValidSamp)
        {
            motionVectorFilled[currentPixelIndex] = motionVectorRaw[currentPixelIndex];
            depthTextureFilled[currentPixelIndex] = depthTextureRaw[currentPixelIndex];
            motionCATFilled[currentPixelIndex] = currentCAT;
            return;
        }
    }
    
    float2 confirmedVector = 0.0f;
    float confirmedDepth = 0.0f;
    float2 contestedVector = 0.0f;
    float contestedDepth = -FLT_MAX;
    
    {
        for (int layer = 0; layer < atrousLayers; ++layer)
        {
            for (int i = 0; i < subsampleCount9PointPatch; ++i)
            {
                int2 finerIndex = currentPixelIndex + subsamplePixelOffset9PointPatch[i] * atrousLayerOffsets[layer];
                
                float2 elementVector = motionVectorRaw[finerIndex];
                float elementDepth = depthTextureRaw[finerIndex];
                uint elementCAT = motionCATRaw[finerIndex];
                
                if (elementCAT == ReprojCAT0ValidSamp)
                {
                    if (elementDepth > contestedDepth)
                    {
                        contestedVector = elementVector;
                        contestedDepth = elementDepth;
                    }
                }
            }
        }
    }
    
    float2 filteredVector = 0.0f;
    float filteredDepth = 0.0f;
    uint filteredCAT = ReprojCAT0ValidSamp;
   
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            depthTextureCoarser[coarserPixelIndex] = filteredDepth;
            motionCATCoarser[coarserPixelIndex] = filteredCAT;
        }
    }
}
