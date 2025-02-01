#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float> depthTextureFiner;
Texture2D<uint> motionCATFiner;

RWTexture2D<float2> motionVectorCoarser;
RWTexture2D<float> depthTextureCoarser;
RWTexture2D<uint> motionCATCoarser;

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
    
    float2 confirmedVector = 0.0f;
    float confirmedDepth = 0.0f;
    float2 contestedVector = 0.0f;
    float contestedDepth = -FLT_MAX;
    
    float2 filteredVector = 0.0f;
    float filteredDepth = 0.0f;
    uint filteredCAT = ReprojCAT0ValidSamp;
    
    int confirmedSamples = 0;
    int contestedSamples = 0;
    int invalidSamples = 0;
    {
        for (int stride = 0; stride < ATROUS_LAYERS; ++stride)
        {
            for (int i = 0; i < subsampleCount9PointPatch; ++i)
            {
                int2 finerIndex = finerPixelUpperLeft + subsamplePixelOffset9PointPatch[i] * atrousStrides[stride];
                float2 finerVector = motionVectorFiner[finerIndex];
            
                float2 pixelCenter = float2(finerIndex) + 0.5f;
                float2 viewportUV = pixelCenter * viewportInv;
                float2 screenPos = viewportUV;
            
                float2 halfTopTranslation = finerVector * tipTopDistance.y;
                float2 halfTopTracedScreenPos = screenPos + halfTopTranslation; //Now it's at the tip
                float2 sampleUVHalfTop = clamp(halfTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
                float finerDepth = depthTextureFiner.SampleLevel(bilinearClampedSampler, sampleUVHalfTop, 0);
            
                uint finerCAT = motionCATFiner[finerIndex];
 
                if (finerCAT == ReprojCAT0ValidSamp)
                {
                    confirmedVector += finerVector;
                    confirmedDepth += finerDepth;
                    confirmedSamples += 1;
                }
                else if (finerCAT == ReprojCAT1Contested)
                {
                //finerVector -= ContestedMotionCat2;
                    if (finerDepth > contestedDepth)
                    {
                        contestedVector = finerVector;
                        contestedDepth = finerDepth;
                    }
                    contestedSamples += 1;
                }
                else
                {
                    invalidSamples += 1;
                }
            }
        }
    }
    
    //#define DEBUG_COLORS       
    if (confirmedSamples >= subsampleCount9PointPatch)
    {
        filteredVector = confirmedVector * SafeRcp(float(confirmedSamples));
        filteredDepth = confirmedDepth * SafeRcp(float(confirmedSamples));
        filteredCAT = ReprojCAT0ValidSamp;
#ifdef DEBUG_COLORS
        filteredVector = debugCat1;
#endif
    }
    else if (contestedSamples > 0)
    {
        filteredVector = contestedVector;
        filteredDepth = contestedDepth;
        filteredCAT = ReprojCAT1Contested;
#ifdef DEBUG_COLORS
        filteredVector = debugCat2;
#endif
    }
    else if (confirmedSamples > 0)
    {
        confirmedVector /= float(confirmedSamples);
        confirmedDepth /= float(confirmedSamples);
        
        filteredVector = confirmedVector;
        filteredDepth = confirmedDepth;
        filteredCAT = ReprojCAT1Contested;
#ifdef DEBUG_COLORS
        filteredVector = debugCat3;
#endif
    }
    else
    {
        filteredVector = float2(0.0f, 0.0f);
        filteredDepth = 0.0f;
        filteredCAT = ReprojCAT2Unwritten;
#ifdef DEBUG_COLORS
        filteredVector = debugCat4;
#endif
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(coarserPixelIndex) < CoarserDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorCoarser[coarserPixelIndex] = filteredVector;
            depthTextureCoarser[coarserPixelIndex] = filteredDepth;
            motionCATCoarser[coarserPixelIndex] = filteredCAT;
        }
    }
}
