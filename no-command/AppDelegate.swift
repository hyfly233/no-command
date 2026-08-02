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
        // 应用被激活（点开设置窗口、从系统设置授权回来等）时：
        // ① 刷新辅助功能权限并自动拉起拦截；② 刷新运行中应用列表，
        // 避免白名单页签因 TabView 视图缓存而显示陈旧的应用列表
        AppState.shared.refreshPermission()
        AppState.shared.refreshRunningApps()
    }
}
