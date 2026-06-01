//
//  default.metal
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/16.
//

#include <metal_stdlib>
using namespace metal;

constant float kMaxHDRValue = 500.0f;


struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    simd::float4x4 modelMat;
    simd::float4x4 viewMat;
    simd::float4x4 ProjectionMat;
    float4x4 normalMatrix;               // 法线变换矩阵（模型矩阵的逆转置）
    float4x4 lightSpaceMatrix;
    float3   lightDirection;             // 光照方向
    float3   lightColor;
    float    lightIntensity;
    float3   cameraPosition;
};

struct CameraData {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

struct CameraPostParams {
    float manualExposure;
    float aperture;
    float shutterSpeed;
    float iso;
    float evComp;
    int isPhysicalMode;
    float pad[2];
};

float DistributionGGX(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (M_PI_F * denom * denom);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

float3 FresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// 专门为环境光 (IBL) 设计的带有粗糙度抑制的菲涅尔近似公式 (Sébastien Lagarde 提供)
float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    // 随着粗糙度增加，强制压低掠射角的高光强度，防止粗糙物体边缘变镜子
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}


#pragma mark - IBL 预计算数学工具与 Compute Kernels

// 将 3D 方向映射到 2D 等距柱状全景图 UV (与你的 Skybox 逻辑保持一致)
float2 sampleSphericalMap(float3 v) {
    float u = atan2(v.z, v.x) / (2.0 * M_PI_F) + 0.5;
    float v_coord = acos(v.y) / M_PI_F;
    return float2(u, v_coord);
}

// 根据 CubeMap 的面(0-5)和像素坐标获取 3D 方向
float3 getDirFromCube(uint2 pos, uint face, uint width, uint height) {
    float2 uv = float2(pos) / float2(width, height);
    uv = uv * 2.0 - 1.0;
    uv.y = -uv.y; // Metal Y 轴向下
    
    float3 dir;
    switch(face) {
        case 0: dir = float3( 1.0,   uv.y, -uv.x); break; // +X
        case 1: dir = float3(-1.0,   uv.y,  uv.x); break; // -X
        case 2: dir = float3( uv.x,  1.0,  -uv.y); break; // +Y
        case 3: dir = float3( uv.x, -1.0,   uv.y); break; // -Y
        case 4: dir = float3( uv.x,  uv.y,  1.0);  break; // +Z
        case 5: dir = float3(-uv.x,  uv.y, -1.0);  break; // -Z
    }
    return normalize(dir);
}

// Hammersley 序列与重要性采样
float RadicalInverse_VdC(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

float2 Hammersley(uint i, uint N) {
    return float2(float(i)/float(N), RadicalInverse_VdC(i));
}

float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * M_PI_F * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta);
    
    float3 H = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    
    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);
    
    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

