//
//  PermissionManager.swift
//  no-command
//
//  no-command：辅助功能权限管理。
//
//  会话级事件 tap（CGEventTap, .cgSessionEventTap）需要「辅助功能」授权，
//  用 AXIsProcessTrusted() 检查。「输入监控」只适用于只读监听型 tap，
//  本项目要丢弃事件，必须用会话级 tap + 辅助功能权限。
//

import AppKit
import ApplicationServices

enum PermissionManager {

    /// 当前是否已获得辅助功能权限
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 跳转系统设置 → 隐私与安全性 → 辅助功能
    static func openSystemSettings() {
        // 首选辅助功能深链；若无法打开则回退到「隐私与安全性」总页
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
        ]
        for url in urls.compactMap({ $0 }) where NSWorkspace.shared.open(url) {
            return
        }
    }
}
