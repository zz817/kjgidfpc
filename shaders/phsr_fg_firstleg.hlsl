#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCurrRaw;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCurrRaw;

RWTexture2D<float2> motionVectorCoarser;
RWTexture2D<float> depthCoarser;

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
    int2 coarserPixelIndex = dispatchThreadId;
    
    int2 finerPixelUpperLeft = 2 * coarserPixelIndex;
    float2 finerVectors[FOUR_POINTS_TIAN_SIZE];
    int validSampleFlagga[FOUR_POINTS_TIAN_SIZE];
    
    float2 filteredVector = 0.0f;
    float filteredDepthValid = 0.0f;
    int validSamples = 0;
    {
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
            finerVectors[i] = finerVector;
            float finerDepth = depthTextureFiner[finerIndex];
            
            if (all(finerVector < ImpossibleMotionContested))
            {
                filteredVector += finerVector;
                filteredDepthValid += finerDepth;
                validSamples += 1;
                validSampleFlagga[i] = VALID_SAMPLE_FLAGGA;
            }
            else
            {
                validSampleFlagga[i] = INVALID_SAMPLE_FLAG;
            }
        }
        float normalization = SafeRcp(float(validSamples));
        filteredVector *= normalization;
        filteredDepthValid *= normalization;
    }
    
    float filteredDepth = 0.0f;
    if (validSamples != subsampleCount4PointTian)
    {
        float filteredDepthInvalid = 0.0f;
        int invalidSamples = subsampleCount4PointTian - validSamples;
        bool isBoundaryCondition = false;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            if (validSampleFlagga[i] == INVALID_SAMPLE_FLAG)
            {
                int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
                float2 pixelCenter = float2(finerIndex) + 0.5f;
                float2 viewportUV = pixelCenter * viewportInv;
                float2 screenPos = viewportUV;
                float2 halfTopTranslation = filteredVector * tipTopDistance.y;
                float2 reversedTracedPos = screenPos - halfTopTranslation; //+ -> tip; - -> top
                isBoundaryCondition = isBoundaryCondition | isOutofScreen(reversedTracedPos);
                float2 reversedUV = clamp(reversedTracedPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
                float fetchedFinerDepth = depthTextureCurrRaw.SampleLevel(bilinearClampedSampler, reversedUV, 0);
            
                filteredDepthInvalid += fetchedFinerDepth;
            }
        }
        float normalization = SafeRcp(float(invalidSamples));
        filteredDepthInvalid *= normalization;
        bool isOcclusionFilling = filteredDepthValid < filteredDepthInvalid ? false : true;
        
        bool shouldNotFill = validSamples == 0 ? true : false;
        shouldNotFill = shouldNotFill | (!isBoundaryCondition && !isOcclusionFilling);
        
        if (shouldNotFill)
        {
            filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionConquered, ImpossibleMotionConquered);
            filteredDepth = 0.0f; //Least prioritized possible depth
        }
        else
        {
            filteredVector = filteredVector;
            filteredDepth = filteredDepthValid;
        }
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < CoarserDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            depthCoarser[coarserPixelIndex] = filteredDepth;
        }
    }
}
