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
    /// 自身 bundle id：前台是自身时仅 ⌘W 放行（可关设置窗口），⌘Q/⌃⌘Q/⌃⌘W 照常拦截；退出走菜单按钮
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
        // ⌥⌘Q：部分 App 用它做「退出并恢复窗口」类操作，加入预设一并拦截
        ShortcutRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                     name: "退出应用（⌥⌘Q）", keyCode: 12,
                     requiresCommand: true, requiresControl: false,
                     requiresOption: true, requiresShift: false,
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
    /// 白名单条目（bundle id + 持久化显示名）
    @Published var whitelistEntries: [WhitelistEntry] {
        didSet { saveJSON(whitelistEntries, key: "whitelistEntries") }
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
        // 预设启用集合：用局部变量计算后再一次性赋值（init 中在全部存储属性初始化前读写 self 会被编译器拒绝）
        var enabled: Set<UUID>
        // 区分「从未保存」（默认全开）与「用户全部关掉」（空数组），避免误重置
        if let savedIDs = defaults.stringArray(forKey: "enabledPresetIDs") {
            enabled = Set(savedIDs.compactMap { UUID(uuidString: $0) })
        } else {
            enabled = Set(presets.map(\.id))
        }
        // 升级兼容：新版本新增的预设规则（如 ⌥⌘Q）首次出现时默认启用，
        // 之后以用户手动开关为准（knownPresetIDs 记录已见过的预设 id，只补一次）
        let allPresetIDs = Set(presets.map(\.id))
        let knownPresetIDs = Set((defaults.stringArray(forKey: "knownPresetIDs") ?? []).compactMap { UUID(uuidString: $0) })
        enabled.formUnion(allPresetIDs.subtracting(knownPresetIDs))
        defaults.set(allPresetIDs.map(\.uuidString), forKey: "knownPresetIDs")
        enabledPresetIDs = enabled
        if let data = defaults.data(forKey: "customRules"),
           let rules = try? JSONDecoder().decode([ShortcutRule].self, from: data) {
            customRules = rules
        } else {
            customRules = []
        }
        // 白名单：优先读新版（带显示名的条目）；兼容旧版（纯 bundle id 数组）迁移，
        // 旧条目的显示名在应用运行时会被 refreshRunningApps 自动补全
        if let data = defaults.data(forKey: "whitelistEntries"),
           let entries = try? JSONDecoder().decode([WhitelistEntry].self, from: data) {
            whitelistEntries = entries
        } else if let old = defaults.stringArray(forKey: "whitelist") {
            whitelistEntries = old.map { WhitelistEntry(bundleID: $0, name: $0) }
            defaults.removeObject(forKey: "whitelist")
        } else {
            whitelistEntries = []
        }
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
        return whitelistEntries.contains { $0.bundleID == bundleID }
    }

    /// 加入白名单（记录显示名，应用退出后仍显示名字）。
    /// 自身 bundle id 禁止加入：若自身在白名单中，前台是自身时会因白名单而全部放行，
    /// 导致 ⌘Q 关掉设置窗口/退掉 App 的问题再次出现（自身只应放行 ⌘W，见 KeyboardInterceptor）。
    func addToWhitelist(bundleID: String, name: String) {
        guard bundleID != AppState.selfBundleID else { return }
        if let idx = whitelistEntries.firstIndex(where: { $0.bundleID == bundleID }) {
            whitelistEntries[idx].name = name // 已有则更新显示名
        } else {
            whitelistEntries.append(WhitelistEntry(bundleID: bundleID, name: name))
        }
    }

    func removeFromWhitelist(_ bundleID: String) {
        whitelistEntries.removeAll { $0.bundleID == bundleID }
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

    /// 刷新运行中应用列表（供白名单选择），并顺手补全白名单条目的持久化显示名
    func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular } // 只列常规前台应用，过滤菜单栏/后台代理
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier else { return nil }
                return RunningApp(bundleID: id, name: app.localizedName ?? id)
            }
        runningApps = apps.sorted { $0.name < $1.name }

        // 运行中的应用在名单内时，刷新持久化显示名（didSet 自动保存）；
        // 兼容旧数据迁移（name == bundleID）与手动输入的条目
        for app in runningApps {
            if let idx = whitelistEntries.firstIndex(where: { $0.bundleID == app.bundleID }),
               whitelistEntries[idx].name != app.name {
                whitelistEntries[idx].name = app.name
            }
        }
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
