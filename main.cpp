#define _CRT_SECURE_NO_WARNINGS

#include <d3d11.h>

#include <array>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#include <iostream>

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_write.h"
#include "util.h"

#define JSON_NOEXCEPTION 1
#include "json.h"

using json = nlohmann::json;

struct FrameGenerationInputCb
{
    float    prevClipToClip[16];
    float    clipToPrevClip[16];
    float    tipTopDistance[2];
    float    viewportSize[2];
    float    viewportInv[2];
    uint32_t dimensions[2]; // x, y
};

struct ConfigInfo
{
    DXGI_FORMAT depthFormat;
    DXGI_FORMAT mevcFormat;
    uint32_t    beginFrameId;
    uint32_t    endFrameId;
    uint32_t    interpolatedFrames;
};

uint32_t g_ColorWidth;
uint32_t g_ColorHeight;

ID3D11Device*        g_pDevice;
ID3D11DeviceContext* g_pContext;

static constexpr size_t ComputeShaderTypeCount = static_cast<size_t>(ComputeShaderType::Count);
static constexpr size_t StagTypeCount          = static_cast<size_t>(StagResType::Count);
static constexpr size_t InputTypeCount         = static_cast<size_t>(InputResType::Count);
static constexpr size_t ConstBufferTypeCount   = static_cast<size_t>(ConstBufferType::Count);
static constexpr size_t InternalTypeCount      = static_cast<size_t>(InternalResType::Count);
static constexpr size_t SamplerTypeCount      = static_cast<size_t>(SamplerType::Count);

std::array<ID3D11ComputeShader*, ComputeShaderTypeCount> ComputeShaders{};

std::array<ID3D11Texture2D*, StagTypeCount> StagResourceList{};

std::array<ID3D11Texture2D*, InputTypeCount> InputResourceList{};
std::array<ResourceView, InputTypeCount>     InputResourceViewList{};

std::array<ID3D11Buffer*, ConstBufferTypeCount> ConstantBufferList{};

std::array<ID3D11Texture2D*, InternalTypeCount> InternalResourceList{};
std::array<ResourceView, InternalTypeCount>     InternalResourceViewList{};

std::array<ID3D11SamplerState*, SamplerTypeCount> SamplerList{};

std::map<ID3D11Resource*, ResourceView> ResourceViewMap{};

FrameGenerationInputCb g_constBufData;
ConfigInfo             g_configInfo = {DXGI_FORMAT_R24_UNORM_X8_TYPELESS, DXGI_FORMAT_R16G16_FLOAT, 0, 1, 1};

// Outputs
ID3D11Texture2D*           g_pColorOutput;
ID3D11UnorderedAccessView* g_pColorOutputUav;

#pragma comment(lib, "d3d11")

#define RELEASE_SAFE(pObj) \
    if (pObj != nullptr)   \
    {                      \
        pObj->Release();   \
        pObj = nullptr;    \
    }

void ParseConfig(ConfigInfo& info)
{
    json config = {};
    std::ifstream file("config.json");
    if (file.is_open())
    {
        file >> config;

        if (config.contains("DepthFormat"))
        {
            info.depthFormat = static_cast<DXGI_FORMAT>(config["DepthFormat"].get<uint32_t>());
        }
        if (config.contains("MevcFormat"))
        {
            info.mevcFormat = static_cast<DXGI_FORMAT>(config["MevcFormat"].get<uint32_t>());
        }
        if (config.contains("BeginFrameId"))
        {
            info.beginFrameId = config["BeginFrameId"].get<uint32_t>();
        }
        if (config.contains("EndFrameId"))
        {
            info.endFrameId = config["EndFrameId"].get<uint32_t>();
        }
        if (config.contains("InterpolatedFrames"))
        {
            info.interpolatedFrames = config["InterpolatedFrames"].get<uint32_t>();
        }
    }
}

DXGI_FORMAT GetInputResFormat(InputResType type)
{
    switch (type)
    {
    case InputResType::CurrColor:
    case InputResType::PrevColor:
        return DXGI_FORMAT_R8G8B8A8_UNORM;

    case InputResType::CurrDepth:
    case InputResType::PrevDepth:
        return g_configInfo.depthFormat;
        break;
    case InputResType::CurrMevc:
    case InputResType::PrevMevc:
        return g_configInfo.mevcFormat;
    case InputResType::Count:
    default:
        return DXGI_FORMAT_UNKNOWN;
    }
}

void ReleaseContext()
{
    for (auto res : StagResourceList)
    {
        auto view = ResourceViewMap.find(res);
        if (view != ResourceViewMap.end())
        {
            RELEASE_SAFE(view->second.srv);
            RELEASE_SAFE(view->second.uav);
        }
        RELEASE_SAFE(res);
    }

    for (auto shader : ComputeShaders)
    {
        RELEASE_SAFE(shader);
    }

    for (auto res : InputResourceList)
    {
        auto view = ResourceViewMap.find(res);
        if (view != ResourceViewMap.end())
        {
            RELEASE_SAFE(view->second.srv);
            RELEASE_SAFE(view->second.uav);
        }
        RELEASE_SAFE(res);
    }

    for (auto res : InternalResourceList)
    {
        auto view = ResourceViewMap.find(res);
        if (view != ResourceViewMap.end())
        {
            RELEASE_SAFE(view->second.srv);
            RELEASE_SAFE(view->second.uav);
        }
        RELEASE_SAFE(res);
    }

    for (auto buf : ConstantBufferList)
    {
        RELEASE_SAFE(buf);
    }

    for (auto sampler : SamplerList)
    {
        RELEASE_SAFE(sampler);
    }

    RELEASE_SAFE(g_pColorOutputUav);
    RELEASE_SAFE(g_pColorOutput);

    RELEASE_SAFE(g_pContext);
    RELEASE_SAFE(g_pDevice);
}

