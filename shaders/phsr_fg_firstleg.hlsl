#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCurrRaw;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCurrRaw;

RWTexture2D<float2> motionVectorCoarser;
RWTexture2D<float> depthTextureCoarser;

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
    //Cached values
    float2 finerVectors[FOUR_POINTS_TIAN_SIZE];
    float finerDepths[FOUR_POINTS_TIAN_SIZE];
    int validSampleFlagga[FOUR_POINTS_TIAN_SIZE];
    
    float2 reprojectedVector = float2(0.0f, 0.0f);
    float reprojectedDepth = 0.0f;
    int validSamples = 0;
    {
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
            float2 finerVector = motionVectorFiner[finerIndex];
            float finerDepth = depthTextureFiner[finerIndex];
            
            finerVectors[i] = finerVector;
            finerDepths[i] = finerDepth;
            
            if (all(finerVector < ImpossibleMotionValue))
            {
                reprojectedVector = reprojectedVector + finerVector;
                reprojectedDepth = reprojectedDepth + finerDepth;
                
                validSampleFlagga[i] = VALID_SAMPLE_FLAGGA;
                validSamples += 1;
            }
            else
            {
                validSampleFlagga[i] = INVALID_SAMPLE_FLAG;
            }
            
            float normalization = SafeRcp(float(validSamples));
            reprojectedVector = reprojectedVector * normalization;
            reprojectedDepth = reprojectedDepth * normalization;
        }
    }
    
    bool isOutofScreenFlag = false; //true: inpaint, false: otherwise
    bool isOcclUncoverFlag = false; //true: uncover, false: inpaint
    {
        const float distanceTop = tipTopDistance.y;
        
        float unprojectedDepth = 0.0f;
        int invalidSampleCount = subsampleCount4PointTian - validSamples;
        for (int i = 0; i < subsampleCount4PointTian; ++i)
        {
            if (validSampleFlagga[i] == INVALID_SAMPLE_FLAG)
            {
                int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset4PointTian[i];
                float2 finerVector = finerVectors[i];
                float finerDepth = finerDepths[i];
                
                float2 pixelCenter = float2(finerIndex) + 0.5f;
                float2 viewportUV = pixelCenter * viewportInv;
                float2 screenPos = viewportUV;
                
                float2 halfTopTranslation = distanceTop * reprojectedVector;
                float2 topTracedScreenPos = screenPos - halfTopTranslation;
                
                if (isOutofScreen(topTracedScreenPos))
                {
                    isOutofScreenFlag = true;
                    break;
                }
                
                float2 sampleUVTop = clamp(topTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
                unprojectedDepth += depthTextureCurrRaw.SampleLevel(bilinearClampedSampler, sampleUVTop, 0);
            }
        }
        
        float normalizationInvalid = SafeRcp(float(invalidSampleCount));
        unprojectedDepth = unprojectedDepth * normalizationInvalid;
        
#ifdef DEPTH_LESSER_CLOSER
        if (reprojectedDepth < unprojectedDepth)
#endif
#ifdef DEPTH_GREATER_CLOSER
        if (reprojectedDepth > unprojectedDepth)
#endif
        {
            isOcclUncoverFlag = true;
        }
        else
        {
            isOcclUncoverFlag = false;
        }
    }
    
    float2 filteredVector = float2(0.0f, 0.0f);
    float filteredDepth = 0.0f;
    if (validSamples == subsampleCount4PointTian)
    {
        filteredVector = reprojectedVector;
        filteredDepth = reprojectedDepth;
    }
    else if (validSamples > 0)
    {
        if (isOutofScreenFlag)
        {
            filteredVector = reprojectedVector;
            filteredDepth = reprojectedDepth;
        }
        else if (!isOcclUncoverFlag)
        {
            filteredVector = reprojectedVector;
            filteredDepth = reprojectedDepth;
        }
        else
        {
            filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);;
            filteredDepth = 0.0f;
        }
    }
    else
    {
        filteredVector = float2(0.0f, 0.0f) + float2(ImpossibleMotionOffset, ImpossibleMotionOffset);
        filteredDepth = 0.0f;
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
