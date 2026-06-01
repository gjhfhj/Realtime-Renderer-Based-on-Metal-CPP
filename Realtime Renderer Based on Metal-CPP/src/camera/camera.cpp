//
//  camera.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//
#include "camera/camera.hpp"
// Metal坐标系约定为标准右手系
//      +Y
//      ↑
//      |
//      o----→ +X
//     /
//   +Z  （朝屏幕外）

//Camera::Camera(const float3 &pos, const float3 &viewPoint, float fovy )
//:pos(pos), viewPoint(viewPoint),
//R(float3{1, 0, 0}), U(float3{0, 1, 0}), F(float3{0, 0, -1}) {}


float4x4 Camera::getViewMatrix() const {
    return matrix_make_rows(right.x, right.y, right.z, simd::dot(-right, pos),
                            up.x, up.y, up.z, simd::dot(-up, pos),
                            -forward.x, -forward.y, -forward.z, simd::dot(forward, pos),
                            0, 0, 0, 1);
}

float4x4 Camera::getViewMatrixWithNoTranslation() const {
    return matrix_make_rows(right.x, right.y, right.z, 0.f,
                            up.x, up.y, up.z, 0.f,
                            -forward.x, -forward.y, -forward.z, 0.f,
                            0, 0, 0, 1);
}

float4x4 Camera::getProjectionMatrix() const {
    float fovyRad = radians(zoom);
    float tanHalfFovy = tan(fovyRad / 2.0f);
    
    float4x4 proj = matrix_identity_float4x4;
    
    proj.columns[0][0] = 1.0f / (aspect * tanHalfFovy);
    proj.columns[1][1] = 1.0f / tanHalfFovy;
    proj.columns[2][2] = farPlane / (nearPlane - farPlane);
    proj.columns[2][3] = -1.0f;
    proj.columns[3][2] = -(farPlane * nearPlane) / (farPlane - nearPlane);
    proj.columns[3][3] = 0.0f;
    
    return matrix_perspective_right_hand(zoom, aspect, 0.1, farPlane);
}

void Camera::update(const bool keys[256], float deltaTime) {
    float moveSpeed = speed * deltaTime;
    
    if (keys[KEY_SHIFT]) {
        moveSpeed *= 20.0f;
    }
    
    // 计算水平方向的 forward（忽略 pitch）
    // 只使用 yaw 来计算水平面上的前进方向
    simd::float3 horizontalForward;
    horizontalForward.x = cos(radians(yaw));
    horizontalForward.y = 0.0f;  // 保持在水平面
    horizontalForward.z = sin(radians(yaw));
    horizontalForward = normalize(horizontalForward);
    
    // 水平的右方向（垂直于 horizontalForward）
    simd::float3 horizontalRight = normalize(cross(horizontalForward, worldUp));
    
    // WASD 移动：只在水平面上
    if (keys[KEY_W]) {
        pos += horizontalForward * moveSpeed;
    }
    if (keys[KEY_S]) {
        pos -= horizontalForward * moveSpeed;
    }
    if (keys[KEY_A]) {
        pos -= horizontalRight * moveSpeed;
    }
    if (keys[KEY_D]) {
        pos += horizontalRight * moveSpeed;
    }
    
    // QE 移动：严格垂直方向（世界坐标的 Y 轴）
    if (keys[KEY_Q]) {
        pos.y -= moveSpeed;  // 下降
    }
    if (keys[KEY_E]) {
        pos.y += moveSpeed;  // 上升
    }
}

void Camera::onMouseMove(float deltaX, float deltaY) {
    yaw   += deltaX * sensitivity;
    pitch += deltaY * sensitivity;

    if (pitch > 89.0f) pitch = 89.0f;
    if (pitch < -89.0f) pitch = -89.0f;

    updateVectors();
}

void Camera::updateVectors() {
    // 计算视线方向（包含 pitch）
    simd::float3 dir;
    dir.x = cos(radians(yaw)) * cos(radians(pitch));
    dir.y = sin(radians(pitch));
    dir.z = sin(radians(yaw)) * cos(radians(pitch));
    forward = normalize(dir);

    // 相机的右方向和上方向（用于视图矩阵）
    right = normalize(cross(forward, worldUp));
    up    = normalize(cross(right, forward));
}

float Camera::radians(float degrees) const {
    return degrees * M_PI / 180.0f;
}


#pragma mark -- Physical Camera stuff

PhysicalCamera::PhysicalCamera() {
    updatePhysicalFOV();
}

void PhysicalCamera::updatePhysicalFOV() {
    // 物理公式：计算基于焦距和传感器尺寸的垂直 FOV
    // FOV = 2 * arctan(SensorHeight / (2 * FocalLength))
    float fovRadians = 2.0f * atan(sensorHeight / (2.0f * focalLength));
    
    // 将计算出的物理 FOV 转换回角度，赋值给父类的 zoom (FOV)
    this->zoom = fovRadians * 180.0f / M_PI;
}

float4x4 PhysicalCamera::getProjectionMatrix() const {
    // 确保每次获取矩阵时，FOV 都与当前焦距匹配
    // 因为 C++ const 函数不能修改成员变量，如果你设计 focalLength 经常变，
    // 在 setFocalLength 的 setter 里调用 updatePhysicalFOV()。
    
    float fovyRad = radians(this->zoom);
    float tanHalfFovy = tan(fovyRad / 2.0f);
    
    float4x4 proj = matrix_identity_float4x4;
    proj.columns[0][0] = 1.0f / (aspect * tanHalfFovy);
    proj.columns[1][1] = 1.0f / tanHalfFovy;
    proj.columns[2][2] = farPlane / (nearPlane - farPlane);
    proj.columns[2][3] = -1.0f;
    proj.columns[3][2] = -(farPlane * nearPlane) / (farPlane - nearPlane);
    proj.columns[3][3] = 0.0f;
    
    return proj;
}
