//
//  renderer.mm
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION

#include "renderer.hpp"
#include "model/texture.hpp"
#include <iostream>

// Uniform 结构体保持不变
struct Uniforms {
  simd::float4x4 modelViewProjectionMatrix;
  simd::float4x4 modelMat;
  simd::float4x4 viewMat;
  simd::float4x4 ProjectionMat;
  simd::float4x4 normalMatrix;
  simd::float4x4 lightSpaceMatrix;
  simd::float3 lightDirection;
  simd::float3 lightColor = {10.f, 0.f, 0.f};
  float lightIntensity = 50.f;
  simd::float3 cameraPosition;
};

Renderer::Renderer(MTL::Device *device, int width, int height,
                   const std::string &resourceBasePath)
    :_currentWidth(width), _currentHeight(height), _device(device), sampleCount(4) {
        
  _commandQueue = _device->newCommandQueue();
  _lastFrameTime = std::chrono::high_resolution_clock::now();
  _activeCamera = &_normalCamera;
  _physicalParams.isPhysicalMode = 0;
  _physicalParams.manualExposure = 0.1f;

  _scene.addModelInstance(Model{
      _device, _commandQueue,
      "/Users/menji/coding/xcode/Realtime Renderer Based on "
      "Metal-CPP/assets/models/Television_01_4k.gltf/Television_01_4k.gltf",
      float3{-2.f, 1.f, 0.f}, float3{0.f, 0.f, 0.f}, float3{3.f, 3.f, 3.f}});

  _scene.addModelInstance(
      Model{_device, _commandQueue,
            "/Users/menji/coding/xcode/Realtime Renderer Based on "
            "Metal-CPP/assets/models/moai50k/moai50k.obj",
            simd::float3{2.f, 1.f, 0.f}, simd::float3{0.f, 0.f, 0.f},
            simd::float3{10.f, 10.f, 10.f}});

  _scene.addModelInstance(
      Model{_device, _commandQueue,
            "/Users/menji/coding/xcode/Realtime Renderer Based on "
            "Metal-CPP/assets/models/tree01/tree004.gltf",
            simd::float3{10.f, 1.f, 6.f}, simd::float3{0.f, 0.f, 0.f},
            simd::float3{4.f, 4.f, 4.f}});

  _scene.addModelInstance(
      Model{_device, _commandQueue,
            "/Users/menji/coding/xcode/Realtime Renderer Based on "
            "Metal-CPP/assets/models/chess_set_4k/chess_set_4k.fbx",
            simd::float3{0.f, 0.f, 0.f}, simd::float3{0.f, 0.f, 0.f},
            simd::float3{.5f, .5f, .5f}});

//      _scene.addModelInstance(Model{
//         _device,
//         _commandQueue,"/Users/menji/Downloads/house/flat-archiviz.gltf",
//         float3{-2.f, 8.f, 0.f},
//         float3{0.f, 0.f, 0.f},
//         float3{1.f, 1.f, 1.f}
//     });

  simd::float3 skyboxVertices[] = {{-1.0f, -1.0f, -1.0f}, {1.0f, -1.0f, -1.0f},
                                   {1.0f, 1.0f, -1.0f},   {-1.0f, 1.0f, -1.0f},
                                   {-1.0f, -1.0f, 1.0f},  {1.0f, -1.0f, 1.0f},
                                   {1.0f, 1.0f, 1.0f},    {-1.0f, 1.0f, 1.0f}};
  uint32_t skyboxIndices[] = {0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4,
                              0, 3, 7, 7, 4, 0, 1, 2, 6, 6, 5, 1,
                              0, 4, 5, 5, 1, 0, 3, 7, 6, 6, 2, 3};

  _skyboxVertexBuffer = _device->newBuffer(
      skyboxVertices, sizeof(skyboxVertices), MTL::ResourceStorageModeShared);
  _skyboxIndexBuffer = _device->newBuffer(skyboxIndices, sizeof(skyboxIndices),
                                          MTL::ResourceStorageModeShared);
  // CameraData 是两个 float4x4 矩阵，大小为 128 字节
  _cameraBuffer = _device->newBuffer(sizeof(simd::float4x4) * 2,
                                     MTL::ResourceStorageModeShared);

  initPipelines();
  initTextures(width, height);
  initPassDescriptors();
  precomputeIBL();
}

