#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionReprojectedTop;
Texture2D<float2> motionReprojectedTip;

RWTexture2D<float2> motionReprojectedTopFiltered;
RWTexture2D<float2> motionReprojectedTipFiltered;

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
	
    float2 pixelCenter = float2(currentPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
	
    const float distanceHalfTop = tipTopDistance.y;
    const float distanceHalfTip = tipTopDistance.x;

    float2 motionHalfTopRaw[THREE_BY_THREE_PATCH_SIZE];
    float2 motionHalfTipRaw[THREE_BY_THREE_PATCH_SIZE];
    bool   motionHalfTopInvisible[THREE_BY_THREE_PATCH_SIZE];
    bool   motionHalfTipInvisible[THREE_BY_THREE_PATCH_SIZE];
    {
        for (int patchIndex = 0; patchIndex < subsampleCount9PointPatch; ++patchIndex)
        {
            int2 patchOffset                = subsamplePixelOffset9PointPatch[patchIndex];
            int2   patchPixelIndex          = currentPixelIndex + patchOffset;
            motionHalfTopRaw[patchIndex]    = motionReprojectedTop[patchPixelIndex];
            motionHalfTipRaw[patchIndex]    = motionReprojectedTip[patchPixelIndex];
            bool bIsHalfTopInvisible     = any(motionHalfTopRaw[patchIndex] >= ImpossibleMotionValue) ? true : false;
            bool bIsHalfTipInvisible     = any(motionHalfTipRaw[patchIndex] >= ImpossibleMotionValue) ? true : false;
            motionHalfTopInvisible[patchIndex] = bIsHalfTopInvisible;
            motionHalfTipInvisible[patchIndex] = bIsHalfTipInvisible;
        }
    }
    int topGapSamples = 0;
    int tipGapSamples = 0;
    int topClosestIndex = 0;
    int tipClosestIndex = 0;
    float topClosestDistance = 1000000.0f;
    float tipClosestDistance = 1000000.0f;
    {
        for (int patchIndex = 0; patchIndex < subsampleCount9PointPatch; ++patchIndex)
        {
            float2 mvHTopRaw           = motionHalfTopRaw[patchIndex];
            float2 mvHTipRaw           = motionHalfTipRaw[patchIndex];
            bool   bIsHalfTopInvisible = motionHalfTopInvisible[patchIndex];
            bool   bIsHalfTipInvisible = motionHalfTipInvisible[patchIndex];
            
            if (bIsHalfTopInvisible)
            {
                topGapSamples++;
            }
            if (bIsHalfTipInvisible)
            {
                tipGapSamples++;
            }
            float topDistance = 0.0f;
            float tipDistance = 0.0f;
            for (int innerLoop = 0; innerLoop < subsampleCount9PointPatch; ++innerLoop)
            {
                if (!motionHalfTopInvisible[innerLoop])
                {
                    topDistance += length(mvHTopRaw - motionHalfTopRaw[innerLoop]);
                }
                if (!motionHalfTipInvisible[innerLoop])
                {
                    tipDistance += length(mvHTipRaw - motionHalfTipRaw[innerLoop]);
                }
            }
            if (topDistance < topClosestDistance)
            {
                topClosestDistance = topDistance;
                topClosestIndex    = patchIndex;
            }
            if (tipDistance < tipClosestDistance)
            {
                tipClosestDistance = tipDistance;
                tipClosestIndex    = patchIndex;
            }
        }
    }
    
	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            bool bIsHalfTopInvisible = any(motionHalfTopRaw[0] >= ImpossibleMotionValue) ? true : false;
            bool bIsHalfTipInvisible = any(motionHalfTipRaw[0] >= ImpossibleMotionValue) ? true : false;

            float2 impossibleMvec = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);

            if (bIsHalfTopInvisible)
            {
                if (topGapSamples >= 5)
                {
                    motionReprojectedTopFiltered[currentPixelIndex] = motionHalfTopRaw[topClosestIndex];
                }
                else
                {
                    motionReprojectedTopFiltered[currentPixelIndex] = impossibleMvec;
                }
            }
            else
            {
                motionReprojectedTopFiltered[currentPixelIndex] = motionHalfTopRaw[0];
            }
            if (bIsHalfTipInvisible)
            {
                if (tipGapSamples >= 5)
                {
                    motionReprojectedTipFiltered[currentPixelIndex] = motionHalfTipRaw[tipClosestIndex];
                }
                else
                {
                    motionReprojectedTipFiltered[currentPixelIndex] = impossibleMvec;
                }
            }
            else
            {
                motionReprojectedTipFiltered[currentPixelIndex] = motionHalfTipRaw[0];
            }
        }

        motionReprojectedTopFiltered[currentPixelIndex] = motionHalfTopRaw[topClosestIndex];
        motionReprojectedTipFiltered[currentPixelIndex] = motionHalfTipRaw[tipClosestIndex];
    }
}