HRESULT InitSampleContext(bool debugLayer)
{
    ULONG createFlags = 0;
    if (debugLayer)
    {
        createFlags |= D3D11_CREATE_DEVICE_DEBUG;
    }

    const D3D_FEATURE_LEVEL pFeatureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
    };
    const UINT nFeatureLevels = 1;

    return D3D11CreateDevice(nullptr,
                             D3D_DRIVER_TYPE_HARDWARE,
                             nullptr,
                             createFlags,
                             pFeatureLevels,
                             1,
                             D3D11_SDK_VERSION,
                             &g_pDevice,
                             nullptr,
                             &g_pContext);
}

HRESULT InitStagingResources(int width, int height)
{
    HRESULT hr = E_FAIL;

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Format               = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.Width                = width;
    desc.Height               = height;
    desc.MipLevels            = 1;
    desc.SampleDesc.Count     = 1;
    desc.SampleDesc.Quality   = 0;
    desc.ArraySize            = 1;
    desc.CPUAccessFlags       = D3D11_CPU_ACCESS_WRITE | D3D11_CPU_ACCESS_READ;
    desc.BindFlags            = 0;
    desc.Usage                = D3D11_USAGE_STAGING;

    hr = g_pDevice->CreateTexture2D(&desc, nullptr, &StagResourceList[static_cast<size_t>(StagResType::ColorInput)]);
    hr = g_pDevice->CreateTexture2D(&desc, nullptr, &StagResourceList[static_cast<size_t>(StagResType::ColorOutput)]);

    if (SUCCEEDED(hr))
    {
        desc.Format = DXGI_FORMAT_R16G16_FLOAT;
        hr = g_pDevice->CreateTexture2D(&desc, nullptr, &StagResourceList[static_cast<size_t>(StagResType::Mevc)]);
    }

    if (SUCCEEDED(hr))
    {
        desc.Format = DXGI_FORMAT_R24G8_TYPELESS;
        hr = g_pDevice->CreateTexture2D(&desc, nullptr, &StagResourceList[static_cast<size_t>(StagResType::Depth)]);
    }

    return hr;
}

