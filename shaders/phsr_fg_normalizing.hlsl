#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> currMvec;
//Texture2D<float2> prevMvec;
RWTexture2D<float2> currMvecNorm;
//RWTexture2D<float2> prevMvecNorm;

cbuffer shaderConsts : register(b0)
{
    uint2 dimensions;
    float2 distance;
    float2 viewportSize;
    float2 viewportInv;
}

#define TILE_SIZE 8

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
    float2 mCurr = currMvec[currentPixelIndex];
    
    float2 mDilated = float2(0.0f, 0.0f);
    float dilatedSamples = 0.0f;
    for (int i = 0; i < subsampleCount9PointPatch; i++)
    {
        int2 elementIndex = currentPixelIndex + subsamplePixelOffset9PointPatch[i];
        float2 mElement = currMvec[elementIndex];
        if (abs(mElement.x) > 1 || abs(mElement.y) > 1)
        {
            mDilated += mElement;
            dilatedSamples += 1.0f;
        }
    }
    mDilated = mDilated * SafeRcp(dilatedSamples);
    if (abs(mCurr.x) <= 1 && abs(mCurr.y) <= 1)
    {
        mCurr = mDilated;
    }
    
    bool bIsValidPixel = all(uint2(currentPixelIndex) < dimensions);
    if (bIsValidPixel)
    {
        currMvecNorm[currentPixelIndex] = mCurr * viewportInv;
        //prevMvecNorm[currentPixelIndex] = prevMvec[currentPixelIndex] * viewportInv;
    }
}
