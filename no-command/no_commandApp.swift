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
        MenuBarExtra("no-command", systemImage: "command") {
            MenuView()
        }
        .menuBarExtraStyle(.menu)

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
