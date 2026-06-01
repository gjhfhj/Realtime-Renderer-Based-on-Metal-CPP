//
//  transparentWindowModifier.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/5/7.
//

import SwiftUI
import AppKit

// 作用:在挂载时找到它所在的 NSWindow 并进行“魔改”
struct TransparentWindowModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.isOpaque = false
            window.backgroundColor = .clear
            
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            
            
            window.hasShadow = false
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