Renderer::~Renderer() {
  _commandQueue->release();
  if (_renderPSO)
    _renderPSO->release();
  if (_shadowPSO)
    _shadowPSO->release();
  // TODO: 记得释放其他所有的 Texture 和 PipelineState
}

void Renderer::update(const bool *keys) {
  auto currentTime = std::chrono::high_resolution_clock::now();
  float deltaTime =
      std::chrono::duration<float>(currentTime - _lastFrameTime).count();
  _lastFrameTime = currentTime;

  _activeCamera->update(keys, deltaTime);
}

void Renderer::onMouseMove(int deltaX, int deltaY) {
  _activeCamera->onMouseMove(static_cast<float>(deltaX), -static_cast<float>(deltaY));
}

void Renderer::setExposure(float exp) { _physicalParams.manualExposure = exp; }

void Renderer::setPhysicalCameraMode(bool isPhysical) {
    _physicalParams.isPhysicalMode = isPhysical ? 1 : 0;
    _activeCamera = isPhysical ? (Camera*)&_physicalCamera : &_normalCamera;
}

void Renderer::Renderer::setPhysicalCameraParams(float ap, float shutter, float iso, float ev) {
    _physicalParams.aperture = ap;
    _physicalParams.shutterSpeed = shutter;
    _physicalParams.iso = iso;
    _physicalParams.evComp = ev;
}

