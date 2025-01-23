#pragma warning(error: 3206)

uint2 ZOrder2DMTSS(uint Index, const uint SizeLog2)
{
    uint2 Coord = 0;
    [unroll]
    for (uint i = 0; i < SizeLog2; i++)
    {
        Coord.x |= ((Index >> (2 * i + 0)) & 0x1) << i;
        Coord.y |= ((Index >> (2 * i + 1)) & 0x1) << i;
    }

    return Coord;
}

//#define UNREAL_ENGINE_COORDINATES
#define NVRHI_DONUT_COORDINATES

#define DEPTH_LESSER_CLOSER
//#define DEPTH_GREATER_CLOSER

#define DepthFirst19DigitsMask 0xFFFFE000
#define DepthFirst31DigitsMask 0xFFFFFFFE

#define MaxDepthFirst19Digits 0xFFFFE000
#define MinDepthFirst19Digits 0x00000000

#define IndexLast13DigitsMask 0x00001FFF

#define UnwrittenLast13DigitsMask 0x00000000

#define UnwrittenLast1DigitMT1 0x00000000
#define WrittenLast1DigitMT1 0x00000001

#ifdef DEPTH_LESSER_CLOSER
static uint UnwrittenPackedClearValue = MaxDepthFirst19Digits | UnwrittenLast13DigitsMask;
#endif
#ifdef DEPTH_GREATER_CLOSER
static uint UnwrittenPackedClearValue = MinDepthFirst19Digits | UnwrittenLast13DigitsMask;
#endif
static const uint UnwrittenIndexIndicator = UnwrittenLast13DigitsMask;
static const uint UnwrittenMTSSIndicator = UnwrittenLast1DigitMT1;
static const uint WrittenMTSSIndicator = WrittenLast1DigitMT1;

static const uint ReprojCAT0ValidSamp = 0x00000000;
static const uint ReprojCAT1Contested = 0x00000001;
static const uint ReprojCAT2Unwritten = 0x00000002;

static const float FLT_MAX = 3.402823466e+38f;

//static int depthTotalBits = 19;
static const int expCustomized = 7;
static const int manCustomized = 12;

static const float3 debugRed = float3(1.0f, 0.0f, 0.0f);
static const float3 debugGreen = float3(0.0f, 1.0f, 0.0f);
static const float3 debugBlue = float3(0.0f, 0.0f, 1.0f);
static const float3 debugYellow = float3(1.0f, 1.0f, 0.0f);
static const float3 debugMagenta = float3(1.0f, 0.0f, 1.0f);
static const float3 debugCyan = float3(0.0f, 1.0f, 1.0f);

static const float2 debugCat1 = float2(0.0f, 0.0f);
static const float2 debugCat2 = float2(0.5f, 0.0f);
static const float2 debugCat3 = float2(0.5f, 0.5f);
static const float2 debugCat4 = float2(0.5f, 0.0f);

//Nasha depth: No sig, 7bits exp, 12bits mantissa
uint compressDepth(float incomingDepth)
{
    float incomingAs32F = float(incomingDepth);
    uint incoming32Uint = asuint(incomingAs32F);
    
    int sig32 = (incoming32Uint >> 31) & 0x1;
    int exp32 = (incoming32Uint >> 23) & 0xFF;
    int man32 = incoming32Uint & 0x7FFFFF;
    
    int sig19 = sig32; //Not gonna use it
    int exp19 = exp32 - 127 + ((1 << (expCustomized - 1)) - 1);
    int man19 = man32 >> (23 - manCustomized);

    if (exp19 <= 0)
    {
        int man32Denorm = (man32 | (1 << 24)) >> (1 - exp19);
        man19 = man32Denorm >> (23 - manCustomized);
        if (man32Denorm & (1 << (23 - manCustomized - 1)))
        {
            man19 += 1;
        }
        exp19 = 0;
    }
    
    uint returning19Uint = 0;
    //returning16Uint |= (sig16 << 15);
    returning19Uint |= (exp19 << manCustomized);
    returning19Uint |= man19;
    
    return (returning19Uint << (32 - (expCustomized + manCustomized))) & DepthFirst19DigitsMask;
}

