#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> currMotionVector;
Texture2D<float> depthTextureTop;

RWTexture2D<uint> motionReprojFullTopX;
RWTexture2D<uint> motionReprojFullTopY;

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
    float2 fullTopTranslation = mCurr * distanceFull;
    float2 fullTopTracedScreenPos = screenPos + fullTopTranslation;
    int2 fullTopTracedIndex = floor(fullTopTracedScreenPos * viewportSize);
    float2 fullTopTracedFloatCenter = float2(fullTopTracedIndex) + float2(0.5f, 0.5f);
    float2 fullTopTracedPos = fullTopTracedFloatCenter * viewportInv;
    float2 samplePosFullTop = fullTopTracedPos - fullTopTranslation;
    float2 sampleUVFullTop = samplePosFullTop;
    sampleUVFullTop = clamp(sampleUVFullTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float fullTopDepth = depthTextureTop.SampleLevel(bilinearClampedSampler, sampleUVFullTop, 0);
    uint fullTopDepthAsUIntHigh19 = compressDepth(fullTopDepth);
    
    uint packedAsUINTHigh19FullTopX = fullTopDepthAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19FullTopY = fullTopDepthAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
    
	{
        bool bIsValidHalfTopPixel = all(fullTopTracedIndex < int2(dimensions)) && all(fullTopTracedIndex >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionReprojFullTopX[fullTopTracedIndex], packedAsUINTHigh19FullTopX, originalValX);
            InterlockedMax(motionReprojFullTopY[fullTopTracedIndex], packedAsUINTHigh19FullTopY, originalValY);
        }
    }
}
