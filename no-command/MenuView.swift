//
//  MenuView.swift
//  no-command
//
//  no-command：菜单栏下拉内容（紧凑版）。
//  总开关 + 预设快捷键开关 + 权限状态 + 最近拦截 + 设置/退出。
//  完整管理（白名单、日志、自定义录制）在设置窗口。
//

import SwiftUI

/// 菜单栏下拉内容
struct MenuView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var logs = LogStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头部：名称 + 运行状态点
            // 用 Label 保证图标与文字在同一水平线（.menu 样式下 Image+Text 可能被菜单按各自尺寸渲染导致不对齐）
            HStack(spacing: 6) {
                Label("no-command", systemImage: "command")
                    .font(.headline)              // 图标与文字共享同一字号，垂直对齐一致
                    .labelStyle(.titleAndIcon)
                Spacer()
                Circle()
                    .fill(state.masterEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            Toggle("启用拦截", isOn: $state.masterEnabled)

            Divider()

            // 预设快捷键开关
            ForEach(state.presets) { rule in
                Toggle(rule.display, isOn: Binding(
                    get: { state.enabledPresetIDs.contains(rule.id) },
                    set: { on in
                        if on { state.enabledPresetIDs.insert(rule.id) }
                        else { state.enabledPresetIDs.remove(rule.id) }
                    }
                ))
            }

            // 权限状态
            if state.permissionGranted {
                Label("辅助功能已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("需要辅助功能授权", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("打开系统设置…") { PermissionManager.openSystemSettings() }
            }

            // 最近一条拦截日志
            if let last = logs.entries.last {
                Text(last.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // 设置入口：openWindow(id:) 打开 Window 场景（官方 API，可靠）。
            // 不用 SettingsLink（MenuBarExtra 下打不开的已知缺陷），
            // 不用 showSettingsWindow:（Apple 告警禁用）。
            Button {
                openSettings()
            } label: {
                Label("设置…", systemImage: "gearshape")
            }
            Button { NSApp.terminate(nil) } label: {
                Label("退出", systemImage: "power")
            }
        }
        .padding(8)
        .frame(width: 280)
        .onAppear { state.refreshPermission() }
    }

    /// 打开设置窗口并确保置顶。
    /// LSUIElement 菜单栏 App 默认不会成为前台激活应用，直接 openWindow 时
    /// 窗口会排在别的应用窗口后面；因此先激活 App，再对窗口强制置前兜底。
    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        bringSettingsWindowFront(remainingAttempts: 5)
    }

    /// 设置窗口创建是异步的（openWindow 返回后窗口可能尚未出现），轮询查找并强制置前
    private func bringSettingsWindowFront(remainingAttempts: Int) {
        guard remainingAttempts > 0 else { return }
        if let window = NSApp.windows.first(where: { $0.title == "设置" }) {
            window.makeKeyAndOrderFront(nil)   // 成为关键窗口（接收键盘事件）
            window.orderFrontRegardless()      // 即使激活失败也强行置前
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.bringSettingsWindowFront(remainingAttempts: remainingAttempts - 1)
            }
        }
    }
}
