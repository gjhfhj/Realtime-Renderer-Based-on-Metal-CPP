//
//  scene.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//

#pragma once

#include <simd/simd.h>
#include "model.hpp"

struct ModelInstance {
    size_t modelIndex;
    simd::float4x4 modelMatrix;
};

class Scene {
public:
    void addModelInstance(const Model &model);
    void addModelInstance(const Model &model,
                          const simd::float4x4 &matrix);
    
    void draw();
    void updateState() = delete; //暂时保持静态
    
    const std::vector<Model>& getModels() const { return models; }
    const std::vector<ModelInstance>& getInstances() const { return instances; }
    const Model& getModel(size_t index) const { return models[index]; }
private:
    size_t findOrAddModel(const Model &model);
private:
    std::vector<Model> models {}; //
    std::vector<ModelInstance> instances {};
    
};