void Renderer::render(CA::MetalDrawable *drawable) {
  if (!drawable)
    return;

  // 1. 准备 Target
  MTL::Texture *renderTarget = drawable->texture(); // 实际drawable resulution
  // 渲染线程自己检查分辨率是否发生变化
  int targetWidth = (int)renderTarget->width();
  int targetHeight = (int)renderTarget->height();
  if (_currentWidth != targetWidth || _currentHeight != targetHeight) {
      // 只有尺寸真正改变时，才在当前线程安全地重建内部缓冲贴图
      initTextures(targetWidth, targetHeight);
      initPassDescriptors();
      
      float newAspect = (float)targetWidth / (float)targetHeight;
      _activeCamera->setAspect(newAspect);
      
      _currentWidth = targetWidth;
      _currentHeight = targetHeight;
  }
  _postMergePassDescriptor->colorAttachments()->object(0)->setTexture(
      renderTarget);

  // 2. 录制 CommandBuffer
  MTL::CommandBuffer *commandBuffer = _commandQueue->commandBuffer();
  commandBuffer->setLabel(
      NS::String::string("Render Commands", NS::ASCIIStringEncoding));

  simd::float3 globalLightDir =
      simd::normalize(simd::float3{75.f, 50.0f, 60.f});
  simd::float3 lightPos = globalLightDir * 30.0f;
  simd::float3 target = {0.0f, 0.0f, 0.0f};
  simd::float3 up = {0.0f, 1.0f, 0.0f};
  simd::float4x4 lightView = matrix_look_at_right_hand(lightPos, target, up);
  simd::float4x4 lightProj =
      matrix_ortho_right_hand(-25.0f, 25.0f, -25.0f, 25.0f, 0.1f, 100.0f);
  simd::float4x4 globalLightSpaceMatrix = lightProj * lightView;

  // 用来在帧末统一释放的临时 buffers
  std::vector<MTL::Buffer *> uniformBuffers;

  // shadow pass Rneder
  MTL::RenderCommandEncoder *shadowEncoder =
      commandBuffer->renderCommandEncoder(_shadowPassDescriptor);
  shadowEncoder->setRenderPipelineState(_shadowPSO);
  shadowEncoder->setDepthStencilState(_depthStencilState);

  for (const auto &instance : _scene.getInstances()) {
    const Model &model = _scene.getModel(instance.modelIndex);
    shadowEncoder->setVertexBuffer(model.getVertexBuffer(), 0, 0);

    for (const auto &sub : model.getSubmeshes()) {
      MTL::Buffer *thisUniform =
          _device->newBuffer(sizeof(Uniforms), MTL::ResourceStorageModeShared);
      uniformBuffers.push_back(thisUniform);
      Uniforms *uniforms = (Uniforms *)thisUniform->contents();
      uniforms->modelMat = instance.modelMatrix * sub.nodeTransform;
      uniforms->lightSpaceMatrix = globalLightSpaceMatrix;

      shadowEncoder->setVertexBuffer(thisUniform, 0, 1);
      shadowEncoder->drawIndexedPrimitives(
          MTL::PrimitiveTypeTriangle, sub.indexCount, MTL::IndexTypeUInt32,
          model.getIndexBuffer(), sub.indexOffset * sizeof(uint32_t));
    }
  }
  shadowEncoder->endEncoding();

  // light
  std::vector<LightData> frameLights;
  for (const auto &instance : _scene.getInstances()) {
    const Model &model = _scene.getModel(instance.modelIndex);
    for (auto light : model.getLights()) {
      if (light.position.w < 0.5f) {
        continue;
      }
      // 光源也要乘以 ModelInstance 的矩阵
      simd::float4 worldPos = instance.modelMatrix *
                              simd::float4{light.position.x, light.position.y,
                                           light.position.z, 1.0f};
      light.position.x = worldPos.x;
      light.position.y = worldPos.y;
      light.position.z = worldPos.z;

      simd::float4 worldDir = instance.modelMatrix *
                              simd::float4{light.direction.x, light.direction.y,
                                           light.direction.z, 0.0f};
      light.direction.x = worldDir.x;
      light.direction.y = worldDir.y;
      light.direction.z = worldDir.z;

      frameLights.push_back(light);
    }
  }

  float t = std::min(std::max((_physicalParams.manualExposure - 0.1f) / (1.0f - 0.1f), 0.0f), 1.0f);

  simd::float3 duskColor = {0.8f, 0.608f, 0.300f}; // 0.1 时的暖黄光
  simd::float3 dayColor = {1.0f, 0.98f, 0.95f};    // 1.0 时的冷白光

  // 线性插值 (Lerp)： color = dusk + (day - dusk) * t
  simd::float3 dynamicLightColor = duskColor + (dayColor - duskColor) * t;

  LightData hardcodedSun;
  hardcodedSun.position =
      simd::float4{0.0f, 0.0f, 0.0f, 0.0f}; // w=0.0 表示平行光
  // 注意这里直接用在函数开头定义的 globalLightDir
  hardcodedSun.direction =
      simd::float4{globalLightDir.x, globalLightDir.y, globalLightDir.z, 0.0f};
  // 颜色和强度 (3.0f 强度根据画面的亮暗自行调整)
  hardcodedSun.color = simd::float4{dynamicLightColor.x, dynamicLightColor.y,
                                    dynamicLightColor.z, 50.0f};
  frameLights.push_back(hardcodedSun);

  int lightCount = static_cast<int>(frameLights.size());
  MTL::Buffer *lightBuffer = nullptr;

  if (lightCount > 0) {
    lightBuffer =
        _device->newBuffer(frameLights.data(), sizeof(LightData) * lightCount,
                           MTL::ResourceStorageModeShared);
  } else {
    // 防崩溃：即使没有光源，也要创建一个正好等于 1 个 LightData 大小的假
    // Buffer，满足 Metal 的空间检查
    LightData dummyLight = {}; // 默认初始化为0
    lightBuffer = _device->newBuffer(&dummyLight, sizeof(LightData),
                                     MTL::ResourceStorageModeShared);
  }
  uniformBuffers.push_back(lightBuffer);

  // forward pass Render
  MTL::RenderCommandEncoder *forwardEncoder =
      commandBuffer->renderCommandEncoder(_forwardPassDescriptor);
  forwardEncoder->setRenderPipelineState(_renderPSO);
  forwardEncoder->setDepthStencilState(_depthStencilState);

  for (const auto &instance : _scene.getInstances()) {
    const Model &model = _scene.getModel(instance.modelIndex);
    forwardEncoder->setVertexBuffer(model.getVertexBuffer(), 0, 0);

    for (const auto &sub : model.getSubmeshes()) {
      MTL::Buffer *thisUniform =
          _device->newBuffer(sizeof(Uniforms), MTL::ResourceStorageModeShared);
      uniformBuffers.push_back(thisUniform);
      Uniforms *uniforms = (Uniforms *)thisUniform->contents();

      uniforms->modelViewProjectionMatrix =
          _activeCamera->getProjectionMatrix() * _activeCamera->getViewMatrix() *
          instance.modelMatrix * sub.nodeTransform;
      uniforms->modelMat = instance.modelMatrix * sub.nodeTransform;
      uniforms->viewMat = _activeCamera->getViewMatrix();
      uniforms->normalMatrix =
          inverse(transpose(instance.modelMatrix * sub.nodeTransform));
      uniforms->ProjectionMat = _activeCamera->getProjectionMatrix();
      uniforms->lightSpaceMatrix = globalLightSpaceMatrix;
      uniforms->lightDirection = globalLightDir;
      uniforms->lightColor = simd::float3{.8f, .608f, 0.300f};
      uniforms->lightIntensity = 30.f;
      uniforms->cameraPosition = _activeCamera->pos;

      forwardEncoder->setVertexBuffer(thisUniform, 0, 1);
      forwardEncoder->setFragmentBuffer(thisUniform, 0, 1);
      forwardEncoder->setFragmentBuffer(lightBuffer, 0, 2);
      forwardEncoder->setFragmentBytes(&lightCount, sizeof(int), 3);

      auto &material = model.getMaterial(sub.materialIndex);
      forwardEncoder->setFragmentTexture(material.albedoTexture, 0);
      forwardEncoder->setFragmentTexture(material.normalTexture, 1);
      forwardEncoder->setFragmentTexture(material.metallicTexture, 2);
      forwardEncoder->setFragmentTexture(material.roughnessTexture, 3);
      forwardEncoder->setFragmentTexture(material.aoTexture, 4);
      forwardEncoder->setFragmentTexture(material.alphaTexture, 5);
      forwardEncoder->setFragmentTexture(material.emissiveTexture, 6);
      forwardEncoder->setFragmentTexture(_skyboxTexture, 7);
        forwardEncoder->setFragmentBytes(&_physicalParams.manualExposure, sizeof(float), 0);
      forwardEncoder->setFragmentTexture(_irradianceMap, 8);
      forwardEncoder->setFragmentTexture(_prefilterMap, 9);
      forwardEncoder->setFragmentTexture(_brdfLUT, 10);
      forwardEncoder->setFragmentTexture(_shadowMap, 11);

      forwardEncoder->drawIndexedPrimitives(
          MTL::PrimitiveTypeTriangle, sub.indexCount, MTL::IndexTypeUInt32,
          model.getIndexBuffer(), sub.indexOffset * sizeof(uint32_t));
    }
  }

  // skybox Render
  // 注意：确保你在 initPipelines 或 initTextures 里初始化了 _cameraBuffer 和
  // _skyboxVertexBuffer
  struct CameraData {
    simd::float4x4 viewMatrix;
    simd::float4x4 projectionMatrix;
  };
  CameraData cameraData{_activeCamera->getViewMatrixWithNoTranslation(),
                        _activeCamera->getProjectionMatrix()};
  memcpy(_cameraBuffer->contents(), &cameraData, sizeof(CameraData));

  forwardEncoder->setRenderPipelineState(_skyboxPSO);
  forwardEncoder->setDepthStencilState(_depthStateLessEqualNoWrite);
  forwardEncoder->setVertexBuffer(_skyboxVertexBuffer, 0, 0);
  forwardEncoder->setVertexBuffer(_cameraBuffer, 0, 1);
  forwardEncoder->setFragmentTexture(_skyboxTexture, 0);
  forwardEncoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, 36,
                                        MTL::IndexTypeUInt32,
                                        _skyboxIndexBuffer, 0);

  // 结束 Forward 和 Skybox pass
  forwardEncoder->endEncoding();

  // Post processing
  //  --- 4.1 Bloom Threshold ---
  MTL::RenderCommandEncoder *bloomThresholdEncoder =
      commandBuffer->renderCommandEncoder(_bloomThresholdPassDescriptor);
  bloomThresholdEncoder->setRenderPipelineState(_bloomThresholdPSO);
  bloomThresholdEncoder->setFragmentTexture(_rawColorTexture, 0);
  float threshold = 2.0f;
  bloomThresholdEncoder->setFragmentBytes(&threshold, sizeof(float), 0);
  bloomThresholdEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle,
                                        NS::UInteger(0), NS::UInteger(6));
  bloomThresholdEncoder->endEncoding();

  // --- 4.2 Bloom Blur (Compute Pass) ---
  MTL::ComputeCommandEncoder *computeEncoder =
      commandBuffer->computeCommandEncoder();
  MTL::Size threadgroupSize = MTL::Size(16, 16, 1);
  MTL::Size gridSize =
      MTL::Size(_bloomThresholdMap->width(), _bloomThresholdMap->height(), 1);

  computeEncoder->setComputePipelineState(_blurXPSO);
  computeEncoder->setTexture(_bloomThresholdMap, 0);
  computeEncoder->setTexture(_blurTempMap, 1);
  computeEncoder->dispatchThreads(gridSize, threadgroupSize);

  computeEncoder->setComputePipelineState(_blurYPSO);
  computeEncoder->setTexture(_blurTempMap, 0);
  computeEncoder->setTexture(_bloomBlurMap, 1);
  computeEncoder->dispatchThreads(gridSize, threadgroupSize);
  computeEncoder->endEncoding();

  // --- 4.3 Post Merge (渲染到屏幕) ---
  MTL::RenderCommandEncoder *postMergeEncoder =
      commandBuffer->renderCommandEncoder(_postMergePassDescriptor);
  if (_physicalParams.isPhysicalMode) {
      postMergeEncoder->setRenderPipelineState(_postMergePhysicalPSO);
  } else {
      postMergeEncoder->setRenderPipelineState(_postMergeNormalPSO);
  }
    postMergeEncoder->setFragmentBytes(&_physicalParams, sizeof(CameraPostParams), 0);
  postMergeEncoder->setFragmentTexture(_rawColorTexture, 0);
  postMergeEncoder->setFragmentTexture(_bloomBlurMap, 1);
  postMergeEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0),
                                   NS::UInteger(6));
  postMergeEncoder->endEncoding();

 //提交
  commandBuffer->presentDrawable(drawable);
  commandBuffer->commit();

  //    commandBuffer->waitUntilCompleted();

  // 清理本帧临时的 uniformBuffers
  for (auto buf : uniformBuffers) {
    buf->release();
  }
}

