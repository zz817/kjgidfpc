#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> prevMotionVector;
Texture2D<float2> currMotionVector;
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

    const float distanceFull    = tipTopDistance.x + tipTopDistance.y;
    const float distanceHalfTip = tipTopDistance.x;
    const float distanceHalfTop = tipTopDistance.y;
    const float alpha           = distanceHalfTip;

    float2 mCurr                  = currMotionVector.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    float2 fullTopTranslation     = mCurr * distanceFull;
    float2 fullTopTracedScreenPos = screenPos + fullTopTranslation;
    int2   fullTopTracedIndex     = floor(fullTopTracedScreenPos * viewportSize);
    float2 fullTopTracedUV        = fullTopTracedScreenPos;
    fullTopTracedUV               = clamp(fullTopTracedUV, 0.0f, 1.0f);
    float2 mPrev                  = prevMotionVector.SampleLevel(bilinearClampedSampler, fullTopTracedUV, 0);

    float2 rendezvousScreenPos = screenPos + mCurr;
    rendezvousScreenPos        = rendezvousScreenPos - 0.5f * alpha * (mCurr + mPrev);
    rendezvousScreenPos        = rendezvousScreenPos - 0.5f * alpha * alpha * (mCurr - mPrev);
    rendezvousScreenPos        = clamp(rendezvousScreenPos, 0.0f, 1.0f);
    int2 rendezvousIndex       = floor(rendezvousScreenPos * viewportSize);
   
    float halfTopDepth             = depthTextureTop.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    uint halfTopDepthAsUIntHigh19 = compressDepth(halfTopDepth);
    
    float halfTipDepth             = depthTextureTip.SampleLevel(bilinearClampedSampler, fullTopTracedUV, 0);
    uint halfTipDepthAsUIntHigh19 = compressDepth(halfTipDepth);
    
    uint packedAsUINTHigh19HalfTopX = halfTopDepthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTopY = halfTopDepthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipX = halfTipDepthAsUIntHigh19 | (fullTopTracedIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipY = halfTipDepthAsUIntHigh19 | (fullTopTracedIndex.y & IndexLast13DigitsMask);
    
	{
        bool bIsValidHalfTopPixel = all(rendezvousIndex < int2(dimensions)) && all(rendezvousIndex >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojHalfTopX[rendezvousIndex], packedAsUINTHigh19HalfTopX, originalValX);
            InterlockedMax(motionReprojHalfTopY[rendezvousIndex], packedAsUINTHigh19HalfTopY, originalValY);
            InterlockedMax(motionReprojHalfTipX[rendezvousIndex], packedAsUINTHigh19HalfTipX, originalValX);
            InterlockedMax(motionReprojHalfTipY[rendezvousIndex], packedAsUINTHigh19HalfTipY, originalValY);
        }
    }
}
