#pragma once

#include "tinyexr.h"

#include <dxgiformat.h>
#include <d3d11.h>

#include <stdint.h>
#include <tuple>
#include <vector>
#include <fstream>
#include <assert.h>

#define TINYEXR_IMPLEMENTATION

enum class ComputeShaderType : uint32_t {
  Clear,
  Normalizing,
  Reprojection,
  MergeHalf,
  MergeFull,
  FirstLeg,
  Pull,
  LastStretch,
  Push,
  Resolution,
  AxPb,
  Multiply,
  InnerProduct,
  Count
};

enum class StagResType : uint8_t {
  ColorInput,
  ColorOutput,
  Mevc,
  Depth,
  Count
};

enum class InputResType : uint32_t {
  CurrColor,
  PrevColor,
  CurrDepth,
  PrevDepth,
  CurrMevc,
  PrevMevc,
  Count
};

enum class InternalResType : uint32_t {
  ReprojectedX,
  ReprojectedY,
  
  ReprojectedMV,
  ReprojectedMVSmoothed,
  ReprojectedMVFilled,

  ReprojectedDepth,
  ReprojectedDepthSmoothed,
  ReprojectedDepthFilled,

  ReprojectedCAT,
  ReprojectedCATSmoothed,
  //ReprojectedCATFilled,

  CurrMvecDuplicated,
 
  MotionVectorLv1,
  MotionVectorLv2,
  MotionVectorLv3,
  MotionVectorLv4,
  MotionVectorLv5,
  MotionVectorLv6,
  MotionVectorLv7,

  InpaintedDepthLv1,
  InpaintedDepthLv2,
  InpaintedDepthLv3,
  InpaintedDepthLv4,
  InpaintedDepthLv5,
  InpaintedDepthLv6,
  InpaintedDepthLv7,

  PushedVectorLv1,
  PushedVectorLv2,
  PushedVectorLv3,
  PushedVectorLv4,
  PushedVectorLv5,
  PushedVectorLv6,

  PushedDepthLv1,
  PushedDepthLv2,
  PushedDepthLv3,
  PushedDepthLv4,
  PushedDepthLv5,
  PushedDepthLv6,

  CATLv1,
  CATLv2,
  CATLv3,
  CATLv4,
  CATLv5,
  CATLv6,
  CATLv7,

  PushedCATLv1,
  PushedCATLv2,
  PushedCATLv3,
  PushedCATLv4,
  PushedCATLv5,
  PushedCATLv6,

  Count
};

enum class ConstBufferType : uint32_t {
  Clearing,
  Normalizing,
  Mevc,
  Merge,
  PushPull,
  Resolution,
  Count
};

enum class SamplerType : uint32_t
{
  LinearClamp,
  LinearMirror,
  AnisoClamp,
  PointClamp,
  PointMirror,
  Count
};

struct ResourceView {
  ID3D11ShaderResourceView* srv;
  ID3D11UnorderedAccessView* uav;
};

struct ClipInfo {
  float prevClipToClip[16];
  float clipToPrevClip[16];
};

struct ClearingConstParamStruct {
  uint32_t dimensions[2];
  float tipTopDistance[2];
  float viewportSize[2];
  float viewportInv[2];
};

struct NormalizingConstParamStruct
{
  uint32_t dimensions[2];
  float    tipTopDistance[2];
  float    viewportSize[2];
  float    viewportInv[2];
};

struct MVecParamStruct {
    float prevClipToClip[16];
    float clipToPrevClip[16];

    uint32_t dimensions[2];
    float tipTopDistance[2];
    float viewportSize[2];
    float viewportInv[2];
};

struct MergeParamStruct {
    float prevClipToClip[16];
    float clipToPrevClip[16];

    uint32_t dimensions[2];
    float tipTopDistance[2];
    float viewportSize[2];
    float viewportInv[2];
};

struct PyramidParamStruct {
    uint32_t FinerDimension[2];
    uint32_t CoarserDimension[2];
    float tipTopDistance[2];
    float viewportInv[2];

    void becomeCoarser()
    {
        FinerDimension[0] = CoarserDimension[0];
        FinerDimension[1] = CoarserDimension[1];
        CoarserDimension[0] /= 2;
        CoarserDimension[1] /= 2;

        viewportInv[0] *= 2.0f;
        viewportInv[1] *= 2.0f;
    };
    void becomeFiner()
    {
        CoarserDimension[0] = FinerDimension[0];
        CoarserDimension[1] = FinerDimension[1];
        FinerDimension[0] *= 2;
        FinerDimension[1] *= 2;

        viewportInv[0] *= 0.5f;
        viewportInv[1] *= 0.5f;
    };
};

struct ResolutionConstParamStruct {
    float prevClipToClip[16];
    float clipToPrevClip[16];

    uint32_t dimensions[2];
    float tipTopDistance[2];
    float viewportSize[2];
    float viewportInv[2];
};

struct ShaderInfo {
    ComputeShaderType shaderType;
    std::string dxbcFile;
};

uint32_t as_uint(const float x)
{
    return *(uint32_t*)&x;
}

