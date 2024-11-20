#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<uint> motionReprojFullTopX;
RWTexture2D<uint> motionReprojFullTopY;

RWTexture2D<float2> motionReprojectedFullTop;

Texture2D<float> currDepthUnprojected;
Texture2D<float2> currMotionUnprojected;

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
	
    const float distanceFull = tipTopDistance.x + tipTopDistance.y;
	
    uint fullTopX = motionReprojFullTopX[currentPixelIndex];
    uint fullTopY = motionReprojFullTopY[currentPixelIndex];
    int2 fullTopIndex = int2(fullTopX & IndexLast13DigitsMask, fullTopY & IndexLast13DigitsMask);
    bool bIsFullTopUnwritten = any(fullTopIndex == UnwrittenIndexIndicator);
    float currDepthValue = currDepthUnprojected[fullTopIndex];
    float2 motionVectorFullTop = currMotionUnprojected[fullTopIndex];
    float2 samplePosFullTop = screenPos - motionVectorFullTop * distanceFull;
    float2 motionCaliberatedUVFullTop = samplePosFullTop;
    motionCaliberatedUVFullTop = clamp(motionCaliberatedUVFullTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float2 motionFullTopCaliberated = currMotionUnprojected.SampleLevel(bilinearClampedSampler, motionCaliberatedUVFullTop, 0);
    if (bIsFullTopUnwritten)
    {
        motionFullTopCaliberated = float2(0.0f, 0.0f);// + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
    }
	
	{
        bool bIsValidPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidPixel)
        {
            motionReprojectedFullTop[currentPixelIndex] = motionFullTopCaliberated;
        }
    }
}
