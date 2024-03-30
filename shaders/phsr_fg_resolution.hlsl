#include "phsr_common.hlsli"

Texture2D<float3> colorTextureTip;
Texture2D<float> depthTextureTip;
Texture2D<float3> colorTextureTop;
Texture2D<float> depthTextureTop;

Texture2D<float2> currMotionUnprojected;
Texture2D<float2> prevMotionUnprojected;

Texture2D<float2> motionReprojectedHalfTop;

Texture2D<float4> uiColorTexture;

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

static float3 debugRed = float3(1.0f, 0.0f, 0.0f);
static float3 debugGreen = float3(0.0f, 1.0f, 0.0f);
static float3 debugBlue = float3(0.0f, 0.0f, 1.0f);
static float3 debugYellow = float3(1.0f, 1.0f, 0.0f);
static float3 debugMagenta = float3(1.0f, 0.0f, 1.0f);
static float3 debugCyan = float3(0.0f, 1.0f, 1.0f);

//#define DEBUG_COLORS

[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    float2 pixelCenter = float2(currentPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;

    float2 velocityHalf = motionReprojectedHalfTop[currentPixelIndex];
    
    bool isTopInvisible = any(velocityHalf >= ImpossibleMotionValue) ? true : false;
    bool isTopVisible = !isTopInvisible;
    if (isTopInvisible)
    {
        velocityHalf -= float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
    }

    if (isTopInvisible && isProxTopVisible)
    {
        isTopVisible = true;
        velocityHalf = velocityProxTop;
    }
    
    const float distanceTip = tipTopDistance.x;
    const float distanceTop = tipTopDistance.y;

    float2 halfTipTranslation = distanceTip * velocityHalf;
    float2 halfTopTranslation = distanceTop * velocityHalf;

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
        //finalSample = float3(halfTopTranslation, 0.0f);
#endif
    }
    else
    {
        finalSample = tipSample;
#ifdef DEBUG_COLORS
        finalSample = debugGreen;
        //finalSample = float3(halfTipTranslation, 0.0f);
#endif
    }

	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            float4 uiColorBlendingIn = uiColorTexture[currentPixelIndex];
            float3 finalOutputColor = lerp(finalSample, uiColorBlendingIn.rgb, uiColorBlendingIn.a);
            outputTexture[currentPixelIndex] = float4(finalSample, 1.0f);
            //outputTexture[currentPixelIndex] = float4(motionUnprojected[currentPixelIndex], motionUnprojected[currentPixelIndex]);
            //outputTexture[currentPixelIndex] = float4(velocityTopCombined, velocityTipCombined) * 10.0f;
        }
    }
}
