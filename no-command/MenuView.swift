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
        VStack(alignment: .leading, spacing: 10) {
            header

            statusCard

            Toggle("启用拦截", isOn: $state.masterEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            presetSection

            Divider()

            logPreview

            Divider()

            footerButtons
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { state.refreshPermission() }
    }

    // MARK: - 子视图

    /// 头部：名称 + 运行状态点
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
                .foregroundStyle(.secondary)
            Text("no-command")
                .font(.headline)
            Spacer()
            Circle()
                .fill(state.interceptorState.color)
                .frame(width: 8, height: 8)
        }
    }

    /// 状态卡：用背景色把「现在到底拦不拦」做成一眼可见的信号，
    /// 并直接给出下一步动作（授权 / 重试），不用再翻设置窗口。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.interceptorState == .running
                      ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                Text(state.interceptorState.text)
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(state.interceptorState.color)

            switch state.interceptorState {
            case .running, .paused:
                EmptyView()
            case .unauthorized:
                Button("打开系统设置…") { PermissionManager.openSystemSettings() }
                    .controlSize(.small)
            case .notReady:
                Button("重试启动") { state.refreshPermission() }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.interceptorState.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    /// 预设开关 + 生效中的自定义组合数量
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("预设组合")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.presets) { rule in
                Toggle(isOn: Binding(
                    get: { state.enabledPresetIDs.contains(rule.id) },
                    set: { on in
                        if on { state.enabledPresetIDs.insert(rule.id) }
                        else { state.enabledPresetIDs.remove(rule.id) }
                    }
                )) {
                    Text(rule.display).monospacedDigit()
                }
                .toggleStyle(.checkbox)
            }
            let customCount = state.customRules.filter(\.isEnabled).count
            if customCount > 0 {
                Text("另有 \(customCount) 条自定义组合生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 最近一条拦截日志：点击直达日志页签
    private var logPreview: some View {
        Button {
            openSettings(.logs)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(logs.entries.last?.message ?? "暂无拦截记录")
                        .font(.caption)
                        .foregroundStyle(logs.entries.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !logs.entries.isEmpty {
                        Text("查看全部日志")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开日志页签")
    }

    /// 底部入口：直接落到对应页签，省一次切换
    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                openSettings(.shortcuts)
            } label: {
                Label("快捷键设置…", systemImage: "gearshape")
            }
            Button {
                openSettings(.whitelist)
            } label: {
                Label("白名单设置…", systemImage: "checklist")
            }
            Button { NSApp.terminate(nil) } label: {
                Label("退出", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
    }

    /// 打开设置窗口并确保置顶；tab 决定首次打开时落在哪一页。
    /// LSUIElement 菜单栏 App 默认不会成为前台激活应用，直接 openWindow 时
    /// 窗口会排在别的应用窗口后面；因此先激活 App，再对窗口强制置前兜底。
    private func openSettings(_ tab: SettingsTab) {
        state.settingsTab = tab
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