HRESULT InitAlgoResources(int width, int height)
{
    HRESULT hr = S_OK;

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width                = width;
    desc.Height               = height;
    desc.MipLevels            = 1;
    desc.SampleDesc.Count     = 1;
    desc.SampleDesc.Quality   = 0;
    desc.ArraySize            = 1;
    desc.CPUAccessFlags       = 0;
    desc.Usage                = D3D11_USAGE_DEFAULT;

    auto createViewFunc = [](ID3D11Texture2D* res, ResourceView& resView) {
        D3D11_TEXTURE2D_DESC desc = {};
        res->GetDesc(&desc);

        HRESULT hr = S_OK;

        if (desc.BindFlags & D3D11_BIND_SHADER_RESOURCE)
        {
            D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
            srvDesc.Format                          = desc.Format;
            srvDesc.ViewDimension                   = D3D11_SRV_DIMENSION_TEXTURE2D;
            srvDesc.Texture2D.MipLevels             = 1;
            srvDesc.Texture2D.MostDetailedMip       = 0;

            hr = g_pDevice->CreateShaderResourceView(res, &srvDesc, &resView.srv);
        }

        if (desc.BindFlags & D3D11_BIND_UNORDERED_ACCESS)
        {
            D3D11_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
            uavDesc.Format                           = desc.Format;
            uavDesc.ViewDimension                    = D3D11_UAV_DIMENSION_TEXTURE2D;
            uavDesc.Texture2D.MipSlice               = 0;

            if (SUCCEEDED(hr))
            {
                hr = g_pDevice->CreateUnorderedAccessView(res, &uavDesc, &resView.uav);
            }
        }

        if (SUCCEEDED(hr))
        {
            ResourceViewMap.insert({res, resView});
        }
        return hr;
    };

    for (uint32_t i = 0; i < static_cast<uint32_t>(InputResType::Count) && SUCCEEDED(hr); i++)
    {
        DXGI_FORMAT  fmt     = DXGI_FORMAT_UNKNOWN;
        InputResType resType = static_cast<InputResType>(i);
        fmt                  = GetInputResFormat(resType);
        assert(fmt != DXGI_FORMAT_UNKNOWN);
        desc.Format    = fmt;
        desc.BindFlags = 0;

        UINT formatSupport{};
        g_pDevice->CheckFormatSupport(fmt, &formatSupport);
        if ((formatSupport & D3D11_FORMAT_SUPPORT_TYPED_UNORDERED_ACCESS_VIEW) &&
            (resType != InputResType::CurrDepth) && resType != InputResType::PrevDepth)
        {
            desc.BindFlags |= D3D11_BIND_UNORDERED_ACCESS;
        }

        if (formatSupport & D3D11_FORMAT_SUPPORT_TEXTURE2D)
        {
            desc.BindFlags |= D3D11_BIND_SHADER_RESOURCE;
        }

        hr = g_pDevice->CreateTexture2D(&desc, nullptr, &InputResourceList[i]);

        if (SUCCEEDED(hr))
        {
            hr = createViewFunc(InputResourceList[static_cast<size_t>(i)],
                                InputResourceViewList[static_cast<size_t>(i)]);
        }
    }

    if (SUCCEEDED(hr))
    {
        desc.Format    = DXGI_FORMAT_R8G8B8A8_UNORM;
        desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
        hr             = g_pDevice->CreateTexture2D(&desc, nullptr, &g_pColorOutput);

        D3D11_UNORDERED_ACCESS_VIEW_DESC UAVDesc = {};
        UAVDesc.ViewDimension                    = D3D11_UAV_DIMENSION_TEXTURE2D;
        UAVDesc.Texture2D.MipSlice               = 0;
        UAVDesc.Format                           = DXGI_FORMAT_R8G8B8A8_UNORM;
        hr = g_pDevice->CreateUnorderedAccessView(g_pColorOutput, &UAVDesc, &g_pColorOutputUav);
    }

    for (uint32_t i = 0; i < static_cast<uint32_t>(InternalResType::Count) && SUCCEEDED(hr); i++)
    {
        DXGI_FORMAT     fmt     = DXGI_FORMAT_UNKNOWN;
        InternalResType resType = static_cast<InternalResType>(i);
        fmt                     = GetInternalResFormat(resType);
        assert(fmt != DXGI_FORMAT_UNKNOWN);

        auto resolution = GetInternalResResolution(resType, width, height);
        assert(resolution.first != 0);
        assert(resolution.second != 0);

        desc.Width     = resolution.first;
        desc.Height    = resolution.second;
        desc.Format    = fmt;
        desc.BindFlags = 0;

        UINT formatSupport{};
        g_pDevice->CheckFormatSupport(fmt, &formatSupport);
        if (formatSupport & D3D11_FORMAT_SUPPORT_TYPED_UNORDERED_ACCESS_VIEW)
        {
            desc.BindFlags |= D3D11_BIND_UNORDERED_ACCESS;
        }

        if (formatSupport & D3D11_FORMAT_SUPPORT_TEXTURE2D)
        {
            desc.BindFlags |= D3D11_BIND_SHADER_RESOURCE;
        }

        hr = g_pDevice->CreateTexture2D(&desc, nullptr, &InternalResourceList[i]);

        if (SUCCEEDED(hr))
        {
            hr = createViewFunc(InternalResourceList[static_cast<size_t>(i)],
                                InternalResourceViewList[static_cast<size_t>(i)]);
        }
    }

    D3D11_BUFFER_DESC bufDesc   = {};
    bufDesc.Usage               = D3D11_USAGE_DYNAMIC;
    bufDesc.CPUAccessFlags      = D3D11_CPU_ACCESS_WRITE;
    bufDesc.BindFlags           = D3D11_BIND_CONSTANT_BUFFER;
    bufDesc.StructureByteStride = 0;

    if (SUCCEEDED(hr))
    {
        bufDesc.ByteWidth = sizeof(ClearingConstParamStruct);
        hr                = g_pDevice->CreateBuffer(&bufDesc,
                                     nullptr,
                                     &ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Clearing)]);
    }

    if (SUCCEEDED(hr))
    {
        bufDesc.ByteWidth = sizeof(MVecParamStruct);
        hr                = g_pDevice->CreateBuffer(&bufDesc,
                                     nullptr,
                                     &ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Mevc)]);
    }

    if (SUCCEEDED(hr))
    {
        bufDesc.ByteWidth = sizeof(MergeParamStruct);
        hr                = g_pDevice->CreateBuffer(&bufDesc,
                                     nullptr,
                                     &ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Merge)]);
    }

    if (SUCCEEDED(hr))
    {
        bufDesc.ByteWidth = sizeof(PushPullParameters);
        hr                = g_pDevice->CreateBuffer(&bufDesc,
                                     nullptr,
                                     &ConstantBufferList[static_cast<uint32_t>(ConstBufferType::PushPull)]);
    }

    if (SUCCEEDED(hr))
    {
        bufDesc.ByteWidth = sizeof(ResolutionConstParamStruct);
        hr                = g_pDevice->CreateBuffer(&bufDesc,
                                     nullptr,
                                     &ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Resolution)]);
    }

    return hr;
}

HRESULT InitResources()
{
    HRESULT hr = E_FAIL;

    int  width   = 0;
    int  height  = 0;
    int  channel = 0;
    auto pPixels = stbi_load("ColorInput/colorinput_0.png", &width, &height, &channel, 4);

    hr = InitStagingResources(width, height);

    if (SUCCEEDED(hr))
    {
        hr = InitAlgoResources(width, height);
    }

    if (SUCCEEDED(hr))
    {
        g_ColorWidth  = width;
        g_ColorHeight = height;

        g_constBufData.dimensions[0]   = g_ColorWidth;
        g_constBufData.dimensions[1]   = g_ColorHeight;
        g_constBufData.viewportSize[0] = static_cast<float>(g_ColorWidth);
        g_constBufData.viewportSize[1] = static_cast<float>(g_ColorHeight);
        g_constBufData.viewportInv[0]  = 1.0 / static_cast<float>(g_ColorWidth);
        g_constBufData.viewportInv[1]  = 1.0 / static_cast<float>(g_ColorHeight);
    }

    return hr;
}

