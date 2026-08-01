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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头部：名称 + 运行状态点
            HStack {
                Image(systemName: "keyboard")
                Text("no-command")
                    .font(.headline)
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

            SettingsLink { Label("设置…", systemImage: "gearshape") }
            Button("退出 no-command") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 280)
        .onAppear { state.refreshPermission() }
    }
}
