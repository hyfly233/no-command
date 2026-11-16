//
//  UIState.swift
//  no-command
//
//  no-command：界面共享的运行状态与页签定义。
//  状态文案与颜色集中在此，菜单与设置窗口保持一致，避免两处判断漂移。
//

import SwiftUI

/// 拦截器运行状态：由 AppState 派生，菜单与设置窗口共用同一套文案与颜色，
/// 避免「授权有效但事件 tap 创建失败」时界面仍显示正常。
enum InterceptorState {
    /// 总开关开、已授权、事件 tap 已创建
    case running
    /// 总开关关闭：全部放行
    case paused
    /// 缺少辅助功能授权：拦截未安装，⌘Q 等会正常生效
    case unauthorized
    /// 已授权但事件 tap 未创建（创建失败，原因见日志）
    case notReady

    /// 一行状态说明
    var text: String {
        switch self {
        case .running: return "拦截中"
        case .paused: return "已暂停（总开关关闭，全部放行）"
        case .unauthorized: return "未授权辅助功能（⌘Q 等仍会正常生效）"
        case .notReady: return "拦截未就绪（事件 tap 未创建，详见日志）"
        }
    }

    /// 状态点/文字颜色
    var color: Color {
        switch self {
        case .running: return .green
        case .paused: return .gray
        case .unauthorized: return .orange
        case .notReady: return .red
        }
    }
}

/// 设置窗口页签（菜单可直接跳到指定页签）
enum SettingsTab: Hashable {
    case shortcuts
    case whitelist
    case logs
}

/// 手动/勾选添加白名单的结果，供界面给出明确反馈（而不是静默失败）
enum WhitelistAddResult: Equatable {
    case added
    case exists
    case blockedSelf
    case invalid

    var text: String {
        switch self {
        case .added: return "已加入白名单"
        case .exists: return "已在白名单中"
        case .blockedSelf: return "no-command 自身不能加入白名单（⌘W 已单独放行）"
        case .invalid: return "bundle id 格式不正确，示例：com.google.Chrome"
        }
    }
}
