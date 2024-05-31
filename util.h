#pragma once

#include <dxgiformat.h>
#include <d3d11.h>

#include <stdint.h>
#include <tuple>

enum class ComputeShaderType : uint32_t {
  Clear,
  Normalizing,
  Reprojection,
  Advection,
  MergeHalf,
  MergeTip,
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
  ReprojectedHalfTopX,
  ReprojectedHalfTopY,
  AdvectedHalfTipX,
  AdvectedHalfTipY,

  ReprojectedHalfTop,
  ReprojectedHalfTopFiltered,

  ReprojectedTopDepth,
  AdvectedTipDepth,

  ColorReprojectedTop,
  ColorAdvectedTip,

  CurrMevcFiltered,
  PrevMevcFiltered,
  CurrMvecDuplicated,
  PrevMvecDuplicated,

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
    case InternalResType::ReprojectedHalfTopX:
    case InternalResType::ReprojectedHalfTopY:
    case InternalResType::AdvectedHalfTipX:
    case InternalResType::AdvectedHalfTipY:
      return DXGI_FORMAT_R32_UINT;

    case InternalResType::ColorAdvectedTip:
    case InternalResType::ColorReprojectedTop:
      return DXGI_FORMAT_R11G11B10_FLOAT;

    case InternalResType::ReprojectedHalfTop:
    case InternalResType::ReprojectedHalfTopFiltered:
    case InternalResType::CurrMevcFiltered:
    case InternalResType::PrevMevcFiltered:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::PrevMvecDuplicated:
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

    case InternalResType::ReprojectedTopDepth:
    case InternalResType::AdvectedTipDepth:
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

    case InternalResType::Count:
    default:
      return DXGI_FORMAT_UNKNOWN;
  }
}

std::pair<uint32_t, uint32_t> GetInternalResResolution(InternalResType type,
                                                       uint32_t originWidth,
                                                       uint32_t originHeight) {
  switch (type) {
    case InternalResType::ReprojectedHalfTopX:
    case InternalResType::ReprojectedHalfTopY:
    case InternalResType::AdvectedHalfTipX:
    case InternalResType::AdvectedHalfTipY:
    case InternalResType::ColorAdvectedTip:
    case InternalResType::ColorReprojectedTop:
    case InternalResType::AdvectedTipDepth:
    case InternalResType::ReprojectedTopDepth:
    case InternalResType::ReprojectedHalfTop:
    case InternalResType::ReprojectedHalfTopFiltered:
    case InternalResType::CurrMevcFiltered:
    case InternalResType::PrevMevcFiltered:
    case InternalResType::CurrMvecDuplicated:
    case InternalResType::PrevMvecDuplicated:
      return {originWidth, originHeight};

    case InternalResType::MotionVectorLv1:
    case InternalResType::InpaintedDepthLv1:
    case InternalResType::PushedVectorLv1:
    case InternalResType::PushedDepthLv1:
      return {originWidth / 2, originHeight / 2};

    case InternalResType::MotionVectorLv2:
    case InternalResType::InpaintedDepthLv2:
    case InternalResType::PushedVectorLv2:
    case InternalResType::PushedDepthLv2:
      return {originWidth / 4, originHeight / 4};

    case InternalResType::MotionVectorLv3:
    case InternalResType::InpaintedDepthLv3:
    case InternalResType::PushedVectorLv3:
    case InternalResType::PushedDepthLv3:
      return {originWidth / 8, originHeight / 8};

    case InternalResType::MotionVectorLv4:
    case InternalResType::InpaintedDepthLv4:
    case InternalResType::PushedVectorLv4:
    case InternalResType::PushedDepthLv4:
	  return {originWidth / 16, originHeight / 16};

    case InternalResType::MotionVectorLv5:
    case InternalResType::InpaintedDepthLv5:
    case InternalResType::PushedVectorLv5:
    case InternalResType::PushedDepthLv5:
      return {originWidth / 32, originHeight / 32};

    case InternalResType::MotionVectorLv6:
    case InternalResType::InpaintedDepthLv6:
    case InternalResType::PushedVectorLv6:
    case InternalResType::PushedDepthLv6:
      return {originWidth / 64, originHeight / 64};

    case InternalResType::MotionVectorLv7:
    case InternalResType::InpaintedDepthLv7:
      return {originWidth / 128, originHeight / 128};

    case InternalResType::Count:
    default:
      return {0, 0};
  }
}