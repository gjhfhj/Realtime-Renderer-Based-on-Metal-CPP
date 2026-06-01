//
//  triangle.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//
#pragma once

#include <simd/simd.h>

struct Triangle {
    simd::float3 p0,p1,p2;
    simd::float3 n0,n1,n2;
    
    Triangle(const simd::float3 &p0, const simd::float3 &p1, const simd::float3 &p2);
    Triangle(const simd::float3 &p0, const simd::float3 &p1, const simd::float3 &p2,
             const simd::float3 &n0, const simd::float3 &n1, const simd::float3 &n2);
};