float SafeRcp(float x)
{
    return x > 0.0 ? rcp(float(x)) : 0.0;
}

float2 ComputeStaticVelocityTipTop(float2 ScreenPos, float DeviceZ, float4x4 TopClipToTipClip)
{
    float3 PosN = float3(ScreenPos, DeviceZ);

    float4 ThisClip = float4(PosN, 1);
    float4 PrevClip = mul(TopClipToTipClip, ThisClip);
    float2 PrevScreen = PrevClip.xy / PrevClip.w;
    return float2(PosN.xy - PrevScreen);
}

float2 ComputeStaticVelocityTopTip(float2 ScreenPos, float DeviceZPrev, float4x4 TipClipToTopClip)
{
    float3 PosN = float3(ScreenPos, DeviceZPrev);

    float4 PrevClip = float4(PosN, 1);
    float4 ThisClip = mul(TipClipToTopClip, PrevClip);
    float2 ThisScreen = ThisClip.xy / ThisClip.w;
    return float2(ThisScreen - PosN.xy);
}

bool IsOffScreen(uint bCameraCut, float2 ScreenPos)
{
    bool bIsCameraCut = bCameraCut != 0;
    bool bIsOutOfBounds = max(abs(ScreenPos.x), abs(ScreenPos.y)) >= 1.0;

    return (bIsCameraCut || bIsOutOfBounds);
}

#define FOUR_POINTS_TIAN_SIZE 4
#define THREE_BY_THREE_PATCH_SIZE 9
#define THREE_BY_THREE_PATCH_DIM 3

static const int subsampleCount4PointTian = 4;
static const int subsampleCount5PointStencil = 5;
static const int subsampleCount9PointPatch = 9;

static const int2 subsamplePixelOffset4PointTian[FOUR_POINTS_TIAN_SIZE] =
{
    int2(0, 0), //K
    
    int2(0, 1),
    int2(1, 0),
    int2(1, 1)
};

static const int finerRelativeIndexTab[2] = { -1, 1 };

static const int2 subsamplePixelOffset5PointStencil[5] =
{
    int2(0, 0), // K
    
    int2(0, -1),
    int2(-1, 0),
    int2(1, 0),
    int2(0, 1)
};

static const int2 subsamplePixelOffset9PointPatch[THREE_BY_THREE_PATCH_SIZE] =
{
    int2(0, 0), // K
    
    int2(-1, -1),
    int2(0, -1),
    int2(1, -1),
    int2(-1, 0),
    int2(1, 0),
    int2(-1, 1),
    int2(0, 1),
    int2(1, 1)
};

float gaussianDistributionWeightForVariance(float2 offset, float patchSize)
{
    return exp(-3.0f * (offset.x * offset.x + offset.y * offset.y) / ((patchSize + 1.0f) * (patchSize + 1.0f)));
}

static const float lanzcosPie = 3.1415926535897932f;
static const float lanzcosWidth = 2.0f;

float LanzcosEachDim(float diff)
{
    if (abs(diff) < 0.00001f)
    {
        return 1.0f;
    }
    else if (abs(diff) >= lanzcosWidth)
    {
        return 0.0f;
    }
    else
    {
        float nominator = lanzcosWidth * sin(lanzcosPie * diff) * sin(lanzcosPie * diff / lanzcosWidth);
        float denominator = lanzcosPie * lanzcosPie * diff * diff;
        return nominator * SafeRcp(denominator);
    }
}

float UpsampleLanzcos(float2 diff, float upsampleFactor)
{
    diff *= (upsampleFactor);
    float contributionX = LanzcosEachDim(diff.x);
    float contributionY = LanzcosEachDim(diff.y);
    return contributionX * contributionY;
}

