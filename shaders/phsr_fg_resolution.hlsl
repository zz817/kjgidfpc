#include "phsr_common.hlsli"

Texture2D<float3> colorTextureTip;
Texture2D<float> depthTextureTip;
Texture2D<float3> colorTextureTop;
Texture2D<float> depthTextureTop;

Texture2D<float2> motionReprojectedHalfTopPyr;
Texture2D<float2> motionReprojectedHalfTopRaw;
Texture2D<uint> motionReprojectedCAT;

//Texture2D<float4> uiColorTexture;

RWTexture2D<float4> outputTexture;

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

//#define DEBUG_COLORS
//#define DEBUG_MV

[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    float2 pixelCenter = float2(currentPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;

    uint velocityHalfCAT = motionReprojectedCAT[currentPixelIndex];
    float2 velocityHalfRaw = motionReprojectedHalfTopRaw[currentPixelIndex];
    bool isTopInvisible = velocityHalfCAT == ReprojCAT2Unwritten ? true : false;
    bool isTopVisible = !isTopInvisible;
    
    float2 velocityHalfPyr = motionReprojectedHalfTopPyr[currentPixelIndex];
    
    const float distanceTip = tipTopDistance.x;
    const float distanceTop = tipTopDistance.y;

    float2 halfTipTranslation = distanceTip * velocityHalfPyr;
    float2 halfTopTranslation = distanceTop * velocityHalfRaw;
    
    float2 tipTracedScreenPos = screenPos + halfTipTranslation;
    float2 topTracedScreenPos = screenPos - halfTopTranslation;
    
    float2 sampleUVTip = tipTracedScreenPos;
    sampleUVTip = clamp(sampleUVTip, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float2 sampleUVTop = topTracedScreenPos;
    sampleUVTop = clamp(sampleUVTop, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    
    float3 tipSample = colorTextureTip.SampleLevel(bilinearClampedSampler, sampleUVTip, 0);
    float tipDepth = depthTextureTip.SampleLevel(bilinearClampedSampler, sampleUVTip, 0);
    float3 topSample = colorTextureTop.SampleLevel(bilinearClampedSampler, sampleUVTop, 0);
    float topDepth = depthTextureTop.SampleLevel(bilinearClampedSampler, sampleUVTop, 0);
    
    float3 finalSample = float3(0.0f, 0.0f, 0.0f);
    if (isTopVisible)
    {
        finalSample = topSample;
#ifdef DEBUG_COLORS
        finalSample = debugRed;
#endif
    }
    else
    {
        finalSample = tipSample;
#ifdef DEBUG_COLORS
        finalSample = debugGreen;
#endif
    }
    
#ifdef DEBUG_MV
    float2 debugMV = motionReprojectedHalfTopPyr.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    finalSample = 12.8f * float3(abs(debugMV), 0.0f);
#endif

	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            outputTexture[currentPixelIndex] = float4(finalSample, 1.0f);
        }
    }
}
