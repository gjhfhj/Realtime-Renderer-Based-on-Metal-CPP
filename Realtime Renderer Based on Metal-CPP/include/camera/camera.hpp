//
//  camera.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/16.
//
#pragma once

#include <simd/simd.h>
#include "util/AAPLMathUtilities.h"
using namespace simd;
// Metal坐标系约定为标准右手系
//      +Y
//      ↑
//      |
//      o----→ +X
//     /
//   +Z  （朝屏幕外）

enum KeyCode {
    KEY_W = 13,
    KEY_A = 0,
    KEY_S = 1,
    KEY_D = 2,
    KEY_Q = 12,
    KEY_E = 14,
    KEY_SHIFT = 56
};

class Camera {
        
public:
    Camera() { updateVectors(); }
    ~Camera() {}
    
    void update(const bool keys[256], float deltaTime);
    void setAspect(float a) {aspect = a;}
    void onMouseMove(float deltaX, float deltaY);
    
    float4x4 getViewMatrix() const;
    float4x4 getViewMatrixWithNoTranslation() const;
    float4x4 getProjectionMatrix() const;

public:
    float3 pos {0.f, 0.0f, 1.5f};
    float3 forward {0.0f, 0.0f, -1.0f};
    float3 up {0.0f, 1.0f, 0.0f};
    float3 right {1.0f, 0.0f, 0.0f};
    float3 worldUp {0.0f, 1.0f, 0.0f};

    float yaw = -90.0f;    // 初始朝 -Z
    float pitch = 0.0f;
    float sensitivity = 0.1f;
    float speed = 8.f;    // 移动速度（每秒单位）
    float zoom = 45.0f;    // FOV

    float aspect = 1280.0f / 720.0f;
    float nearPlane = 0.01f;
    float farPlane = 100.0f;
    
protected:
    float radians(float degrees) const;

private:
    void updateVectors();

    
    
};

#pragma mark -- Physical Camera Stuff

class PhysicalCamera : public Camera {
public:
    PhysicalCamera();
    
    // 物理参数
    float aperture = 5.6f;        // 光圈 (f-stop)
    float shutterSpeed = 1.0f/250.0f; // 快门速度 (s)
    float iso = 200.0f;           // 感光度
    float evComp = 0.0f;          // 曝光补偿
    
    // 镜头物理参数
    float focalLength = 35.0f;    // 焦距 (mm)
    float sensorHeight = 24.0f;   // 传感器高度 (mm) - 标准全画幅尺寸(36x24)
    float focusDistance = 5.0f;   // 对焦距离 (m) - 为后续景深做准备

    // 尽可能还原物理
    float4x4 getProjectionMatrix() const;
    
    // 同步基础参数以防直接读取 base class 的属性
    void updatePhysicalFOV();
};
