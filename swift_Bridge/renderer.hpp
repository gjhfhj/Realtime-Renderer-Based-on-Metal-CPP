//
//  RendererEngine.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

#pragma once

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <chrono>
#include <simd/simd.h>

#include "camera/camera.hpp"
#include "model/scene.hpp"

struct CameraPostParams {
    float manualExposure = 0.1f;
    float aperture;
    float shutterSpeed;
    float iso;
    float evComp;
    int isPhysicalMode;
    float pad[2]; // Metal 端对齐
};

class Renderer {
public:
  // 构造函数：接管原来的初始化逻辑 (Device, CommandQueue, Pipelines,
  // 纹理加载等)
  Renderer(MTL::Device *device, int width, int height,
           const std::string &resourceBasePath);

  // 析构函数：负责 release 所有申请的 MTL 资源
  ~Renderer();

  // 更新deltaTime，更新相机和矩阵
  void update(const bool *keys);

  // 核心渲染逻辑：接管原先的 commandBuffer 录制和各种 Pass 的绘制
  void render(CA::MetalDrawable *drawable);

  // --- 输入与状态接口 ---
  void onMouseMove(int deltaX, int deltaY);
  void setExposure(float exp);
  void meow() { printf("meow\n"); }
  void setPhysicalCameraMode(bool isPhysical);
  void setPhysicalCameraParams(float ap, float shutter, float iso, float ev);

private:
  // --- 核心基础设施 ---
  MTL::Device *_device;
  MTL::CommandQueue *_commandQueue;
    
  int _currentWidth;
  int _currentHeight;

  // --- 场景与相机 ---
  Camera _normalCamera;
  PhysicalCamera _physicalCamera;
  Camera* _activeCamera; //实际活跃相机
  CameraPostParams _physicalParams;
  Scene _scene;

  // --- 渲染状态 (把 main 里的局部变量全搬过来) ---
  std::chrono::time_point<std::chrono::high_resolution_clock> _lastFrameTime;
//  float exposure = 0.1f;
  NS::UInteger sampleCount = 4;

  // --- 管线状态 (Pipeline States) ---
  MTL::RenderPipelineState *_shadowPSO;
  MTL::RenderPipelineState *_renderPSO;
  MTL::RenderPipelineState *_skyboxPSO;
  MTL::ComputePipelineState *_irrPSO;
  MTL::ComputePipelineState *_prefilterPSO;
  MTL::ComputePipelineState *_lutPSO;

  MTL::DepthStencilState *_depthStencilState;
  MTL::DepthStencilState *_depthStateLessEqualNoWrite;

  // 后处理管线
  MTL::RenderPipelineState *_bloomThresholdPSO;
  MTL::ComputePipelineState *_blurXPSO;
  MTL::ComputePipelineState *_blurYPSO;
  MTL::RenderPipelineState *_postMergeNormalPSO;
  MTL::RenderPipelineState *_postMergePhysicalPSO;
  // --- 纹理资源 (Textures) ---
  MTL::Texture *_msaaDepthTexture;
  MTL::Texture *_depthTexture;
  MTL::Texture *_skyboxTexture;
  MTL::Texture *_irradianceMap;
  MTL::Texture *_prefilterMap;
  MTL::Texture *_brdfLUT;
  MTL::Texture *_shadowMap;
  MTL::Texture *_msaaRawColorTexture;
  MTL::Texture *_rawColorTexture;
  MTL::Texture *_bloomThresholdMap;
  MTL::Texture *_blurTempMap;
  MTL::Texture *_bloomBlurMap;

  // --- 缓冲区 (Buffers) ---
  MTL::Buffer *_skyboxVertexBuffer;
  MTL::Buffer *_skyboxIndexBuffer;
  MTL::Buffer *_cameraBuffer;

  // --- Pass Descriptors ---
  MTL::RenderPassDescriptor *_shadowPassDescriptor = nullptr;
  MTL::RenderPassDescriptor *_forwardPassDescriptor = nullptr;
  MTL::RenderPassDescriptor *_bloomThresholdPassDescriptor = nullptr;
  MTL::RenderPassDescriptor *_postMergePassDescriptor= nullptr;

  // --- 内部初始化辅助函数 ---
  void initPipelines();
  void initTextures(int width, int height);
  void initPassDescriptors();
  void precomputeIBL();
};
