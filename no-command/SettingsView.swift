//
//  SettingsView.swift
//  no-command
//
//  no-command：设置窗口。
//  三个页签：快捷键（预设开关 + 自定义录制）、白名单、日志与权限。
//

import SwiftUI

/// 设置窗口（Settings 场景）
struct SettingsView: View {
    var body: some View {
        TabView {
            ShortcutTab()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            WhitelistTab()
                .tabItem { Label("白名单", systemImage: "checklist") }
            LogTab()
                .tabItem { Label("日志", systemImage: "doc.text") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - 快捷键页签

private struct ShortcutTab: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("总开关：启用快捷键拦截", isOn: $state.masterEnabled)
                .font(.headline)

            GroupBox("预设快捷键") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.presets) { rule in
                        HStack {
                            Text(rule.display).monospacedDigit()
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { state.enabledPresetIDs.contains(rule.id) },
                                set: { on in
                                    if on { state.enabledPresetIDs.insert(rule.id) }
                                    else { state.enabledPresetIDs.remove(rule.id) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    Text("⌃⌘Q 锁屏属系统安全快捷键，可能被系统安全层抢先处理，无法保证拦截（系统限制）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("自定义快捷键（录制）") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击「录制新组合」后，按下任意组合键（须含修饰键）即可生成拦截规则；Esc 取消。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(state.isRecording ? "正在录制…（Esc 取消）" : "录制新组合") {
                            if state.isRecording {
                                state.cancelRecording()
                            } else {
                                state.isRecording = true
                                state.recordingMessage = "请按任意组合键…（Esc 取消）"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(state.isRecording ? .red : .accentColor)
                        Text(state.recordingMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !state.customRules.isEmpty {
                        Divider()
                        ForEach(state.customRules) { rule in
                            HStack {
                                Text(rule.display).monospacedDigit()
                                Text(rule.name).foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { on in
                                        if let idx = state.customRules.firstIndex(where: { $0.id == rule.id }) {
                                            state.customRules[idx].isEnabled = on
                                        }
                                    }
                                ))
                                .labelsHidden()
                                Button(role: .destructive) {
                                    state.deleteCustomRule(rule)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(6)
            }

            Toggle("拦截时播放提示音", isOn: $state.beepOnBlock)
        }
        .padding(12)
    }
}

// MARK: - 白名单页签

private struct WhitelistTab: View {
    @ObservedObject private var state = AppState.shared
    @State private var manualBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("白名单内的 App 不会被拦截（⌘Q 等组合正常生效）。no-command 自身：⌘W 正常关闭设置窗口，⌘Q/⌃⌘Q/⌃⌘W 同样受保护。")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("正在运行的应用（勾选加入白名单）") {
                List(state.runningApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.isWhitelisted(app.bundleID) },
                            set: { on in
                                if on {
                                    state.addToWhitelist(bundleID: app.bundleID, name: app.name)
                                } else {
                                    state.removeFromWhitelist(app.bundleID)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .frame(height: 170)
            }

            GroupBox("已加入白名单") {
                // List 常驻：空时框内显示（空），有条目时内部滚动，框架高度稳定
                List {
                    if state.whitelistEntries.isEmpty {
                        Text("（空）").foregroundStyle(.secondary).padding(4)
                    } else {
                        ForEach(state.whitelistEntries.sorted { $0.name < $1.name }) { entry in
                            HStack {
                                Text(entry.name)
                                Text(entry.bundleID).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("移除") { state.removeFromWhitelist(entry.bundleID) }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            HStack {
                TextField("手动输入 bundle id（如 com.google.Chrome）", text: $manualBundleID)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    let id = manualBundleID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    state.addToWhitelist(bundleID: id, name: id) // 手动输入没有应用名，显示名先用 bundle id（运行时自动补全）
                    manualBundleID = ""
                }
            }
        }
        .padding(16)
        .onAppear { state.refreshRunningApps() }
    }
}

// MARK: - 日志页签

private struct LogTab: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var logs = LogStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if state.permissionGranted {
                    Label("辅助功能已授权", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("未授权辅助功能", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("打开系统设置…") { PermissionManager.openSystemSettings() }
                }
                Spacer()
                Button("清空日志") { logs.clear() }
            }

            List(logs.entries) { entry in
                HStack(alignment: .top) {
                    Text(entry.timeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                }
            }
        }
        .padding(16)
        .onAppear { state.refreshPermission() }
    }
}