HRESULT InitSamplerList()
{
    HRESULT hr = S_OK;

    {
        D3D11_SAMPLER_DESC sampDesc = {
            D3D11_FILTER_MIN_MAG_MIP_POINT,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            0.0f,
            1,
            D3D11_COMPARISON_NEVER,
            {0.0f, 0.0f, 0.0f, 0.0f},
            0.0f,
            D3D11_FLOAT32_MAX,
        };
        hr  = g_pDevice->CreateSamplerState(&sampDesc, &SamplerList[static_cast<uint32_t>(SamplerType::PointClamp)]);
    }

    {
        D3D11_SAMPLER_DESC sampDesc = {
            D3D11_FILTER_MIN_MAG_MIP_POINT,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            0.0f,
            1,
            D3D11_COMPARISON_NEVER,
            {0.0f, 0.0f, 0.0f, 0.0f},
            0.0f,
            D3D11_FLOAT32_MAX,
        };
        hr = g_pDevice->CreateSamplerState(&sampDesc, &SamplerList[static_cast<uint32_t>(SamplerType::PointMirror)]);
    }

    {
        D3D11_SAMPLER_DESC sampDesc = {
            D3D11_FILTER_MIN_MAG_MIP_LINEAR,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            0.0f,
            1,
            D3D11_COMPARISON_NEVER,
            {0.0f, 0.0f, 0.0f, 0.0f},
            0.0f,
            D3D11_FLOAT32_MAX,
        };

        hr = g_pDevice->CreateSamplerState(&sampDesc, &SamplerList[static_cast<uint32_t>(SamplerType::LinearClamp)]);
    }

    {
        D3D11_SAMPLER_DESC sampDesc = {
            D3D11_FILTER_MIN_MAG_MIP_LINEAR,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            D3D11_TEXTURE_ADDRESS_MIRROR,
            0.0f,
            1,
            D3D11_COMPARISON_NEVER,
            {0.0f, 0.0f, 0.0f, 0.0f},
            0.0f,
            D3D11_FLOAT32_MAX,
        };

        hr = g_pDevice->CreateSamplerState(&sampDesc, &SamplerList[static_cast<uint32_t>(SamplerType::LinearMirror)]);
    }

    {
        D3D11_SAMPLER_DESC sampDesc = {
            D3D11_FILTER_ANISOTROPIC,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            D3D11_TEXTURE_ADDRESS_CLAMP,
            0.0f,
            1,
            D3D11_COMPARISON_NEVER,
            {0.0f, 0.0f, 0.0f, 0.0f},
            0.0f,
            D3D11_FLOAT32_MAX,
        };

        hr = g_pDevice->CreateSamplerState(&sampDesc, &SamplerList[static_cast<uint32_t>(SamplerType::AnisoClamp)]);
    }

    return hr;
}

HRESULT CreateComputeShader(ID3D11ComputeShader** ppShader, const std::string& dxbcFile)
{
    HRESULT       hr = E_FAIL;
    std::ifstream f(dxbcFile);
    if (f.is_open())
    {
        std::vector<uint8_t> result = AcquireFileContent(dxbcFile);
        hr = g_pDevice->CreateComputeShader(static_cast<void*>(result.data()), result.size(), nullptr, ppShader);
    }
    return hr;
}

void PrepareInput(uint32_t frameIndex)
{
    D3D11_MAPPED_SUBRESOURCE mapped = {};

    auto stagMevc       = StagResourceList[static_cast<size_t>(StagResType::Mevc)];
    auto stagColorInput = StagResourceList[static_cast<size_t>(StagResType::ColorInput)];
    auto stagDepth      = StagResourceList[static_cast<size_t>(StagResType::Depth)];

    {
        std::string clipFile     = "ClipInfo/clipinfo_" + std::to_string(frameIndex) + ".bin";
        auto        pervClipInfo = AcquireFileContent(clipFile);

        uint32_t offset = 0;

        memcpy(g_constBufData.prevClipToClip, pervClipInfo.data() + offset, sizeof(g_constBufData.prevClipToClip));

        offset += sizeof(g_constBufData.prevClipToClip);

        memcpy(g_constBufData.clipToPrevClip, pervClipInfo.data() + offset, sizeof(g_constBufData.clipToPrevClip));
    }

    {
        std::string pervMevcFile = "MotionVector/motionvector_" + std::to_string(frameIndex) + ".bin";
        auto        pervMevc     = AcquireFileContent(pervMevcFile);

        g_pContext->Map(stagMevc, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, pervMevc.data(), pervMevc.size());
        g_pContext->Unmap(stagMevc, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::PrevMevc)], stagMevc);
    }

    {
        std::string currMevcFile = "MotionVector/motionvector_" + std::to_string(frameIndex + 1) + ".bin";
        auto        currMevc     = AcquireFileContent(currMevcFile);

        g_pContext->Map(stagMevc, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, currMevc.data(), currMevc.size());
        g_pContext->Unmap(stagMevc, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::CurrMevc)], stagMevc);
    }

    {
        std::string pervDepthFile = "Depth/depth_" + std::to_string(frameIndex) + ".bin";
        auto        pervDepth     = AcquireFileContent(pervDepthFile);

        g_pContext->Map(stagDepth, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, pervDepth.data(), pervDepth.size());
        g_pContext->Unmap(stagDepth, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::PrevDepth)], stagDepth);
    }

    {
        std::string currDepthFile = "Depth/depth_" + std::to_string(frameIndex + 1) + ".bin";
        auto        currDepth     = AcquireFileContent(currDepthFile);

        g_pContext->Map(stagDepth, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, currDepth.data(), currDepth.size());
        g_pContext->Unmap(stagDepth, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::CurrDepth)], stagDepth);
    }

    {
        std::string    pervColorFile = "ColorInput/colorinput_" + std::to_string(frameIndex) + ".png";
        int            w             = 0;
        int            h             = 0;
        int            ch            = 0;
        unsigned char* pPixels       = stbi_load(pervColorFile.c_str(), &w, &h, &ch, 4);

        g_pContext->Map(stagColorInput, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, pPixels, h * mapped.RowPitch);
        g_pContext->Unmap(stagColorInput, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::PrevColor)], stagColorInput);

        stbi_image_free(pPixels);
    }

    {
        std::string    currColorFile = "ColorInput/colorinput_" + std::to_string(frameIndex + 1) + ".png";
        int            w             = 0;
        int            h             = 0;
        int            ch            = 0;
        unsigned char* pPixels       = stbi_load(currColorFile.c_str(), &w, &h, &ch, 4);

        g_pContext->Map(stagColorInput, 0, D3D11_MAP_WRITE, 0, &mapped);
        memcpy(mapped.pData, pPixels, h * mapped.RowPitch);
        g_pContext->Unmap(stagColorInput, 0);
        g_pContext->CopyResource(InputResourceList[static_cast<size_t>(InputResType::CurrColor)], stagColorInput);

        stbi_image_free(pPixels);
    }
}

