#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<uint> motionAdvectHalfTipX;
RWTexture2D<uint> motionAdvectHalfTipY;

RWTexture2D<float> depthAdvectedTip;
//RWTexture2D<float2> motionAdvectedTip;
RWTexture2D<float3> colorAdvectedTip;

Texture2D<float> prevDepthUnprojected;
Texture2D<float2> motionReprojectedTop;
Texture2D<float3> colorTextureTip;

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
	
    //FIXME: Is it distanceHalfTip or distanceHalfTop? They are both 0.5f for now
    const float distanceHalfTop = tipTopDistance.y;
	
    uint halfTipX = motionAdvectHalfTipX[currentPixelIndex];
    uint halfTipY = motionAdvectHalfTipY[currentPixelIndex];
    int2 halfTipIndex = int2(halfTipX & IndexLast13DigitsMask, halfTipY & IndexLast13DigitsMask);
    bool bIsHalfTipUnwritten = any(halfTipIndex == UnwrittenIndexIndicator);
    //float currDepthValue = currDepthUnprojected[halfTopIndex];
    float2 motionHalfTipAdv = motionReprojectedTop[halfTipIndex];
    float2 samplePosHalfTipAdv = screenPos + motionHalfTipAdv * distanceHalfTop;
    float2 caliberatedUVHalfTop = samplePosHalfTipAdv;
    caliberatedUVHalfTop = clamp(caliberatedUVHalfTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float depthTipAdvSample = prevDepthUnprojected.SampleLevel(bilinearClampedSampler, caliberatedUVHalfTop, 0);
    float3 colorTipAdvSample = colorTextureTip.SampleLevel(bilinearClampedSampler, caliberatedUVHalfTop, 0);
    if (bIsHalfTipUnwritten)
    {
        depthTipAdvSample = ImpossibleDepthValue;
        colorTipAdvSample = float3(ImpossibleColorValue, ImpossibleColorValue, ImpossibleColorValue);
    }
	
	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            depthAdvectedTip[currentPixelIndex] = depthTipAdvSample;
            colorAdvectedTip[currentPixelIndex] = colorTipAdvSample;
        }
    }
}
