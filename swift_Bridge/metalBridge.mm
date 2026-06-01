//
//  metalBridge.mm
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

#import "metalBridge.h"
#import "metalView.h"
#import "renderer.hpp"
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>

@interface MetalBridge () {
    Renderer* _engine;
    bool _keys[256];
    
    // CoreVideo 显示器同步链路
    CVDisplayLinkRef _displayLink;
    
    // 缓存 CAMetalLayer 指针，供后台线程安全使用
    CAMetalLayer* _metalLayer;
}

@property (nonatomic, readwrite) NSView* metalView;
@property (nonatomic, readwrite) BOOL mouseCaptured;
@property (nonatomic, readwrite) double currentFPS;

@property (nonatomic) CFTimeInterval lastFrameTime;
@property (nonatomic) int frameCount;

@end

@implementation MetalBridge

+ (instancetype)shared {
    static MetalBridge* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MetalBridge alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        memset(_keys, 0, sizeof(_keys));
        _engine = nullptr;
    }
    return self;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
    delete _engine;
}

- (void)setupWithWidth:(int)width height:(int)height {
    if (_engine != nullptr) return;
    
    // 1. 使用 Metal-CPP 创建 C++ 类型的 Device
    MTL::Device* pDevice = MTL::CreateSystemDefaultDevice();
    
    // 2. 创建 View 和 Layer
    MetalView* view = [[MetalView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    CAMetalLayer* layer = (CAMetalLayer*)view.layer;
    
    // 3. 核心桥接：将 C++ 的 Device 强转为 ObjC 的 id<MTLDevice>
    layer.device = (__bridge id<MTLDevice>)pDevice;
    
    // 同样，将 C++ 的 PixelFormat 枚举强转为 ObjC 枚举
    layer.pixelFormat = (MTLPixelFormat)MTL::PixelFormatBGRA8Unorm_sRGB;
    
    self.metalView = view;
    
    _metalLayer = layer;
    
    // 4. 传入资源路径并初始化引擎
    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    std::string basePath = [resourcePath UTF8String];
    _engine = new Renderer(pDevice, width, height, basePath);
    
    // 5. 启动渲染循环
    [self setupDisplayLink];
}

#pragma mark - CVDisplayLink (高性能渲染循环)

// 这是一个 C 语言回调，跑在 macOS 分配的高优先级后台线程上
static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp* now,
                                    const CVTimeStamp* outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags* flagsOut,
                                    void* displayLinkContext) {
    MetalBridge* bridge = (__bridge MetalBridge*)displayLinkContext;
    [bridge renderFrame];
    return kCVReturnSuccess;
}

- (void)setupDisplayLink {
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, (__bridge void*)self);
    CVDisplayLinkStart(_displayLink);
}

// 该方法在后台独立线程被高频调用
- (void)renderFrame {
    // 必须加 @autoreleasepool，否则 nextDrawable 会内存泄漏
    @autoreleasepool {
        if (!_engine || !_metalLayer) return; // 确保引擎和 layer 都在
        
        // 删掉原来那句访问 UI 的代码：
        // CAMetalLayer* layer = (CAMetalLayer*)self.metalView.layer;
        
        // 改成直接使用我们缓存好的 _metalLayer：
        id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
        if (!drawable) return;
        
        // 驱动 C++ 引擎
        _engine->update(_keys);
        _engine->render((__bridge CA::MetalDrawable*)drawable);
        
        // 计算 FPS 并推送到主线程的 SwiftUI
        [self calculateFPS];
    }
}

- (void)calculateFPS {
    _frameCount++;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval elapsed = now - _lastFrameTime;
    if (elapsed >= 0.5) {
        double fps = _frameCount / elapsed;
        _frameCount = 0;
        _lastFrameTime = now;
        self.currentFPS = fps;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate didUpdateFPS:fps];
        });
    }
}

#pragma mark - GUI
- (void)setExposure:(float)exposure {
    if (_engine) {
        // 链接后端
        _engine->setExposure(exposure);
    }
}

