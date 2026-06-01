//
//  metalview.hpp
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/16.
//
#ifndef METALVIEW_HPP
#define METALVIEW_HPP

#ifdef __OBJC__
@class NSApplication;
@class NSWindow;
@class NSView;
@class CAMetalLayer;
#else
class NSApplication;
class NSWindow;
class NSView;
class CAMetalLayer;
#endif

#include <functional>

// MetalViewWrapper：C++ 侧的窗口与平台封装类
// 对外提供：
// - 获取 CAMetalLayer
// - 设置输入回调
// - 启动事件循环
class MetalViewWrapper {
public:

    MetalViewWrapper(int width, int height);
    
    NSApplication* getApp() const { return _app; }
    NSView* getView() const {return _view; }
    CAMetalLayer* getLayer() const { return _layer; }
    
    
    // 设置 C++ 风格的输入回调（由 ObjC 事件触发）
    void setKeyCallback(std::function<void(int key, bool isPressed)> callback) { onKey = callback; }
    void setMouseMoveCallback(std::function<void(int x,int y)> callback) { onMouseMove = callback; }
    void setRenderCallback(std::function<void()> callback) { onRenderFrame = callback; }
    
    void setMouseCaptured(bool captured);
    bool isMouseCaptured() const { return _mouseCaptured; }
    void getWindowCenter(int& x, int& y);
    
    // 启动主事件循环（阻塞调用）
    // 通常在 main 中最后调用
    void run();
    
    

private:
    NSApplication* _app = nullptr;
    NSWindow* _window = nullptr;
    NSView* _view = nullptr;
    CAMetalLayer* _layer = nullptr;
    bool _mouseCaptured = false;

public:
    // 回调
    std::function<void(int, bool)> onKey;
    std::function<void(int,int)> onMouseMove;
    std::function<void()> onRenderFrame;
    
};

#endif // METALVIEW_HPP

//C++ main
// └── MetalViewWrapper
//      ├── NSApplication
//      ├── NSWindow
//      ├── MetalView (NSView)
//      │    └── CAMetalLayer
//      │         └── CAMetalDrawable
//      └── 输入事件 → C++ 回调