void Renderer::initPipelines() {
  //把 main.mm 里的 Library 加载和各种 MTL::RenderPipelineState
  MTL::Library *library = _device->newDefaultLibrary();
  // forward screen Render
  MTL::Function *vShader;
  MTL::Function *fShader;
  MTL::RenderPipelineDescriptor *pDesc =
      MTL::RenderPipelineDescriptor::alloc()->init();
  NS::Error *error = nullptr;

  { // shadow Pipeline
    vShader = library->newFunction(
        NS::String::string("shadowVertex", NS::ASCIIStringEncoding));
    pDesc->setLabel(
        NS::String::string("shadow Pipeline", NS::ASCIIStringEncoding));
    pDesc->setVertexFunction(vShader);
    pDesc->setFragmentFunction(nullptr);
    pDesc->setVertexDescriptor(Model::createVertexDescriptor());
    pDesc->colorAttachments()->object(0)->setPixelFormat(
        MTL::PixelFormatInvalid);
    pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    _shadowPSO = _device->newRenderPipelineState(pDesc, &error);
    assert(_shadowPSO && !error);
  }

  { // Main RenderPipeline
    vShader = library->newFunction(
        NS::String::string("vertexShader", NS::ASCIIStringEncoding));
    fShader = library->newFunction(
        NS::String::string("fragmentShader", NS::ASCIIStringEncoding));
    assert(vShader && fShader);

    pDesc->setLabel(
        NS::String::string("main Render Pipeline", NS::ASCIIStringEncoding));
    pDesc->setRasterSampleCount(sampleCount);
    pDesc->setVertexFunction(vShader);
    pDesc->setFragmentFunction(fShader);
    pDesc->setVertexDescriptor(Model::createVertexDescriptor());
    assert(pDesc);
    pDesc->colorAttachments()->object(0)->setPixelFormat(
        MTL::PixelFormatRGBA16Float);
    pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    _renderPSO = _device->newRenderPipelineState(pDesc, &error);
    assert(_renderPSO && !error);
  }

  { // skybox pipeline
    vShader = library->newFunction(
        NS::String::string("skyboxVertex", NS::ASCIIStringEncoding));
    fShader = library->newFunction(
        NS::String::string("skyboxFragment", NS::ASCIIStringEncoding));
    assert(vShader && fShader);

    auto skyboxVertexDesc = MTL::VertexDescriptor::alloc()->init();
    skyboxVertexDesc->attributes()->object(0)->setFormat(
        MTL::VertexFormatFloat3);
    skyboxVertexDesc->attributes()->object(0)->setOffset(0);
    skyboxVertexDesc->attributes()->object(0)->setBufferIndex(0);
    skyboxVertexDesc->layouts()->object(0)->setStride(sizeof(simd::float3));

    pDesc->setLabel(
        NS::String::string("skybox Pipeline", NS::ASCIIStringEncoding));
    pDesc->setVertexFunction(vShader);
    pDesc->setFragmentFunction(fShader);
    pDesc->setVertexDescriptor(skyboxVertexDesc);
    assert(pDesc);
    _skyboxPSO = _device->newRenderPipelineState(pDesc, &error);
    assert(_skyboxPSO && !error);

    auto computeIrrdiance = library->newFunction(
        NS::String::string("computeIrradiance", NS::ASCIIStringEncoding));
    error = nullptr;
    _irrPSO = _device->newComputePipelineState(computeIrrdiance, &error);

    auto computePrefilter = library->newFunction(
        NS::String::string("computePrefilter", NS::ASCIIStringEncoding));
    error = nullptr;
    _prefilterPSO = _device->newComputePipelineState(computePrefilter, &error);

    auto computeBRDFLut = library->newFunction(
        NS::String::string("computeBRDFLut", NS::ASCIIStringEncoding));
    error = nullptr;
    _lutPSO = _device->newComputePipelineState(computeBRDFLut, &error);
  }

  { // post processing pipeline
    /// bloom threshold
    vShader = library->newFunction(
        NS::String::string("vertexPassthrough", NS::ASCIIStringEncoding));
    fShader = library->newFunction(
        NS::String::string("fragmentBloomThreshold", NS::ASCIIStringEncoding));
    pDesc->setLabel(NS::String::string("bloom threshold Pipeline",
                                       NS::ASCIIStringEncoding));
    pDesc->setRasterSampleCount(1);
    pDesc->setVertexFunction(vShader);
    pDesc->setFragmentFunction(fShader);
    pDesc->setVertexDescriptor(nullptr);
    pDesc->setDepthAttachmentPixelFormat(MTL::PixelFormatInvalid);
    _bloomThresholdPSO = _device->newRenderPipelineState(pDesc, &error);

    /// bloom blur
    auto blurXFn = library->newFunction(
        NS::String::string("gaussian_blur_x", NS::ASCIIStringEncoding));
    auto blurYFn = library->newFunction(
        NS::String::string("gaussian_blur_y", NS::ASCIIStringEncoding));
    error = nullptr;
    _blurXPSO = _device->newComputePipelineState(blurXFn, &error);
    _blurYPSO = _device->newComputePipelineState(blurYFn, &error);
    blurXFn->release();
    blurYFn->release();

    /// post merge
    /// normal
    fShader = library->newFunction(NS::String::string(
        "fragmentPostprocessMerge", NS::ASCIIStringEncoding));
    pDesc->setLabel(
        NS::String::string("post merge Pipeline", NS::ASCIIStringEncoding));
    pDesc->setFragmentFunction(fShader);
    pDesc->colorAttachments()->object(0)->setPixelFormat(
        MTL::PixelFormatBGRA8Unorm_sRGB);
    _postMergeNormalPSO = _device->newRenderPipelineState(pDesc, &error);
     ///physical Camera
    fShader = library->newFunction(NS::String::string("fragmentPostprocessPhysical", NS::ASCIIStringEncoding));
    pDesc->setLabel(NS::String::string("post merge physical Piepline", NS::ASCIIStringEncoding));
    pDesc->setFragmentFunction(fShader);
    _postMergePhysicalPSO = _device->newRenderPipelineState(pDesc, &error);
  }
  vShader->release();
  fShader->release();
  pDesc->release();

  { // depthStencil State
    // DepthStenclState
    MTL::DepthStencilDescriptor *depthStencilDesc =
        MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLess);
    depthStencilDesc->setDepthWriteEnabled(true);
    _depthStencilState = _device->newDepthStencilState(depthStencilDesc);

    depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDesc->setDepthWriteEnabled(false);
    _depthStateLessEqualNoWrite =
        _device->newDepthStencilState(depthStencilDesc);
    depthStencilDesc->release();
  }
}

