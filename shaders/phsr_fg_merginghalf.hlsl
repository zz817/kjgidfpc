#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
RWTexture2D<uint> motionReprojX;
RWTexture2D<uint> motionReprojY;
RWTexture2D<uint> motionReprojXPP;
RWTexture2D<uint> motionReprojYPP;

cbuffer shaderConsts : register(b0)
{
    float4x4 prevClipToClip;
    float4x4 clipToPrevClip;
    
    uint2 dimensions;
    float2 tipTopDistance;
    float2 viewportSize;
    float2 viewportInv;
}

SamplerState bilinearClampedSampler : register(s0);

#define TILE_SIZE 8

#define Patch3x3Switches 0x000003FF
#define PatchLUSwitches 0x0000001b
#define PatchLDSwitches 0x000000d8
#define PatchRUSwitches 0x00000036
#define PatchRDSwitches 0x000001b0

//------------------------------------------------------- ENTRY POINT
[shader("compute")]
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void main(uint2 groupId : SV_GroupID, uint2 localId : SV_GroupThreadID, uint groupThreadIndex : SV_GroupIndex)
{
    uint2 dispatchThreadId = localId + groupId * uint2(TILE_SIZE, TILE_SIZE);
    int2 currentPixelIndex = dispatchThreadId;
	
    uint reprojX = motionReprojX[currentPixelIndex];
    uint reprojXIndex = reprojX & IndexLast13DigitsMask;
    uint reprojXFilled = reprojX;
    if (reprojXIndex == UnwrittenIndexIndicator)
    {
        uint closestDistance = 0;
        uint closestElementIndex = 0;
        uint patchUnwrittenSwitches = 0;
        for (int i = 0; i < subsampleCount9PointPatch; ++i)
        {
            int2 offset = int2(subsamplePixelOffset9PointPatch[i]);
            int2 offsetIndex = currentPixelIndex + offset;
            uint reprojXOffset = motionReprojX[offsetIndex];
            uint reprojXOffsetIndex = reprojXOffset & IndexLast13DigitsMask;
            if (reprojXOffsetIndex != UnwrittenIndexIndicator)
            {
                uint distance = abs(reprojX - reprojXOffset);
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    closestElementIndex = reprojXOffset;
                }
            }
            else
            {
                uint patchSwitch = 1 << i;
                patchUnwrittenSwitches |= patchSwitch;
            }
        }
        bool bIsPatchUnwrittenTian = false;
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchLUSwitches) == PatchLUSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchLDSwitches) == PatchLDSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchRUSwitches) == PatchRUSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchRDSwitches) == PatchRDSwitches);
        if (!bIsPatchUnwrittenTian)
        {
            reprojXFilled = closestElementIndex;
        }
        else
        {
            reprojXFilled = UnwrittenPackedClearValue;
        }
    }
    
    uint reprojY = motionReprojY[currentPixelIndex];
    uint reprojYIndex = reprojY & IndexLast13DigitsMask;
    uint reprojYFilled = reprojY;
    if (reprojYIndex == UnwrittenIndexIndicator)
    {
        uint closestDistance = 0;
        uint closestElementIndex = 0;
        uint patchUnwrittenSwitches = 0;
        for (int i = 0; i < subsampleCount9PointPatch; ++i)
        {
            int2 offset = int2(subsamplePixelOffset9PointPatch[i]);
            int2 offsetIndex = currentPixelIndex + offset;
            uint reprojYOffset = motionReprojY[offsetIndex];
            uint reprojYOffsetIndex = reprojYOffset & IndexLast13DigitsMask;
            if (reprojYOffsetIndex != UnwrittenIndexIndicator)
            {
                uint distance = abs(reprojY - reprojYOffset);
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    closestElementIndex = reprojYOffset;
                }
            }
            else
            {
                uint patchSwitch = 1 << i;
                patchUnwrittenSwitches |= patchSwitch;
            }
        }
        bool bIsPatchUnwrittenTian = false;
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchLUSwitches) == PatchLUSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchLDSwitches) == PatchLDSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchRUSwitches) == PatchRUSwitches);
        bIsPatchUnwrittenTian |= ((patchUnwrittenSwitches & PatchRDSwitches) == PatchRDSwitches);
        if (!bIsPatchUnwrittenTian)
        {
            reprojYFilled = closestElementIndex;
        }
        else
        {
            reprojYFilled = UnwrittenPackedClearValue;
        }
    }
    
	{
        bool bIsValidhistoryPixel = all(uint2(currentPixelIndex) < dimensions);
        if (bIsValidhistoryPixel)
        {
            motionReprojXPP[currentPixelIndex] = reprojXFilled;
            motionReprojYPP[currentPixelIndex] = reprojYFilled;
        }
    }
}
