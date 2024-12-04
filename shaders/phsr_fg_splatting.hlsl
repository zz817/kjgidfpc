#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> prevMotionVector;
Texture2D<float2> currMotionVector;
Texture2D<float2> motionReprojectedFullTopFiltered;
Texture2D<float> depthTextureTip;
Texture2D<float> depthTextureTop;

RWTexture2D<uint> motionReprojHalfTopX;
RWTexture2D<uint> motionReprojHalfTopY;
RWTexture2D<uint> motionReprojHalfTipX;
RWTexture2D<uint> motionReprojHalfTipY;

cbuffer shaderConsts : register(b0)
{
    float4x4 prevClipToClip;
    float4x4 clipToPrevClip;
    
    uint2 dimensions;
    float2 tipTopDistance;
    float2 viewportSize;
    float2 viewportInv;
};

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
    float2 mCurr = currMotionVector.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    float dCurr = depthTextureTop.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    float dPrev = depthTextureTip.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    
    const float distanceFull = tipTopDistance.x + tipTopDistance.y;
    const float distanceHalfTip = tipTopDistance.x;
    const float distanceHalfTop = tipTopDistance.y;
    
    float2 fullTopTranslation = mCurr * distanceFull;
    float2 fullTopTracedScreenPos = screenPos + fullTopTranslation;
    float2 fullTopTracedUV = clamp(fullTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float2 mPrev = prevMotionVector.SampleLevel(bilinearClampedSampler, fullTopTracedUV, 0);
    
    float2 rvPointRaw = viewportUV + mCurr;
    float alpha = distanceHalfTip;
    rvPointRaw -= 0.5f * alpha * (mCurr + mPrev);
    rvPointRaw -= 0.5f * alpha * alpha * (mCurr - mPrev);
    int2 rvPointIndexTop = floor(rvPointRaw * viewportSize);
    uint halfTopDepthAsUIntHigh19 = compressDepth(dCurr);

    uint packedAsUINTHigh19HalfTopX = halfTopDepthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTopY = halfTopDepthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
    
    float2 mCurrFiltered = motionReprojectedFullTopFiltered[currentPixelIndex];
    float2 mPrevLocalize = prevMotionVector.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    float2 rvPointFiltered = viewportUV + mCurrFiltered;
    rvPointFiltered -= 0.5f * alpha * (mCurrFiltered + mPrevLocalize);
    rvPointFiltered -= 0.5f * alpha * alpha * (mCurrFiltered - mPrevLocalize);
    int2 rvPointIndexTip = floor(rvPointFiltered * viewportSize);
    uint halfTipDepthAsUIntHigh19 = compressDepth(dPrev);

    uint packedAsUINTHigh19HalfTipX = halfTipDepthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipY = halfTipDepthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);

	{
        bool bIsValidHalfTopPixel = all(rvPointIndexTop < int2(dimensions)) && all(rvPointIndexTop >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojHalfTopX[rvPointIndexTop], packedAsUINTHigh19HalfTopX, originalValX);
            InterlockedMax(motionReprojHalfTopY[rvPointIndexTop], packedAsUINTHigh19HalfTopY, originalValY);
        }
    }
    
    {
        bool bIsValidHalfTipPixel = all(rvPointIndexTip < int2(dimensions)) && all(rvPointIndexTip >= int2(0, 0));
        if (bIsValidHalfTipPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojHalfTipX[rvPointIndexTip], packedAsUINTHigh19HalfTipX, originalValX);
            InterlockedMax(motionReprojHalfTipY[rvPointIndexTip], packedAsUINTHigh19HalfTipY, originalValY);
        }
    }
}