// 1. 生成漫反射 Irradiance Map (半球积分)
kernel void computeIrradiance(
    texture2d<float, access::sample> envMap [[texture(0)]],
    texturecube<float, access::write> outCube [[texture(1)]],
    uint3 gid [[thread_position_in_grid]])
{
    uint width = outCube.get_width();
    if(gid.x >= width || gid.y >= width) return;

    float3 N = getDirFromCube(gid.xy, gid.z, width, width);
    float3 irradiance = float3(0.0);
    
    float3 up    = float3(0.0, 1.0, 0.0);
    float3 right = normalize(cross(up, N));
    up           = normalize(cross(N, right));

    float sampleDelta = 0.025;
    float nrSamples = 0.0;
    constexpr sampler envSampler(address::repeat, filter::linear, mip_filter::none);

    for(float phi = 0.0; phi < 2.0 * M_PI_F; phi += sampleDelta) {
        for(float theta = 0.0; theta < 0.5 * M_PI_F; theta += sampleDelta) {
            float3 tangentSample = float3(sin(theta) * cos(phi),  sin(theta) * sin(phi), cos(theta));
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;
            
            float2 uv = sampleSphericalMap(sampleVec);
            irradiance += envMap.sample(envSampler, uv).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    irradiance = M_PI_F * irradiance * (1.0 / float(nrSamples));
    outCube.write(float4(irradiance, 1.0), gid.xy, gid.z);
}

// 2. 生成高光 Prefilter Map (重要性采样)
kernel void computePrefilter(
    texture2d<float, access::sample> envMap [[texture(0)]],
    texturecube<float, access::write> outCube [[texture(1)]],
    constant float& roughness [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]])
{
    uint width = outCube.get_width();
    if(gid.x >= width || gid.y >= width) return;

    float3 N = getDirFromCube(gid.xy, gid.z, width, width);
    float3 R = N;
    float3 V = R;
    
    constexpr sampler envSampler(address::repeat, filter::linear, mip_filter::none);
    
    const uint SAMPLE_COUNT = 1024u;
    float totalWeight = 0.0;
    float3 prefilteredColor = float3(0.0);
    
    for(uint i = 0u; i < SAMPLE_COUNT; ++i) {
        float2 Xi = Hammersley(i, SAMPLE_COUNT);
        float3 H  = ImportanceSampleGGX(Xi, N, roughness);
        float3 L  = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if(NdotL > 0.0) {
            float2 uv = sampleSphericalMap(L);
            prefilteredColor += envMap.sample(envSampler, uv).rgb * NdotL;
            totalWeight      += NdotL;
        }
    }
    prefilteredColor = prefilteredColor / totalWeight;
    outCube.write(float4(prefilteredColor, 1.0), gid.xy, gid.z);
}

// 3. 生成 BRDF LUT (纯数学积分)
kernel void computeBRDFLut(
    texture2d<float, access::write> outTexture [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if(gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    // UV 映射到 (NdotV, roughness)
    float NdotV = max(float(gid.x) / float(outTexture.get_width() - 1), 0.001);
    float roughness = float(gid.y) / float(outTexture.get_height() - 1);
    
    float3 V = float3(sqrt(1.0 - NdotV*NdotV), 0.0, NdotV);
    float3 N = float3(0.0, 0.0, 1.0);
    
    float A = 0.0;
    float B = 0.0;
    const uint SAMPLE_COUNT = 1024u;
    
    for(uint i = 0u; i < SAMPLE_COUNT; ++i) {
        float2 Xi = Hammersley(i, SAMPLE_COUNT);
        float3 H  = ImportanceSampleGGX(Xi, N, roughness);
        float3 L  = normalize(2.0 * dot(V, H) * H - V);
        
        float NdotL = max(L.z, 0.0);
        float NdotH = max(H.z, 0.0);
        float VdotH = max(dot(V, H), 0.0);
        
        if(NdotL > 0.0) {
            float G = GeometrySmith(N, V, L, roughness);
            float G_Vis = (G * VdotH) / (NdotH * NdotV);
            float Fc = pow(1.0 - VdotH, 5.0);
            
            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }
    A /= float(SAMPLE_COUNT);
    B /= float(SAMPLE_COUNT);
    
    outTexture.write(float4(A, B, 0.0, 1.0), gid);
}

#pragma mark - Rasterization

struct VertexIn {
    float3 position     [[attribute(0)]];
    float3 normal       [[attribute(1)]];
    float3 tangent      [[attribute(2)]];
    float3 bitangent    [[attribute(3)]];
    float2 uv           [[attribute(4)]];
    float4 color        [[attribute(5)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 worldNormal;
    float3 worldTangent;
    float3 worldBitangent;
    float2 uv;
    float4 color;
    float4 fragPosLightSpace;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.ProjectionMat * uniforms.viewMat * uniforms.modelMat * float4(in.position, 1.0);
    out.worldPos = (uniforms.modelMat * float4(in.position, 1.0)).xyz;  // 简化，实际用 model * pos
    out.worldNormal = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
    out.worldTangent = normalize((uniforms.normalMatrix * float4(in.tangent, 0.0)).xyz);
    out.worldBitangent = normalize((uniforms.normalMatrix * float4(in.bitangent, 0.0)).xyz);
    out.uv = in.uv;
    out.color = in.color;
    out.fragPosLightSpace = uniforms.lightSpaceMatrix * uniforms.modelMat * float4(in.position, 1.0);
    return out;
}

struct MaterialUniforms {
    float3 albedo       = {.0f, .0f, .0f};
    float  metallic     = 0.0f;
    float  roughness    = 0.5f;
    float  ao           = 1.0f;
    float  alpha        = 1.0f;
    float3 emissive     = {0.0f, 0.0f, 0.0f};
};

struct LightData {
    float4 position;  // xyz = 位置, w = 类型(0平行光, 1点光源)
    float4 color;     // xyz = 颜色, w = 强度
    float4 direction; // xyz = 方向, w = 参数
};

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant Uniforms& uniforms          [[buffer(1)]],
                               constant LightData* lights           [[buffer(2)]],
                               constant int& lightCount             [[buffer(3)]],
                               texture2d<float> albedoTexture       [[texture(0)]],
                               texture2d<float> normalTexture       [[texture(1)]],
                               texture2d<float> metallicTexture     [[texture(2)]],
                               texture2d<float> roughnessTexture    [[texture(3)]],
                               texture2d<float> aoTexture           [[texture(4)]],
                               texture2d<float> alphaTexture        [[texture(5)]],
                               texture2d<float> emissiveTexture     [[texture(6)]],
                               texture2d<float> skyboxTexture       [[texture(7)]],
                               texturecube<float> irradianceMap     [[texture(8)]],
                               texturecube<float> prefilterMap      [[texture(9)]],
                               texture2d<float>   brdfLUT           [[texture(10)]],
                               depth2d<float> shadowMap [[texture(11)]]
                               ) {
    
    constexpr sampler textureSampler(address::repeat, filter::linear, mip_filter::linear,
                                     max_anisotropy(16));
    
    
    // 1. 坐标转换：透视除法
    float normalOffsetScale = 0.05; // 偏移量，视情况调节
    float3 offsetWorldPos = in.worldPos + normalize(in.worldNormal) * normalOffsetScale;
    float4 fragPosLightSpaceWithOffset = uniforms.lightSpaceMatrix * float4(offsetWorldPos, 1.0);

    float3 projCoords = fragPosLightSpaceWithOffset.xyz / fragPosLightSpaceWithOffset.w;
    
    // 2. 将 XY 从 NDC空间 [-1, 1] 映射到 UV空间 [0, 1]
    // 注意：Metal 的 Y 轴向下，所以 Y 需要翻转
    float2 shadowUV;
    shadowUV.x = projCoords.x * 0.5 + 0.5;
    shadowUV.y = -projCoords.y * 0.5 + 0.5;
    
    // 当前片段在光源视角的深度 (Metal 的 NDC Z 已经是 [0, 1] 了，直接用)
    float currentDepth = projCoords.z;
    
    // 3. 计算阴影因子 (0.0 表示完全在阴影中，1.0 表示完全被照亮)
    /// 预定义泊松圆盘 (16次采样)，用于生成均匀的高质量随机采样点
    constexpr float2 poissonDisk[16] = {
        float2( -0.94201624, -0.39906216 ), float2( 0.94558609, -0.76890725 ),
        float2( -0.094184101, -0.92938870 ), float2( 0.34495938, 0.29387760 ),
        float2( -0.91588581, 0.45771432 ), float2( -0.81544232, -0.87912464 ),
        float2( -0.38277543, 0.27676845 ), float2( 0.97484398, 0.75648379 ),
        float2( 0.44323325, -0.97511554 ), float2( 0.53742981, -0.47373420 ),
        float2( -0.26496911, -0.41893023 ), float2( 0.79197514, 0.19090188 ),
        float2( -0.24188840, 0.99706507 ), float2( -0.81409955, 0.91437590 ),
        float2( 0.19984126, 0.78641367 ), float2( 0.14383161, -0.14100790 )
    };

    // 3. 计算阴影因子 (PCSS)
    float shadow = 1.0;
    
    if (shadowUV.x >= 0.0 && shadowUV.x <= 1.0 &&
        shadowUV.y >= 0.0 && shadowUV.y <= 1.0 &&
        currentDepth <= 1.0) {
        
        // 基础 Bias，防止自阴影 (Peter Panning)
        float bias = max(0.0005 * (1.0 - dot(normalize(in.worldNormal), normalize(uniforms.lightDirection))), 0.0001);
        
        constexpr sampler depthSampler(coord::normalized, filter::nearest, address::clamp_to_edge);
        constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less);
        
        // 【可调参数】光源的物理大小，决定了最宽的半影能有多糊
        float lightSize = 0.005;
        
        // -----------------------------------------------------------
        // Step 1: Blocker Search (寻找遮挡物平均深度)
        // -----------------------------------------------------------
        int blockerCount = 0;
        float avgBlockerDepth = 0.0;
        float searchRadius = lightSize;

        for(int i = 0; i < 16; ++i) {
            float2 sampleUV = shadowUV + poissonDisk[i] * searchRadius;
            // 读取深度图里的 Z 值
            float z = shadowMap.sample(depthSampler, sampleUV);
            if(z < currentDepth - bias) {
                avgBlockerDepth += z;
                blockerCount++;
            }
        }
        
        if (blockerCount == 0) {
            // 完全没有被遮挡，直接跳过后续计算，极其省性能！
            shadow = 1.0;
        } else if (blockerCount == 16) {
            // 被完全死死遮住，处于本影区
            shadow = 0.0;
        } else {
        // -----------------------------------------------------------
        // Step 2: Penumbra Estimation (计算半影宽度)
        // -----------------------------------------------------------
            avgBlockerDepth /= float(blockerCount);
            // 平行光的半影公式：距离差越大，半影越宽
            float penumbraRatio = (currentDepth - avgBlockerDepth);
            float filterRadius = penumbraRatio * lightSize * 5.0; // 30.0 也是一个缩放系数，用来放大半影效果
            
            // -----------------------------------------------------------
            // Step 3: Dynamic PCF (动态模糊过滤)
            // -----------------------------------------------------------
            float pcfShadow = 0.0;
            for(int i = 0; i < 16; ++i) {
                float2 sampleUV = shadowUV + poissonDisk[i] * filterRadius;
                // 使用硬件加速的 sample_compare 拿到 0 或 1，并累加
                pcfShadow += shadowMap.sample_compare(shadowSampler, sampleUV, currentDepth - bias);
            }
            shadow = pcfShadow / 16.0;
        }
    }

    // === 1. 采样贴图或使用默认值 ===
    float3 albedo = float3(0.8, 0.8, 0.8);  // 默认白色
    if (!is_null_texture(albedoTexture)) {
        albedo = albedoTexture.sample(textureSampler, in.uv).rgb;
//        albedo = pow(albedo, float3(2.2));   sRGB转线性空间 !!!!加载
        //你在 C++ 里给 Albedo 设置了 MTLPixelFormatRGBA8Unorm_sRGB 格式。当 Metal 的 GPU 采样这种格式的纹理时，硬件已经自动帮你把它从 sRGB 转换成了线性空间（Linear）。
//        你在这里再 pow(albedo, 2.2)，相当于把原本正确的亮度再次强行压暗。0.5 的亮度被压成了 0.21，直接导致你的棋子看起来像烧焦了一样黑死！
    }
    
    // 法线贴图（切线空间）
    float3 normal = normalize(in.worldNormal);
    if (!is_null_texture(normalTexture)) {
        float3 tangentNormal = normalTexture.sample(textureSampler, in.uv).xyz * 2.0 - 1.0;
        
//        tangentNormal.y = -tangentNormal.y;
        
        float3x3 TBN = float3x3(
            normalize(in.worldTangent),
            normalize(in.worldBitangent),
            normalize(in.worldNormal)
        );
        normal = normalize(TBN * tangentNormal);
    }
    
    // 金属度和粗糙度（通常MetallicRoughness在一张图的不同通道）
    float metallic = 0.0;
    float roughness = 0.5;
    if (!is_null_texture(metallicTexture)) {
        metallic = metallicTexture.sample(textureSampler, in.uv).r;
    }
    
    if (!is_null_texture(roughnessTexture)) {
        roughness = roughnessTexture.sample(textureSampler, in.uv).r;
    }

    // 环境光遮蔽AO
    float ao = 1.0;
    if (!is_null_texture(aoTexture)) {
        ao = aoTexture.sample(textureSampler, in.uv).r;
    }
    
    // === 2. PBR计算准备 ===
    float3 N = normal;
    float3 V = normalize(uniforms.cameraPosition - in.worldPos);
    
    // 计算基础反射率F0（非金属约0.04，金属使用albedo）
    float3 F0 = float3(0.04);
    F0 = mix(F0, albedo, metallic);
    
    // 准备一个变量，用于累加所有光源的直接光照贡献
    float3 Lo = float3(0.0);
    
    // === 3. 遍历所有光源进行 PBR 累加 ===
    for (int i = 0; i < lightCount; ++i) {
        LightData light = lights[i];
        float type = light.position.w;
        
        float3 L;
        float attenuation = 1.0;
        float currentShadow = 1.0; // 默认没有阴影
        
        if (type < 0.5) {
            // --- 平行光 (Directional Light) ---
            L = normalize(light.direction.xyz);
            // 只有平行光使用我们在函数最前面计算出的 ShadowMap 阴影因子
            currentShadow = shadow;
        } else {
            // --- 点光源 (Point Light) ---
            float3 lightVec = light.position.xyz - in.worldPos;
            float distance = length(lightVec);
            
            // 1. 防 NaN 保护：如果距离太近，给一个默认向上的方向，避免 normalize(0)
            L = distance > 0.0001 ? (lightVec / distance) : float3(0.0, 1.0, 0.0);
            
            // 2. 防爆保护：限制灯泡的最小物理半径（比如 0.5 米）
            // 这样就算贴在灯泡表面，亮度也不会趋近于无穷大，防止 Float16 溢出
            float minRadius = 0.5;
            attenuation = 1.0 / max(distance * distance, minRadius * minRadius);
            
            currentShadow = 1.0;
        }
        
        float3 H = normalize(V + L);
        
        // --- Cook-Torrance BRDF 计算 (针对当前光源) ---
        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
        
        // 镜面反射项
        float3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        float3 specular = numerator / denominator;
        
        // 漫反射项（能量守恒：kD = 1 - kS）
        float3 kS = F;
        float3 kD = float3(1.0) - kS;
        kD *= 1.0 - metallic;  // 金属没有漫反射
        
        // Lambert漫反射
        float NdotL = max(dot(N, L), 0.0);
        float3 diffuse = kD * albedo / M_PI_F;
        
        // 当前光源的辐射率 = 颜色 * 强度 * 衰减
        float3 radiance = light.color.xyz * light.color.w * attenuation;
        
        // 累加当前光源的贡献到 Lo
        Lo += (diffuse + specular) * radiance * NdotL * currentShadow;
    }
    
    // ===  PBR 环境光 (IBL) ===
    float NdotV = max(dot(N, V), 0.0);
    constexpr sampler cubeSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSampler(filter::linear, address::clamp_to_edge);
    
    // 1. 漫反射 IBL
    // 带有粗糙度抑制的菲涅尔 (你代码里已经有了这个函数)
    float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
    float3 kS_ibl = F_ibl;
    float3 kD_ibl = 1.0 - kS_ibl;
    kD_ibl *= 1.0 - metallic;
    
    float3 irradiance = irradianceMap.sample(cubeSampler, N).rgb;
    float3 diffuseAmbient = irradiance * albedo * kD_ibl * ao;
    
    // 2. 高光 IBL
    float3 R = reflect(-V, N);
    const float MAX_REFLECTION_LOD = 4.0; // prefilterMap 的最大 Mip 级数
    float lod = roughness * MAX_REFLECTION_LOD;
    float3 prefilteredColor = prefilterMap.sample(cubeSampler, R, level(lod)).rgb;
    
    float2 envBRDF = brdfLUT.sample(lutSampler, float2(NdotV, roughness)).rg;
    float3 specularAmbient = prefilteredColor * (F_ibl * envBRDF.x + envBRDF.y) * ao;
    
    // 最终环境光
    float3 ambient = diffuseAmbient + specularAmbient;
    
    // === 最终颜色合成 ===
    // Lo 乘以曝光调节系数，你原先写的是 * 10，保持不变或提取为 uniform
    float3 color = ambient + Lo * 1;
    
    return float4(color, 1.0);
}
#pragma mark - Shadow
struct ShadowVertexOut {
    float4 position [[position]];
};

vertex ShadowVertexOut shadowVertex(VertexIn in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(1)]]) {
    ShadowVertexOut out;
    // 使用光源的 MVP 矩阵
    out.position = uniforms.lightSpaceMatrix * uniforms.modelMat * float4(in.position, 1.0);
    return out;     
}



#pragma mark - Skybox

struct SkyboxVertexIn {
    float3 position [[attribute(0)]];
};

struct SkyboxVertexOut {
    float4 position [[position]];
    float3 worldPos;  // 用于采样 cubemap 的方向向量
};

vertex SkyboxVertexOut skyboxVertex(
    SkyboxVertexIn in [[stage_in]],
    constant CameraData& camera [[buffer(1)]]
) {
    SkyboxVertexOut out;
    
    // 移除视图矩阵的平移部分（只保留旋转）
    float4x4 viewNoTranslation = camera.viewMatrix;
    viewNoTranslation[3] = float4(0.0, 0.0, 0.0, 1.0);
    
    // 变换顶点位置（skybox 跟随相机）
    float4 clipPos = camera.projectionMatrix * viewNoTranslation * float4(in.position, 1.0);
    
    // 让 skybox 永远在最远处（depth = 1.0）
    out.position = clipPos.xyww;  // 这个技巧让 z/w = 1.0
    
    // 使用顶点位置作为采样方向
    out.worldPos = in.position;
    
    return out;
}

fragment float4 skyboxFragment(
    SkyboxVertexOut in [[stage_in]],
    texture2d<float> skyboxTexture [[texture(0)]]
) {
    // 修复 1: Mipmap 必须设为 none！
    // 你的 textureutils 并没有生成 mipmaps，设为 linear 会导致未定义行为
    constexpr sampler textureSampler(
        address::repeat,
        filter::linear,
        mip_filter::none
    );
    
    float3 dir = normalize(in.worldPos);
    
    // 修复 2: 使用更标准的 atan2/acos 映射，并翻转 V 坐标
    // atan2 返回 [-π, π]，除以 2π 得到 [-0.5, 0.5]，+0.5 得到 [0, 1]
    float u = atan2(dir.z, dir.x) / (2.0 * M_PI_F) + 0.5;
    
    // dir.y 范围 [-1, 1]。acos 范围 [π, 0] (从下到上)
    // 我们需要把 +Y (天空) 映射到 V=0 (纹理顶部)
    float v = acos(dir.y) / M_PI_F;
    
    // 如果发现接缝处不对，可以尝试微调： float2 uv = float2(u, v);
    float2 uv = float2(u, v);
    
    float4 rawColor = skyboxTexture.sample(textureSampler, uv);
    
    // 修复 3: 曝光控制
    // HDR 值通常很大 (e.g. 太阳可能 > 10.0)，不乘系数直接 ToneMapping 会导致颜色过饱和
    float3 color = rawColor.rgb * 1; // 0.5 是曝光度，觉得暗可以改成 1.0，觉得亮改成 0.1
    
    return float4(color, 1.0);
}

#pragma mark - Post processing

struct VertexInOut
{
    float4 position [[position]];
    float2 uv;
};

constant float4 s_quad[] = {
    float4( -1.0f, +1.0f, 0.0f, 1.0f ),
    float4( -1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, +1.0f, 0.0f, 1.0f ),
    float4( -1.0f, +1.0f, 0.0f, 1.0f )
};

constant float2 s_quadtc[] = {
    float2( 0.0f, 0.0f ),
    float2( 0.0f, 1.0f ),
    float2( 1.0f, 1.0f ),
    float2( 1.0f, 1.0f ),
    float2( 1.0f, 0.0f ),
    float2( 0.0f, 0.0f )
};

// Fullscreen quad vertex shader.
// Used for post-processing passes.
vertex VertexInOut vertexPassthrough( uint vid [[vertex_id]] )
{
    VertexInOut o;
    o.position = s_quad[vid];
    o.uv = s_quadtc[vid];
    return o;
}

fragment float4 fragmentPassthrough( VertexInOut in [[stage_in]], texture2d< float > tin )
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    return tin.sample( s, in.uv );
}

// Bloom threshold pass.
// Extracts high-luminance pixels for bloom filtering.
fragment float4 fragmentBloomThreshold( VertexInOut in [[stage_in]],
                                       texture2d< float > tin [[texture(0)]],
                                       constant float* threshold [[buffer(0)]] )
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    float4 c = tin.sample( s, in.uv );
    
    // 计算亮度 (使用更现代的 Rec.709 亮度系数)
    float luminance = dot( c.rgb, float3( 0.2126f, 0.7152f, 0.0722f ) );
    
    // 算出超出阈值的部分 (如果没超过，excess 就是 0)
    float excess = max(0.0f, luminance - (*threshold));
    
    // 根据超出部分的比例，平滑地缩放原颜色
    // 避免除以 0 的情况
    float3 extractedColor = c.rgb * (excess / max(luminance, 0.00001f));
    
    return float4(extractedColor, 1.0f);
}


