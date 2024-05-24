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
    
    float2 surfaceInv = float2(1.0f, 1.0f) / float2(FinerDimension);
    
    float2 pixelCenter = float2(finerPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
    
    float2 unpushedVector = motionVectorFiner[finerPixelIndex];
    float2 fetchedVector = motionVectorCoarser[coarserPixelIndex];
    
    float2 halfTopTranslation = fetchedVector * tipTopDistance.y;
    float2 halfTopTracedScreenPos = screenPos + halfTopTranslation; //Now it's at the tip
    float2 sampleUVHalfTop = clamp(halfTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float fetchedFinerDepth = depthTextureFiner.SampleLevel(bilinearClampedSampler, sampleUVHalfTop, 0);
    
    float2 selectedVector = 0.0f;
    float coarserDepth = depthTextureCoarser[coarserPixelIndex];
    float votedDepth = 0.0f;
    if (any(unpushedVector >= ImpossibleMotionValue))
    {
        float totalVotes = 0.0f;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 elementIndex = finerPixelIndex + subsamplePixelOffset9PointPatch[i];
            float2 unpushedElement = motionVectorFiner[elementIndex];
            float elementDepth = depthTextureFiner[elementIndex];
            if (all(unpushedElement < ImpossibleMotionValue))
            {
                votedDepth += elementDepth;
                totalVotes += 1.0f;
            }
        }
        totalVotes = 1.0f;
        if (totalVotes > 0.0f)
        {
            float normalizationFactor = SafeRcp(totalVotes);
            votedDepth = votedDepth * normalizationFactor;
            if ((abs(votedDepth - fetchedFinerDepth) * SafeRcp(votedDepth)) < 0.25f)
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
            depthTextureFinerUAV[finerPixelIndex] = votedDepth;
        }
    }
}
