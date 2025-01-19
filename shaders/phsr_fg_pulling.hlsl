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
    float2 contestedFurthestVector = float2(0.0f, 0.0f);
    float reprojectedDepth = 0.0f;
    float contestedFurthestDepth = ClosestDepth;
    
    float2 filteredVector = float2(0.0f, 0.0f);
    float filteredDepth = 0.0f;
    {
        float2 validVector = float2(0.0f, 0.0f);
        int validSamples = 0;
        int contestedSamples = 0;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
            float finerDepth = depthTextureFiner[finerIndex];
            
            if (all(finerVector < ImpossibleMotionBorderline))
            {
                reprojectedVector += finerVector;
                reprojectedDepth += finerDepth;
                validSamples += 1;
            }
            else if (all(finerVector) < ImpossibleMotionUnwritten)
            {
                finerVector -= float2(ImpossibleMotionContested, ImpossibleMotionContested);
                //We want the furthest depth chosen as the contested
#ifdef DEPTH_LESSER_CLOSER
                if (finerDepth > contestedFurthestDepth)
#endif
#ifdef DEPTH_GREATER_CLOSER
                if (finerDepth < contestedFurthestDepth)
#endif
                {
                    contestedFurthestVector = finerVector;
                    contestedFurthestDepth = finerDepth;
                }
                contestedSamples += 1;
            }
            else
            {
                //Do nothing
            }
        }
        int unwrittenSamples = subsampleCount4PointTian - validSamples - contestedSamples;
        reprojectedVector = reprojectedVector * SafeRcp(float(validSamples));
        reprojectedDepth = reprojectedDepth * SafeRcp(float(validSamples));
        
        if (validSamples == subsampleCount4PointTian)
        {
            filteredVector = reprojectedVector;
            filteredDepth = reprojectedDepth;
        }
        else if (contestedSamples > 0)
        {
            filteredVector = contestedFurthestVector;
            filteredDepth = contestedFurthestDepth;
        }
        else if (unwrittenSamples == subsampleCount4PointTian)
        {
            filteredVector = float2(ImpossibleMotionUnwritten, ImpossibleMotionUnwritten);
            filteredDepth = 0.0f;
        }
        else
        {
            filteredVector = reprojectedVector;
            filteredVector += float2(ImpossibleMotionContested, ImpossibleMotionContested);
            filteredDepth = reprojectedDepth;
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
