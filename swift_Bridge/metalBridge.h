//
//  metalBridge.h
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MetalBridgeDelegate <NSObject>
@optional
- (void)didUpdateFPS:(double)fps;
- (void)didMouseCaptureChanged:(BOOL)captured;
- (void)didTogglePhysicalCamera;
@end

@interface MetalBridge : NSObject

+ (instancetype)shared;

@property (nonatomic, weak, nullable) id<MetalBridgeDelegate> delegate;
@property (nonatomic, readonly) NSView* metalView;
@property (nonatomic, readonly) BOOL mouseCaptured;
@property (nonatomic, readonly) double currentFPS;

// SwiftUI 调用的初始化接口
- (void)setupWithWidth:(int)width height:(int)height;
- (void)setMouseCaptured:(BOOL)captured;
- (void)setExposure:(float)exposure;

// 供 MetalView 调用的输入接口
- (void)setResolutionWidth:(int)width height:(int)height;
- (void)setKeyPressed:(unsigned short)keyCode isPressed:(BOOL)pressed;
- (void)sendMouseDeltaX:(float)dx deltaY:(float)dy;
- (void)sendMouseClickX:(float)x y:(float)y;
- (void)sendMouseDeltaX:(float)dx deltaY:(float)dy;

- (void)setPhysicalCameraMode:(BOOL)enabled;
- (void)setPhysicalCameraParamsWithAperture:(float)aperture
                               shutterSpeed:(float)shutter
                                        iso:(float)iso
                                     evComp:(float)evComp;
// 给 CVDisplayLink 调用的渲染帧入口
- (void)renderFrame;

@end

NS_ASSUME_NONNULL_END