// bloom blur
kernel void gaussian_blur_x(texture2d<float, access::read> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]])
{
    // 防止越界
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    // 经典 5 采样高斯权重 (总和为 1.0)
    float weights[5] = {0.06136, 0.24477, 0.38774, 0.24477, 0.06136};
    float4 color = float4(0.0);

    // 在 X 轴上采样 5 个像素
    for (int i = -2; i <= 2; ++i) {
        // clamp 防止采样超出图片边缘
        uint2 samplePos = uint2(clamp(int(gid.x) + i, 0, int(inTexture.get_width() - 1)), gid.y);
        color += inTexture.read(samplePos) * weights[i + 2];
    }
    
    outTexture.write(color, gid);
}

kernel void gaussian_blur_y(texture2d<float, access::read> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float weights[5] = {0.06136, 0.24477, 0.38774, 0.24477, 0.06136};
    float4 color = float4(0.0);

    // 在 Y 轴上采样 5 个像素
    for (int i = -2; i <= 2; ++i) {
        uint2 samplePos = uint2(gid.x, clamp(int(gid.y) + i, 0, int(inTexture.get_height() - 1)));
        color += inTexture.read(samplePos) * weights[i + 2];
    }
    
    outTexture.write(color, gid);
}


// ACES filmic tone mapping curve.
// Converts HDR color into displayable LDR range.
static float3 ToneMapACES(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

// Final post-processing merge pass.
// Combines base color and bloom, applies exposure and tone mapping.
fragment float4 fragmentPostprocessMerge(VertexInOut in [[stage_in]],
                                         constant CameraPostParams& params [[buffer(0)]],
                                         texture2d< float > texture0 [[texture(0)]],
                                         texture2d< float > texture1 [[texture(1)]])
                                         
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    float4 t0 = texture0.sample( s, in.uv );
    float4 t1 = texture1.sample( s, in.uv );
    float3 c = t0.rgb + t1.rgb;
    c = ToneMapACES( c * params.manualExposure );
    return float4( c, 1.0f );
}


#pragma mark -- Physical Camera Stuffs
fragment float4 fragmentPostprocessPhysical(VertexInOut in [[stage_in]],
                                            constant CameraPostParams& params [[buffer(0)]],
                                            texture2d< float > texture0 [[texture(0)]],
                                            texture2d< float > texture1 [[texture(1)]])
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    float3 hdrColor = texture0.sample( s, in.uv ).rgb + texture1.sample( s, in.uv ).rgb;

    // 核心物理曝光计算
    float ev100 = log2((params.aperture * params.aperture) / params.shutterSpeed) - log2(params.iso / 100.0);
    float finalEV = ev100 - params.evComp;
    float maxLuminance = 1.2 * exp2(finalEV);
    float exposureMultiplier = 1.0 / maxLuminance;

    float3 exposedColor = hdrColor * exposureMultiplier;
    return float4( ToneMapACES(exposedColor), 1.0f );
}