#pragma mark - Input Handling
/* macOS 键码
按键    键码 (十进制)    按键    键码 (十进制)    按键    键码 (十进制)
A       0               J       38            7         26
B       11              K       40            8         28
C       8               L       37            9         25
D       2               M       46            0         29
E       14              N       45          Space       49
F       3               O       31          Delete      51
G       5               P       35          Enter       36
H       4               Q       12           Tab        48
I       34              R       15           Esc        53
S       1               T       17         Command   55 (左) / 54 (右)
U       32              V       9           Shift    56 (左) / 60 (右)
W       13              X       7         Caps Lock     57
Y       16              Z       6          Option    58 (左) / 61 (右)
方向上   126           方向下     125          方向左      123
方向右   124             F1      122          F2         120
*/

- (void)setKeyPressed:(unsigned short)keyCode isPressed:(BOOL)pressed {
    if (keyCode < 256) {
        _keys[keyCode] = pressed;
    }
    
    // 48 是 Tab 键，53 是 ESC，35 是 'P' 键
    if (keyCode == 48 && pressed) {
        [self setMouseCaptured:!self.mouseCaptured];
    } else if (keyCode == 53 && pressed) {
        if (self.mouseCaptured) {
            [self setMouseCaptured:NO];
        } else {
            exit(0);
        }
    } else if (keyCode == 35 && pressed) {
        // 按下 'P' 键
        // 只有在非漫游模式（鼠标未被捕获，即打开了面板时），才允许切换相机 UI
        if (!self.mouseCaptured) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(didTogglePhysicalCamera)]) {
                    [self.delegate didTogglePhysicalCamera];
                }
            });
        }
    }
}

- (void)sendMouseDeltaX:(float)dx deltaY:(float)dy {
    // 只要 mouseCaptured 为 YES，就能正常转动视角
    if (_engine && self.mouseCaptured) {
        _engine->onMouseMove((int)dx, (int)dy);
    }
}

- (void)sendMouseClickX:(float)x y:(float)y {
    if (_engine) {
        // 调用 底层渲染 的鼠标拾取方法
        _engine->meow(); // 目前底层为作对应代码适配，暂为meow 代替
    }
}

- (void)setMouseCaptured:(BOOL)captured {
    // 修复栈溢出：使用下划线变量直接赋值，避免触发 setter 循环
    _mouseCaptured = captured;
    
    // 先干净利落地完成类型强转，再用点语法赋值，避免编译器解析歧义
    MetalView* view = (MetalView*)self.metalView;
    view.isMouseCaptured = captured;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate didMouseCaptureChanged:captured];
    });
}

- (void)setResolutionWidth:(int)width height:(int)height {
    if (_engine && _metalLayer) {
        // 这里必须考虑 Mac Retina 屏幕的缩放因子 (通常是 2.0)
        CGFloat scale = self.metalView.window.backingScaleFactor;
        if (scale <= 0.0) {
            // 如果获取不到 window，强制回退到主屏幕的 Retina 缩放因子 (通常是 2.0)
            scale = [NSScreen mainScreen].backingScaleFactor;
        }
        _metalLayer.contentsScale = scale;
        
        // 更新 CAMetalLayer 的 drawableSize
        _metalLayer.drawableSize = CGSizeMake(width * scale, height * scale);
        
        // 通知 C++ 引擎重建渲染目标：取消了，避免CVDisplayLink线程驱动renderer导致抓去贴图时，主线程驱动底层resizeResulution把资源弄掉了，就崩溃。
        //_engine->setWindowSize(width * scale, height * scale);
        // 目前的做法是只让主线程swift控制的告诉系统的 CAMetalLayer 它的新物理尺寸， 底层确认是否尺寸有变化，有则重新依据尺寸配置资源
    }
}

- (void)setPhysicalCameraMode:(BOOL)enabled {
    if (_engine) _engine->setPhysicalCameraMode(enabled);
}

- (void)setPhysicalCameraParamsWithAperture:(float)aperture shutterSpeed:(float)shutter iso:(float)iso evComp:(float)evComp {
    if (_engine) {
        _engine->setPhysicalCameraParams(aperture, shutter, iso, evComp);
    }
}
@end