void Renderer::initTextures(int width, int height) {
  //防止先前图片导致内存泄漏
  if (_msaaDepthTexture) { _msaaDepthTexture->release();}
  if (_depthTexture) { _depthTexture->release();}
  if (_msaaRawColorTexture) { _msaaRawColorTexture->release();}
  if (_rawColorTexture) { _rawColorTexture->release();}
  if (_bloomThresholdMap) { _bloomThresholdMap->release();}
  if (_blurTempMap) { _blurTempMap->release();}
  if (_bloomBlurMap) { _bloomBlurMap->release();}
    
      
  // 从原先main.mm同步过来的， 但那个版本好久没更新同步现状了。
  MTL::TextureDescriptor *desc = MTL::TextureDescriptor::alloc()->init();
  desc->setWidth(width);
  desc->setHeight(height);

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

  desc->setUsage(
      MTL::TextureUsageRenderTarget); // rendertarget才能被pass直接写入的
  _msaaDepthTexture = _device->newTexture(desc);

  // depthTexture
  desc->setTextureType(MTL::TextureType2D);
  desc->setSampleCount(1);
  _depthTexture = _device->newTexture(desc);

  // msaaRenderTarget
  desc->setTextureType(MTL::TextureType2DMultisample);
  desc->setSampleCount(sampleCount);
  desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
  _msaaRawColorTexture = _device->newTexture(desc);

  // rawColorTexture HDR 相关的离屏纹理 (rawColor 和 bloom)
  desc->setTextureType(MTL::TextureType2D);
  desc->setSampleCount(1);
  desc->setArrayLength(1);
  desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
  desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead |
                 MTL::TextureUsageShaderWrite);
  _rawColorTexture = _device->newTexture(desc);
  // bloomThresholdMap
  _bloomThresholdMap = _device->newTexture(desc);
  // bloomBlurMap
  _blurTempMap = _device->newTexture(desc);
  _bloomBlurMap = _device->newTexture(desc);

  // shadowMap
  desc->setTextureType(MTL::TextureType2D);
  //        desc->setArrayLength(1);
  desc->setWidth(2048); // 阴影分辨率建议开大一点，比如 2048 或 4096
  desc->setHeight(2048);
  desc->setPixelFormat(MTL::PixelFormatDepth32Float);
  desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
  _shadowMap = _device->newTexture(desc);

  // Load HDR equirectangular texture
  _skyboxTexture = TextureLoader::load(
      _device, _commandQueue,
      "/Users/menji/coding/xcode/Realtime Renderer Based on Metal-CPP/Realtime "
      "Renderer Based on Metal-CPP/kloppenheim_06_4k.hdr",
      TextureLoader::ColorSpace::SRGB, false);

  // Irradiance Map
  desc->setTextureType(MTL::TextureTypeCube);
  desc->setWidth(32);
  desc->setHeight(32);
  desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
  desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
  _irradianceMap = _device->newTexture(desc);

  // Prefilter Map
  desc->setTextureType(MTL::TextureTypeCube);
  desc->setPixelFormat(MTL::PixelFormatRGBA16Float);
  desc->setWidth(512);
  desc->setHeight(512);
  desc->setMipmapLevelCount(5); // Mipmap 层数 (512, 256, 128, 64, 32)
  desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
  _prefilterMap = _device->newTexture(desc);

  // BRDF lut
  desc->setTextureType(MTL::TextureType2D);
  desc->setPixelFormat(MTL::PixelFormatRG16Float); // 只需要 R 和 G 两个通道
  desc->setWidth(512);
  desc->setHeight(512);
  desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
  _brdfLUT = _device->newTexture(desc);

  desc->release();
}

