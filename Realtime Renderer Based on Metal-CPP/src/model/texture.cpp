//
//  textureutils.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/20.
//

//
//  使用 stb_image 加载 HDR 纹理
//
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define TINYEXR_IMPLEMENTATION
#include "util/tinyexr/tinyexr.h"

#include <Metal/Metal.hpp>
#include "model/texture.hpp"
#include <iostream>


MTL::Texture* TextureLoader::load(MTL::Device* device,
                                  MTL::CommandQueue *commandQueue,
                                   const std::string& path,
                                   ColorSpace colorSpace,
                                  bool generateMipmap) {
    if (!std::filesystem::exists(path)) {
        std::cerr << "Texture not found: " << path << std::endl;
        return nullptr;
    }
    std::string ext = std::filesystem::path(path).extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    
    // 根据扩展名选择加载器
    if (ext == ".exr") {
        return loadEXR(device, commandQueue, path, generateMipmap);
    } else if (ext == ".hdr" || ext == ".pic") {
        return loadHDR(device, commandQueue, path, generateMipmap);
    } else {
        // PNG, JPG, TGA, BMP 等
        return loadSTB(device, commandQueue, path, colorSpace, generateMipmap);
    }
}

MTL::Texture* TextureLoader::loadSTB(MTL::Device* device,
                                     MTL::CommandQueue* commandQueue,
                                     const std::string& path,
                                     ColorSpace colorSpace,
                                     bool generateMipmap) {
    int width, height, channels;
    unsigned char* data = stbi_load(path.c_str(), &width, &height, &channels, 4);
    
    if (!data) {
        std::cerr << "STB failed to load: " << path << " - " << stbi_failure_reason() << std::endl;
        return nullptr;
    }
    
    // 1. 动态计算 Mipmap 层级
    uint32_t mipLevels = generateMipmap ? static_cast<uint32_t>(std::floor(std::log2(std::max(width, height)))) + 1 : 1;
    
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setTextureType(MTL::TextureType2D);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setMipmapLevelCount(mipLevels);
    
    // 允许 Shader 读取，同时也允许 GPU 写入（生成 Mipmap 必须要有 Write 权限）
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    if (colorSpace == ColorSpace::SRGB) {
        desc->setPixelFormat(MTL::PixelFormatRGBA8Unorm_sRGB);
    } else {
        desc->setPixelFormat(MTL::PixelFormatRGBA8Unorm);
    }
    
    MTL::Texture* texture = device->newTexture(desc);
    if (texture) {
        // 2. 写入第 0 级高清图
        MTL::Region region = MTL::Region::Make2D(0, 0, width, height);
        texture->replaceRegion(region, 0, data, width * 4);
        
        // 3. 呼叫 M2 Pro 的 GPU 硬件生成剩下的 Mipmap
        if (mipLevels > 1 && commandQueue != nullptr) {
            MTL::CommandBuffer* cmd = commandQueue->commandBuffer();
            cmd->setLabel(NS::String::string("Generate STB Mipmaps", NS::ASCIIStringEncoding));
            MTL::BlitCommandEncoder* blit = cmd->blitCommandEncoder();
            blit->generateMipmaps(texture);
            blit->endEncoding();
            cmd->commit();
            cmd->waitUntilCompleted();
        }
    }
    
    stbi_image_free(data);
    desc->release();
    
    return texture;
}

MTL::Texture* TextureLoader::loadHDR(MTL::Device* device,
                                     MTL::CommandQueue* commandQueue,
                                     const std::string& path,
                                     bool generateMipmap) {
    int width, height, channels;
    float* data = stbi_loadf(path.c_str(), &width, &height, &channels, 4);
    
    if (!data) {
        std::cerr << "STB failed to load HDR: " << path << " - " << stbi_failure_reason() << std::endl;
        return nullptr;
    }
    
    uint32_t mipLevels = generateMipmap ? static_cast<uint32_t>(std::floor(std::log2(std::max(width, height)))) + 1 : 1;
    
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setTextureType(MTL::TextureType2D);
    desc->setPixelFormat(MTL::PixelFormatRGBA32Float);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setMipmapLevelCount(mipLevels);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    MTL::Texture* texture = device->newTexture(desc);
    if (texture) {
        MTL::Region region = MTL::Region::Make2D(0, 0, width, height);
        texture->replaceRegion(region, 0, data, width * 4 * sizeof(float));
        
        if (mipLevels > 1 && commandQueue != nullptr) {
            MTL::CommandBuffer* cmd = commandQueue->commandBuffer();
            MTL::BlitCommandEncoder* blit = cmd->blitCommandEncoder();
            blit->generateMipmaps(texture);
            blit->endEncoding();
            cmd->commit();
            cmd->waitUntilCompleted();
        }
    }
    
    stbi_image_free(data);
    desc->release();
    
    return texture;
}

MTL::Texture* TextureLoader::loadEXR(MTL::Device* device,
                                     MTL::CommandQueue* commandQueue,
                                     const std::string& path,
                                     bool generateMipmap) {
#ifdef TINYEXR_IMPLEMENTATION
    float* rgba = nullptr;
    int width, height;
    const char* err = nullptr;
    
    int ret = LoadEXR(&rgba, &width, &height, path.c_str(), &err);
    
    if (ret != TINYEXR_SUCCESS) {
        if (err) {
            std::cerr << "TinyEXR Error: " << err << " in " << path << std::endl;
            FreeEXRErrorMessage(err);
        }
        return nullptr;
    }
    
    uint32_t mipLevels = generateMipmap ? static_cast<uint32_t>(std::floor(std::log2(std::max(width, height)))) + 1 : 1;
    
    MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setTextureType(MTL::TextureType2D);
    desc->setPixelFormat(MTL::PixelFormatRGBA32Float);
    desc->setWidth(width);
    desc->setHeight(height);
    desc->setMipmapLevelCount(mipLevels);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    
    MTL::Texture* texture = device->newTexture(desc);
    if (texture) {
        MTL::Region region = MTL::Region::Make2D(0, 0, width, height);
        texture->replaceRegion(region, 0, rgba, width * 4 * sizeof(float));
        
        if (mipLevels > 1 && commandQueue != nullptr) {
            MTL::CommandBuffer* cmd = commandQueue->commandBuffer();
            MTL::BlitCommandEncoder* blit = cmd->blitCommandEncoder();
            blit->generateMipmaps(texture);
            blit->endEncoding();
            cmd->commit();
            cmd->waitUntilCompleted();
        }
    }
    
    free(rgba);
    desc->release();
    
    return texture;
#else
    std::cerr << "EXR support not compiled. Use TinyEXR or convert to HDR/PNG." << std::endl;
    return nullptr;
#endif
}