void DumpOutput(uint32_t frameIndex)
{
    std::string genFrameFile = "ColorOutput/coloroutput_" + std::to_string(frameIndex) + ".png";

    ID3D11Texture2D* pTempOut = StagResourceList[static_cast<uint32_t>(StagResType::ColorOutput)];
    g_pContext->CopyResource(pTempOut, g_pColorOutput);

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    g_pContext->Map(pTempOut, 0, D3D11_MAP_READ, 0, &mapped);
    stbi_write_png(genFrameFile.c_str(), g_ColorWidth, g_ColorHeight, 4, mapped.pData, mapped.RowPitch);
    g_pContext->Unmap(pTempOut, 0);
}

void ProcessFrameGenerationClearing(ClearingConstParamStruct* pCb, uint32_t grid[])
{
    g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Clear)], nullptr, 0);
    ID3D11UnorderedAccessView* ppUavs[] = {
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullY)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipY)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopY)].uav,
    };

    g_pContext->CSSetUnorderedAccessViews(0, 6, ppUavs, 0);

    ID3D11Buffer*            buf    = ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Clearing)];
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    memcpy(mapped.pData, pCb, mapped.RowPitch);
    g_pContext->Unmap(buf, 0);

    g_pContext->CSSetConstantBuffers(0, 1, &buf);
    g_pContext->Dispatch(grid[0], grid[1], grid[2]);

    ID3D11UnorderedAccessView* emptyUavs[6] = {nullptr};

    g_pContext->CSSetUnorderedAccessViews(0, 6, emptyUavs, 0);
}

void ProcessFrameGenerationReprojection(MVecParamStruct* pCb, uint32_t grid[])
{
    g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Reprojection)], nullptr, 0);

    ID3D11ShaderResourceView* ppSrvs[] = {
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::PrevMevcFiltered)].srv,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::CurrMevcFiltered)].srv,
        InputResourceViewList[static_cast<uint32_t>(InputResType::PrevDepth)].srv,
        InputResourceViewList[static_cast<uint32_t>(InputResType::CurrDepth)].srv};
    g_pContext->CSSetShaderResources(0, 4, ppSrvs);

    ID3D11UnorderedAccessView* ppUavs[] = {
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullY)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipY)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopX)].uav,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopY)].uav,
    };

    g_pContext->CSSetUnorderedAccessViews(0, 6, ppUavs, 0);

    ID3D11Buffer*            buf    = ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Mevc)];
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    memcpy(mapped.pData, pCb, mapped.RowPitch);
    g_pContext->Unmap(buf, 0);

    g_pContext->CSSetSamplers(0, 1, &SamplerList[static_cast<uint32_t>(SamplerType::LinearClamp)]);
    g_pContext->CSSetConstantBuffers(0, 1, &buf);
    g_pContext->Dispatch(grid[0], grid[1], grid[2]);

    ID3D11UnorderedAccessView* emptyUavs[6] = {nullptr};
    g_pContext->CSSetUnorderedAccessViews(0, 6, emptyUavs, 0);
    ID3D11ShaderResourceView* emptySrvs[4] = {nullptr};
    g_pContext->CSSetShaderResources(0, 4, emptySrvs);
}

void ProcessFrameGenerationMerging(MergeParamStruct* pCb, uint32_t grid[])
{
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::MergeHalf)], nullptr, 0);

        ID3D11UnorderedAccessView* ppUavs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipX)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipY)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopX)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopY)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTip)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTop)].uav,
        };
        g_pContext->CSSetUnorderedAccessViews(0, 6, ppUavs, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::CurrMevcFiltered)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::PrevMevcFiltered)].srv,
            InputResourceViewList[static_cast<uint32_t>(InputResType::CurrDepth)].srv,
            InputResourceViewList[static_cast<uint32_t>(InputResType::PrevDepth)].srv};
        g_pContext->CSSetShaderResources(0, 4, ppSrvs);

        ID3D11Buffer*            buf    = ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Merge)];
        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, pCb, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);

        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        g_pContext->CSSetSamplers(0, 1, &SamplerList[static_cast<uint32_t>(SamplerType::LinearClamp)]);

        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[6] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 6, emptyUavs, 0);
        ID3D11ShaderResourceView* emptySrvs[4] = {nullptr};
        g_pContext->CSSetShaderResources(0, 4, emptySrvs);
    }

    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::MergeFull)], nullptr, 0);
        ID3D11UnorderedAccessView* ppUavs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullX)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFullY)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFull)].uav,
        };
        g_pContext->CSSetUnorderedAccessViews(0, 3, ppUavs, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::CurrMevcFiltered)].srv,
            InputResourceViewList[static_cast<uint32_t>(InputResType::PrevDepth)].srv};
        g_pContext->CSSetShaderResources(0, 2, ppSrvs);

        g_pContext->CSSetSamplers(0, 1, &SamplerList[static_cast<uint32_t>(SamplerType::LinearClamp)]);

        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[3] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 3, emptyUavs, 0);
        ID3D11ShaderResourceView* emptySrvs[2] = {nullptr};
        g_pContext->CSSetShaderResources(0, 2, emptySrvs);
    }
}