float UpsampleFilterGaussian(float2 diff, float upsampleFactor)
{
    float u2 = upsampleFactor * upsampleFactor;
    // 1 - 1.9 * x^2 + 0.9 * x^4
    float x2 = saturate(u2 * dot(diff, diff));
    return float(((float(0.9f)) * x2 - float(1.9f)) * x2 + float(1.0f));
}

float GetUpsampleKernelWeight(float2 diff, float upsampleFactor, float minimalContribution)
{
    //mtss_float kernelWeight = UpsampleBicubic(diff, upsampleFactor);
    float kernelWeight = UpsampleLanzcos(diff, upsampleFactor);
    //mtss_float kernelWeight = UpsampleFilterTent(diff, 2.0f * SafeRcp(upsampleFactor));
    //mtss_float kernelWeight = UpsampleFilterGaussian(diff, upsampleFactor);
    //mtss_float kernelWeight = UpsampleFilterUniversal(diff, SafeRcp(upsampleFactor));
    return max(kernelWeight, minimalContribution);
}

float GetBlunterKernelWeight(float2 diff, float upsampleFactor, float minimalContribution)
{
    //mtss_float kernelWeight = UpsampleBicubic(diff, 1.0f);
    float kernelWeight = UpsampleFilterGaussian(diff, 0.45f);
    //mtss_float kernelWeight = UpsampleFilterTent(diff, 2.0f * SafeRcp(upsampleFactor));
    //mtss_float kernelWeight = UpsampleFilterGaussian(diff, upsampleFactor);
    //mtss_float kernelWeight = UpsampleFilterUniversal(diff, SafeRcp(upsampleFactor));
    return max(kernelWeight, minimalContribution);
}

float3 HSVtoRGB(float3 hsv)
{
    float h = hsv.x;
    float s = hsv.y;
    float v = hsv.z;

    const float PI = 3.14159265358979;
    float3 rgb = (float3) v;

    if (s > 0)
    {
        h = fmod(h + 2.0 * PI, 2.0 * PI);
        h /= (PI / 3.0);
        int i = int(floor(h));
        float f = h - i;
        float p = v * (1.0 - s);
        float q = v * (1.0 - (s * f));
        float t = v * (1.0 - (s * (1.0 - f)));

        switch (i)
        {
            case 0:
                rgb = float3(v, t, p);
                break;
            case 1:
                rgb = float3(q, v, p);
                break;
            case 2:
                rgb = float3(p, v, t);
                break;
            case 3:
                rgb = float3(p, q, v);
                break;
            case 4:
                rgb = float3(t, p, v);
                break;
            default:
                rgb = float3(v, p, q);
                break;
        }
    }
    return rgb;
}

float3 heatMap(float value, float lb = 0.0, float ub = 1.0)
{
    float p = saturate((value - lb) / (ub - lb));

    float r, g, b;
    float h = 3.7 * (1.0 - p); // 3.7 is blue
    float s = sqrt(p);
    float v = sqrt(p);
    return HSVtoRGB(float3(h, s, v));
}

float pseudoNormalizedSigmoid(float x, float power = 3.0f)
{
    x = saturate(x);
    float oneMinusX = 1.0f - x;
    float xPowered = pow(x, power);
    float oneMinusXPowered = pow(oneMinusX, power);
    return xPowered / (xPowered + oneMinusXPowered);
}

// Apply this to tonemap linear HDR color "c" after a sample is fetched in the resolve.
// Note "c" 1.0 maps to the expected limit of low-dynamic-range monitor output.

#define TONEMAPPING_ENABLED

float3 Tonemap(float3 c)
{
#ifdef TONEMAPPING_ENABLED
    return c * rcp(c + 1.0f);
#else
    return c;
#endif
}

// Maps standard viewport UV to screen position.
float2 ViewportUVToScreenPos(float2 ViewportUV)
{
    return float2(2.0f * ViewportUV.x - 1.0f, 1.0f - 2.0f * ViewportUV.y);
}

float2 ScreenPosToViewportUV(float2 ScreenPos)
{
    return float2(0.5f + 0.5f * ScreenPos.x, 0.5f - 0.5f * ScreenPos.y);
}
