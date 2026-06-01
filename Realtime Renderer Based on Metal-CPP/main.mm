//
//  main.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/15.
//
#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>    // Apple 平台的基础运行库，
#include <Metal/Metal.hpp>              // Apple 的 GPU API
#include <QuartzCore/QuartzCore.hpp>

#include <iostream>
#include <simd/simd.h>
#include "metalview.hpp"
#include "thread/thread_pool.hpp"
#include "camera/camera.hpp"
#include "model/scene.hpp"
#include "model/texture.hpp"       

struct SimpleTask : public Task {
    void run() override {std::cout<<"hello"<<std::endl;}
    ~SimpleTask() {}
};

static bool mouseCaptured = false;  // 初始捕获鼠标
static bool keys[256] = {false};
static auto lastFrameTime = std::chrono::high_resolution_clock::now();
static std::string modelDir = "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/assets/models/";
NS::UInteger sampleCount = 4;
float exposure = .1f;
int main(int argc, const char * argv[]) {
    
    
#pragma mark - Init some infras
    MTL::Device *metalDevice = MTL::CreateSystemDefaultDevice();
    MTL::Library *library = metalDevice->newDefaultLibrary();
    MTL::CommandQueue *commandQueue = metalDevice->newCommandQueue(); assert(commandQueue);
    
    MetalViewWrapper window(1280, 720);
    CA::MetalLayer *metalLayer = (__bridge CA::MetalLayer*)window.getLayer();
    metalLayer->setPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);
   
    Camera camera {};
    Scene scene {};
    
//    scene.addModelInstance(Model(
//         metalDevice,
//         commandQueue,
//         "/Users/menji/Downloads/classroom/classroom.gltf",
//         float3{0.f, -10.f, 0.f},
//         float3{0.f, 180.f, 0.f},
//         float3{1.f, 1.f, 1.f}
//         ));
//
    scene.addModelInstance(Model{
       metalDevice,
       commandQueue,
       "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/assets/models/Television_01_4k.gltf/Television_01_4k.gltf",
       float3{5.f, 4.f, 0.f},
       float3{0.f, 0.f, 0.f},
       float3{3.f, 3.f, 3.f}
   });
    scene.addModelInstance(Model{
       metalDevice,
       commandQueue,
       "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/assets/models/moai50k/moai50k.obj",
       float3{1.f, 1.f, 0.f},
       float3{0.f, 0.f, 0.f},
       float3{10.f, 10.f, 10.f}
   });
    scene.addModelInstance(Model{
       metalDevice,
       commandQueue,"/Users/menji/Downloads/house/flat-archiviz.gltf",
       float3{-2.f, 6.f, 0.f},
       float3{0.f, 0.f, 0.f},
       float3{1.f, 1.f, 1.f}
   });
    scene.addModelInstance(Model{
        metalDevice,
        commandQueue,
        "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/assets/models/chess_set_4k/chess_set_4k.fbx",
        float3{0.f, 0.f, 0.f},
        float3{0.f, 0.f, 0.f},
        float3{.5f, .5f, .5f}
    });
//    scene.addModelInstance(Model{
//        metalDevice,
//        commandQueue,
//        "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/assets/models/terrain/terrain.obj",
//        float3{4.f, -5.f, 0.f},
//        float3{0.f, 0.f, 0.f},
//        float3{.0001f, .0001f, .0001f}
//    });

    


#pragma mark - Event CallBack
    
    window.setKeyCallback([&](int key, bool isPressed){
        if (key >= 0 && key < 256) {
            keys[key] =     isPressed;  // 直接设置状态，不再切换
        }
        
        // ESC 退出（只在按下时触发）
        if (key == 53 && isPressed) {
//            [self terminate:nil];
            exit(78);
        }
        
        if (key == 48 && isPressed) {  // 48 = TAB
           mouseCaptured = !mouseCaptured;
           window.setMouseCaptured(mouseCaptured);
           std::cout << "Mouse captured: " << (mouseCaptured ? "ON" : "OFF") << std::endl;
       }
    });

    // 鼠标回调 - 统一使用 delta 模式
    window.setMouseMoveCallback([&](int deltaX, int deltaY){
        // 无论什么模式，都是 delta 值
        camera.onMouseMove(static_cast<float>(deltaX),
                          -static_cast<float>(deltaY));
    });
    
