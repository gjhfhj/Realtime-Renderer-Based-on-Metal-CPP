//
//  scene.cpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/17.
//

#include "model/scene.hpp"

void Scene::addModelInstance(const Model &model, const simd::float4x4 &matrix) {
    size_t modelIdx = findOrAddModel(model);
    instances.push_back(ModelInstance{modelIdx, matrix});
}

void Scene::addModelInstance(const Model &model) {
    size_t modelIdx = findOrAddModel(model);
    instances.push_back(ModelInstance(modelIdx, model.getModelMatrix()));
}


size_t Scene::findOrAddModel(const Model &model) {
    // 找不同
    for(size_t i = 0; i < models.size(); i++) {
        if(model.name == models[i].name) {
            return i;
        }
    }
    // 不存在则添加新模型
    models.push_back(model);
    return models.size() - 1;
}


//void Scene::addModel(const Model &model,
//                     const simd::float3 &pos,
//                     const simd::float3 &rotate,
//                     const simd::float3 &scale) {
//    
//    bool different = true;
//    size_t index = 0;
//    for(size_t i  = 0; i < instances.size(); i++) {
//        if( model.name == models[i].name ) {
//            different = false;
//            index = i;
//            break;
//        }
//    }
//    
//    float4x4 modelMatrix = getModelMatrix(pos, rotate, scale);
//    
//    if(different) {
//        models.push_back(model);
//        instances.push_back(ModelInstance{models.size()-1, modelMatrix});
//    }else {
//        instances.push_back(ModelInstance{index, modelMatrix});
//    }
//}
