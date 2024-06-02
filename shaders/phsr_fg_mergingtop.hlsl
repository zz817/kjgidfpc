#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<uint> motionReprojHalfTopX;
RWTexture2D<uint> motionReprojHalfTopY;
RWTexture2D<uint> motionReprojFullTopX;
RWTexture2D<uint> motionReprojFullTopY;

RWTexture2D<float> depthReprojectedTop;
RWTexture2D<float2> motionReprojHalfTop;
RWTexture2D<float2> motionReprojFullTop;
RWTexture2D<float3> colorReprojectedTop;

Texture2D<float> currDepthUnprojected;
Texture2D<float2> currMotionUnprojected;
Texture2D<float3> colorTextureTop;

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
	
    uint halfTopX = motionReprojHalfTopX[currentPixelIndex];
    uint halfTopY = motionReprojHalfTopY[currentPixelIndex];
    int2 halfTopIndex = int2(halfTopX & IndexLast13DigitsMask, halfTopY & IndexLast13DigitsMask);
    bool bIsHalfTopUnwritten = any(halfTopIndex == UnwrittenIndexIndicator);
    //float currDepthValue = currDepthUnprojected[halfTopIndex];
    float2 motionVectorHalfTop = currMotionUnprojected[halfTopIndex];
    float2 samplePosHalfTop = screenPos - motionVectorHalfTop * distanceHalfTop;
    float2 motionCaliberatedUVHalfTop = samplePosHalfTop;
    motionCaliberatedUVHalfTop = clamp(motionCaliberatedUVHalfTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float depthTopRepSample = currDepthUnprojected.SampleLevel(bilinearClampedSampler, motionCaliberatedUVHalfTop, 0);
    float2 motionTopRepSample = currMotionUnprojected.SampleLevel(bilinearClampedSampler, motionCaliberatedUVHalfTop, 0);
    float3 colorTopRepSample = colorTextureTop.SampleLevel(bilinearClampedSampler, motionCaliberatedUVHalfTop, 0);
    if (bIsHalfTopUnwritten)
    {
        colorTopRepSample = float3(ImpossibleColorValue, ImpossibleColorValue, ImpossibleColorValue);
        motionTopRepSample = float2(ImpossibleMotionValue, ImpossibleMotionValue);
        depthTopRepSample = ImpossibleDepthValue;
    }
    
    uint fullTopX = motionReprojFullTopX[currentPixelIndex];
    uint fullTopY = motionReprojFullTopY[currentPixelIndex];
    int2 fullTopIndex = int2(fullTopX & IndexLast13DigitsMask, fullTopY & IndexLast13DigitsMask);
    bool bIsFullTopUnwritten = any(fullTopIndex == UnwrittenIndexIndicator);
    //float currDepthValue = currDepthUnprojected[halfTopIndex];
    float2 motionVectorFullTop = currMotionUnprojected[fullTopIndex];
    float2 samplePosFullTop = screenPos - motionVectorFullTop * tipTopDistance.x;
    float2 motionCaliberatedUVFullTop = samplePosFullTop;
    motionCaliberatedUVFullTop = clamp(motionCaliberatedUVFullTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    //float depthFullTopRepSample = currDepthUnprojected.SampleLevel(bilinearClampedSampler, motionCaliberatedUVFullTop, 0);
    float2 motionFullTopRepSample = currMotionUnprojected.SampleLevel(bilinearClampedSampler, motionCaliberatedUVFullTop, 0);
    //float3 colorFullTopRepSample = colorTextureTop.SampleLevel(bilinearClampedSampler, motionCaliberatedUVFullTop, 0);
    if (bIsFullTopUnwritten)
    {
        //colorFullTopRepSample = float3(ImpossibleColorValue, ImpossibleColorValue, ImpossibleColorValue);
        motionFullTopRepSample = float2(ImpossibleMotionValue, ImpossibleMotionValue);
        //depthFullTopRepSample = ImpossibleDepthValue;
    }
	
	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            depthReprojectedTop[currentPixelIndex] = depthTopRepSample;
            motionReprojHalfTop[currentPixelIndex] = motionTopRepSample;
            motionReprojFullTop[currentPixelIndex] = motionFullTopRepSample;
            colorReprojectedTop[currentPixelIndex] = colorTopRepSample;
        }
    }
}
