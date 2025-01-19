#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCoarser;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCoarser;

RWTexture2D<float2> motionVectorFinerUAV;
RWTexture2D<float> depthTextureFinerUAV;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
    
    float2 tipTopDistance;
    float2 viewportInv;//1.0f / float2(FinerDimension);
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 finerPixelIndex = dispatchThreadId;
    int2 coarserPixelIndex = finerPixelIndex / 2;
    
    float2 pixelCenter = float2(finerPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
    
    float2 unpushedVector = motionVectorFiner[finerPixelIndex];
    float2 fetchedVector = motionVectorCoarser[coarserPixelIndex];
    float unpushedDepth = depthTextureFiner[finerPixelIndex];
    float fetchedFinerDepth = depthTextureCoarser[coarserPixelIndex];
    
    float2 halfTopTranslation = fetchedVector * tipTopDistance.y;
    float2 halfTopTracedScreenPos = screenPos + halfTopTranslation; //Now it's at the tip
    float2 sampleUVHalfTop = clamp(halfTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    
    float2 selectedVector = 0.0f;
    float selectedDepth = 0.0f;
    if (any(unpushedVector == ImpossibleMotionUnwritten))
    {
        selectedVector = fetchedVector;
    }
    else if (any(unpushedVector > ImpossibleMotionContested))
    {
#ifdef DEPTH_LESSER_CLOSER
        if (unpushedDepth < fetchedFinerDepth)
#endif
#ifdef DEPTH_GREATER_CLOSER
        if (unpushedDepth > fetchedFinerDepth)
#endif
        {
            selectedVector = fetchedVector;
        }
        else
        {
            selectedVector = unpushedVector;
        }
    }
    else
    {
        selectedVector = unpushedVector;
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(finerPixelIndex) < FinerDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorFinerUAV[finerPixelIndex] = selectedVector;
            depthTextureFinerUAV[finerPixelIndex] = 0.0f;
        }
    }
}
