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
    float  mDepthCurr             = depthTextureTop.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    uint   mDepthCurrAsUIntHigh19 = compressDepth(mDepthCurr);

    float2 fullTopTranslation     = mCurr * distanceFull;
    float2 fullTopTracedScreenPos = screenPos + fullTopTranslation;
    float2 samplePosFullTop       = fullTopTracedScreenPos;
    float2 sampleUVFullTop        = samplePosFullTop;
    sampleUVFullTop               = clamp(sampleUVFullTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    int2  fullTopTracedIndex      = floor(sampleUVFullTop * viewportSize);
    float fullTopDepth            = depthTextureTop.SampleLevel(bilinearClampedSampler, sampleUVFullTop, 0);
    uint fullTopDepthAsUIntHigh19 = compressDepth(fullTopDepth);

    float2 mPrev                  = prevMotionVector.SampleLevel(bilinearClampedSampler, sampleUVFullTop, 0);
    float  mDepthPrev             = depthTextureTip.SampleLevel(bilinearClampedSampler, sampleUVFullTop, 0);
    uint   mDepthPrevAsUIntHigh19 = compressDepth(mDepthPrev);

    float2 rendezvousPos = screenPos + mCurr;
    rendezvousPos        = rendezvousPos - 0.5 * alpha * (mCurr + mPrev);
    rendezvousPos        = rendezvousPos - 0.5 * alpha * alpha * (mCurr - mPrev);
    //rendezvousPos        = screenPos + 0.5 * mCurr;
    int2 rendezvousIndex = floor(rendezvousPos * viewportSize);
    
    uint packedAsUINTHigh19HalfTopX = mDepthCurrAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTopY = mDepthCurrAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipX = mDepthPrevAsUIntHigh19 | (fullTopTracedIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipY = mDepthPrevAsUIntHigh19 | (fullTopTracedIndex.y & IndexLast13DigitsMask);
    
	{
        bool bIsValidRVPixel = all(rendezvousIndex < int2(dimensions)) && all(rendezvousIndex >= int2(0, 0));
        if (bIsValidRVPixel)
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
