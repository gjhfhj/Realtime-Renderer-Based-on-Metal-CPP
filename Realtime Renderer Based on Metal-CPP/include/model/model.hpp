//
//  model.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//

#pragma once

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <Metal/Metal.hpp>
#include <vector>
#include <filesystem>
#include <string>
#include <simd/simd.h>
#include <map>
//aiScene (场景根)
//├── mMeshes[] (网格数组)
//│   ├── mVertices[] (顶点位置)
//│   ├── mNormals[] (顶点法线)
//│   ├── mTangents[] (切线)
//│   ├── mTextureCoords[] (UV坐标)
//│   ├── mFaces[] (面/三角形)
//│   └── mMaterialIndex (指向材质的索引)
//│
//├── mMaterials[] (材质数组)
//│   ├── 基础颜色/Albedo
//│   ├── 金属度/粗糙度
//│   └── 纹理路径引用
//│
//└── mTextures[] (嵌入纹理数组，可选)
//    └── 二进制图像数据

struct Vertex {
    simd::float3 position;
    simd::float3 normal;
    simd::float3 tangent;
    simd::float3 bitangent;
    simd::float2 uv;
    simd::float4 color;
};

struct LightData {
    simd::float4 position;
    simd::float4 color;
    simd::float4 direction;
};

struct PBRMaterial {
    simd::float3 albedo      = {1.0f, 1.0f, 1.0f};
    float        metallic    = 0.0f;
    float        roughness   = 0.5f;
    float        ao          = 1.0f;
    float        alpha       = 1.0f;
    simd::float3 emissive    = {0.0f, 0.0f, 0.0f};

    std::string albedoMap;
    std::string normalMap;
    std::string metallicMap;
    std::string roughnessMap;
    std::string ambientOcclusionMap;
    std::string alphaMap;
    std::string emissiveMap;
    
    MTL::Texture* albedoTexture      = nullptr;
    MTL::Texture* normalTexture      = nullptr;
    MTL::Texture* metallicTexture    = nullptr;
    MTL::Texture* roughnessTexture   = nullptr;
    MTL::Texture* aoTexture          = nullptr;
    MTL::Texture* alphaTexture       = nullptr;
    MTL::Texture* emissiveTexture    = nullptr;
    
    bool isTransparent() const {
        return alpha < 1.0f || alphaTexture != nullptr;
    }
};

struct Submesh {
    std::string name;
    uint32_t    indexOffset;
    uint32_t    indexCount;
    uint32_t    materialIndex;
    simd::float4x4 nodeTransform;
};

class Model {
public:
    Model(MTL::Device* device,
          MTL::CommandQueue* commandQueue,
          const std::filesystem::path &filename = "",
          const simd::float3 &pos = {0.f, 0.f, 0.f},
          const simd::float3 &rotate = {0.f, 0.f, 0.f},
          const simd::float3 &scale = {1.f, 1.f, 1.f});
    ~Model();
    
    // 深拷贝 应对scene.addModel, 否则other里头的指针成了野指针
    Model(const Model& other);
    static MTL::VertexDescriptor* createVertexDescriptor();

    simd::float4x4 setModelMatrix(const simd::float3 &pos,const simd::float3 &rotate,const simd::float3 &s) const;
    
    inline MTL::Buffer* getVertexBuffer() const { return vertexBuffer; }
    inline MTL::Buffer* getIndexBuffer() const { return indexBuffer; }
    inline size_t getIndexCount() const { return indexCount; }
    inline const std::vector<LightData>& getLights() const { return lights; }
    
    inline simd::float4x4 &getModelMatrix() {return modelMatrix; }
    inline const simd::float4x4 &getModelMatrix() const {return modelMatrix; }
    inline std::vector<Submesh> &getSubmeshes() {return submeshes; }
    inline const std::vector<Submesh> &getSubmeshes() const {return submeshes; }
    inline const std::vector<PBRMaterial>& getMaterials() const { return materials; }
    inline const PBRMaterial& getMaterial(size_t subIndex) const { return materials[subIndex]; }
public:
    std::string name;
    std::string modelDir;
    std::vector<Submesh> submeshes;
private:
    size_t indexCount = 0;
    MTL::Buffer* vertexBuffer = nullptr;
    MTL::Buffer* indexBuffer = nullptr;
    std::vector<PBRMaterial> materials;
    std::vector<LightData> lights;
private:
    void ProcessNode(aiNode* node, const aiScene* scene, const simd::float4x4& parentTransform,const std::map<std::string, aiLight*> &lightMap);
    void ProcessMesh(aiMesh* mesh, const aiScene* scene, const simd::float4x4& worldTransform);
    void loadTextures(MTL::Device* device, MTL::CommandQueue* commandQueue, const aiScene* scene);
    std::string resolveTexturePath(const std::string& texturePath,
                                   const std::string& modelDir,
                                   const aiScene* scene,
                                   const aiMaterial* material,
                                   aiTextureType type,
                                   unsigned int index);
    MTL::Texture* loadEmbeddedTexture(MTL::Device* device,
                                      MTL::CommandQueue* commandQueue,
                                      const aiScene* scene,
                                      const std::string& embeddedPath,
                                      bool isSRGB);
private:
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    simd::float4x4 modelMatrix {};
};



//// 第1步: 读取文件
//const aiScene* scene = importer.ReadFile(filename, flags);
//
//// 第2步: 遍历节点树(递归)
//ProcessNode(scene->mRootNode, scene);
//    └──> 对每个节点的 mesh
//         └──> ProcessMesh(mesh, scene)
//              ├── 提取顶点数据 (位置、法线、UV等)
//              ├── 提取索引数据 (三角形)
//              └── 记录材质索引
//
//// 第3步: 处理材质
//for (每个材质) {
//    提取颜色值 (albedo, metallic, roughness)
//    提取纹理路径 (diffuse, normal, roughness等)
//}
//
//// 第4步: 加载纹理
//loadTextures() // 根据路径加载图片文件
