#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCurrRaw;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCurrRaw;

RWTexture2D<float2> motionVectorCoarser;
RWTexture2D<float> depthTextureCoarser;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
    
    float2 tipTopDistance;
    float2 viewportInv; //1.0f / float2(FinerDimension);
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

#define VALID_SAMPLE_FLAGGA 1
#define INVALID_SAMPLE_FLAG 0

bool isOutofScreen(float2 screenPos)
{
    return any(screenPos < 0.0f) || any(screenPos > 1.0f);
}

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 coarserPixelIndex = dispatchThreadId;
    
    int2 finerPixelUpperLeft = 2 * coarserPixelIndex;
    //Cached values
    float2 reprojectedVector = float2(0.0f, 0.0f);
    float2 contestedVector = float2(0.0f, 0.0f);
    float reprojectedDepth = 0.0f;
    float contestedDepth = 0.0f;
    
    float2 filteredVector = float2(0.0f, 0.0f);
    float filteredDepth = 0.0f;
    {
        int validSamples = 0;
        int contestedSamples = 0;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
            float finerDepth = depthTextureFiner[finerIndex];
            
            if (all(finerVector < ImpossibleMotionValue))
            {
                reprojectedVector += finerVector;
                reprojectedDepth += finerDepth;
                validSamples += 1;
            }
            else if (all(finerVector < ImpossibleMotionOffset))
            {
                contestedVector += (finerVector - float2(ImpossibleMotionValue, ImpossibleMotionValue));
                contestedDepth += finerDepth;
                contestedSamples += 1;
            }
        }
        if (validSamples == subsampleCount4PointTian)
        {
            filteredVector = reprojectedVector / float(subsampleCount4PointTian);
            filteredDepth = reprojectedDepth / float(subsampleCount4PointTian);
        }
        else if (contestedSamples > 0)
        {
            filteredVector = contestedVector / float(contestedSamples);
            filteredDepth = contestedDepth / float(contestedSamples);
            filteredVector += float2(ImpossibleMotionValue, ImpossibleMotionValue);
        }
        else
        {
            filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
            filteredDepth = 0.0f;
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < CoarserDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            depthTextureCoarser[coarserPixelIndex] = filteredDepth;
        }
    }
}
