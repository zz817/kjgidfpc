#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> prevMotionVector;
Texture2D<float2> currMotionVector;
Texture2D<float> depthTextureTop;

RWTexture2D<uint> motionReprojX;
RWTexture2D<uint> motionReprojY;

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
    float2 mCurr = currMotionVector[currentPixelIndex];
    float dCurr = depthTextureTop[currentPixelIndex];
    uint depthAsUIntHigh19 = compressDepth(dCurr);
   
    const float distanceAlpha1st = tipTopDistance.x;
    const float distanceAlphaSqr = distanceAlpha1st * distanceAlpha1st;
    const float distanceFull = tipTopDistance.x + tipTopDistance.y;
    
    float2 topTranslation = mCurr * distanceFull;
    float2 topTracedScreenPos = screenPos + topTranslation;
    float2 topTracedBackUV = topTracedScreenPos * viewportInv;
    topTracedBackUV = clamp(topTracedBackUV, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float2 mPrev = prevMotionVector.SampleLevel(bilinearClampedSampler, topTracedBackUV, 0);
    
    float2 rvPoint = screenPos + mCurr;
    rvPoint += 0.5f * distanceAlpha1st * (-mCurr - mPrev);
    rvPoint += 0.5f * distanceAlphaSqr * (-mCurr + mPrev);
    
    int2 rvPointIndex = int2(rvPoint * viewportSize);
    
    uint packedAsUINTRvX = depthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTRvY = depthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
    
	{
        bool bIsValidHalfTopPixel = all(rvPointIndex < int2(dimensions)) && all(rvPointIndex >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojX[rvPointIndex], packedAsUINTRvX, originalValX);
            InterlockedMax(motionReprojY[rvPointIndex], packedAsUINTRvY, originalValY);
        }
    }
}
