//
//  metalview.mm
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/1/15.
//
#import <AppKit/AppKit.h>           // 提供窗口、事件、NSApplication、NSWindow、NSView 等。
#import <QuartzCore/CAMetalLayer.h> // 提供CAMetalLayer（Metal 的渲染层）。
#import <Metal/Metal.h>             // 原生的 Objective-C Metal 接口（ID<MTLDevice> 等）。

#import "metalview.hpp"

// AppDelegate：最小化的 macOS 应用代理
// 作用：
//  - 告诉 AppKit 这是一个“合法的 App”，从而启用完整事件系统
//  - 处理窗口关闭后的退出逻辑
@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
// 当最后一个窗口被关闭时，返回 YES 表示自动退出应用
// 如果没有这个方法：关窗口 ≠ 程序退出
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

// MetalView：NSView 子类
// 职责：
//  - 接收系统输入事件（键盘 / 鼠标）
//  - 持有 CAMetalLayer 作为渲染目标
//  - 将事件桥接回 C++ 层（MetalViewWrapper）
@interface MetalView : NSView {
    BOOL _justCaptured;  // 刚刚切换到捕获模式的标志
}
@property MetalViewWrapper* wrapper;
- (void)centerCursor;  // 将光标移到窗口中心
@end

@implementation MetalView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _justCaptured = NO;
    }
    return self;
}

#pragma mark - Event Handling

- (void)keyDown:(NSEvent *)event {
    if (_wrapper && _wrapper->onKey) {
        _wrapper->onKey((int)[event keyCode], true);
    }
}

- (void)keyUp:(NSEvent *)event {
    if (_wrapper && _wrapper->onKey) {
        _wrapper->onKey((int)[event keyCode], false);
    }
}

- (void)mouseMoved:(NSEvent *)event {
    // 如果刚切换到捕获模式，忽略第一次移动
    if (_justCaptured) {
        _justCaptured = NO;
        return;
    }
    
    // 使用 delta 模式
    if (_wrapper && _wrapper->onMouseMove) {
        float deltaX = [event deltaX];
        float deltaY = [event deltaY];
        _wrapper->onMouseMove((int)deltaX, (int)deltaY);
    }
}


- (void)centerCursor {
    // 获取窗口在屏幕上的位置
    NSRect windowFrame = [self.window frame];
    NSRect contentRect = [self.window contentRectForFrameRect:windowFrame];
    
    // 计算窗口内容区域的中心点（屏幕坐标）
    CGPoint center = CGPointMake(
        contentRect.origin.x + contentRect.size.width / 2.0,
        contentRect.origin.y + contentRect.size.height / 2.0
    );
    
    // 移动光标到中心
//    CGWarpMouseCursorPosition(center); // 我取消了, 因为这样可以确保切换的一一瞬间保持连贯 但保留了上面的计算center的 Obj-c代码
}

- (void)setJustCaptured:(BOOL)captured {
    _justCaptured = captured;
}

- (void)renderFrame {
    if (_wrapper && _wrapper->onRenderFrame) {
        _wrapper->onRenderFrame();
    }
}

- (BOOL)acceptsFirstResponder {
    return YES;
}
@end

// MetalViewWrapper 构造函数
// 作用：
// 1. 初始化 NSApplication（AppKit 核心）
// 2. 创建 NSWindow / NSView
// 3. 创建并绑定 CAMetalLayer
// 4. 建立 ObjC -> C++ 的事件回调通道
MetalViewWrapper::MetalViewWrapper(int width, int height) {
    @autoreleasepool {
        // 获取全局唯一的 NSApplication 实例（AppKit 的核心对象）
        NSApplication* app = [NSApplication sharedApplication];
        // 安装最小 AppDelegate
        // 使用 static 保证 delegate 生命周期与应用一致
        static AppDelegate* delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        // 将程序设为前台应用：
        // - 显示在 Dock
        // - 能接收键盘和鼠标事件
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        _app = app;
        
        // 创建主窗口（位置 + 大小 + 样式）
        NSRect rect = NSMakeRect(100,100,width,height);
        _window = [[NSWindow alloc] initWithContentRect:rect
                                               styleMask:(NSWindowStyleMaskTitled |
                                                          NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskResizable)
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        // 创建自定义 MetalView，用于接收输入事件并承载 CAMetalLayer
        MetalView* view = [[MetalView alloc] initWithFrame:rect];
        // 告诉 AppKit：这个 View 使用 Core Animation Layer
        // 否则后续设置 view.layer 会无效
        view.wantsLayer = YES;

        view.wrapper = this; // 绑定回调到 wrapper

        // 创建 cpp风格CA::MetalLayer：
        // Metal 的渲染目标工厂（负责生成 drawable）
        _layer = [CAMetalLayer layer];
        // 绑定 Metal 设备（GPU）
        // 与 Metal-cpp 中的 MTL::CreateSystemDefaultDevice() 对应
        _layer.device = MTLCreateSystemDefaultDevice();
        // 将 CAMetalLayer 绑定到 View
        // 形成 Window -> View -> Layer -> Drawable 的渲染链路
        view.layer = _layer;

        _view = view;
        [_window setContentView:_view];
        // 将 MetalView 设为第一响应者
        // 否则键盘事件不会传递到 keyDown:
        [_window makeFirstResponder:_view];
        [_window makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];

        // 默认 mouseMoved 事件是关闭的
        // 必须显式开启，否则 mouseMoved: 不会被调用
        [_view.window setAcceptsMouseMovedEvents:YES];
        
        // 添加定时器驱动渲染，每秒60fps
        NSTimer* renderTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 120.0
                                                                        target:view
                                                                      selector:@selector(renderFrame)
                                                                      userInfo:nil
                                                                       repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:renderTimer forMode:NSRunLoopCommonModes];
    }
}

void MetalViewWrapper::setMouseCaptured(bool captured) {
    _mouseCaptured = captured;
    MetalView* view = (MetalView*)_view;
    
    if (captured) {
        // 步骤1：先把光标移到窗口中心（此时还关联着）
        [view centerCursor];
        
        // 步骤2：等一小会儿，让光标移动完成
        // 使用 dispatch_after 延迟执行
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
            // 步骤3：解耦鼠标和光标
            CGAssociateMouseAndMouseCursorPosition(NO);
            
            // 步骤4：隐藏光标
            [NSCursor hide];
            
            // 步骤5：设置标志，忽略下一次 mouseMoved
            [view setJustCaptured:YES];
        });
    } else {
        // 恢复正常模式
        CGAssociateMouseAndMouseCursorPosition(YES);
        [NSCursor unhide];
    }
}

void MetalViewWrapper::getWindowCenter(int& x, int& y) {
    NSRect frame = [_window frame];
    x = (int)(frame.size.width / 2);
    y = (int)(frame.size.height / 2);
}

// 启动 macOS 主事件循环（阻塞）
// 等价于把事件处理权交给 AppKit
void MetalViewWrapper::run() {
    @autoreleasepool {
        [NSApplication.sharedApplication run]; // 阻塞，窗口事件循环
    }
}



