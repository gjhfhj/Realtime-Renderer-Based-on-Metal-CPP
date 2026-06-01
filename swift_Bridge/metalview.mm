//
//  metalview.mm
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

#import "metalView.h"
#import "metalBridge.h"
#import <QuartzCore/CAMetalLayer.h>

@interface MetalView () {
    BOOL _justCaptured;
    NSTrackingArea* _trackingArea; //  补充：现代 macOS 必备的鼠标追踪器
}
@end

@implementation MetalView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.layer = [CAMetalLayer layer];
        self.wantsLayer = YES;
        _justCaptured = NO;
        _isMouseCaptured = NO;
    }
    return self;
}

//  补充：注册鼠标追踪区域，保证 100% 收到 mouseMoved 事件
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    // 要求：只要鼠标在视图内，或者本窗口是激活状态，就持续汇报移动
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

// 让 View 能接收键盘和焦点
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self.window setAcceptsMouseMovedEvents:YES];
        [self.window makeFirstResponder:self];
    }
}

#pragma mark - Input Events

- (void)keyDown:(NSEvent *)event {
    [[MetalBridge shared] setKeyPressed:[event keyCode] isPressed:YES];
}

- (void)keyUp:(NSEvent *)event {
    [[MetalBridge shared] setKeyPressed:[event keyCode] isPressed:NO];
}

#pragma mark - Mouse / Trackpad Events

// 1. 左键点击
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self]; // 抢占焦点
    
    if (!self.isMouseCaptured) {
        // 【编辑模式】：执行拾取 (meow)
        NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
        [[MetalBridge shared] sendMouseClickX:location.x y:location.y];
    } else {
        // 【漫游模式】：什么都不做，屏蔽左键
    }
}

// 2. 右键点击
- (void)rightMouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    
    if (!self.isMouseCaptured) {
        // 【编辑模式】：点击右键进入漫游模式
        [[MetalBridge shared] setMouseCaptured:YES];
    } else {
        // 【漫游模式】：什么都不做，屏蔽右键
    }
}

// 3. 单指移动 (不按压)
- (void)mouseMoved:(NSEvent *)event {
    if (_justCaptured) {
        _justCaptured = NO;
        return;
    }
    // 💡 删除了原先调用 sendMouseDeltaX 的逻辑
    // 这样在漫游模式下，你单指在触摸板上乱滑，视角绝对不会跟着乱动了！
}

// 4. 双指滑动 (Mac 触摸板最原生的平移操作)
- (void)scrollWheel:(NSEvent *)event {

}

// 5. 左键拖拽 (或者开启了“三指拖移”后的三指滑动)
- (void)mouseDragged:(NSEvent *)event {
    if (self.isMouseCaptured) {
        // 如果你习惯用 Mac 辅助功能里的“三指拖移”来操作，这里会生效
        float dx = [event deltaX];
        float dy = [event deltaY];
        
        if (dx != 0 || dy != 0) {
            [[MetalBridge shared] sendMouseDeltaX:dx deltaY:dy];
        }
    }
}

// 6. 右键拖拽
- (void)rightMouseDragged:(NSEvent *)event {
    // 根据需要决定右键拖拽要不要转视角，如果不需要，直接留空即可
}

- (void)setIsMouseCaptured:(BOOL)captured {
    if (_isMouseCaptured == captured) return; // 避免重复调用
    _isMouseCaptured = captured;
    
    if (captured) {
        _justCaptured = YES;
        //  修复：去掉 dispatch_async，立即执行！
        // 并且去掉 Bug 频发的坐标 Warp，直接原地冻结隐藏鼠标
        [NSCursor hide];
        CGAssociateMouseAndMouseCursorPosition(NO);
    } else {
        // 释放鼠标，恢复系统关联
        CGAssociateMouseAndMouseCursorPosition(YES);
        [NSCursor unhide];
    }
}
@end
