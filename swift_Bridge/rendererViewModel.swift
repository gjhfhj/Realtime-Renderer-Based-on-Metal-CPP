//
//  rendererViewModel.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

import SwiftUI
import Foundation
import Combine
// NSObject 是实现 ObjC 协议的前提
final class RendererViewModel: NSObject, ObservableObject {
    @Published var fps: Double = 0.0
    @Published var mouseCaptured: Bool = false
    
    // --- 物理相机模式状态 ---
    @Published var isPhysicalCameraMode: Bool = false
    @Published var hoveredDialName: String? = nil
    let scrollEventPublisher = PassthroughSubject<(String, CGFloat, CGFloat), Never>()
    
    private var scrollMonitor: Any?
    // --- 物理曝光参数 (预留给后端) ---
    
    private func updatePhysicalParams() {
        MetalBridge.shared().setPhysicalCameraParamsWithAperture(Float(aperture), shutterSpeed: Float(shutterSpeed), iso: Float(iso), evComp: Float(ev)
        )
    }
    
    @Published var shutterSpeed: Double = 1.0 / 250.0 { didSet { updatePhysicalParams() } }
    @Published var iso: Double = 200.0 { didSet { updatePhysicalParams() } }
    @Published var aperture: Double = 5.6 { didSet { updatePhysicalParams() } }
    @Published var Lut: Double = 0.0
    @Published var powerMode: Double = 0.0
    @Published var ev: Double = 0.0 { didSet { updatePhysicalParams() } }
    
    func didTogglePhysicalCamera() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            self.isPhysicalCameraMode.toggle()
            
            //根据模式动态挂载/卸载雷达
            if self.isPhysicalCameraMode {
                startScrollMonitor()
            } else {
                stopScrollMonitor()
            }
            
            MetalBridge.shared().setPhysicalCameraMode(self.isPhysicalCameraMode)
            if self.isPhysicalCameraMode { updatePhysicalParams() }
        }
    }
    
    private func startScrollMonitor() {
        if scrollMonitor != nil { return }
        
        // 挂载一个局部的事件监听器，专门抓 .scrollWheel
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            
            // 如果在相机模式下，且鼠标停在旋钮上，截胡事件！
            if self.isPhysicalCameraMode, let dialName = self.hoveredDialName {
                self.scrollEventPublisher.send((dialName, event.scrollingDeltaX, event.scrollingDeltaY))
                return nil // 返回 nil 表示事件被吃掉，不再向下传递给 SwiftUI 或 Metal
            }
            return event // 否则放行，不影响正常滚动
        }
    }

    private func stopScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil // 销毁句柄，释放内存
        }
    }
    
    // PBR 相关的控制参数
    @Published var lightIntensity: Double = 50.0
    @Published var exposure: Double = 0.1 {
        didSet {
            // 数据变了则通知外交官metalBridge
            MetalBridge.shared().setExposure(Float(exposure))
        }
    }

    override init() {
            super.init() // 先让父类 NSObject 完成初始化
            
            // 将自己设置为 Bridge 的代理，这样底层发生变化时才能收到通知
            MetalBridge.shared().delegate = self
        }
}

// 接收来自 ObjC/C++ 底层的回调
extension RendererViewModel: MetalBridgeDelegate {
    func didUpdateFPS(_ fps: Double) {
        // 数据驱动：只要赋了值，SwiftUI 就会自动刷新屏幕
        self.fps = fps
    }
    
    func didMouseCaptureChanged(_ captured: Bool) {
        self.mouseCaptured = captured
    }
}
