//
//  textureutils.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/20.
//
#pragma once

#include <Metal/Metal.hpp>
#include <string>
#include <filesystem>
class TextureLoader {
public:
    enum class ColorSpace {
        SRGB,    // 用于 Albedo
        LINEAR   // 用于 Normal, Roughness, Metallic, AO
    };
    
    // 主加载函数 - 自动检测格式
    static MTL::Texture* load(MTL::Device* device,
                              MTL::CommandQueue *commandQueue,
                              const std::string& path,
                              ColorSpace colorSpace = ColorSpace::LINEAR,
                              bool generateMipmap = true);

private:
    static MTL::Texture* loadSTB(MTL::Device* device, MTL::CommandQueue* commandQueue, const std::string& path, ColorSpace colorSpace, bool generateMipmap);
    static MTL::Texture* loadEXR(MTL::Device* device, MTL::CommandQueue* commandQueue, const std::string& path, bool generateMipmap);
    static MTL::Texture* loadHDR(MTL::Device* device, MTL::CommandQueue* commandQueue, const std::string& path, bool generateMipmap);

};



