#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float3> inputVectorA;
Texture2D<float3> inputVectorB;

RWTexture2D<float3> innerProductAB;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
}

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
    float perPixelWeight = 0.0f;
    float validSamples = 0.0f;
    {
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
 
            if (all(finerVector < ImpossibleMotionValue))
            {
                filteredVector += finerVector;
                validSamples += 1.0f;
            }
        }
        if (validSamples == 0.0f)
        {
            filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
            perPixelWeight = 0.0f;
        }
        else
        {
            float perPixelWeight = validSamples * SafeRcp(float(subsampleCount4PointTian));
            float normalization = SafeRcp(validSamples);
            filteredVector *= normalization;
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < CoarserDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            motionReliabilityCoarser[coarserPixelIndex] = perPixelWeight;
        }
    }
}