void AddPushPullPasses(ID3D11Texture2D* pInput, ID3D11Texture2D* pOutput, const int layers)
{
    if (layers == 0)
    {
        g_pContext->CopyResource(pOutput, pInput);
        return;
    }

    PushPullParameters ppParameters  = {};
    ppParameters.FinerDimension[0]   = g_ColorWidth;
    ppParameters.FinerDimension[1]   = g_ColorHeight;
    ppParameters.CoarserDimension[0] = ppParameters.FinerDimension[0] / 2;
    ppParameters.CoarserDimension[1] = ppParameters.FinerDimension[1] / 2;

    ID3D11Buffer* buf = ConstantBufferList[static_cast<uint32_t>(ConstBufferType::PushPull)];

    PushPullParameters ppParametersLv01 = ppParameters;
    // Pulling
    if (layers >= 1)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::FirstLeg)], nullptr, 0);
        g_pContext->CSSetShaderResources(0, 1, &ResourceViewMap[pInput].srv);

        ID3D11UnorderedAccessView* ppUavs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv1)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv1)].uav};
        g_pContext->CSSetUnorderedAccessViews(0, 2, ppUavs, 0);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv01, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv01.CoarserDimension[0] + 8 - 1) / 8,
                           (ppParametersLv01.CoarserDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[2] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 2, emptyUavs, 0);
    }

    PushPullParameters ppParametersLv12;
    ppParametersLv12.FinerDimension[0]   = ppParametersLv01.FinerDimension[0] / 2;
    ppParametersLv12.FinerDimension[1]   = ppParametersLv01.FinerDimension[1] / 2;
    ppParametersLv12.CoarserDimension[0] = ppParametersLv01.CoarserDimension[0] / 2;
    ppParametersLv12.CoarserDimension[1] = ppParametersLv01.CoarserDimension[1] / 2;
    if (layers >= 2)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Pull)], nullptr, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv1)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv1)].srv};

        g_pContext->CSSetShaderResources(0, 2, ppSrvs);

        ID3D11UnorderedAccessView* ppUavs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv2)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv2)].uav};
        g_pContext->CSSetUnorderedAccessViews(0, 2, ppUavs, 0);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv12, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv12.CoarserDimension[0] + 8 - 1) / 8,
                           (ppParametersLv12.CoarserDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[2] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 2, emptyUavs, 0);
    }

    PushPullParameters ppParametersLv23;
    ppParametersLv23.FinerDimension[0]   = ppParametersLv12.FinerDimension[0] / 2;
    ppParametersLv23.FinerDimension[1]   = ppParametersLv12.FinerDimension[1] / 2;
    ppParametersLv23.CoarserDimension[0] = ppParametersLv12.CoarserDimension[0] / 2;
    ppParametersLv23.CoarserDimension[1] = ppParametersLv12.CoarserDimension[1] / 2;

    if (layers >= 3)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Pull)], nullptr, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv2)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv2)].srv};

        g_pContext->CSSetShaderResources(0, 2, ppSrvs);

        ID3D11UnorderedAccessView* ppUavs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv3)].uav,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv3)].uav};
        g_pContext->CSSetUnorderedAccessViews(0, 2, ppUavs, 0);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv23, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv23.CoarserDimension[0] + 8 - 1) / 8,
                           (ppParametersLv23.CoarserDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[2] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 2, emptyUavs, 0);
    }

    if (layers >= 3)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Push)], nullptr, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv2)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv3)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv2)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv3)].srv,
        };
        g_pContext->CSSetShaderResources(0, 4, ppSrvs);

        g_pContext->CSSetUnorderedAccessViews(
            0,
            1,
            &InternalResourceViewList[static_cast<uint32_t>(InternalResType::PushedVectorLv2)].uav,
            nullptr);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv23, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv23.FinerDimension[0] + 8 - 1) / 8,
                           (ppParametersLv23.FinerDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[1] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 1, emptyUavs, 0);
    }

    if (layers >= 2)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Push)], nullptr, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv1)].srv,
            layers >= 3 ? InternalResourceViewList[static_cast<uint32_t>(InternalResType::PushedVectorLv2)].srv
                        : InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv2)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv1)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv2)].srv,
        };
        g_pContext->CSSetShaderResources(0, 4, ppSrvs);

        g_pContext->CSSetUnorderedAccessViews(
            0,
            1,
            &InternalResourceViewList[static_cast<uint32_t>(InternalResType::PushedVectorLv1)].uav,
            nullptr);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv12, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv12.FinerDimension[0] + 8 - 1) / 8,
                           (ppParametersLv12.FinerDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[1] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 1, emptyUavs, 0);
    }

    if (layers >= 1)
    {
        g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::LastStretch)], nullptr, 0);

        ID3D11ShaderResourceView* ppSrvs[] = {
            ResourceViewMap[pInput].srv,
            layers >= 2 ? InternalResourceViewList[static_cast<uint32_t>(InternalResType::PushedVectorLv1)].srv
                        : InternalResourceViewList[static_cast<uint32_t>(InternalResType::MotionVectorLv1)].srv,
            InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReliabilityLv1)].srv};
        g_pContext->CSSetShaderResources(0, 3, ppSrvs);

        g_pContext->CSSetUnorderedAccessViews(0, 1, &ResourceViewMap[pOutput].uav, nullptr);

        D3D11_MAPPED_SUBRESOURCE mapped = {};
        g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
        memcpy(mapped.pData, &ppParametersLv01, mapped.RowPitch);
        g_pContext->Unmap(buf, 0);
        g_pContext->CSSetConstantBuffers(0, 1, &buf);

        uint32_t grid[] = {(ppParametersLv01.FinerDimension[0] + 8 - 1) / 8,
                           (ppParametersLv01.FinerDimension[1] + 8 - 1) / 8,
                           1};
        g_pContext->Dispatch(grid[0], grid[1], grid[2]);

        ID3D11UnorderedAccessView* emptyUavs[1] = {nullptr};
        g_pContext->CSSetUnorderedAccessViews(0, 1, emptyUavs, 0);
    }
}

