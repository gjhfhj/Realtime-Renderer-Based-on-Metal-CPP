//
//  model.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//
#include "model/model.hpp"
#include "model/texture.hpp"
#include "util/stb_image.h"
#include "util/mathutils.hpp"
#include <iostream>

#include <iomanip>
#include <sstream>


// URL 解码工具函数，专门用来把 %20 还原成空格，以及处理其他特殊字符
static std::string urlDecode(const std::string& encoded) {
    std::string decoded;
    decoded.reserve(encoded.length());
    for (size_t i = 0; i < encoded.length(); ++i) {
        if (encoded[i] == '%' && i + 2 < encoded.length()) {
            std::string hexStr = encoded.substr(i + 1, 2);
            char decodedChar = static_cast<char>(std::strtol(hexStr.c_str(), nullptr, 16));
            decoded += decodedChar;
            i += 2; // 跳过紧接着的两个十六进制字符
        } else {
            decoded += encoded[i];
        }
    }
    return decoded;
}

simd::float4x4 aiMatrixToSimd(const aiMatrix4x4& m);

Model::Model(MTL::Device* device,
             MTL::CommandQueue* commandQueue,
             const std::filesystem::path &filename,
             const simd::float3 &pos,
             const simd::float3 &rotate,
             const simd::float3 &s) {
    if (!device) {
        throw std::runtime_error("Failed to create Metal system default device");
    }
    

    Assimp::Importer importer;
    const aiScene* scene = importer.ReadFile(
        filename.c_str(),
        aiProcess_Triangulate |
        aiProcess_GenSmoothNormals |
        aiProcess_CalcTangentSpace |
        aiProcess_JoinIdenticalVertices |
        aiProcess_ImproveCacheLocality |
        aiProcess_ValidateDataStructure |  // 新增：验证数据
        aiProcess_OptimizeMeshes |         // 新增：优化网格
        aiProcess_FlipUVs |                // 新增：翻转 UV（Metal 坐标系）
        aiProcess_SortByPType              // 新增：按类型排序
    );
    if (!scene) {
        std::cerr << "Assimp 加载 " << filename << " 失败: " << importer.GetErrorString() << std::endl;
        throw std::runtime_error(importer.GetErrorString());  // 改为抛异常，便于上层捕获
    }
    
    name = filename.stem();
    modelDir = filename.parent_path().string() + "/";
    modelMatrix =   translate(pos) *
                    rotateZ(radians(rotate.z)) *
                    rotateY(radians(rotate.y)) *
                    rotateX(radians(rotate.x)) *
                    scale(s);
    std::map<std::string, aiLight*> lightMap;
    if (scene->HasLights()) {
        std::cout << "检测到光源数量: " << scene->mNumLights << "\n";
        for (unsigned int i = 0; i < scene->mNumLights; i++) {
            lightMap[scene->mLights[i]->mName.C_Str()] = scene->mLights[i];
        }
    }
    std::cout << "\nNow loading " << name << "\n";
    
#pragma  mark - Process Material
    
    materials.resize(scene->mNumMaterials);
    for (unsigned int i = 0; i < scene->mNumMaterials; i++) {
        aiMaterial* aiMat = scene->mMaterials[i];
        PBRMaterial& mat = materials[i];
        
        // 1. 基础参数（如果没有贴图时使用）
        aiColor4D color;
        if (AI_SUCCESS == aiGetMaterialColor(aiMat, AI_MATKEY_BASE_COLOR, &color)) {  // PBR base color (glTF/FBX)
            mat.albedo = {color.r, color.g, color.b};
        } else if (AI_SUCCESS == aiGetMaterialColor(aiMat, AI_MATKEY_COLOR_DIFFUSE, &color)) {  // 后备 diffuse
            mat.albedo = {color.r, color.g, color.b};
        }
        aiGetMaterialFloat(aiMat, AI_MATKEY_METALLIC_FACTOR, &mat.metallic);        // PBR metallic
        aiGetMaterialFloat(aiMat, AI_MATKEY_ROUGHNESS_FACTOR, &mat.roughness);      // PBR roughness
        aiGetMaterialFloat(aiMat, AI_MATKEY_OPACITY, &mat.alpha);                   // PBR alpha
        // 无ao MATKEY词条                                                           // PBR AO
        if (AI_SUCCESS == aiGetMaterialColor(aiMat, AI_MATKEY_COLOR_EMISSIVE, &color)) {
            mat.emissive = {color.r, color.g, color.b};                             // PBR emissive
        }
        
        // 2. 贴图路径（Metallic-Roughness 映射）
        aiString path;
        
        // 提取材质自身的名称（如果建模软件里命名了的话）
        aiString aiMatName;
        aiMat->Get(AI_MATKEY_NAME, aiMatName);
        std::string matNameStr = (aiMatName.length > 0) ? aiMatName.C_Str() : "Unnamed";

        // 将模型名称(name)、材质索引(i)和材质名称一起打印
        std::cout << "------\n";
        std::cout << "Model [" << name << "] -> Material[" << i << "] <" << matNameStr << ">:\n";
        
        // Albedo / Base Color / Diffuse Color
        if (aiMat->GetTextureCount(aiTextureType_BASE_COLOR) > 0) {  // glTF PBR
            aiMat->GetTexture(aiTextureType_BASE_COLOR, 0, &path);
            mat.albedoMap = modelDir + normalizePath(path.C_Str());
        } else if (aiMat->GetTextureCount(aiTextureType_DIFFUSE) > 0) {  // 后备 diffuse
            aiMat->GetTexture(aiTextureType_DIFFUSE, 0, &path);
            mat.albedoMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "AlbedoMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Albedo路径\n";
        

        // Normal Map
        if (aiMat->GetTextureCount(aiTextureType_NORMAL_CAMERA) > 0) {  // PBR normal
            aiMat->GetTexture(aiTextureType_NORMAL_CAMERA, 0, &path);
            mat.normalMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "NormalMap:" << normalizePath(path.C_Str()) << '\n';
        } else if (aiMat->GetTextureCount(aiTextureType_NORMALS) > 0 ||
                   aiMat->GetTextureCount(aiTextureType_HEIGHT) > 0) {  // 后备
            aiMat->GetTexture(aiMat->GetTextureCount(aiTextureType_NORMALS) > 0 ? aiTextureType_NORMALS : aiTextureType_HEIGHT, 0, &path);
            mat.normalMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "NormalMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Normal路径\n";
        
        // Metal Map
        if (aiMat->GetTextureCount(aiTextureType_METALNESS) > 0) {
            aiMat->GetTexture(aiTextureType_METALNESS, 0, &path);
            mat.metallicMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "MetallicMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Metallic路径\n";
        
        // Roughness Map
        if (aiMat->GetTextureCount(aiTextureType_DIFFUSE_ROUGHNESS) > 0) {
            aiMat->GetTexture(aiTextureType_DIFFUSE_ROUGHNESS, 0, &path);
            mat.roughnessMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "RoughnessMap:" << normalizePath(path.C_Str()) << '\n';
        } else if (aiMat->GetTextureCount(aiTextureType_SHININESS) > 0) {  // 备用
            aiMat->GetTexture(aiTextureType_SHININESS, 0, &path);
            mat.roughnessMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "RoughnessMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Roughness路径\n";
        // Ambient Occlusion Map
        if (aiMat->GetTextureCount(aiTextureType_AMBIENT_OCCLUSION) > 0) {
            aiMat->GetTexture(aiTextureType_AMBIENT_OCCLUSION, 0, &path);
            mat.ambientOcclusionMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "AmbientOcclusionMap:" <<mat.ambientOcclusionMap << '\n';
        } else if (aiMat->GetTextureCount(aiTextureType_LIGHTMAP) > 0) {  // 后备 lightmap 作为 AO
            aiMat->GetTexture(aiTextureType_LIGHTMAP, 0, &path);
            mat.ambientOcclusionMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "AmbientOcclusionMap:" <<mat.ambientOcclusionMap << '\n';
        } else std::cout << "没有货渠道AO路径\n";
        
        // Alpha/Opacity Map
        if (aiMat->GetTextureCount(aiTextureType_OPACITY) > 0) {
            aiMat->GetTexture(aiTextureType_OPACITY, 0, &path);
            mat.alphaMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "AlphaMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Alpha路径\n";
        
        // Emissive
        if (aiMat->GetTextureCount(aiTextureType_EMISSIVE) > 0) {
            aiMat->GetTexture(aiTextureType_EMISSIVE, 0, &path);
            mat.emissiveMap = modelDir + normalizePath(path.C_Str());
            std::cout<< "EmissiveMap:" << normalizePath(path.C_Str()) << '\n';
        } else std::cout << "没有货渠道Emissive路径\n";
        
        
        // 如果 ORM 贴图是合并的（R=AO, G=roughness, B=metallic），你可以在这里检测并设置 mat.metallicRoughnessMap = ormPath; mat.ambientOcclusionMap = ""; 但 Assimp 通常分开解析
    }
    loadTextures(device, commandQueue, scene);
    
#pragma mark - Process Vertex and Index
    
    vertices.reserve(10000);  // 根据模型大小调整
    indices.reserve(30000);
    
    simd::float4x4 identity = matrix_identity_float4x4;
    ProcessNode(scene->mRootNode, scene, identity, lightMap);
    
    if (vertices.empty() || indices.empty()) {
        std::cerr << "Error: Model '" << name << "' failed to load vertices/indices" << std::endl;
        vertexBuffer = nullptr;
        indexBuffer = nullptr;
        return;
    }
    
    if (!vertices.empty()) {
        indexCount = indices.size();
        vertexBuffer = device->newBuffer(vertices.data(), vertices.size() * sizeof(Vertex), MTL::ResourceStorageModeShared);
        indexBuffer = device->newBuffer(indices.data(), indices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
    }

    
    indices.clear(); indices.shrink_to_fit();
    vertices.clear(); vertices.shrink_to_fit();
    device->release();
}

void Model::ProcessNode(aiNode* node, const aiScene* scene, const simd::float4x4& parentTransform, const std::map<std::string, aiLight*> &lightMap) {
    // 1. 计算当前节点的世界变换 = 父变换 * 局部变换
    simd::float4x4 localTransform = aiMatrixToSimd(node->mTransformation);
    simd::float4x4 worldTransform = parentTransform * localTransform;
    
//    std::cout << "Node: " << node->mName.C_Str() << "\n";
//    std::cout << "  Position: ("
//              << worldTransform.columns[3].x << ", "
//              << worldTransform.columns[3].y << ", "
//              << worldTransform.columns[3].z << ")\n";
    
    // 插入一个便利光源的
    std::string nodeName = node->mName.C_Str();
    auto it = lightMap.find(nodeName);
    if (it != lightMap.end()) {
        aiLight* aiL = it->second; // 直接从迭代器获取 value
        LightData ld;
        // 判定光源类型 (w分量)
        if (aiL->mType == aiLightSource_DIRECTIONAL) ld.position.w = 0.0f;
        else if (aiL->mType == aiLightSource_POINT) ld.position.w = 1.0f;
        else ld.position.w = 2.0f; // SPOT 暂时当作点光源处理
        
        // 颜色和强度 (由于 Blender 导出的强度常常过大或过小，你可以乘以一个缩放系数，这里暂定放大倍数)
        // 很多时候 mColorDiffuse 里带了强度，或者可以在 Blender 里通过 emissive 调节
        ld.color = {aiL->mColorDiffuse.r, aiL->mColorDiffuse.g, aiL->mColorDiffuse.b, 1.0f}; // 初始给个强度 100
        
        // 解析局部坐标/方向并乘以当前 Node 的世界矩阵
        simd::float4 localPos = {aiL->mPosition.x, aiL->mPosition.y, aiL->mPosition.z, 1.0f}; // 位置的 w=1
        simd::float4 localDir = {aiL->mDirection.x, aiL->mDirection.y, aiL->mDirection.z, 0.0f}; // 向量的 w=0
        
        simd::float4 worldPos = worldTransform * localPos;
        simd::float4 worldDir = worldTransform * localDir;
        
        ld.position.x = worldPos.x; ld.position.y = worldPos.y; ld.position.z = worldPos.z;
        ld.direction.x = worldDir.x; ld.direction.y = worldDir.y; ld.direction.z = worldDir.z;
        
        lights.push_back(ld);
        std::cout << "已加载光源: " << nodeName << " 类型: " << ld.position.w << "\n";
    }
    
    
    
    // 2. 处理当前节点的所有网格,传入世界变换
    for (unsigned i = 0; i < node->mNumMeshes; i++) {
        aiMesh* mesh = scene->mMeshes[node->mMeshes[i]];
        ProcessMesh(mesh, scene, worldTransform);
    }
    
    // 3. 递归处理子节点,传入当前世界变换作为子节点的父变换
    for (unsigned i = 0; i < node->mNumChildren; i++) {
        ProcessNode(node->mChildren[i], scene, worldTransform, lightMap);  // ← 关键!
    }
}
void Model::ProcessMesh(aiMesh* mesh, const aiScene* scene, const simd::float4x4& worldTransform) {
    Submesh sub;
    sub.name = mesh->mName.C_Str();
    sub.indexOffset = static_cast<uint32_t>(indices.size());
    sub.materialIndex = mesh->mMaterialIndex;
    sub.nodeTransform = worldTransform;
    
    uint32_t baseVertex = static_cast<uint32_t>(vertices.size());
    
    // vertex
    for (unsigned i = 0; i < mesh->mNumVertices; i++) {
        Vertex v;
        v.position = { mesh->mVertices[i].x, mesh->mVertices[i].y, mesh->mVertices[i].z };
        
        if (mesh->HasNormals()) {
            v.normal = { mesh->mNormals[i].x, mesh->mNormals[i].y, mesh->mNormals[i].z };
        } else {
            v.normal = {0.0f, 0.0f, 0.0f};
        }
        
        if (mesh->HasTangentsAndBitangents()) {
            v.tangent = { mesh->mTangents[i].x, mesh->mTangents[i].y, mesh->mTangents[i].z };
            v.bitangent = { mesh->mBitangents[i].x, mesh->mBitangents[i].y, mesh->mBitangents[i].z };
        } else {
            v.tangent = {0.0f, 0.0f, 0.0f};
            v.bitangent = {0.0f, 0.0f, 0.0f};
        }
        
        if (mesh->mTextureCoords[0]) {
            v.uv = { mesh->mTextureCoords[0][i].x, mesh->mTextureCoords[0][i].y };
        } else {
            v.uv = {0.0f, 0.0f};
        }
        
        if (mesh->HasVertexColors(0)) {
            v.color = { mesh->mColors[0][i].r, mesh->mColors[0][i].g, mesh->mColors[0][i].b, mesh->mColors[0][i].a };
        } else {
            v.color = {1.0f, 1.0f, 1.0f, 1.0f};
        }
        vertices.push_back(v);
    }
    
    for (unsigned i = 0; i < mesh->mNumFaces; i++) {
        aiFace face = mesh->mFaces[i];
        for (unsigned j = 0; j < face.mNumIndices; j++) {
            indices.push_back(baseVertex + face.mIndices[j]);  // ← 使用 baseVertex
        }
    }
    
    sub.indexCount = static_cast<uint32_t>(indices.size()) - sub.indexOffset;
    submeshes.push_back(sub);
}

void Model::loadTextures(MTL::Device* device, MTL::CommandQueue* commandQueue, const aiScene* scene) {    for (size_t i = 0; i < materials.size(); i++) {
        PBRMaterial& mat = materials[i];
        aiMaterial* aiMat = scene->mMaterials[i];
        
        auto loadTexture = [&](const std::string& texPath,
                               MTL::Texture** outTexture,
                               aiTextureType type,
                               bool isSRGB) {
            std::string resolvedPath = resolveTexturePath(
                texPath, modelDir, scene, aiMat, type, 0
            );
            
            if (resolvedPath.empty()) return;
                           
            // 嵌入纹理
            if (!resolvedPath.empty() && resolvedPath[0] == '*') {
                *outTexture = loadEmbeddedTexture(device, commandQueue, scene, resolvedPath, isSRGB);
                return;
            }
            
            auto colorSpace = isSRGB ? TextureLoader::ColorSpace::SRGB
                                                     : TextureLoader::ColorSpace::LINEAR;
            
            *outTexture = TextureLoader::load(device, commandQueue, resolvedPath, colorSpace, true);
            
            if (*outTexture) {
                std::cout << "✓ Loaded: " << std::filesystem::path(resolvedPath).filename()
                          << " (" << (*outTexture)->width() << "x" << (*outTexture)->height() << ")"
                          << std::endl;
            }
        };
        
        loadTexture(mat.albedoMap, &mat.albedoTexture,
                   aiTextureType_BASE_COLOR, true);   // sRGB
        loadTexture(mat.normalMap, &mat.normalTexture,
                   aiTextureType_NORMAL_CAMERA, false); // Linear
        loadTexture(mat.metallicMap, &mat.metallicTexture,
                   aiTextureType_METALNESS, false);
        loadTexture(mat.roughnessMap, &mat.roughnessTexture,
                   aiTextureType_DIFFUSE_ROUGHNESS, false);
        loadTexture(mat.ambientOcclusionMap, &mat.aoTexture,
                   aiTextureType_AMBIENT_OCCLUSION, false);
        loadTexture(mat.alphaMap, &mat.alphaTexture,
                   aiTextureType_OPACITY, false);
        loadTexture(mat.emissiveMap, &mat.emissiveTexture,
                   aiTextureType_EMISSIVE, true);
    }
}


std::string Model::resolveTexturePath(const std::string& texturePath,
                                      const std::string& modelDir,
                                      const aiScene* scene,
                                      const aiMaterial* material,
                                      aiTextureType type,
                                      unsigned int index) {
    // 1. 检查是否是嵌入纹理（路径格式如 "*0", "*1"）
    if (!texturePath.empty() && texturePath[0] == '*') {
        return texturePath;
    }
    
    // 2. 如果路径为空，尝试从材质获取
    std::string path = texturePath;
    if (path.empty()) {
        aiString aiPath;
        if (material->GetTexture(type, index, &aiPath) == AI_SUCCESS) {
            path = aiPath.C_Str();
        } else {
            return "";  // 没有纹理
        }
    }
    
    path = urlDecode(path);
    
    // 3. 检查是否是嵌入纹理标记
    if (!path.empty() && path[0] == '*') {
        return path;
    }
    
    // 4. 构建可能的路径列表（按优先级）
    std::vector<std::string> possiblePaths;
    std::string baseName = std::filesystem::path(path).filename().string();
    
    // a. 原始路径（可能是相对或绝对）
    possiblePaths.push_back(path);
    
    // b. 模型目录 + 原始路径
    possiblePaths.push_back(modelDir + path);
    
    // c. 模型目录 + 文件名（忽略子路径）
    possiblePaths.push_back(modelDir + baseName);
    
    // d. 模型目录 + textures/ + 文件名
    possiblePaths.push_back(modelDir + "textures/" + baseName);
    possiblePaths.push_back(modelDir + "Textures/" + baseName);
    
    // e. 模型目录 + texture/ + 文件名
    possiblePaths.push_back(modelDir + "texture/" + baseName);
    possiblePaths.push_back(modelDir + "Texture/" + baseName);
    
    // f. 模型目录 + maps/ + 文件名
    possiblePaths.push_back(modelDir + "maps/" + baseName);
    possiblePaths.push_back(modelDir + "Maps/" + baseName);
    
    // e. source  texutres
    possiblePaths.push_back(modelDir + "//textures" + baseName);
    possiblePaths.push_back(modelDir + "//Trextures" + baseName);
    

    
    // 5. 检查哪个路径存在
    for (const auto& p : possiblePaths) {
        if (std::filesystem::exists(p)) {
            return p;
        }
    }
    
    // 6. 都不存在，输出警告
    std::cerr << "Warning: Texture not found: " << path
              << " (tried " << possiblePaths.size() << " locations)" << std::endl;
    return "";
}

MTL::Texture* Model::loadEmbeddedTexture(MTL::Device* device,
                                         MTL::CommandQueue* commandQueue,
                                         const aiScene* scene,
                                         const std::string& embeddedPath,
                                         bool isSRGB) {
    // 解析嵌入纹理索引（格式 "*0", "*1" 等）
    if (embeddedPath.empty() || embeddedPath[0] != '*') {
        return nullptr;
    }
    
    unsigned int index = std::stoi(embeddedPath.substr(1));
    if (index >= scene->mNumTextures) {
        std::cerr << "Error: Embedded texture index out of range: " << index << std::endl;
        return nullptr;
    }
    
    const aiTexture* aiTex = scene->mTextures[index];
    
    int width, height, channels;
    unsigned char* data = nullptr;
    
    // 检查纹理是否是压缩格式（如 PNG, JPG）
    if (aiTex->mHeight == 0) {
        // 压缩格式，需要解码
        data = stbi_load_from_memory(
            reinterpret_cast<unsigned char*>(aiTex->pcData),
            aiTex->mWidth,  // mWidth 在这里表示数据大小
            &width, &height, &channels, 4
        );
    } else {
        // 未压缩的原始 RGBA 数据
        width = aiTex->mWidth;
        height = aiTex->mHeight;
        channels = 4;
        
        // 直接复制数据（aiTexture 使用 ARGB8888 格式）
        data = new unsigned char[width * height * 4];
        for (int i = 0; i < width * height; i++) {
            const aiTexel& texel = aiTex->pcData[i];
            data[i * 4 + 0] = texel.r;
            data[i * 4 + 1] = texel.g;
            data[i * 4 + 2] = texel.b;
            data[i * 4 + 3] = texel.a;
        }
    }
    
    if (!data) {
        std::cerr << "Error: Failed to decode embedded texture " << index << std::endl;
        return nullptr;
    }
    
    uint32_t mipLevels = static_cast<uint32_t>(std::floor(std::log2(std::max(width, height)))) + 1;
        
        MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
        desc->setTextureType(MTL::TextureType2D);
        desc->setPixelFormat(isSRGB ? MTL::PixelFormatRGBA8Unorm_sRGB : MTL::PixelFormatRGBA8Unorm);
        desc->setWidth(width);
        desc->setHeight(height);
        desc->setMipmapLevelCount(mipLevels); // <--- 设置层数
        desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite); // 必须开启 Write 才能生成
        
        MTL::Texture* texture = device->newTexture(desc);
        if (texture) {
            MTL::Region region = MTL::Region::Make2D(0, 0, width, height);
            texture->replaceRegion(region, 0, data, width * 4);
            
            // 🚨 呼叫 GPU 生成 Mipmap
            if (mipLevels > 1 && commandQueue != nullptr) {
                MTL::CommandBuffer* cmd = commandQueue->commandBuffer();
                cmd->setLabel(NS::String::string("Generate Embedded Mipmaps", NS::ASCIIStringEncoding));
                MTL::BlitCommandEncoder* blit = cmd->blitCommandEncoder();
                blit->generateMipmaps(texture);
                blit->endEncoding();
                cmd->commit();
                cmd->waitUntilCompleted();
            }
        }
        
        // 清理
        if (aiTex->mHeight == 0) {
            stbi_image_free(data);
        } else {
            delete[] data;
        }
        desc->release();
        
        return texture;
}

MTL::VertexDescriptor* Model::createVertexDescriptor() {
    auto* desc = MTL::VertexDescriptor::alloc()->init();

    // position
    desc->attributes()->object(0)->setFormat(MTL::VertexFormatFloat3);
    desc->attributes()->object(0)->setOffset(0);
    desc->attributes()->object(0)->setBufferIndex(0);

    // normal
    desc->attributes()->object(1)->setFormat(MTL::VertexFormatFloat3);
    desc->attributes()->object(1)->setOffset(sizeof(simd::float3));
    desc->attributes()->object(1)->setBufferIndex(0);

    // tangent
    desc->attributes()->object(2)->setFormat(MTL::VertexFormatFloat3);
    desc->attributes()->object(2)->setOffset(sizeof(simd::float3) * 2);
    desc->attributes()->object(2)->setBufferIndex(0);

    // bitangent
    desc->attributes()->object(3)->setFormat(MTL::VertexFormatFloat3);
    desc->attributes()->object(3)->setOffset(sizeof(simd::float3) * 3);
    desc->attributes()->object(3)->setBufferIndex(0);

    // uv
    desc->attributes()->object(4)->setFormat(MTL::VertexFormatFloat2);
    desc->attributes()->object(4)->setOffset(sizeof(simd::float3) * 4);
    desc->attributes()->object(4)->setBufferIndex(0);

    // color
    desc->attributes()->object(5)->setFormat(MTL::VertexFormatFloat4);
    desc->attributes()->object(5)->setOffset(sizeof(simd::float3) * 4 + sizeof(simd::float2));
    desc->attributes()->object(5)->setBufferIndex(0);

    // layout
    desc->layouts()->object(0)->setStride(sizeof(Vertex));
    desc->layouts()->object(0)->setStepFunction(MTL::VertexStepFunctionPerVertex);

    return desc;
}

simd::float4x4 Model::setModelMatrix(const simd::float3 &pos,
                                     const simd::float3 &rotate,
                                     const simd::float3 &s) const {
    return translate(pos) *
        rotateZ(radians(rotate.z)) *
        rotateY(radians(rotate.y)) *
        rotateX(radians(rotate.x)) *
        scale(s);
}

Model::~Model() {
    if (vertexBuffer) vertexBuffer->release();
    if (indexBuffer) indexBuffer->release();
    for (auto& mat : materials) {
        if (mat.albedoTexture) mat.albedoTexture->release();
        if (mat.normalTexture) mat.normalTexture->release();
        if (mat.metallicTexture) mat.metallicTexture->release();
        if (mat.roughnessTexture) mat.roughnessTexture->release();
        if (mat.aoTexture) mat.aoTexture->release();
        if (mat.alphaTexture) mat.alphaTexture->release();
        if (mat.emissiveTexture) mat.emissiveTexture->release();
    }
}

Model::Model(const Model& other) {
    name = other.name;
    modelDir    = other.modelDir;
    submeshes   = other.submeshes;
    indexCount  = other.indexCount;
    materials   = other.materials;
    modelMatrix = other.modelMatrix;
    lights      = other.lights;

    materials.reserve(other.materials.size());
    for (const auto& otherMat : other.materials) {
        PBRMaterial mat = otherMat;  // 拷贝 scalars 和 strings
        // retain 纹理指针（如果已加载）
        if (otherMat.albedoTexture) mat.albedoTexture = otherMat.albedoTexture->retain();
        if (otherMat.normalTexture) mat.normalTexture = otherMat.normalTexture->retain();
        if (otherMat.metallicTexture) mat.metallicTexture = otherMat.metallicTexture->retain();
        if (otherMat.roughnessTexture) mat.roughnessTexture = otherMat.roughnessTexture->retain();
        if (otherMat.aoTexture) mat.aoTexture = otherMat.aoTexture->retain();
        if (otherMat.alphaTexture) mat.alphaTexture = otherMat.alphaTexture->retain();
        if (otherMat.emissiveTexture) mat.emissiveTexture = otherMat.emissiveTexture->retain();
        materials.push_back(mat);
    }
    
    if (other.vertexBuffer && other.indexBuffer) {
        auto* device = MTL::CreateSystemDefaultDevice();
        
        // 深拷贝 buffer
        vertexBuffer = device->newBuffer(
            other.vertexBuffer->contents(),
            other.vertexBuffer->length(),
            MTL::ResourceStorageModeShared
        );
        
        indexBuffer = device->newBuffer(
            other.indexBuffer->contents(),
            other.indexBuffer->length(),
            MTL::ResourceStorageModeShared
        );
        
        device->release();
    }
}


simd::float4x4 aiMatrixToSimd(const aiMatrix4x4& m) {
    return simd::float4x4 {
        simd::make_float4(m.a1, m.b1, m.c1, m.d1),
        simd::make_float4(m.a2, m.b2, m.c2, m.d2),
        simd::make_float4(m.a3, m.b3, m.c3, m.d3),
        simd::make_float4(m.a4, m.b4, m.c4, m.d4)
    };
}
