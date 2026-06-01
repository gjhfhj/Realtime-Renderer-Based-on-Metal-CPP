//
//  contentView.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = RendererViewModel()

    var body: some View {
        let isCameraMode = vm.isPhysicalCameraMode && !vm.mouseCaptured
        ZStack {
            // 透明窗口修改器 (不会占用空间)
            TransparentWindowModifier().frame(width: 0, height: 0)
            
            // 使用 GeometryReader 约束死循环
            GeometryReader { geo in
                MetalViewRepresentable()
                    .frame(
                        // 强制给 SwiftUI 两个绝对数字进行动画插值，消灭 nil 状态
                        width: isCameraMode ? 274 : geo.size.width,
                        height: isCameraMode ? 198 : geo.size.height
                    )
                    .cornerRadius(isCameraMode ? 4 : 0)
                    // 使用 position 进行绝对居中定位，比 offset 更稳且不干扰父级约束
                    .border(Color.red, width: 2)
                    .position(
                        x: (geo.size.width / 2), // 屏幕宽度的一半 (水平居中)
                        y: (geo.size.height / 2) + (isCameraMode ? 59 : 0) // 屏幕高度一半 + 42的偏移量
                    )
                    // 弹簧动画现在可以完美执行，因为它知道起点和终点的具体像素了 但会在动画的瞬间卡死，因为动画缩小的过程每一帧的resolution变化都触发底层事件重制贴图资源bro
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCameraMode)
            }
            .ignoresSafeArea(.all) // 这里好像很重要
            
            if isCameraMode {
                CameraSimulatorView(vm: vm)
                        .transition(.opacity)
                        .zIndex(1) // 确保在最上层
            } else {
                NormalModeUIVStack(vm: vm)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCameraMode)
        .onAppear {
            MetalBridge.shared().delegate = vm
        }
    }
}

struct CameraSimulatorView: View {
    @ObservedObject var vm: RendererViewModel
    
    let cameraWidth: CGFloat = 800
    
    // --- 相机物理档位数据 ---
    let isoLabels = ["100", "200", "400", "800", "1600", "800", "400", "200"]
    let isoValues: [Double] = [100, 200, 400, 800, 1600, 800, 400, 200]
    
    let shutterLabels = ["1/60s", "1/125s", "16", "8", "4", "2", "1s", "1/2s", "1/4s", "1/8s", "1/15s", "1/30s"]
    let shutterValues: [Double] =  [1/60, 1/125, 16, 8, 4, 2, 1, 1/2, 1/4, 1/8, 1/15, 1/30]
    
    let LutLables = ["cinematic", "TV", "Film", "Custom"]
    let LutValues: [Double] = [0, 1, 2, 3]
    
    let powerModeLabels = ["Normal", "Night", "Portrait", "Landscape"]
    let powerModeValues: [Double] = [0, 1, 2, 3]
    
    let evLables = ["-1", "-0.5", "0", "+0.5", "1"]
    let evValues: [Double] = [-1, -0.5, 0, 0.5, 1]
    
    let apertureLabels = ["f/1.4", "f/2.0", "f/2.8", "f/4.0", "f/5.6", "f/8.0"]
    let apertureValues: [Double] = [1.4, 2.0, 2.8, 4.0, 5.6, 8.0]
    
    var body: some View {
            ZStack {
//                // 1. 底层：Metal 视口
//                MetalViewRepresentable()
//                    .frame(width: 274, height: 200)
//                    .cornerRadius(4)
//                    .offset(x: 0, y: 42)
//                    
                // 2. 中层：physical_camera
                Image("physical_camera_simulator")
                    .resizable()
                    .scaledToFit()
                    .frame(width: cameraWidth)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                
                // 3. 各种dial
                
                // dial_iso
                RotatableDial(
                    vm: vm, imageName: "dial_iso",
                    title: "ISO",
                    labels: isoLabels,
                    values: isoValues,
                    boundValue: $vm.iso,
                    stepAngle: 45.0,
                    dialSize: 100
                )
                
//                .border(Color.red, width: 2)
                .zIndex(2)
                .offset(x: -258, y: -73)
                
                // dial_shutter
                RotatableDial(
                    vm: vm, imageName: "dial_shutter",
                    title: "SHUTTER",
                    labels: shutterLabels,
                    values: shutterValues,
                    boundValue: $vm.shutterSpeed,
                    stepAngle: 30.0,
                    dialSize: 100
                )
//                .border(Color.red, width: 2)
//                .onHover(perform: text(self.lable))
                .zIndex(2)
                .offset(x: 265, y: -73)
                
                // dial_Lut
                RealisticCylinderDial(
                    vm: vm, imageName: "dial_Lut",
                    title: "Lut",
                    labels: LutLables,
                    values: LutValues,
                    boundValue: $vm.Lut,
                    dialWidth: 60,
                    dialHeight: 40,
                    stepWidth: 3.0
                )
                .zIndex(1)
//                .border(Color.red, width: 2)
                .offset(x: -265, y: -168)
                
                // dial_powerMode
                RealisticCylinderDial(
                    vm: vm, imageName: "dial_powerMode",
                    title: "powerMode",
                    labels: powerModeLabels,
                    values: powerModeValues,
                    boundValue: $vm.powerMode,
                    dialWidth: 79,
                    dialHeight: 25,
                    stepWidth: 1.0
                )
                .zIndex(1)
//                .border(Color.red, width: 2)
                .offset(x: 108  , y: -176)
                
                // dial_ev
                RealisticCylinderDial(
                    vm: vm, imageName: "dial_ev",
                    title: "ev",
                    labels: evLables,
                    values: evValues,
                    boundValue: $vm.ev,
                    dialWidth: 55,
                    dialHeight: 17,
                    stepWidth: 1
                )
                .zIndex(1)
//                .border(Color.red, width: 2)
                .offset(x: 195  , y: -155)
                
                // dial_aperture
                RealisticCylinderDial(
                    vm: vm, imageName: "dial_aperture",
                    title: "aperture",
                    labels: apertureLabels,
                    values: apertureValues,
                    boundValue: $vm.aperture,
                    dialWidth: 88,
                    dialHeight: 47,
                    stepWidth: 1.0
                )
                .zIndex(1)
//                .border(Color.red, width: 2)
                .offset(x: 278  , y: -160)
                
                // 顶部提示返回文本
                VStack {
                    Text("Physical Camera Mode - Press 'P' to Return")
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.top, -30)
                    Spacer()
                }
            }
            .frame(width: cameraWidth, height: cameraWidth * 0.7)
        }
}


struct NormalModeUIVStack: View {
    @ObservedObject var vm: RendererViewModel
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                FPSBadge(fps: vm.fps)
                    .allowsHitTesting(false)
                
                Spacer()
                
                // 【只有按下 TAB 释放鼠标时，才显示编辑面板】
                if !vm.mouseCaptured {
                    VStack(alignment: .trailing, spacing: 10) {
                        // 曝光滑块控制面板
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Exposure: \(String(format: "%.2f", vm.exposure))")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Slider(value: $vm.exposure, in: 0.0...5.0)
                                .accentColor(.white)
                        }
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .frame(width: 220)
                        
                        Text("Press 'P' to open Physical Camera")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.top, 4)
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // 底部操作提示
            if !vm.mouseCaptured {
                Text("Press TAB to capture mouse, ESC to exit")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
    }
}

// FPSBadge
struct FPSBadge: View {
    let fps: Double
    
    var indicatorColor: Color {
        if fps >= 60 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            
            Text(String(format: "%.0f FPS", fps))
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
    }
}