void ProcessFrameGenerationResolution(ResolutionConstParamStruct* pCb, uint32_t grid[])
{
    g_pContext->CSSetShader(ComputeShaders[static_cast<uint32_t>(ComputeShaderType::Resolution)], nullptr, 0);

    ID3D11ShaderResourceView* ppSrvs[] = {
        InputResourceViewList[static_cast<uint32_t>(InputResType::PrevColor)].srv,
        InputResourceViewList[static_cast<uint32_t>(InputResType::PrevDepth)].srv,
        InputResourceViewList[static_cast<uint32_t>(InputResType::CurrColor)].srv,
        InputResourceViewList[static_cast<uint32_t>(InputResType::CurrDepth)].srv,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::CurrMevcFiltered)].srv,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedFull)].srv,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTip)].srv,
        InternalResourceViewList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopFiltered)].srv};
    g_pContext->CSSetShaderResources(0, 8, ppSrvs);

    g_pContext->CSSetUnorderedAccessViews(0, 1, &g_pColorOutputUav, 0);

    ID3D11Buffer*            buf    = ConstantBufferList[static_cast<uint32_t>(ConstBufferType::Resolution)];
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    g_pContext->Map(buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    memcpy(mapped.pData, pCb, mapped.RowPitch);
    g_pContext->Unmap(buf, 0);

    g_pContext->CSSetConstantBuffers(0, 1, &buf);
    g_pContext->CSSetSamplers(0, 1, &SamplerList[static_cast<uint32_t>(SamplerType::LinearClamp)]);
    g_pContext->Dispatch(grid[0], grid[1], grid[2]);

    ID3D11UnorderedAccessView* emptyUavs[1] = {nullptr};
    g_pContext->CSSetUnorderedAccessViews(0, 1, emptyUavs, 0);
    ID3D11ShaderResourceView* emptySrvs[8] = {nullptr};
    g_pContext->CSSetShaderResources(0, 8, emptySrvs);
}

