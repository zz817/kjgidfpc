#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCoarser;
Texture2D<float> depthTextureFiner;
Texture2D<float> depthTextureCoarser;
Texture2D<uint> motionCATFiner;
Texture2D<uint> motionCATCoarser;

RWTexture2D<float2> motionVectorFinerUAV;
RWTexture2D<float> depthTextureFinerUAV;
RWTexture2D<uint> motionCATFinerUAV;

cbuffer shaderConsts : register(b0)
{
    uint2 FinerDimension;
    uint2 CoarserDimension;
    
    float2 tipTopDistance;
    float2 viewportInv; //1.0f / float2(FinerDimension);
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
    
    float2 unpushedVector = motionVectorFiner[finerPixelIndex];
    float unpushedDepth = depthTextureFiner[finerPixelIndex];
    uint unpushedCAT = motionCATFiner[finerPixelIndex];
    
    float2 fetchedVector = motionVectorCoarser[coarserPixelIndex];
    float fetchedDepth = depthTextureCoarser[coarserPixelIndex];
    uint fetchedCAT = motionCATCoarser[coarserPixelIndex];
    
    /*
    float2 surfaceInv = float2(1.0f, 1.0f) / float2(FinerDimension);
    float2 pixelCenter = float2(finerPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
    float2 halfTopTranslation = fetchedVector * tipTopDistance.y;
    float2 halfTopTracedScreenPos = screenPos + halfTopTranslation; //Now it's at the tip
    float2 sampleUVHalfTop = clamp(halfTopTracedScreenPos, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float fetchedFinerDepth = depthTextureFiner.SampleLevel(bilinearClampedSampler, sampleUVHalfTop, 0);
    */
    
    float2 selectedVector = 0.0f;
    float votedDepth = 0.0f;
    uint votedCAT = ReprojCAT0ValidSamp;
    if (unpushedCAT == ReprojCAT2Unwritten)
    {
        selectedVector = fetchedVector;
        votedDepth = fetchedDepth;
        votedCAT = fetchedCAT;
    }
    else if (unpushedCAT == ReprojCAT1Contested)
    {
        if (fetchedDepth > unpushedDepth)
        {
            selectedVector = fetchedVector;
            votedDepth = fetchedDepth;
        }
        else
        {
            selectedVector = unpushedVector;
            votedDepth = unpushedDepth;
        }
        votedCAT = ReprojCAT1Contested;
    }
    else
    {
        selectedVector = unpushedVector;
        votedDepth = unpushedDepth;
        votedCAT = unpushedCAT;
    }
    
    {
        bool bIsValidhistoryPixel = all(uint2(finerPixelIndex) < FinerDimension);
        if (bIsValidhistoryPixel)
        {
            motionVectorFinerUAV[finerPixelIndex] = selectedVector;
            depthTextureFinerUAV[finerPixelIndex] = votedDepth;
            motionCATFinerUAV[finerPixelIndex] = votedCAT;
        }
    }
}
