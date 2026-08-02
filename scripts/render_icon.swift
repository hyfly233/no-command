#!/usr/bin/env swift
// =============================================================================
// no-command 应用图标渲染脚本
// 生成 macOS 全套 AppIcon（16/32/128/256/512 × 1x/2x）：
//   深蓝紫渐变圆角背景 + 白色 ⌘ 符号（SF Symbol "command" 矢量渲染）。
//
// 用法：
//   swift scripts/render_icon.swift [输出目录，默认 scripts/../no-command/Assets.xcassets/AppIcon.appiconset]
// =============================================================================
import AppKit

let size = 1024
let cornerRadius: CGFloat = 220

// 生成 1024 主图
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("无法创建图形上下文")
}
ctx.setShouldAntialias(true)

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// 圆角裁剪 + 垂直渐变背景（上 #5C66D1 → 下 #262852）
let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
bgPath.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.82, alpha: 1.0),
    NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.32, alpha: 1.0),
])!
gradient.draw(in: rect, angle: -90)

// 白色 ⌘ 符号（先按原色画出，再用 sourceAtop 重着色为白色）
if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)) {

    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symbolSide: CGFloat = 540
    let origin = CGPoint(x: (CGFloat(size) - symbolSide) / 2,
                         y: (CGFloat(size) - symbolSide) / 2)
    tinted.draw(in: NSRect(origin: origin, size: NSSize(width: symbolSide, height: symbolSide)))
}
image.unlockFocus()

// 输出各尺寸 PNG（macOS 图标命名规范）
let outputs: [(Int, String)] = [
    (16, "AppIcon-16.png"),
    (32, "AppIcon-16@2x.png"),
    (32, "AppIcon-32.png"),
    (64, "AppIcon-32@2x.png"),
    (128, "AppIcon-128.png"),
    (256, "AppIcon-128@2x.png"),
    (256, "AppIcon-256.png"),
    (512, "AppIcon-256@2x.png"),
    (512, "AppIcon-512.png"),
    (1024, "AppIcon-512@2x.png"),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "no-command/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (s, name) in outputs {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("创建位图失败") }
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 编码失败") }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("生成 \(name)（\(s)×\(s)）")
}
print("完成：\(outDir)")