#pragma mark - Set the Application Stage
    
    
    // Uniform buffer（每帧更新）
    struct Uniforms {
        simd::float4x4 modelViewProjectionMatrix;
        simd::float4x4 modelMat;
        simd::float4x4 viewMat;
        simd::float4x4 ProjectionMat;
        simd::float4x4 normalMatrix;  // 添加法线矩阵
        float4x4 lightSpaceMatrix;
        simd::float3   lightDirection;
        simd::float3   lightColor = {10.f, 0.f, 0.f};
        float          lightIntensity = 50.f;
        simd::float3   cameraPosition;
    };
    
    struct CameraData {
        simd::float4x4 viewMatrix;
        simd::float4x4 projectionMatrix;
        
    };
    // Skybox vertices (8 points, float3 position)
    simd::float3 skyboxVertices[] = {
        {-1.0f, -1.0f, -1.0f},
        { 1.0f, -1.0f, -1.0f},
        { 1.0f,  1.0f, -1.0f},
        {-1.0f,  1.0f, -1.0f},
        {-1.0f, -1.0f,  1.0f},
        { 1.0f, -1.0f,  1.0f},
        { 1.0f,  1.0f,  1.0f},
        {-1.0f,  1.0f,  1.0f}
    };

    // Skybox indices (36 for triangle list, covering all 6 faces)
    uint32_t skyboxIndices[] = {
        0, 1, 2, 2, 3, 0,  // Front
        4, 5, 6, 6, 7, 4,  // Back
        0, 3, 7, 7, 4, 0,  // Left
        1, 2, 6, 6, 5, 1,  // Right
        0, 4, 5, 5, 1, 0,  // Bottom
        3, 7, 6, 6, 2, 3   // Top
    };
    
    MTL::RenderPipelineState *gbufferPipelineState;

    /// Forward Scene pipleines
    MTL::RenderPipelineState *shadowPSO;
    MTL::RenderPipelineState *renderPSO;
    MTL::RenderPipelineState *skyboxPipelineState;
    MTL::ComputePipelineState* irrPSO;
    MTL::ComputePipelineState* prefilterPSO;
    MTL::ComputePipelineState* lutPSO;
    MTL::DepthStencilState* depthStencilState;
    MTL::DepthStencilState* depthStateLessEqualNoWrite;
    /// PostProcessing pipelines
    MTL::RenderPipelineState *bloomThresholdPipelineState;
    MTL::ComputePipelineState* blurXPSO;
    MTL::ComputePipelineState* blurYPSO;
    MTL::RenderPipelineState *postMergePipelineState;
    
    MTL::Texture *msaaDepthTexture;
    MTL::Texture *depthTexture;
    MTL::Texture *skyboxTexture;
    MTL::Texture* irradianceMap;
    MTL::Texture* prefilterMap;
    MTL::Texture* brdfLUT;
    MTL::Texture *shadowMap;
    MTL::Texture *msaaRawColorTexure;
    MTL::Texture *rawColorTexture;
    MTL::Texture *bloomThresholdMap;
    MTL::Texture *blurTempMap;
    MTL::Texture *bloomBlurMap;
    MTL::Texture *renderTarget;

    MTL::Buffer* skyboxVertexBuffer = metalDevice->newBuffer(skyboxVertices, sizeof(skyboxVertices), MTL::ResourceStorageModeShared);
    MTL::Buffer* skyboxIndexBuffer = metalDevice->newBuffer(skyboxIndices, sizeof(skyboxIndices), MTL::ResourceStorageModeShared);
    MTL::Buffer* cameraBuffer = metalDevice->newBuffer(sizeof(CameraData), MTL::ResourceStorageModeShared);
    
    MTL::RenderPassDescriptor *shadowPassDescriptor;
    MTL::RenderPassDescriptor *forwardPassDescriptor;
    MTL::RenderPassDescriptor *bloomThresholdPassDescriptor;
    MTL::RenderPassDescriptor *bloomBlurPassDescriptor;
    MTL::RenderPassDescriptor *postMergePassDescriptor;

    CA::MetalDrawable* drawable;
    { // forward screen Render
        MTL::Function *vShader;
        MTL::Function *fShader;
        MTL::RenderPipelineDescriptor *pDesc = MTL::RenderPipelineDescriptor::alloc()->init();
        NS::Error *error = nullptr;
        
        { // shadow Pipeline
            vShader = library->newFunction(NS::String::string("shadowVertex",NS::ASCIIStringEncoding));
            pDesc->setLabel(NS::String::string("shadow Pipeline", NS::ASCIIStringEncoding));
            pDesc->setVertexFunction(vShader);
            pDesc->setFragmentFunction(nullptr);
            pDesc->setVertexDescriptor(Model::createVertexDescriptor());
            pDesc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatInvalid);
            pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
            shadowPSO = metalDevice->newRenderPipelineState(pDesc, &error);
            assert(shadowPSO && !error);
        }
        
        { // Main RenderPipeline
            vShader = library->newFunction(NS::String::string("vertexShader", NS::ASCIIStringEncoding));
            fShader = library->newFunction(NS::String::string("fragmentShader", NS::ASCIIStringEncoding)); assert(vShader && fShader);
            
            
            pDesc->setLabel(NS::String::string("main Render Pipeline", NS::ASCIIStringEncoding));
            pDesc->setRasterSampleCount(sampleCount);
            pDesc->setVertexFunction(vShader);
            pDesc->setFragmentFunction(fShader);
            pDesc->setVertexDescriptor(Model::createVertexDescriptor()); assert(pDesc);
            pDesc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatRGBA16Float);
            pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
            renderPSO = metalDevice->newRenderPipelineState(pDesc, &error);
            assert(renderPSO && !error);

        }
        
        { // skybox pipeline
            vShader = library->newFunction(NS::String::string("skyboxVertex", NS::ASCIIStringEncoding));
            fShader = library->newFunction(NS::String::string("skyboxFragment", NS::ASCIIStringEncoding));
            assert(vShader && fShader);
            
            auto skyboxVertexDesc = MTL::VertexDescriptor::alloc()->init();
            skyboxVertexDesc->attributes()->object(0)->setFormat(MTL::VertexFormatFloat3);
            skyboxVertexDesc->attributes()->object(0)->setOffset(0);
            skyboxVertexDesc->attributes()->object(0)->setBufferIndex(0);
            skyboxVertexDesc->layouts()->object(0)->setStride(sizeof(simd::float3));
            
            pDesc->setLabel(NS::String::string("skybox Pipeline", NS::ASCIIStringEncoding));
            pDesc->setVertexFunction(vShader);
            pDesc->setFragmentFunction(fShader);
            pDesc->setVertexDescriptor(skyboxVertexDesc); assert(pDesc);
            skyboxPipelineState = metalDevice->newRenderPipelineState(pDesc, &error); assert(skyboxPipelineState && !error);
            
            auto computeIrrdiance = library->newFunction(NS::String::string("computeIrradiance",NS::ASCIIStringEncoding));
            error = nullptr;
            irrPSO = metalDevice->newComputePipelineState(computeIrrdiance, &error);
            
            auto computePrefilter = library->newFunction(NS::String::string("computePrefilter", NS::ASCIIStringEncoding));
            error = nullptr;
            prefilterPSO = metalDevice->newComputePipelineState(computePrefilter, &error);
            
            auto computeBRDFLut = library->newFunction(NS::String::string("computeBRDFLut", NS::ASCIIStringEncoding));
            error = nullptr;
            lutPSO = metalDevice->newComputePipelineState(computeBRDFLut, &error);
        }
        
        { // post processing pipeline
            /// bloom threshold
            vShader = library->newFunction(NS::String::string("vertexPassthrough", NS::ASCIIStringEncoding));
            fShader = library->newFunction(NS::String::string("fragmentBloomThreshold", NS::ASCIIStringEncoding));
            pDesc->setLabel(NS::String::string("bloom threshold Pipeline", NS::ASCIIStringEncoding));
            pDesc->setRasterSampleCount(1);
            pDesc->setVertexFunction(vShader);
            pDesc->setFragmentFunction(fShader);
            pDesc->setVertexDescriptor(nullptr);
            pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatInvalid);
            bloomThresholdPipelineState = metalDevice->newRenderPipelineState(pDesc, &error);
        
            /// bloom blur
            auto blurXFn = library->newFunction(NS::String::string("gaussian_blur_x", NS::ASCIIStringEncoding));
            auto blurYFn = library->newFunction(NS::String::string("gaussian_blur_y", NS::ASCIIStringEncoding));
            error = nullptr;
            blurXPSO = metalDevice->newComputePipelineState(blurXFn, &error);
            blurYPSO = metalDevice->newComputePipelineState(blurYFn, &error);
            blurXFn->release();
            blurYFn->release();
            
            /// post merge
            fShader = library->newFunction(NS::String::string("fragmentPostprocessMerge", NS::ASCIIStringEncoding));
            pDesc->setLabel(NS::String::string("post merge Pipeline", NS::ASCIIStringEncoding));
            pDesc->setFragmentFunction(fShader);
            pDesc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);
            postMergePipelineState = metalDevice->newRenderPipelineState(pDesc, &error);
        }
        vShader->release(); fShader->release();
        pDesc->release();
    }
    
    { // depthStencil State
        // DepthStenclState
        MTL::DepthStencilDescriptor* depthStencilDesc = MTL::DepthStencilDescriptor::alloc()->init();
        depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLess);
        depthStencilDesc->setDepthWriteEnabled(true);
        depthStencilState = metalDevice->newDepthStencilState(depthStencilDesc);
        
        depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
        depthStencilDesc->setDepthWriteEnabled(false);
        depthStateLessEqualNoWrite = metalDevice->newDepthStencilState(depthStencilDesc);
        depthStencilDesc->release();
    }
    
    { // Texture
        MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
        desc->setWidth(1280);
        desc->setHeight(720);
        
        // type
        // samplecount
        // setArrayLength
        // pixelFormat
        // set usage
        // newTexture
        
        
        // msaadepthTexture
        desc->setTextureType(MTL::TextureType2DMultisample);
        desc->setSampleCount(sampleCount);
        desc->setPixelFormat(MTL::PixelFormatDepth32Float);
        
        desc->setUsage(MTL::TextureUsageRenderTarget); // rendertarget才能被pass直接写入的
        msaaDepthTexture = metalDevice->newTexture(desc);
        
        // depthTexture
        desc->setTextureType(MTL::TextureType2D);
        desc->setSampleCount(1);
        depthTexture =metalDevice->newTexture(desc);
        
        // msaaRenderTarget
        desc->setTextureType(MTL::TextureType2DMultisample);
        desc->setSampleCount(sampleCount);
        desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
        msaaRawColorTexure = metalDevice->newTexture(desc);
        
        // rawColorTexture HDR 相关的离屏纹理 (rawColor 和 bloom)
        desc->setTextureType(MTL::TextureType2D);
        desc->setSampleCount(1);
        desc->setArrayLength(1);
        desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
        desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
        rawColorTexture = metalDevice->newTexture(desc);
        // bloomThresholdMap
        bloomThresholdMap = metalDevice->newTexture(desc);
        // bloomBlurMap
        blurTempMap = metalDevice->newTexture(desc);
        bloomBlurMap = metalDevice->newTexture(desc);
        
        // shadowMap
        desc->setTextureType(MTL::TextureType2D);
//        desc->setArrayLength(1);
        desc->setWidth(2048);  // 阴影分辨率建议开大一点，比如 2048 或 4096
        desc->setHeight(2048);
        desc->setPixelFormat(MTL::PixelFormatDepth32Float);
        desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
        shadowMap = metalDevice->newTexture(desc);
        
        
        // Load HDR equirectangular texture
        skyboxTexture = TextureLoader::load(metalDevice, commandQueue, "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/Realtime Renderer Based on Metal-CPP/kloppenheim_06_4k.hdr", TextureLoader::ColorSpace::SRGB, false);
        
        // Irradiance Map
        desc->setTextureType(MTL::TextureTypeCube);
        desc->setWidth(32);
        desc->setHeight(32);
        desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
        desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
        irradianceMap = metalDevice->newTexture(desc);
        
        // Prefilter Map
        desc->setTextureType(MTL::TextureTypeCube);
        desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
        desc->setWidth(512);
        desc->setHeight(512);
        desc->setMipmapLevelCount(5); // Mipmap 层数 (512, 256, 128, 64, 32)
        desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
        prefilterMap = metalDevice->newTexture(desc);
        
        // BRDF lut
        desc->setTextureType(MTL::TextureType2D);
        desc->setPixelFormat(MTL::PixelFormatRG16Float); // 只需要 R 和 G 两个通道
        desc->setWidth(512);
        desc->setHeight(512);
        desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
        brdfLUT = metalDevice->newTexture(desc);
        
        desc->release();
    }
    
    { // shadow renderPass
        shadowPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassDepthAttachmentDescriptor *dd = shadowPassDescriptor->depthAttachment();
        dd->setTexture(shadowMap);
        dd->setLoadAction(MTL::LoadActionClear);
        dd->setClearDepth(1.0);
        dd->setStoreAction(MTL::StoreActionStore);
    }
    
    { // forward screen renderPass
        forwardPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassColorAttachmentDescriptor* cd = forwardPassDescriptor->colorAttachments()->object(0);
        cd->setLoadAction(MTL::LoadActionClear);
        cd->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
        cd->setStoreAction(MTL::StoreActionMultisampleResolve);
        cd->setTexture(msaaRawColorTexure);
        cd->setResolveTexture(rawColorTexture);
        // 加 depth
        MTL::RenderPassDepthAttachmentDescriptor* depthDesc = forwardPassDescriptor->depthAttachment();
        depthDesc->setTexture(msaaDepthTexture);  // 假设你的 MetalViewWrapper 暴露了 depth texture（很多实现有）
        
//        depthDesc->setResolveTexture(depthTexture); 深度不用resolve
        depthDesc->setLoadAction(MTL::LoadActionClear);
        depthDesc->setClearDepth(1.0);
        depthDesc->setStoreAction(MTL::StoreActionDontCare);
    }
    
    
    { // post processing renderPass
        /// bloom threshold
        bloomThresholdPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        MTL::RenderPassColorAttachmentDescriptor *cd = bloomThresholdPassDescriptor->colorAttachments()->object(0);
        cd->setLoadAction(MTL::LoadActionDontCare);
        cd->setStoreAction(MTL::StoreActionStore);
        cd->setTexture(bloomThresholdMap);
        
        // blur the bloom  : compute no need  passDesc
        
        
        /// merge the post processing results with the scene rendering
        postMergePassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
        cd = postMergePassDescriptor->colorAttachments()->object(0);
        cd->setLoadAction(MTL::LoadActionClear);
        cd->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
        cd->setStoreAction(MTL::StoreActionStore);
    }
    
    { // IBL preCompute
        MTL::CommandBuffer* precomputeCmdBuffer = commandQueue->commandBuffer();
        precomputeCmdBuffer->setLabel(NS::String::string("IBL Pre-computation", NS::ASCIIStringEncoding));
        MTL::ComputeCommandEncoder* computeEncoder = precomputeCmdBuffer->computeCommandEncoder();
        
        // 1. 生成 Irradiance Map (32x32x6)
        computeEncoder->setComputePipelineState(irrPSO);
        computeEncoder->setTexture(skyboxTexture, 0);
        computeEncoder->setTexture(irradianceMap, 1);
        MTL::Size gridSizeIrr = MTL::Size(32, 32, 6);
        MTL::Size threadGroupSizeIrr = MTL::Size(8, 8, 1);
        computeEncoder->dispatchThreads(gridSizeIrr, threadGroupSizeIrr);
        
        // 2. 生成 Prefilter Map (5个 Mip 层级)
        computeEncoder->setComputePipelineState(prefilterPSO);
        computeEncoder->setTexture(skyboxTexture, 0);
        uint32_t maxMipLevels = 5;
        for (uint32_t mip = 0; mip < maxMipLevels; ++mip) {
            float roughness = (float)mip / (float)(maxMipLevels - 1);
            computeEncoder->setBytes(&roughness, sizeof(float), 0);
            
            // 创建指定 Mip 级别的 TextureView 以供 Compute Shader 写入
            MTL::Texture* mipView = prefilterMap->newTextureView(
                MTL::PixelFormatRGBA16Float,
                MTL::TextureTypeCube,
                NS::Range(mip, 1),
                NS::Range(0, 6)
            );
            computeEncoder->setTexture(mipView, 1);
            
            uint32_t mipWidth = 512 * std::pow(0.5, mip);
            MTL::Size gridSizePrefilter = MTL::Size(mipWidth, mipWidth, 6);
            MTL::Size threadGroupSizePrefilter = MTL::Size(std::min(mipWidth, 16u), std::min(mipWidth, 16u), 1);
            computeEncoder->dispatchThreads(gridSizePrefilter, threadGroupSizePrefilter);
            
            mipView->release();
        }
        
        // 3. 生成 BRDF LUT (512x512)
        computeEncoder->setComputePipelineState(lutPSO);
        computeEncoder->setTexture(brdfLUT, 0);
        MTL::Size gridSizeLut = MTL::Size(512, 512, 1);
        MTL::Size threadGroupSizeLut = MTL::Size(16, 16, 1);
        computeEncoder->dispatchThreads(gridSizeLut, threadGroupSizeLut);
        
        computeEncoder->endEncoding();
        precomputeCmdBuffer->commit();
        precomputeCmdBuffer->waitUntilCompleted(); // 必须阻塞 CPU，确保纹理生成完毕再开始渲染
        std::cout << "IBL Pre-computation Completed." << std::endl;
    }
    
    
