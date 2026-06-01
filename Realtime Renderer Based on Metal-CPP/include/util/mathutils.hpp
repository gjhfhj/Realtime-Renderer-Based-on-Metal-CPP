//
//  mathutils.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/19.
//
#pragma once
#include <simd/simd.h>

using namespace simd;

inline float4x4 identity() {return matrix_identity_float4x4;}

inline float radians(float degree) { return degree * 3.14159265 / 180; }


inline float4x4 translate(const float3& t)
{
    simd::float4x4 m = matrix_identity_float4x4;
    m.columns[3] = simd_make_float4(t, 1.0f);
    return m;
}

inline float4x4 rotateX(float rad)
{
    float c = cosf(rad);
    float s = sinf(rad);

    return float4x4(
        simd_make_float4(1, 0, 0, 0),
        simd_make_float4(0, c, s, 0),
        simd_make_float4(0, -s, c, 0),
        simd_make_float4(0, 0, 0, 1)
    );
}

inline float4x4 rotateY(float rad)
{
    float c = cosf(rad);
    float s = sinf(rad);

    return float4x4(
        simd_make_float4(c, 0, -s, 0),
        simd_make_float4(0, 1, 0, 0),
        simd_make_float4( s, 0, c, 0),
        simd_make_float4(0, 0, 0, 1)
    );
}

inline float4x4 rotateZ(float rad)
{
    float c = cosf(rad);
    float s = sinf(rad);

    return float4x4(
        simd_make_float4(c, s, 0, 0),
        simd_make_float4(-s, c, 0, 0),
        simd_make_float4(0, 0, 1, 0),
        simd_make_float4(0, 0, 0, 1)
    );
}

inline float4x4 scale(const float3& s)
{
    simd::float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = s.x;
    m.columns[1].y = s.y;
    m.columns[2].z = s.z;
    return m;
}

inline float4x4 getModelMatrix(const float3 &pos, const float3 &rotate, const float3 &s ) {
    return translate(pos) *
           rotateZ(radians(rotate.z)) *
           rotateY(radians(rotate.y)) *
           rotateX(radians(rotate.x)) *
           scale(s);
}



inline std::string normalizePath(std::string path) {
    for (char& c : path) {
        if (c == '\\') c = '/';
    }
    return path;
}
