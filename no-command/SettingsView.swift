//
//  SettingsView.swift
//  no-command
//
//  no-command：设置窗口。
//  三个页签：快捷键（预设开关 + 自定义录制）、白名单、日志与权限。
//

import SwiftUI

/// 设置窗口（`Window` 场景，不是 Settings 场景：见 no_commandApp.swift:21-24）
struct SettingsView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        // selection 绑定 AppState：菜单可以直接打开指定页签，窗口重开时保留上次位置
        TabView(selection: $state.settingsTab) {
            ShortcutTab()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            WhitelistTab()
                .tabItem { Label("白名单", systemImage: "checklist") }
                .tag(SettingsTab.whitelist)
            LogTab()
                .tabItem { Label("日志", systemImage: "doc.text") }
                .tag(SettingsTab.logs)
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - 快捷键页签

private struct ShortcutTab: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBanner

            Toggle("总开关：启用快捷键拦截", isOn: $state.masterEnabled)
                .font(.headline)

            GroupBox("预设快捷键") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.presets) { rule in
                        HStack(spacing: 8) {
                            Text(rule.display)
                                .monospacedDigit()
                                .frame(width: 56, alignment: .leading)
                            Text(rule.name)
                                .foregroundStyle(.secondary)
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
                                state.settingsTab = .shortcuts
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
                    if state.customRules.isEmpty {
                        Text("还没有自定义组合。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
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
                                .help("删除这条组合")
                            }
                        }
                    }
                }
                .padding(6)
            }

            Toggle("拦截时播放提示音", isOn: $state.beepOnBlock)

            Spacer(minLength: 0)
        }
        .padding(12)
        .onAppear { state.refreshPermission() }
    }

    /// 顶部状态条：直接把「现在拦不拦」写在最显眼处，并给出对应的下一步动作
    private var statusBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: state.interceptorState == .running
                  ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(state.interceptorState.color)
            Text(state.interceptorState.text)
                .font(.callout)
            Spacer()
            switch state.interceptorState {
            case .running, .paused:
                EmptyView()
            case .unauthorized:
                Button("打开系统设置…") { PermissionManager.openSystemSettings() }
            case .notReady:
                Button("重试启动") { state.refreshPermission() }
            }
        }
        .padding(8)
        .background(state.interceptorState.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 白名单页签

private struct WhitelistTab: View {
    @ObservedObject private var state = AppState.shared
    @State private var manualBundleID = ""
    /// 最近一次添加结果；用于替代原来的静默失败
    @State private var feedback: WhitelistAddResult?
    /// 运行中应用列表的搜索词（应用多时靠滚动找太慢）
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白名单内的 App 不会被拦截（⌘Q 等组合正常生效）。no-command 自身：⌘W 正常关闭设置窗口，⌘Q/⌃⌘Q/⌃⌘W 同样受保护。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索正在运行的应用", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            GroupBox("正在运行的应用（勾选加入白名单）") {
                List(filteredApps) { app in
                    HStack {
                        Text(app.name)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.isWhitelisted(app.bundleID) },
                            set: { on in
                                if on {
                                    feedback = state.addToWhitelist(bundleID: app.bundleID, name: app.name)
                                } else {
                                    state.removeFromWhitelist(app.bundleID)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .frame(height: 150)
                .overlay {
                    // 空态说明：区分「没搜到」和「没有可加入的应用」
                    if filteredApps.isEmpty {
                        Text(search.isEmpty ? "没有可加入白名单的前台应用" : "没有匹配「\(search)」的应用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("已加入白名单（\(state.whitelistEntries.count)）") {
                // List 常驻：空时框内显示提示，有条目时内部滚动，框架高度稳定
                List {
                    if state.whitelistEntries.isEmpty {
                        Text("还没有白名单应用；勾选上方应用或手动输入 bundle id。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(4)
                    } else {
                        ForEach(state.whitelistEntries.sorted { $0.name < $1.name }) { entry in
                            HStack {
                                Text(entry.name)
                                Text(entry.bundleID).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    state.removeFromWhitelist(entry.bundleID)
                                    feedback = nil
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("从白名单移除")
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                TextField("手动输入 bundle id（如 com.google.Chrome）", text: $manualBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addManual() }
                Button("添加") { addManual() }
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // 添加结果就地反馈：成功绿色、无效/自身橙色
            if let feedback {
                Label(feedback.text, systemImage: feedback == .added
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(feedback == .added ? .green : .orange)
            }
        }
        .padding(16)
        .onAppear { state.refreshRunningApps() }
    }

    /// 按名称或 bundle id 过滤运行中应用；搜索词为空时全量
    private var filteredApps: [RunningApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return state.runningApps }
        return state.runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    private func addManual() {
        let id = manualBundleID.trimmingCharacters(in: .whitespaces)
        // 手动输入没有应用名，显示名先用 bundle id（运行时自动补全）
        feedback = state.addToWhitelist(bundleID: id, name: id)
        if feedback == .added || feedback == .exists {
            manualBundleID = ""
        }
    }
}

// MARK: - 日志页签

private struct LogTab: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var logs = LogStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusLabel
                Spacer()
                Text("\(logs.entries.count)/\(LogStore.capacity)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("清空日志") { logs.clear() }
                    .disabled(logs.entries.isEmpty)
            }

            // 最新一条在底部：进入页签或新增日志时自动滚到底，
            // 否则打开日志页看到的是最旧的一屏，用户以为没有新拦截。
            ScrollViewReader { proxy in
                List(logs.entries) { entry in
                    HStack(alignment: .top) {
                        Text(entry.timeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .textSelection(.enabled)
                    }
                    .id(entry.id)
                }
                .overlay {
                    if logs.entries.isEmpty {
                        Text("暂无日志；拦截命中、权限变化会记录在这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear { scrollToLatest(proxy) }
                .onChange(of: logs.entries.count) { _, _ in scrollToLatest(proxy) }
            }
        }
        .padding(16)
        .onAppear { state.refreshPermission() }
    }

    /// 权限状态：与菜单共用 interceptorState 的判定，避免「授权了但没在拦截」显示成正常
    private var statusLabel: some View {
        Label(state.interceptorState.text, systemImage: state.interceptorState == .running
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(state.interceptorState.color)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = logs.entries.last else { return }
        // 列表刚插入时行还没布局，下一轮 runloop 再滚才可靠
        DispatchQueue.main.async {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
