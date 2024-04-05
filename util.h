#pragma once

#include <dxgiformat.h>
#include <d3d11.h>

#include <stdint.h>
#include <tuple>

enum class ComputeShaderType : uint32_t {
  Clear,
  Normalizing,
  Reprojection,
  MergeHalf,
  //MergeFull,
  FirstLeg,
  Pull,
  LastStretch,
  Push,
  Resolution,
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
  //ReprojectedFullX,
  //ReprojectedFullY,
  //ReprojectedHalfTipX,
  //ReprojectedHalfTipY,
  ReprojectedHalfTopX,
  ReprojectedHalfTopY,

  //ReprojectedFull,
  //ReprojectedHalfTip,
  ReprojectedHalfTop,
  //ReprojectedFullFiltered,
  //ReprojectedHalfTipFiltered,
  ReprojectedHalfTopFiltered,

  CurrMevcFiltered,
  PrevMevcFiltered,
  CurrMvecDuplicated,
  PrevMvecDuplicated,

  //MotionVectorFullLv0,
  //MotionVectorTipLv0,
  //MotionVectorTopLv0,

  MotionVectorLv1,
  MotionVectorLv2,
  MotionVectorLv3,
  MotionVectorLv4,
  MotionVectorLv5,
  MotionVectorLv6,
  MotionVectorLv7,

  ReliabilityLv1,
  ReliabilityLv2,
  ReliabilityLv3,
  ReliabilityLv4,
  ReliabilityLv5,
  ReliabilityLv6,
  ReliabilityLv7,

  PushedVectorLv1,
  PushedVectorLv2,
  PushedVectorLv3,
  PushedVectorLv4,
  PushedVectorLv5,
  PushedVectorLv6,

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

struct PushPullParameters {
  uint32_t FinerDimension[2];
  uint32_t CoarserDimension[2];
  void becomeCoarser()
  {
      FinerDimension[0] = CoarserDimension[0];
      FinerDimension[1] = CoarserDimension[1];
      CoarserDimension[0] /= 2;
      CoarserDimension[1] /= 2;
  };
  void becomeFiner()
  {
      CoarserDimension[0] = FinerDimension[0];
      CoarserDimension[1] = FinerDimension[1];
      FinerDimension[0] *= 2;
      FinerDimension[1] *= 2;
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
    //case InternalResType::ReprojectedFullX:
    //case InternalResType::ReprojectedFullY:
    //case InternalResType::ReprojectedHalfTipX:
    //case InternalResType::ReprojectedHalfTipY:
    case InternalResType::ReprojectedHalfTopX:
    case InternalResType::ReprojectedHalfTopY:
      return DXGI_FORMAT_R32_UINT;

    //case InternalResType::ReprojectedFull:
    //case InternalResType::ReprojectedHalfTip:
    case InternalResType::ReprojectedHalfTop:
    //case InternalResType::ReprojectedFullFiltered:
    //case InternalResType::ReprojectedHalfTipFiltered:
    case InternalResType::ReprojectedHalfTopFiltered:
    case InternalResType::CurrMevcFiltered:
    case InternalResType::PrevMevcFiltered:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::PrevMvecDuplicated:
    //case InternalResType::MotionVectorFullLv0:
    //case InternalResType::MotionVectorTipLv0:
    //case InternalResType::MotionVectorTopLv0:
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

    case InternalResType::ReliabilityLv1:
    case InternalResType::ReliabilityLv2:
    case InternalResType::ReliabilityLv3:
    case InternalResType::ReliabilityLv4:
    case InternalResType::ReliabilityLv5:
    case InternalResType::ReliabilityLv6:
    case InternalResType::ReliabilityLv7:
      return DXGI_FORMAT_R32_FLOAT;

    case InternalResType::Count:
    default:
      return DXGI_FORMAT_UNKNOWN;
  }
}

std::pair<uint32_t, uint32_t> GetInternalResResolution(InternalResType type,
                                                       uint32_t originWidth,
                                                       uint32_t originHeight) {
  switch (type) {
    //case InternalResType::ReprojectedFullX:
    //case InternalResType::ReprojectedFullY:
    //case InternalResType::ReprojectedHalfTipX:
    //case InternalResType::ReprojectedHalfTipY:
    case InternalResType::ReprojectedHalfTopX:
    case InternalResType::ReprojectedHalfTopY:
    //case InternalResType::ReprojectedFull:
    //case InternalResType::ReprojectedHalfTip:
    case InternalResType::ReprojectedHalfTop:
    //case InternalResType::ReprojectedFullFiltered:
    //case InternalResType::ReprojectedHalfTipFiltered:
    case InternalResType::ReprojectedHalfTopFiltered:
    case InternalResType::CurrMevcFiltered:
    case InternalResType::PrevMevcFiltered:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::PrevMvecDuplicated:
    //case InternalResType::MotionVectorFullLv0:
    //case InternalResType::MotionVectorTipLv0:
    //case InternalResType::MotionVectorTopLv0:
      return {originWidth, originHeight};

    case InternalResType::MotionVectorLv1:
    case InternalResType::ReliabilityLv1:
    case InternalResType::PushedVectorLv1:
      return {originWidth / 2, originHeight / 2};

    case InternalResType::MotionVectorLv2:
    case InternalResType::ReliabilityLv2:
    case InternalResType::PushedVectorLv2:
      return {originWidth / 4, originHeight / 4};

    case InternalResType::MotionVectorLv3:
    case InternalResType::ReliabilityLv3:
    case InternalResType::PushedVectorLv3:
      return {originWidth / 8, originHeight / 8};

    case InternalResType::MotionVectorLv4:
    case InternalResType::ReliabilityLv4:
    case InternalResType::PushedVectorLv4:
	  return {originWidth / 16, originHeight / 16};

    case InternalResType::MotionVectorLv5:
    case InternalResType::ReliabilityLv5:
    case InternalResType::PushedVectorLv5:
      return {originWidth / 32, originHeight / 32};

    case InternalResType::MotionVectorLv6:
    case InternalResType::ReliabilityLv6:
    case InternalResType::PushedVectorLv6:
      return {originWidth / 64, originHeight / 64};

    case InternalResType::MotionVectorLv7:
    case InternalResType::ReliabilityLv7:
      return {originWidth / 128, originHeight / 128};

    case InternalResType::Count:
    default:
      return {0, 0};
  }
}