uint32_t float_to_half(const float x)
{ // IEEE-754 16-bit floating-point format (without infinity): 1-5-10, exp-15, +-131008.0, +-6.1035156E-5,
  // +-5.9604645E-8, 3.311 digits
    const uint32_t b = as_uint(x) + 0x00001000; // round-to-nearest-even: add last bit after truncated mantissa
    const uint32_t e = (b & 0x7F800000) >> 23;  // exponent
    const uint32_t m = b & 0x007FFFFF;          // mantissa; in line below: 0x007FF000 = 0x00800000-0x00001000 = decimal
                                                // indicator flag - initial rounding
    return (b & 0x80000000) >> 16 | (e > 112) * ((((e - 112) << 10) & 0x7C00) | m >> 13) |
           ((e < 113) & (e > 101)) * ((((0x007FF000 + m) >> (125 - e)) + 1) >> 1) |
           (e > 143) * 0x7FFF; // sign : normalized : denormalized : saturate
}

std::vector<uint8_t> AcquireExrFileContentMvec(const std::string path)
{
    std::string expectedExtension = ".exr";
    std::string extension         = path.substr(path.size() - expectedExtension.size(), expectedExtension.size());

    int width  = 0;
    int height = 0;
    assert(extension == expectedExtension);
    float*      tempData = nullptr;
    const char* err      = nullptr;
    int         ret      = LoadEXR(&tempData, &width, &height, path.c_str(), &err);

    assert(ret == TINYEXR_SUCCESS);
    // 16 + 16 = 32
    char* m_pData = reinterpret_cast<char*>(new uint32_t[width * height]);
    // Process the data (e.g., print some of the pixel values)
    for (uint32_t h = 0; h < height; ++h)
    {
        for (uint32_t w = 0; w < width; ++w)
        {
            float* pPixel = (tempData + (h * width + w) * 4);
            float  valG   = pPixel[0];
            float  valB   = pPixel[1];
            float  valX   = 2.0f * valB - 1.0f;
            float  valY   = 1.0f - 2.0f * valG;

            valX = valX;
            valY = valY;
            
            uint32_t valX16Bit = float_to_half(valX);
            uint32_t valY16Bit = float_to_half(valY);
            uint32_t val       = (valX16Bit << 16) | valY16Bit;

            uint32_t* pPixel32 = reinterpret_cast<uint32_t*>(m_pData + (h * width + w) * sizeof(uint32_t));
            pPixel32[0]        = val;
        }
    }
    std::vector<uint8_t> result = {};
    result.reserve(width * height * sizeof(uint32_t));
    result.assign(m_pData, m_pData + width * height * sizeof(uint32_t));

    free(tempData);
    delete[] m_pData;

    return result;
}

std::vector<uint8_t> AcquireExrFileContentDepth(const std::string path)
{
    std::string expectedExtension = ".exr";
    std::string extension         = path.substr(path.size() - expectedExtension.size(), expectedExtension.size());

    int width = 0;
    int height = 0;
    assert(extension == expectedExtension);
    float*      tempData = nullptr;
    const char* err      = nullptr;
    int         ret      = LoadEXR(&tempData, &width, &height, path.c_str(), &err);

    assert(ret == TINYEXR_SUCCESS);
    char* m_pData = reinterpret_cast<char*>(new float[width * height]);
    // Process the data (e.g., print some of the pixel values)
    for (uint32_t h = 0; h < height; ++h)
    {
        for (uint32_t w = 0; w < width; ++w)
        {
            float* pPixel   = (tempData + (h * width + w) * 4);
            float* pPixel32 = reinterpret_cast<float*>(m_pData + (h * width + w) * sizeof(float));
            *pPixel32       = pPixel[0];
        }
    }
    std::vector<uint8_t> result = {};
    result.reserve(width * height * sizeof(float));
    result.assign(m_pData, m_pData + width * height * sizeof(float));

    free(tempData);
    delete[] m_pData;
    
    return result;
}

std::vector<uint8_t> AcquireFileContent(const std::string& path) {
  std::vector<uint8_t> result;
  std::ifstream f(path, std::ios::binary);
  if (f.is_open()) {
    f.seekg(0, std::ios::end);
    std::streampos fileSize = f.tellg();
    f.seekg(0, std::ios::beg);
    result.resize(static_cast<size_t>(fileSize));
    f.read((char*)&result[0], fileSize);
  }
  return result;
}

