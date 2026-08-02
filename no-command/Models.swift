//
//  Models.swift
//  no-command
//
//  no-command：快捷键规则与日志条目的数据模型。
//

import Foundation
import CoreGraphics

/// 一条拦截规则：一个「修饰键 + 主键」组合。
struct ShortcutRule: Identifiable, Codable, Equatable {
    var id: UUID
    /// 规则名称（预设规则为固定名，自定义规则标识来源）
    var name: String
    /// 主键物理键位（keyCode 是物理键位，不受键盘布局/输入法影响）
    var keyCode: CGKeyCode
    /// 是否要求 ⌘
    var requiresCommand: Bool
    /// 是否要求 ⌃
    var requiresControl: Bool
    /// 是否要求 ⌥
    var requiresOption: Bool
    /// 是否要求 ⇧
    var requiresShift: Bool
    /// 是否启用（自定义规则持久化此字段；预设规则的启用以 AppState.enabledPresetIDs 为准）
    var isEnabled: Bool
    /// 是否为预设规则（预设不可删除）
    var isPreset: Bool

    /// 判断一次按键事件是否精确命中本规则。
    /// 精确匹配：要求的修饰键必须按下，未要求的必须未按下，
    /// 避免 ⌥⌘Q、⌃⌥⌘Q 等被误判为 ⌘Q。
    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard keyCode == self.keyCode else { return false }
        func down(_ flag: CGEventFlags) -> Bool { flags.contains(flag) }
        return down(.maskCommand) == requiresCommand
            && down(.maskControl) == requiresControl
            && down(.maskAlternate) == requiresOption
            && down(.maskShift) == requiresShift
    }

    /// 人类可读的组合显示，如 ⌃⌥⇧⌘Q
    var display: String {
        var s = ""
        if requiresControl { s += "⌃" }
        if requiresOption { s += "⌥" }
        if requiresShift { s += "⇧" }
        if requiresCommand { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    /// 按键码 → 显示名。
    /// 注意：keyCode 是物理键位（kVK_ANSI_*），字母区按物理位置排布
    /// （A S D F H G Z X C V B Q W E R Y T…），不是字母表顺序，数字行/F 键也不连续，
    /// 因此必须用显式映射表，不能用 ASCII 推算。
    /// 本表已用 Carbon kVK_ANSI_* 系统常量逐项校验。
    private func keyName(for code: CGKeyCode) -> String {
        switch Int(code) {
        // ANSI 字母区（物理键位）
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        // 数字行与符号
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 33: return "["
        case 39: return "'"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 47: return "."
        case 50: return "`"
        // 特殊键
        case 36: return "⏎"
        case 48: return "⇥"
        case 49: return "空格"
        case 51: return "⌫"
        case 53: return "Esc"
        // 功能键
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        // 方向键
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "键\(code)"
        }
    }
}

/// 日志条目（时间 + 内容）
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let message: String

    /// 显示用时间文本
    var timeText: String {
        time.formatted(date: .omitted, time: .standard)
    }
}

/// 运行中的应用（白名单勾选用）
struct RunningApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

/// 白名单条目：bundle id + 显示名。
/// 显示名随条目持久化——应用未运行时也能显示名字，而不是回退成 bundle id。
struct WhitelistEntry: Identifiable, Codable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var name: String
}
