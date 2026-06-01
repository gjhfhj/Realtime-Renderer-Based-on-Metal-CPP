//
//  _physical_camera_action.swift
//  Realtime Renderer Based on Metal-CPP
//
//  Created by gjhfhj on 2026/5/8.
//

import AppKit
import SwiftUI

struct RotatableDial: View {
    @ObservedObject var vm: RendererViewModel
    
    let imageName: String
    let title: String
    let labels: [String]
    let values: [Double]
    @Binding var boundValue: Double
    
    let stepAngle: Double
    let dialSize: CGFloat

    @State private var rotationSteps: Int = 0
    @State private var isInteracting = false
    @State private var scrollAccumulator: CGFloat = 0

    // 安全地将无限步数映射为 0..<count 的真实数组索引
    var actualIndex: Int {
        let count = values.count
        guard count > 0 else { return 0 }
        return (rotationSteps % count + count) % count
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: dialSize, height: dialSize)
            .rotationEffect(.degrees(Double(rotationSteps) * stepAngle))
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: rotationSteps)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInteracting = hovering
                }
                // 告诉 ViewModel 鼠标悬停在了这个组件上
                vm.hoveredDialName = hovering ? title : nil
            }
            // 监听全局滚轮广播
            .onReceive(vm.scrollEventPublisher) { targetName, dx, dy in
                // 确保广播是发给自己的
                guard targetName == title else { return }
                
                // 圆盘取动作幅度更大的那个方向（兼容上下搓或左右搓）
                let delta = abs(dy) > abs(dx) ? dy : dx
                scrollAccumulator += delta
                let sensitivity: CGFloat = 40.0
                
                if abs(scrollAccumulator) > sensitivity {
                    let direction = scrollAccumulator > 0 ? 1 : -1
                    rotationSteps += direction
                    boundValue = values[actualIndex]
                    
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    scrollAccumulator = 0
                }
            }
            .overlay(
                Text("\(title): \(labels[actualIndex])")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.8), in: Capsule())
                    .offset(y: -dialSize/2 - 30)
                    .opacity(isInteracting ? 1 : 0)
            )
            .onAppear {
                if let index = values.firstIndex(of: boundValue) {
                    rotationSteps = index
                }
            }
    }
}

struct RealisticCylinderDial: View {
    @ObservedObject var vm: RendererViewModel
    
    let imageName: String
    let title: String
    let labels: [String]
    let values: [Double]
    @Binding var boundValue: Double
    
    let dialWidth: CGFloat
    let dialHeight: CGFloat
    let stepWidth: CGFloat

    @State private var currentIndex: Int = 0
    @State private var isInteracting = false
    @State private var scrollAccumulator: CGFloat = 0

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(height: dialHeight) // 限高不限宽
                .offset(x: CGFloat(currentIndex) * stepWidth)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: currentIndex)
            
            // 静态圆柱体光影遮罩 (Shading)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0.0),
                    .init(color: .black.opacity(0.2), location: 0.15),
                    .init(color: .white.opacity(0.4), location: 0.35),
                    .init(color: .white.opacity(0.6), location: 0.5),
                    .init(color: .clear, location: 0.6),
                    .init(color: .black.opacity(0.4), location: 0.85),
                    .init(color: .black.opacity(0.85), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
            
            // 3. 顶部微小的高光倒角
            VStack {
                LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 3)
                Spacer()
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 3)
            }
            .allowsHitTesting(false)
        }
        .frame(width: dialWidth, height: dialHeight) // 限制可视区域
        .clipped() // 裁掉超出的长条纹理
        .cornerRadius(4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInteracting = hovering
            }
            // 告诉 ViewModel 鼠标悬停在了这个组件上
            vm.hoveredDialName = hovering ? title : nil
        }
        // 监听全局滚轮广播
        .onReceive(vm.scrollEventPublisher) { targetName, dx, dy in
            guard targetName == title else { return }
            
            // 圆柱拨轮只响应横向双指滑动
            scrollAccumulator += dx
            let sensitivity: CGFloat = 40.0
            
            if abs(scrollAccumulator) > sensitivity {
                let direction = scrollAccumulator > 0 ? -1 : 1
                var newIndex = currentIndex + direction
                let count = values.count
                
                if count > 0 {
                    // 无限循环处理
                    if newIndex < 0 {
                        newIndex = count - 1
                    } else if newIndex >= count {
                        newIndex = 0
                    }
                    
                    if newIndex != currentIndex {
                        currentIndex = newIndex
                        boundValue = values[currentIndex]
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    }
                }
                scrollAccumulator = 0
            }
        }
        .overlay(
            Text("\(title): \(labels[currentIndex])")
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.8), in: Capsule())
                .offset(y: -dialHeight/2 - 25)
                .opacity(isInteracting ? 1 : 0)
        )
        .onAppear {
            if let index = values.firstIndex(of: boundValue) {
                currentIndex = index
            }
        }
    }
}