DXGI_FORMAT GetInternalResFormat(InternalResType type) {
  switch (type) {
    case InternalResType::ReprojectedX:
    case InternalResType::ReprojectedY:
      return DXGI_FORMAT_R32_UINT;

    case InternalResType::ReprojectedMV:
    case InternalResType::ReprojectedMVSmoothed:
    case InternalResType::ReprojectedMVFilled:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::MotionVectorLv1:
    case InternalResType::MotionVectorLv2:
    case InternalResType::MotionVectorLv3:
    case InternalResType::MotionVectorLv4:
    case InternalResType::MotionVectorLv5:
    case InternalResType::MotionVectorLv6:
    case InternalResType::MotionVectorLv7:
    case InternalResType::PushedVectorLv1:
    case InternalResType::PushedVectorLv2:
    case InternalResType::PushedVectorLv3:
    case InternalResType::PushedVectorLv4:
    case InternalResType::PushedVectorLv5:
    case InternalResType::PushedVectorLv6:
      return DXGI_FORMAT_R32G32_FLOAT;

    case InternalResType::ReprojectedDepth:
    case InternalResType::ReprojectedDepthSmoothed:
    case InternalResType::ReprojectedDepthFilled:
    case InternalResType::InpaintedDepthLv1:
    case InternalResType::InpaintedDepthLv2:
    case InternalResType::InpaintedDepthLv3:
    case InternalResType::InpaintedDepthLv4:
    case InternalResType::InpaintedDepthLv5:
    case InternalResType::InpaintedDepthLv6:
    case InternalResType::InpaintedDepthLv7:
    case InternalResType::PushedDepthLv1:
    case InternalResType::PushedDepthLv2:
    case InternalResType::PushedDepthLv3:
    case InternalResType::PushedDepthLv4:
	case InternalResType::PushedDepthLv5:
	case InternalResType::PushedDepthLv6:
      return DXGI_FORMAT_R32_FLOAT;

    case InternalResType::ReprojectedCAT:
    case InternalResType::ReprojectedCATSmoothed:
    case InternalResType::CATLv1:
    case InternalResType::CATLv2:
    case InternalResType::CATLv3:
    case InternalResType::CATLv4:
    case InternalResType::CATLv5:
    case InternalResType::CATLv6:
    case InternalResType::CATLv7:
    case InternalResType::PushedCATLv1:
    case InternalResType::PushedCATLv2:
    case InternalResType::PushedCATLv3:
    case InternalResType::PushedCATLv4:
    case InternalResType::PushedCATLv5:
    case InternalResType::PushedCATLv6:
        return DXGI_FORMAT_R32_UINT;

    case InternalResType::Count:
    default:
      return DXGI_FORMAT_UNKNOWN;
  }
}

std::pair<uint32_t, uint32_t> GetInternalResResolution(InternalResType type,
                                                       uint32_t originWidth,
                                                       uint32_t originHeight) {
  switch (type) {
    case InternalResType::ReprojectedX:
    case InternalResType::ReprojectedY:
    case InternalResType::ReprojectedMV:
    case InternalResType::ReprojectedMVSmoothed:
    case InternalResType::ReprojectedMVFilled:
    case InternalResType::ReprojectedDepth:
    case InternalResType::ReprojectedDepthSmoothed:
    case InternalResType::ReprojectedDepthFilled:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::ReprojectedCAT:
    case InternalResType::ReprojectedCATSmoothed:
      return {originWidth, originHeight};

    case InternalResType::MotionVectorLv1:
    case InternalResType::InpaintedDepthLv1:
    case InternalResType::PushedVectorLv1:
    case InternalResType::PushedDepthLv1:
    case InternalResType::CATLv1:
    case InternalResType::PushedCATLv1:
      return {originWidth / 2, originHeight / 2};

    case InternalResType::MotionVectorLv2:
    case InternalResType::InpaintedDepthLv2:
    case InternalResType::PushedVectorLv2:
    case InternalResType::PushedDepthLv2:
    case InternalResType::CATLv2:
    case InternalResType::PushedCATLv2:
      return {originWidth / 4, originHeight / 4};

    case InternalResType::MotionVectorLv3:
    case InternalResType::InpaintedDepthLv3:
    case InternalResType::PushedVectorLv3:
    case InternalResType::PushedDepthLv3:
    case InternalResType::CATLv3:
    case InternalResType::PushedCATLv3:
      return {originWidth / 8, originHeight / 8};

    case InternalResType::MotionVectorLv4:
    case InternalResType::InpaintedDepthLv4:
    case InternalResType::PushedVectorLv4:
    case InternalResType::PushedDepthLv4:
    case InternalResType::CATLv4:
    case InternalResType::PushedCATLv4:
	  return {originWidth / 16, originHeight / 16};

    case InternalResType::MotionVectorLv5:
    case InternalResType::InpaintedDepthLv5:
    case InternalResType::PushedVectorLv5:
    case InternalResType::PushedDepthLv5:
    case InternalResType::CATLv5:
    case InternalResType::PushedCATLv5:
      return {originWidth / 32, originHeight / 32};

    case InternalResType::MotionVectorLv6:
    case InternalResType::InpaintedDepthLv6:
    case InternalResType::PushedVectorLv6:
    case InternalResType::PushedDepthLv6:
    case InternalResType::CATLv6:
    case InternalResType::PushedCATLv6:
      return {originWidth / 64, originHeight / 64};

    case InternalResType::MotionVectorLv7:
    case InternalResType::InpaintedDepthLv7:
    case InternalResType::CATLv7:
      return {originWidth / 128, originHeight / 128};

    case InternalResType::Count:
    default:
      return {0, 0};
  }
}