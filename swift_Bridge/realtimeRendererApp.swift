//
//  realtimeRendererApp.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

import SwiftUI

@main
struct RealtimeRendererApp: App {
    init() {
        // 在 App 启动时初始化引擎和渲染层
        MetalBridge.shared().setup(withWidth: 1280, height: 720)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
