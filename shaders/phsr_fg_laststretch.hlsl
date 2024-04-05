#include "phsr_common.hlsli"

//------------------------------------------------------- PARAMETERS
Texture2D<float2> motionVectorFiner;
Texture2D<float2> motionVectorCoarser;
//Texture2D<float> motionReliabilityCoarser;

RWTexture2D<float2> motionVectorFinerUAV;

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
	int2 finerPixelIndex = dispatchThreadId;
	int2 coarserPixelIndex = finerPixelIndex / 2;
	
	float2 finerVector = motionVectorFiner[finerPixelIndex];
	//float coarserReliability = motionReliabilityCoarser[coarserPixelIndex];
	
    float2 unpushedVector = motionVectorFiner[finerPixelIndex];
    float2 fetchedVector = motionVectorCoarser[coarserPixelIndex];
    float2 selectedVector = 0.0f;
    if (any(unpushedVector >= ImpossibleMotionValue))
    {
        selectedVector = fetchedVector;
    }
    else
    {
        selectedVector = unpushedVector;
    }
	
	{
		bool bIsValidhistoryPixel = all(uint2(finerPixelIndex) < FinerDimension);
		if (bIsValidhistoryPixel)
		{
			motionVectorFinerUAV[finerPixelIndex] = selectedVector;
		}
	}
}