#pragma mark - Send/Changes to MetalGPU
    
    window.setRenderCallback([&]() {
        auto currentTime = std::chrono::high_resolution_clock::now();
        float deltaTime = std::chrono::duration<float>(currentTime - lastFrameTime).count();
        lastFrameTime = currentTime;
        
        { // update State
            drawable = metalLayer->nextDrawable();
            renderTarget = drawable->texture();
//            forwardPassDescriptor->colorAttachments()->object(0)->setTexture(rawColorTexture);
//            bloomThresholdPassDescriptor->colorAttachments()->object(0)->setTexture(bloomThresholdMap);
            postMergePassDescriptor->colorAttachments()->object(0)->setTexture(renderTarget);
            camera.update(keys, deltaTime);
        }
            
        MTL::CommandBuffer *commandBuffer = commandQueue->commandBuffer(); assert(commandBuffer);
        commandBuffer->setLabel(NS::String::string("Render Commands", NS::ASCIIStringEncoding));
        
        std::vector<MTL::Buffer*> uniformBuffers;
        
        simd::float3 globalLightDir = simd::normalize(simd::float3{75.f, 50.0f, 60.f}); // 统一你的光源方向
        simd::float3 lightPos = globalLightDir * 30.0f; // 光源位置
        simd::float3 target = {0.0f, 0.0f, 0.0f}; // 看向场景中心
        simd::float3 up = {0.0f, 1.0f, 0.0f};
        simd::float4x4 lightView = matrix_look_at_right_hand(lightPos, target, up);
        // ⚠️ 注意：根据你的 moai 模型放大了10倍，正交矩阵的包围盒建议调大一点，否则模型可能超出阴影贴图范围
        simd::float4x4 lightProj = matrix_ortho_right_hand(-25.0f, 25.0f, -25.0f, 25.0f, 0.1f, 100.0f);
        simd::float4x4 globalLightSpaceMatrix = lightProj * lightView;
        
        MTL::RenderCommandEncoder* renderCommandEncoder = commandBuffer->renderCommandEncoder(shadowPassDescriptor);
        { // shadow pass Rneder
            renderCommandEncoder->setRenderPipelineState(shadowPSO);
            renderCommandEncoder->setDepthStencilState(depthStencilState);
            
            
            for(const auto &instance : scene.getInstances()) {
                const Model& model = scene.getModel(instance.modelIndex);
                renderCommandEncoder->setVertexBuffer(model.getVertexBuffer(), 0, 0);
                
                for(const auto &sub : model.getSubmeshes()) {
                    MTL::Buffer *thisUniform  = metalDevice->newBuffer(sizeof(Uniforms), MTL::ResourceStorageModeShared);
                    uniformBuffers.push_back(thisUniform);
                    Uniforms* uniforms = (Uniforms*)thisUniform->contents();
                    uniforms->modelMat = instance.modelMatrix * sub.nodeTransform;
                    uniforms->lightSpaceMatrix = globalLightSpaceMatrix;
                    
                    renderCommandEncoder->setVertexBuffer(thisUniform, 0, 1);
                    
                    // 用 indexed draw 渲染整个模型（不再是 3 个顶点）
                    // 需要 Model 类提供这两个 getter（下面会说怎么加）
                    renderCommandEncoder->drawIndexedPrimitives(
                            MTL::PrimitiveTypeTriangle,
                            sub.indexCount,
                            MTL::IndexTypeUInt32,
                            model.getIndexBuffer(),
                            sub.indexOffset * sizeof(uint32_t)
                        );
                }
            }
            renderCommandEncoder->endEncoding();
        }
        
        { // forward pass Render
            renderCommandEncoder = commandBuffer->renderCommandEncoder(forwardPassDescriptor);
            renderCommandEncoder->setRenderPipelineState(renderPSO);
            renderCommandEncoder->setDepthStencilState(depthStencilState);
            
            for(const auto &instance : scene.getInstances()) {
                const Model& model = scene.getModel(instance.modelIndex);
                renderCommandEncoder->setVertexBuffer(model.getVertexBuffer(), 0, 0);
                
                for(const auto &sub : model.getSubmeshes()) {
                    MTL::Buffer *thisUniform  = metalDevice->newBuffer(sizeof(Uniforms), MTL::ResourceStorageModeShared);
                    uniformBuffers.push_back(thisUniform);
                    Uniforms* uniforms = (Uniforms*)thisUniform->contents();
                    uniforms->modelViewProjectionMatrix = camera.getProjectionMatrix() * camera.getViewMatrix() * instance.modelMatrix * sub.nodeTransform;
                    uniforms->modelMat = instance.modelMatrix * sub.nodeTransform;
                    uniforms->viewMat  = camera.getViewMatrix();
                    uniforms->normalMatrix = inverse(transpose(instance.modelMatrix * sub.nodeTransform));
                    uniforms->ProjectionMat = camera.getProjectionMatrix();
                    uniforms->lightSpaceMatrix = globalLightSpaceMatrix;
                    uniforms->lightDirection = globalLightDir;
                    uniforms->lightColor = simd::float3{.8f, .608f, 0.300f};
                    uniforms->lightIntensity = 30.f;
                    uniforms->cameraPosition = camera.pos;
                    
                    

                    
                    renderCommandEncoder->setVertexBuffer(thisUniform, 0, 1);
                    renderCommandEncoder->setFragmentBuffer(thisUniform, 0, 1);
                    
                    auto& material = model.getMaterial(sub.materialIndex);
                    renderCommandEncoder->setFragmentTexture(material.albedoTexture, 0);
                    renderCommandEncoder->setFragmentTexture(material.normalTexture, 1);
                    renderCommandEncoder->setFragmentTexture(material.metallicTexture, 2);
                    renderCommandEncoder->setFragmentTexture(material.roughnessTexture, 3);
                    renderCommandEncoder->setFragmentTexture(material.aoTexture, 4);
                    renderCommandEncoder->setFragmentTexture(material.alphaTexture, 5);
                    renderCommandEncoder->setFragmentTexture(material.emissiveTexture, 6);
                    renderCommandEncoder->setFragmentTexture(skyboxTexture, 7);
                    renderCommandEncoder->setFragmentBytes(&exposure, sizeof(float), 0);
                    renderCommandEncoder->setFragmentTexture(irradianceMap, 8);
                    renderCommandEncoder->setFragmentTexture(prefilterMap, 9);
                    renderCommandEncoder->setFragmentTexture(brdfLUT, 10);
                    renderCommandEncoder->setFragmentTexture(shadowMap, 11);
                    // 用 indexed draw 渲染整个模型（不再是 3 个顶点）
                    // 需要 Model 类提供这两个 getter（下面会说怎么加）
                    renderCommandEncoder->drawIndexedPrimitives(
                            MTL::PrimitiveTypeTriangle,
                            sub.indexCount,
                            MTL::IndexTypeUInt32,
                            model.getIndexBuffer(),
                            sub.indexOffset * sizeof(uint32_t)
                        );
                }
            }
        }
        
        { // skybox Render
            CameraData cameraData {
                camera.getViewMatrixWithNoTranslation(),
                camera.getProjectionMatrix()
            };
            memcpy(cameraBuffer->contents(), &cameraData, sizeof(CameraData));
            
            renderCommandEncoder->setRenderPipelineState(skyboxPipelineState);
            renderCommandEncoder->setDepthStencilState(depthStateLessEqualNoWrite);
//            renderCommandEncoder->setCullMode(MTL::CullModeFront);
            
            renderCommandEncoder->setVertexBuffer(skyboxVertexBuffer, 0, 0);
            renderCommandEncoder->setVertexBuffer(cameraBuffer, 0, 1);
            // Bind texture (index 0 in fragment)
            renderCommandEncoder->setFragmentTexture(skyboxTexture, 0);

            // Draw indexed
            renderCommandEncoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle,
                                                        36,  // Index count (36 for full cube)
                                                        MTL::IndexTypeUInt32,
                                                        skyboxIndexBuffer,
                                                        0);
        }
    
        renderCommandEncoder->endEncoding();

        //Post processing
        {   /// bloom threshold
            renderCommandEncoder = commandBuffer->renderCommandEncoder(bloomThresholdPassDescriptor);

            renderCommandEncoder->setRenderPipelineState(bloomThresholdPipelineState);
            renderCommandEncoder->setFragmentTexture(rawColorTexture, 0);
            
            float threshold = 2.0f;
            renderCommandEncoder->setFragmentBytes(&threshold, sizeof(float), 0);
            renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
            renderCommandEncoder->endEncoding();
            
            /// bloom blur
            MTL::ComputeCommandEncoder* computeEncoder = commandBuffer->computeCommandEncoder();
            MTL::Size threadgroupSize = MTL::Size(16, 16, 1);
            MTL::Size gridSize = MTL::Size(bloomThresholdMap->width(), bloomThresholdMap->height(), 1);
            computeEncoder->setComputePipelineState(blurXPSO);
            computeEncoder->setTexture(bloomThresholdMap, 0);
            computeEncoder->setTexture(blurTempMap, 1);
            computeEncoder->dispatchThreads(gridSize, threadgroupSize);
            
            computeEncoder->setComputePipelineState(blurYPSO);
            computeEncoder->setTexture(blurTempMap, 0);   // 上一步的输出变成了现在的输入
            computeEncoder->setTexture(bloomBlurMap, 1);      // 最终结果输出
            computeEncoder->dispatchThreads(gridSize, threadgroupSize);
            computeEncoder->endEncoding();
            
            /// post merge
            renderCommandEncoder = commandBuffer->renderCommandEncoder(postMergePassDescriptor);
            renderCommandEncoder->setRenderPipelineState(postMergePipelineState);
            renderCommandEncoder->setFragmentBytes(&exposure, sizeof(float), 0);
            renderCommandEncoder->setFragmentTexture(rawColorTexture, 0);
            renderCommandEncoder->setFragmentTexture(bloomBlurMap, 1);
            renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(6));
            renderCommandEncoder->endEncoding();
        }
        
        
        
        commandBuffer->presentDrawable(drawable);
        commandBuffer->commit();
        for(auto buf : uniformBuffers) buf->release();
        
//        commandBuffer->waitUntilCompleted();
    });
    window.run();
    
//    uniformBuffer->release();
    renderPSO->release();
    commandQueue->release();
    forwardPassDescriptor->release();
    metalDevice->release();
    
    skyboxVertexBuffer->release();
    skyboxIndexBuffer->release();
    
    return EXIT_SUCCESS;
}

