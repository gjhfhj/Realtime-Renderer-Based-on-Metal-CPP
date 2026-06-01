//
//  triangle.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//
#include "model/triangle.hpp"

Triangle::Triangle(const simd::float3 &p0, const simd::float3 &p1, const simd::float3 &p2)
:p0(p0), p1(p1), p2(p2) {
    simd::float3 e1 = p1 - p0;
    simd::float3 e2 = p2 - p0;
    simd::float3 normal = simd::cross(e1, e2);
    n0 = normal; n1 = normal; n2 = normal;
}

Triangle::Triangle(const simd::float3 &p0, const simd::float3 &p1, const simd::float3 &p2,
                   const simd::float3 &n0, const simd::float3 &n1, const simd::float3 &n2)
:p0(p0), p1(p1), p2(p2), n0(n0), n1(n1), n2(n2) {}
