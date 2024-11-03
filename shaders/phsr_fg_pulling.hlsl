#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float> depthTextureFiner;

RWTexture2D<float2> motionVectorCoarser;
RWTexture2D<float> depthTextureCoarser; //This is coarse too

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
    int2 coarserPixelIndex = dispatchThreadId;
    
    int2 finerPixelUpperLeft = 2 * coarserPixelIndex;
    float2 filteredVector = 0.0f;
    float filteredDepth = 0.0f;
    {
        float validSamples = 0.0f;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
            
            float2 pixelCenter = float2(finerIndex) + 0.5f;
            float2 viewportUV = pixelCenter * viewportInv;
            float2 screenPos = viewportUV;
            
            float2 halfTopTranslation = finerVector * tipTopDistance.y;
            float2 halfTopTracedScreenPos = screenPos + halfTopTranslation; //Now it's at the tip
            float2 sampleUVHalfTop = clamp(halfTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
            float finerDepth = depthTextureFiner.SampleLevel(bilinearClampedSampler, sampleUVHalfTop, 0);
 
            if (all(finerVector < ImpossibleMotionValue))
            {
                filteredVector += finerVector;
                filteredDepth += finerDepth;
                validSamples += 1.0f;
            }
        }
        if (validSamples == 0.0f)
        {
            filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
            filteredDepth = 0.0f;
        }
        else
        {
            float perPixelWeight = validSamples * SafeRcp(float(subsampleCount4PointTian));
            float normalization = SafeRcp(validSamples);
            filteredVector *= normalization;
            filteredDepth *= normalization;
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < CoarserDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            depthTextureCoarser[coarserPixelIndex] = filteredDepth;
        }
    }
}
