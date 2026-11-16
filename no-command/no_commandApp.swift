//
//  no_commandApp.swift
//  no-command
//
//  no-command：菜单栏常驻的全局快捷键保护工具。
//  拦截 ⌘Q / ⌘W / ⌃⌘Q / ⌃⌘W（及自定义组合），防止误触退出、关窗、锁屏。
//

import SwiftUI

@main
struct no_commandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // .menuBarExtraStyle(.window)：菜单内容由自绘视图渲染。
        // .menu 样式会把 Toggle 之外的视图（状态点、说明文字、可换行日志）按「禁用菜单项」灰化甚至丢弃，
        // 状态色和两行日志都看不到，因此这里用 .window 保留完整排版与颜色。
        MenuBarExtra("no-command", systemImage: "command") {
            MenuView()
        }
        .menuBarExtraStyle(.window)

        // 设置窗口用普通 Window 场景而非 Settings 场景：
        // MenuBarExtra + Settings 场景在部分 macOS 版本存在 SettingsLink 无法打开窗口的缺陷；
        // 私有选择器 showSettingsWindow: 又被 Apple 告警禁用。
        // Window 场景 + openWindow(id:) 是官方 API，打开/重开均可靠。
        Window("设置", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
