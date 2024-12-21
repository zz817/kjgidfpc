#include "phsr_common.hlsli"

RWTexture2D<uint> motionReprojX;
RWTexture2D<uint> motionReprojY;

RWTexture2D<float4> outputTexture;

Texture2D<float3> colorTextureTip;
Texture2D<float> depthTextureTip;
Texture2D<float2> motionVectorTextureTip;

Texture2D<float3> colorTextureTop;
Texture2D<float> depthTextureTop;
Texture2D<float2> motionVectorTextureTop;

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

// #define DEBUG_COLORS

[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    float2 pixelCenter = float2(currentPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
    
    const float distanceHalfTip = tipTopDistance.x;
    const float distanceHalfTop = tipTopDistance.y;
    const float distanceFull = distanceHalfTip + distanceHalfTop;
    const float distanceAlpha1st = tipTopDistance.x;
    const float distanceAlphaSqr = distanceAlpha1st * distanceAlpha1st;
    
    uint reprojX = motionReprojX[currentPixelIndex];
    uint reprojXIndex = reprojX & IndexLast13DigitsMask;
    uint reprojY = motionReprojY[currentPixelIndex];
    uint reprojYIndex = reprojY & IndexLast13DigitsMask;
    uint2 reprojIndexTop = uint2(reprojXIndex, reprojYIndex);
    float2 topMotionVector = float2(0.0f, 0.0f);
    
    bool isTopInvisible = ((reprojXIndex == UnwrittenIndexIndicator) || (reprojYIndex == UnwrittenIndexIndicator));
    
    if (isTopInvisible)
    {
        topMotionVector = motionVectorTextureTip[currentPixelIndex];
    }
    else
    {
        topMotionVector = motionVectorTextureTop[reprojIndexTop];
    }
    
    float2 topUV = float2(0.0f, 0.0f);
    float2 tipUV = float2(0.0f, 0.0f);
    if (isTopInvisible)
    {
        topUV = screenPos - topMotionVector * distanceHalfTop;
        tipUV = screenPos + topMotionVector * distanceHalfTip;
    }
    else
    {
        float2 departUV = (float2(reprojIndexTop) + float2(0.5f, 0.5f)) * viewportInv;
        float2 trackedUV = departUV + topMotionVector * distanceFull;
        float2 tipMotionVector = motionVectorTextureTip.SampleLevel(bilinearClampedSampler, trackedUV, 0);
        
        topUV = screenPos;
        topUV += 0.5f * distanceAlpha1st * (topMotionVector + tipMotionVector);
        topUV += 0.5f * distanceAlphaSqr * (topMotionVector - tipMotionVector);
        tipUV = -topMotionVector + topUV;
    }
    
    float3 finalSample = float3(0.0f, 0.0f, 0.0f);
    
    float3 topColor = colorTextureTop.SampleLevel(bilinearClampedSampler, topUV, 0);
    float3 tipColor = colorTextureTip.SampleLevel(bilinearClampedSampler, tipUV, 0);
    float topDepth = depthTextureTop.SampleLevel(bilinearClampedSampler, topUV, 0);
    float tipDepth = depthTextureTip.SampleLevel(bilinearClampedSampler, tipUV, 0);
    
    if (any(tipUV < 0.0f) || any(tipUV > 1.0f))
    {
        finalSample = topColor;
#ifdef DEBUG_COLORS
        finalSample = debugRed;
#endif
    }
    else if (any(topUV < 0.0f) || any(topUV > 1.0f))
    {
        finalSample = tipColor;
#ifdef DEBUG_COLORS
        finalSample = debugGreen;
#endif
    }
    /*
    else if (abs(topDepth - tipDepth) < 0.0028f)
    {
        float3 diffColor = abs(topColor - tipColor);
        float diffLuma = dot(diffColor, float3(0.299f, 0.587f, 0.114f));
        if (diffLuma > 0.13f)
        {
            finalSample = lerp(topColor, tipColor, distanceHalfTip);
#ifdef DEBUG_COLORS
        finalSample = debugBlue;
#endif
        }
        else
        {
            finalSample = topColor;
#ifdef DEBUG_COLORS
        finalSample = debugYellow;
#endif
        }
    }
    */
    else
    {
        if (topDepth > tipDepth)
        {
            finalSample = topColor;
#ifdef DEBUG_COLORS
        finalSample = debugMagenta;
#endif
        }
        else
        {
            finalSample = tipColor;
#ifdef DEBUG_COLORS
        finalSample = debugCyan;
#endif
        }
    }
    
    //finalSample = float3(abs(topMotionVector), 0.0f);
    
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            //float4 uiColorBlendingIn = uiColorTexture[currentPixelIndex];
            //float3 finalOutputColor = lerp(finalSample, uiColorBlendingIn.rgb, uiColorBlendingIn.a);
            outputTexture[currentPixelIndex] = float4(finalSample, 1.0f);
            //outputTexture[currentPixelIndex] = float4(motionUnprojected[currentPixelIndex], motionUnprojected[currentPixelIndex]);
            //outputTexture[currentPixelIndex] = float4(abs(velocityHalfPyr), 0.0f, 1.0f);
        }
    }
}
