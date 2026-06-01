//
//  retalViewRepresentable.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/4/4.
//

import SwiftUI
import AppKit

struct MetalViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // 返回我们在 Bridge 中创建并配好 Layer 的 MetalView
        return MetalBridge.shared().metalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 窗口 resize 逻辑按需在这里添加给 C++ 层
        let newSize = nsView.frame.size
            if newSize.width > 0 && newSize.height > 0 {
                //  MetalBridge 里暴露 setResolutionX:Y: 的接口
                MetalBridge.shared().setResolutionWidth(Int32(newSize.width), height: Int32(newSize.height))
            }
    }
}
