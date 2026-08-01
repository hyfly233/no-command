//
//  AppState.swift
//  no-command
//
//  no-command：全局应用状态。
//  配置持久化（UserDefaults）+ 白名单 + 运行中应用 + 自定义组合录制状态。
//
//  说明：这里不用 @AppStorage，而是 @Published + 手动同步 UserDefaults，
//  因为 @AppStorage 不触发 objectWillChange，菜单与设置窗口之间无法实时联动。
//

import AppKit
import Combine
import Foundation

/// 全局应用状态（单例）
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()
    /// 自身 bundle id：前台是自身时恒放行（否则 no-command 无法退出/设置窗口无法关闭）
    static let selfBundleID = Bundle.main.bundleIdentifier ?? "com.hyfly.no-command"

    // MARK: - 预设规则（固定定义；启用状态持久化在 enabledPresetIDs）
    let presets: [ShortcutRule] = [
        ShortcutRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                     name: "退出应用", keyCode: 12,
                     requiresCommand: true, requiresControl: false,
                     requiresOption: false, requiresShift: false,
                     isEnabled: true, isPreset: true),
        ShortcutRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                     name: "关闭窗口", keyCode: 13,
                     requiresCommand: true, requiresControl: false,
                     requiresOption: false, requiresShift: false,
                     isEnabled: true, isPreset: true),
        ShortcutRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                     name: "锁屏（系统安全快捷键，可能无法拦截）", keyCode: 12,
                     requiresCommand: true, requiresControl: true,
                     requiresOption: false, requiresShift: false,
                     isEnabled: true, isPreset: true),
        ShortcutRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                     name: "关闭全部窗口", keyCode: 13,
                     requiresCommand: true, requiresControl: true,
                     requiresOption: false, requiresShift: false,
                     isEnabled: true, isPreset: true),
    ]

    // MARK: - 持久化配置
    /// 总开关（紧急逃生口：关闭后全部放行）
    @Published var masterEnabled: Bool {
        didSet { UserDefaults.standard.set(masterEnabled, forKey: "masterEnabled") }
    }
    /// 拦截时播放系统提示音
    @Published var beepOnBlock: Bool {
        didSet { UserDefaults.standard.set(beepOnBlock, forKey: "beepOnBlock") }
    }
    /// 已启用的预设规则 id 集合
    @Published var enabledPresetIDs: Set<UUID> {
        didSet { UserDefaults.standard.set(enabledPresetIDs.map(\.uuidString), forKey: "enabledPresetIDs") }
    }
    /// 自定义规则（完整持久化）
    @Published var customRules: [ShortcutRule] {
        didSet { saveJSON(customRules, key: "customRules") }
    }
    /// 白名单 bundle id 集合
    @Published var whitelist: Set<String> {
        didSet { UserDefaults.standard.set(Array(whitelist), forKey: "whitelist") }
    }

    // MARK: - 运行时状态
    /// 辅助功能是否已授权（刷新时机：启动 / 应用激活 / 菜单打开）
    @Published var permissionGranted = false
    /// 正在录制自定义组合
    @Published var isRecording = false
    /// 录制提示 / 最近操作提示
    @Published var recordingMessage = ""
    /// 运行中的应用（白名单勾选用）
    @Published var runningApps: [RunningApp] = []

    private init() {
        let defaults = UserDefaults.standard
        masterEnabled = defaults.object(forKey: "masterEnabled") as? Bool ?? true
        beepOnBlock = defaults.object(forKey: "beepOnBlock") as? Bool ?? false
        // 区分「从未保存」（默认全开）与「用户全部关掉」（空数组），避免误重置
        if let savedIDs = defaults.stringArray(forKey: "enabledPresetIDs") {
            enabledPresetIDs = Set(savedIDs.compactMap { UUID(uuidString: $0) })
        } else {
            enabledPresetIDs = Set(presets.map(\.id))
        }
        if let data = defaults.data(forKey: "customRules"),
           let rules = try? JSONDecoder().decode([ShortcutRule].self, from: data) {
            customRules = rules
        } else {
            customRules = []
        }
        whitelist = Set(defaults.stringArray(forKey: "whitelist") ?? [])
    }

    // MARK: - 查询与操作

    /// 命中并已启用了一条规则则返回该规则，否则 nil
    func matchRule(keyCode: CGKeyCode, flags: CGEventFlags) -> ShortcutRule? {
        for p in presets where enabledPresetIDs.contains(p.id) && p.matches(keyCode: keyCode, flags: flags) {
            return p
        }
        for c in customRules where c.isEnabled && c.matches(keyCode: keyCode, flags: flags) {
            return c
        }
        return nil
    }

    /// 白名单判定（前台 app bundle id）
    func isWhitelisted(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return whitelist.contains(bundleID)
    }

    func addToWhitelist(_ bundleID: String) {
        whitelist.insert(bundleID)
    }

    func removeFromWhitelist(_ bundleID: String) {
        whitelist.remove(bundleID)
    }

    /// 上一次记录的授权状态（仅状态变化时记日志，避免刷屏）
    private var lastLoggedGranted: Bool?

    /// 刷新权限状态；权限就绪且拦截器未启动时自动拉起
    func refreshPermission() {
        let granted = PermissionManager.isTrusted
        permissionGranted = granted
        if granted {
            KeyboardInterceptor.shared.start()
        }
        // 状态变化时记一条日志，保证启动/授权链路可观测（log stream 可见）
        if lastLoggedGranted != granted {
            lastLoggedGranted = granted
            if granted {
                LogStore.shared.add("辅助功能已授权，键盘拦截启动")
            } else {
                LogStore.shared.add("未获得辅助功能授权，拦截未启动（系统设置 → 隐私与安全性 → 辅助功能）")
            }
        }
    }

    /// 刷新运行中应用列表（供白名单选择）
    func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular } // 只列常规前台应用，过滤菜单栏/后台代理
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier else { return nil }
                return RunningApp(bundleID: id, name: app.localizedName ?? id)
            }
        runningApps = apps.sorted { $0.name < $1.name }
    }

    /// 白名单 bundle id → 显示名（应用未运行时回退原始 id）
    func whitelistDisplay(_ bundleID: String) -> String {
        runningApps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
    }

    // MARK: - 自定义组合录制

    /// 录制回调：Esc 取消；无修饰键继续等待；有效组合生成规则
    func handleRecording(keyCode: CGKeyCode, flags: CGEventFlags) {
        // Esc（53，无修饰键）取消录制
        if keyCode == 53 && !hasAnyModifier(flags) {
            isRecording = false
            recordingMessage = "已取消录制"
            return
        }
        guard hasAnyModifier(flags) else {
            recordingMessage = "请包含至少一个修饰键（⌘/⌃/⌥/⇧）…"
            return
        }
        let rule = ShortcutRule(
            id: UUID(),
            name: "自定义组合",
            keyCode: keyCode,
            requiresCommand: flags.contains(.maskCommand),
            requiresControl: flags.contains(.maskControl),
            requiresOption: flags.contains(.maskAlternate),
            requiresShift: flags.contains(.maskShift),
            isEnabled: true,
            isPreset: false
        )
        customRules.append(rule)
        isRecording = false
        recordingMessage = "已添加：\(rule.display)"
    }

    /// 手动取消录制
    func cancelRecording() {
        isRecording = false
        recordingMessage = "已取消录制"
    }

    /// 删除自定义规则
    func deleteCustomRule(_ rule: ShortcutRule) {
        customRules.removeAll { $0.id == rule.id }
    }

    private func hasAnyModifier(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate) || flags.contains(.maskShift)
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
