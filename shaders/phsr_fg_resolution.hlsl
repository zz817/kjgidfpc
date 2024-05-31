#include "phsr_common.hlsli"

Texture2D<float3> colorReprojectedTop;
Texture2D<float3> colorAdvectedTip;
Texture2D<float> depthReprojectedTop;
Texture2D<float> depthAdvectedTip;

//Texture2D<float4> uiColorTexture;

RWTexture2D<float4> outputColorTexture;
RWTexture2D<float> outputDepthTexture;

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
    
    float3 topSample = colorReprojectedTop[currentPixelIndex];
    float topDepth = depthReprojectedTop[currentPixelIndex];
    float3 tipSample = colorAdvectedTip[currentPixelIndex];
    float tipDepth = depthAdvectedTip[currentPixelIndex];
    
    bool isTopVisible = topDepth > ImpossibleDepthValue / 2.0f ? false : true;
    bool isTipVisible = tipDepth > ImpossibleDepthValue / 2.0f ? false : true;
    
    float3 finalSample = float3(0.0f, 0.0f, 0.0f);
    float finalDepth = 0.0f;
    if (isTopVisible)
    {
        finalSample = topSample;
        finalDepth = topDepth;
#ifdef DEBUG_COLORS
        finalSample = debugRed;
        //finalSample = float3(halfTopTranslation, 0.0f);
#endif
    }
    else if (isTipVisible)
    {
        //finalSample = spareDepth < tipDepth ? spareSample : tipSample;
        finalSample = tipSample;
        finalDepth = tipDepth;
#ifdef DEBUG_COLORS
        finalSample = debugCyan;
        //finalSample = float3(halfTipTranslation, 0.0f);
#endif
    }
    else
    {
        finalSample = float3(0.0f, 0.0f, 0.0f) + float3(ImpossibleColorValue, ImpossibleColorValue, ImpossibleColorValue);
        finalDepth = ImpossibleDepthValue;
#ifdef DEBUG_COLORS
        finalSample = debugYellow;
        //finalSample = float3(halfTipTranslation, 0.0f);
#endif
    }

	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            //float4 uiColorBlendingIn = uiColorTexture[currentPixelIndex];
            //float3 finalOutputColor = lerp(finalSample, uiColorBlendingIn.rgb, uiColorBlendingIn.a);
            outputColorTexture[currentPixelIndex] = float4(finalSample, 1.0f);
            outputDepthTexture[currentPixelIndex] = finalDepth;
            //outputTexture[currentPixelIndex] = float4(motionUnprojected[currentPixelIndex], motionUnprojected[currentPixelIndex]);
            //outputTexture[currentPixelIndex] = float4(abs(velocityHalfPyr), 0.0f, 1.0f);
        }
    }
}
