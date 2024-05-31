#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionReprojectedTop;
Texture2D<float> depthTextureTip;

RWTexture2D<uint> motionAdvectHalfTipX;
RWTexture2D<uint> motionAdvectHalfTipY;

cbuffer shaderConsts : register(b0)
{
    float4x4 prevClipToClip;
    float4x4 clipToPrevClip;
    
    uint2 dimensions;
    float2 tipTopDistance;
    float2 viewportSize;
    float2 viewportInv;
};

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8
//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
	
    float2 pixelCenter = float2(currentPixelIndex) + 0.5f;
    float2 viewportUV = pixelCenter * viewportInv;
    float2 screenPos = viewportUV;
    float2 mProj = motionReprojectedTop.SampleLevel(bilinearClampedSampler, viewportUV, 0);
    
    const float distanceFull = tipTopDistance.x + tipTopDistance.y;
    const float distanceHalfTip = tipTopDistance.x;
    const float distanceHalfTop = tipTopDistance.y;
	
    //Let the tip flow //FIXME: Is it distanceHalfTip or distanceHalfTop? They are both 0.5f for now
    float2 halfTipTransInvert = mProj * distanceHalfTop;
    float2 halfTipAdvectedScreenPos = screenPos - halfTipTransInvert;
    int2 halfTipAdvectedIndex = floor(halfTipAdvectedScreenPos * viewportSize);
    float2 halfTipAdvectedFloatCenter = float2(halfTipAdvectedIndex) + float2(0.5f, 0.5f);	
    float2 halfTipAdvectedPos = halfTipAdvectedFloatCenter * viewportInv;
    float2 samplePosHalfTipAdv = halfTipAdvectedPos + halfTipTransInvert;
    float2 sampleUVHalfTipAdv = samplePosHalfTipAdv;
    sampleUVHalfTipAdv = clamp(sampleUVHalfTipAdv, float2(0.0f, 0.0f), float2(1.0f, 1.0f));
    float halfTipDepthAdv = depthTextureTip.SampleLevel(bilinearClampedSampler, sampleUVHalfTipAdv, 0);
    uint halfTipDepthAdvAsUIntHigh19 = compressDepth(halfTipDepthAdv);
    
    uint packedAsUINTHigh19HalfTipXAdv = halfTipDepthAdvAsUIntHigh19 | (currentPixelIndex.x & IndexLast13DigitsMask);
    uint packedAsUINTHigh19HalfTipYAdv = halfTipDepthAdvAsUIntHigh19 | (currentPixelIndex.y & IndexLast13DigitsMask);
	
	{
        bool bIsValidHalfTopPixel = all(halfTipAdvectedIndex < int2(dimensions)) && all(halfTipAdvectedIndex >= int2(0, 0));
        if (bIsValidHalfTopPixel)
        {
            uint originalValX;
            uint originalValY;
            InterlockedMax(motionAdvectHalfTipX[halfTipAdvectedIndex], packedAsUINTHigh19HalfTipXAdv, originalValX);
            InterlockedMax(motionAdvectHalfTipY[halfTipAdvectedIndex], packedAsUINTHigh19HalfTipYAdv, originalValY);
        }
    }
}
