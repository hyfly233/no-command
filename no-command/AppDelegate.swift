//
//  AppDelegate.swift
//  no-command
//
//  no-command：应用生命周期代理。
//  启动即拉起拦截器（LSUIElement 无 Dock 图标，菜单栏图标由 MenuBarExtra 提供）；
//  应用激活时刷新辅助功能权限——从系统设置授权回来会自动启动拦截。
//

import AppKit

/// 应用生命周期代理
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 触发单例初始化并尝试启动拦截
        _ = AppState.shared
        AppState.shared.refreshPermission()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 从系统设置授权回来、或菜单被打开时，刷新权限并自动拉起拦截
        AppState.shared.refreshPermission()
    }
}