void RunAlgo(uint32_t frameIndex, uint32_t total)
{
    PrepareInput(frameIndex);

    uint32_t grid[] = {(g_ColorWidth + 8 - 1) / 8, (g_ColorHeight + 8 - 1) / 8, 1};

    for (uint32_t seq = 0; seq < total; seq++)
    {
        float tipDistance                = static_cast<float>(seq + 1) / static_cast<float>(total + 1);
        float topDistance                = 1.0f - tipDistance;
        g_constBufData.tipTopDistance[0] = tipDistance;
        g_constBufData.tipTopDistance[1] = topDistance;

        {
            // Clearing
            ClearingConstParamStruct cb = {};
            memcpy(cb.dimensions, g_constBufData.dimensions, sizeof(cb.dimensions));
            memcpy(cb.tipTopDistance, g_constBufData.tipTopDistance, sizeof(g_constBufData.tipTopDistance));
            memcpy(cb.viewportInv, g_constBufData.viewportInv, sizeof(g_constBufData.viewportInv));
            memcpy(cb.viewportSize, g_constBufData.viewportSize, sizeof(g_constBufData.viewportSize));
            ProcessFrameGenerationClearing(&cb, grid);
        }

        AddPushPullPasses(InputResourceList[static_cast<uint32_t>(InputResType::CurrMevc)],
                          InternalResourceList[static_cast<uint32_t>(InternalResType::CurrMevcFiltered)],
                          3);
        AddPushPullPasses(InputResourceList[static_cast<uint32_t>(InputResType::PrevMevc)],
                          InternalResourceList[static_cast<uint32_t>(InternalResType::PrevMevcFiltered)],
                          3);

        {
            // Reprojection
            MVecParamStruct cb = {};
            memcpy(cb.prevClipToClip, g_constBufData.prevClipToClip, sizeof(cb.prevClipToClip));
            memcpy(cb.clipToPrevClip, g_constBufData.clipToPrevClip, sizeof(cb.clipToPrevClip));
            memcpy(cb.dimensions, g_constBufData.dimensions, sizeof(cb.dimensions));
            memcpy(cb.tipTopDistance, g_constBufData.tipTopDistance, sizeof(g_constBufData.tipTopDistance));
            memcpy(cb.viewportInv, g_constBufData.viewportInv, sizeof(g_constBufData.viewportInv));
            memcpy(cb.viewportSize, g_constBufData.viewportSize, sizeof(g_constBufData.viewportSize));
            ProcessFrameGenerationReprojection(&cb, grid);
        }

        {
            // Merging
            MergeParamStruct cb = {};
            memcpy(cb.prevClipToClip, g_constBufData.prevClipToClip, sizeof(cb.prevClipToClip));
            memcpy(cb.clipToPrevClip, g_constBufData.clipToPrevClip, sizeof(cb.clipToPrevClip));
            memcpy(cb.dimensions, g_constBufData.dimensions, sizeof(cb.dimensions));
            memcpy(cb.tipTopDistance, g_constBufData.tipTopDistance, sizeof(g_constBufData.tipTopDistance));
            memcpy(cb.viewportInv, g_constBufData.viewportInv, sizeof(g_constBufData.viewportInv));
            memcpy(cb.viewportSize, g_constBufData.viewportSize, sizeof(g_constBufData.viewportSize));

            ProcessFrameGenerationMerging(&cb, grid);
        }

        {
            // Push Pull Pass
            AddPushPullPasses(InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedFull)],
                              InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedFullFiltered)],
                              1);
            AddPushPullPasses(InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTip)],
                              InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTipFiltered)],
                              1);
            AddPushPullPasses(InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTop)],
                              InternalResourceList[static_cast<uint32_t>(InternalResType::ReprojectedHalfTopFiltered)],
                              1);
        }

        {
            // Resolution
            ResolutionConstParamStruct cb = {};
            memcpy(cb.dimensions, g_constBufData.dimensions, sizeof(cb.dimensions));
            memcpy(cb.tipTopDistance, g_constBufData.tipTopDistance, sizeof(g_constBufData.tipTopDistance));
            memcpy(cb.viewportInv, g_constBufData.viewportInv, sizeof(g_constBufData.viewportInv));
            memcpy(cb.viewportSize, g_constBufData.viewportSize, sizeof(g_constBufData.viewportSize));
            ProcessFrameGenerationResolution(&cb, grid);
        }
    }

    DumpOutput(frameIndex);
}

int main()
{
    ParseConfig(g_configInfo);

    std::cout << "BeginFrameId: " << g_configInfo.beginFrameId << std::endl;
    std::cout << "EndFrameId: " << g_configInfo.endFrameId << std::endl;
    std::cout << "InterpolatedFrames: " << g_configInfo.interpolatedFrames << ", note current only support 1"
              << std::endl;

    std::filesystem::create_directory("ColorOutput");

    HRESULT hr = InitSampleContext(true);

    if (SUCCEEDED(hr))
    {
        std::cout << "Create D3D11 Context Success" << std::endl;
    }
    else
    {
        std::cout << "Create D3D11 Context Fail" << std::endl;
    }

    std::vector<ShaderInfo> shaderList = {
        {ComputeShaderType::Clear,        "phsr_fg_clearing.dxbc"    },
        {ComputeShaderType::Reprojection, "phsr_fg_reprojection.dxbc"},
        {ComputeShaderType::MergeHalf,    "phsr_fg_merginghalf.dxbc" },
        {ComputeShaderType::MergeFull,    "phsr_fg_mergingfull.dxbc" },
        {ComputeShaderType::FirstLeg,     "phsr_fg_firstleg.dxbc"    },
        {ComputeShaderType::Pull,         "phsr_fg_pulling.dxbc"     },
        {ComputeShaderType::LastStretch,  "phsr_fg_laststretch.dxbc" },
        {ComputeShaderType::Push,         "phsr_fg_pushing.dxbc"     },
        {ComputeShaderType::Resolution,   "phsr_fg_resolution.dxbc"  },
    };

    for (size_t i = 0; i < shaderList.size() && SUCCEEDED(hr); i++)
    {
        hr = CreateComputeShader(&ComputeShaders[static_cast<uint32_t>(shaderList[i].shaderType)],
                                 shaderList[i].dxbcFile);
    }

    if (SUCCEEDED(hr))
    {
        std::cout << "Create Compute Shaders Success" << std::endl;
    }
    else
    {
        std::cout << "Create Compute Shaders Fail. Exit" << std::endl;
    }

    if (SUCCEEDED(hr))
    {
        hr = InitSamplerList();
    }

    if (SUCCEEDED(hr))
    {
        std::cout << "Init Samplers Success" << std::endl;
    }
    else
    {
        std::cout << "Init Samplers Fail. Exit" << std::endl;
    }

    if (SUCCEEDED(hr))
    {
        hr = InitResources();
    }

    if (SUCCEEDED(hr))
    {
        std::cout << "Init Resource Success" << std::endl;
    }
    else
    {
        std::cout << "Init Resource Fail. Exit" << std::endl;
    }

    for (uint32_t i = g_configInfo.beginFrameId; i < g_configInfo.endFrameId && SUCCEEDED(hr); i++)
    {
        std::cout << "Run algo frame: " << i << std::endl;
        RunAlgo(i, g_configInfo.interpolatedFrames);
    }

    ReleaseContext();


    system("pause");
    return hr;
}