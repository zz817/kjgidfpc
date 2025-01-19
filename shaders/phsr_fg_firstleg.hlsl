#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCurrRaw;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCurrRaw;

RWTexture2D<float2> motionVectorSearched;
RWTexture2D<float> depthTextureSearched;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
    
    float2 tipTopDistance;
    float2 viewportInv;//1.0f / float2(FinerDimension);
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

#define VALID_SAMPLE_FLAGGA 1
#define INVALID_SAMPLE_FLAG 0

bool isOutofScreen(float2 screenPos)
{
    return any(screenPos < 0.0f) || any(screenPos > 1.0f);
}

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    
    //Cached values
    float2 finerVectors[FIVE_POINT_STENCIL_SIZE];
    float finerDepths[FIVE_POINT_STENCIL_SIZE];
    int validSampleFlagga[FIVE_POINT_STENCIL_SIZE];
    
    float2 reprojAvgVector = float2(0.0f, 0.0f);
    float reprojAvgDepth = 0.0f;
    int validSamples = 0;
    {
        for (int i = 0; i < subsampleCount5PointStencil; ++i)
        {
            int2 patchElementIndex = currentPixelIndex + subsamplePixelOffset5PointStencil[i];
            float2 finerVector = motionVectorFiner[patchElementIndex];
            float finerDepth = depthTextureFiner[patchElementIndex];
            
            finerVectors[i] = finerVector;
            finerDepths[i] = finerDepth;
            
            if (all(finerVector < ImpossibleMotionBorderline))
            {
                reprojAvgVector = reprojAvgVector + finerVector;
                reprojAvgDepth = reprojAvgDepth + finerDepth;
                
                validSampleFlagga[i] = VALID_SAMPLE_FLAGGA;
                validSamples += 1;
            }
            else
            {
                validSampleFlagga[i] = INVALID_SAMPLE_FLAG;
            }
        }
        
        float normalization = SafeRcp(float(validSamples));
        reprojAvgVector = reprojAvgVector * normalization;
        reprojAvgDepth = reprojAvgDepth * normalization;
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < FinerDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorSearched[currentPixelIndex] = reprojAvgVector;
            depthTextureSearched[currentPixelIndex] = reprojAvgDepth;
        }
    }
}