void Renderer::initPassDescriptors() {
  // 必须先清理旧的，释放内存，避免内存泄漏
  if (_shadowPassDescriptor) { _shadowPassDescriptor->release(); }
  if (_forwardPassDescriptor) { _forwardPassDescriptor->release(); }
  if (_bloomThresholdPassDescriptor) { _bloomThresholdPassDescriptor->release(); }
  if (_postMergePassDescriptor) { _postMergePassDescriptor->release(); }
    
  // 从 main.mm 里的 PassDescriptor 同步的
  { // shadow renderPass
    _shadowPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    MTL::RenderPassDepthAttachmentDescriptor *dd =
        _shadowPassDescriptor->depthAttachment();
    dd->setTexture(_shadowMap);
    dd->setLoadAction(MTL::LoadActionClear);
    dd->setClearDepth(1.0);
    dd->setStoreAction(MTL::StoreActionStore);
  }

  { // forward screen renderPass
    _forwardPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    MTL::RenderPassColorAttachmentDescriptor *cd =
        _forwardPassDescriptor->colorAttachments()->object(0);
    cd->setLoadAction(MTL::LoadActionClear);
    cd->setClearColor(
        MTL::ClearColor(41.0f / 255.0f, 42.0f / 255.0f, 48.0f / 255.0f, 1.0));
    cd->setStoreAction(MTL::StoreActionMultisampleResolve);
    cd->setTexture(_msaaRawColorTexture);
    cd->setResolveTexture(_rawColorTexture);
    // 加 depth
    MTL::RenderPassDepthAttachmentDescriptor *depthDesc =
        _forwardPassDescriptor->depthAttachment();
    depthDesc->setTexture(
        _msaaDepthTexture); // 假设你的 MetalViewWrapper 暴露了 depth
                            // texture（很多实现有）

    //        depthDesc->setResolveTexture(depthTexture); 深度不用resolve
    depthDesc->setLoadAction(MTL::LoadActionClear);
    depthDesc->setClearDepth(1.0);
    depthDesc->setStoreAction(MTL::StoreActionDontCare);
  }

  { // post processing renderPass
    /// bloom threshold
    _bloomThresholdPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    MTL::RenderPassColorAttachmentDescriptor *cd =
        _bloomThresholdPassDescriptor->colorAttachments()->object(0);
    cd->setLoadAction(MTL::LoadActionDontCare);
    cd->setStoreAction(MTL::StoreActionStore);
    cd->setTexture(_bloomThresholdMap);

    // blur the bloom  : compute no need  passDesc

    /// merge the post processing results with the scene rendering
    _postMergePassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    cd = _postMergePassDescriptor->colorAttachments()->object(0);
    cd->setLoadAction(MTL::LoadActionClear);
    cd->setClearColor(
        MTL::ClearColor(41.0f / 255.0f, 42.0f / 255.0f, 48.0f / 255.0f, 1.0));
    cd->setStoreAction(MTL::StoreActionStore);
  }
}

