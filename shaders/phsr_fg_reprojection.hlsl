#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> currMotionVector;
Texture2D<float> depthTextureTop;

RWTexture2D<uint> motionReprojHalfTopX;
RWTexture2D<uint> motionReprojHalfTopY;

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
    
    const float distanceFull = tipTopDistance.x + tipTopDistance.y;
    const float distanceHalfTip = tipTopDistance.x;
    const float distanceHalfTop = tipTopDistance.y;
	
    //Actual top interpolation, effective, proven, trusted <-
    float2 halfTopTranslation = mCurr * distanceHalfTop;
    float2 halfTopTracedScreenPos = screenPos + halfTopTranslation;
    int2 halfTopTracedIndex = floor(halfTopTracedScreenPos * viewportSize);
    float2 halfTopTracedFloatCenter = float2(halfTopTracedIndex) + float2(0.5f, 0.5f);	
    float2 halfTopTracedPos = halfTopTracedFloatCenter * viewportInv;
    float2 samplePosHalfTop = halfTopTracedPos - halfTopTranslation;
    float2 sampleUVHalfTop = samplePosHalfTop;
    sampleUVHalfTop = clamp(sampleUVHalfTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float halfTopDepth = depthTextureTop.SampleLevel(bilinearClampedSampler, sampleUVHalfTop, 0);
    uint halfTopDepthAsUIntHigh19 = compressDepth(halfTopDepth);
    
    uint packedAsUINTHigh19HalfTopX = halfTopDepthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTopY = halfTopDepthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
	
	{
        bool bIsValidHalfTopPixel = all(halfTopTracedIndex < int2(dimensions)) && all(halfTopTracedIndex >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojHalfTopX[halfTopTracedIndex], packedAsUINTHigh19HalfTopX, originalValX);
            InterlockedMax(motionReprojHalfTopY[halfTopTracedIndex], packedAsUINTHigh19HalfTopY, originalValY);
        }
    }
}