void Renderer::precomputeIBL() {
  //贴入 irradiance, prefilter 和 lut 的 compute 调度逻辑
  { // IBL preCompute
    MTL::CommandBuffer *precomputeCmdBuffer = _commandQueue->commandBuffer();
    precomputeCmdBuffer->setLabel(
        NS::String::string("IBL Pre-computation", NS::ASCIIStringEncoding));
    MTL::ComputeCommandEncoder *computeEncoder =
        precomputeCmdBuffer->computeCommandEncoder();

    // 1. 生成 Irradiance Map (32x32x6)
    computeEncoder->setComputePipelineState(_irrPSO);
    computeEncoder->setTexture(_skyboxTexture, 0);
    computeEncoder->setTexture(_irradianceMap, 1);
    MTL::Size gridSizeIrr = MTL::Size(32, 32, 6);
    MTL::Size threadGroupSizeIrr = MTL::Size(8, 8, 1);
    computeEncoder->dispatchThreads(gridSizeIrr, threadGroupSizeIrr);

    // 2. 生成 Prefilter Map (5个 Mip 层级)
    computeEncoder->setComputePipelineState(_prefilterPSO);
    computeEncoder->setTexture(_skyboxTexture, 0);
    uint32_t maxMipLevels = 5;
    for (uint32_t mip = 0; mip < maxMipLevels; ++mip) {
      float roughness = (float)mip / (float)(maxMipLevels - 1);
      computeEncoder->setBytes(&roughness, sizeof(float), 0);

      // 创建指定 Mip 级别的 TextureView 以供 Compute Shader 写入
      MTL::Texture *mipView = _prefilterMap->newTextureView(
          MTL::PixelFormatRGBA16Float, MTL::TextureTypeCube, NS::Range(mip, 1),
          NS::Range(0, 6));
      computeEncoder->setTexture(mipView, 1);

      uint32_t mipWidth = 512 * std::pow(0.5, mip);
      MTL::Size gridSizePrefilter = MTL::Size(mipWidth, mipWidth, 6);
      MTL::Size threadGroupSizePrefilter =
          MTL::Size(std::min(mipWidth, 16u), std::min(mipWidth, 16u), 1);
      computeEncoder->dispatchThreads(gridSizePrefilter,
                                      threadGroupSizePrefilter);

      mipView->release();
    }

    // 3. 生成 BRDF LUT (512x512)
    computeEncoder->setComputePipelineState(_lutPSO);
    computeEncoder->setTexture(_brdfLUT, 0);
    MTL::Size gridSizeLut = MTL::Size(512, 512, 1);
    MTL::Size threadGroupSizeLut = MTL::Size(16, 16, 1);
    computeEncoder->dispatchThreads(gridSizeLut, threadGroupSizeLut);

    computeEncoder->endEncoding();
    precomputeCmdBuffer->commit();
    precomputeCmdBuffer
        ->waitUntilCompleted(); // 必须阻塞 CPU，确保纹理生成完毕再开始渲染
    std::cout << "IBL Pre-computation Completed." << std::endl;
  }
}
