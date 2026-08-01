//
//  KeyboardInterceptor.swift
//  no-command
//
//  no-command：全局键盘拦截器（核心）。
//
//  基于会话级事件 tap（.cgSessionEventTap + .headInsertEventTap）：
//  命中已启用规则的组合键时，回调返回 nil 直接丢弃该事件，前台 App 完全收不到按键。
//
//  前置条件：辅助功能授权（AXIsProcessTrusted，见 PermissionManager）。
//  已知限制：⌃⌘Q 锁屏属系统安全快捷键，可能被 WindowServer/安全层提前处理，
//  普通用户态 App 无法保证拦截；密码框等安全输入模式下的按键也不会进入事件 tap。
//

import Cocoa
import CoreGraphics
import ApplicationServices

/// 全局键盘拦截器（单例，@MainActor）
@MainActor
final class KeyboardInterceptor {

    static let shared = KeyboardInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 防日志刷屏：记录上一次拦截的组合与时间，1 秒内重复拦截只记一次
    private var lastBlockedKey: CGKeyCode = 0
    private var lastBlockedFlags = CGEventFlags()
    private var lastBlockedTime: TimeInterval = 0

    var isRunning: Bool { eventTap != nil }

    private init() {}

    /// 创建并启动事件 tap（须在主线程调用；幂等）。
    /// 未授权时只记录日志，待用户授权后由 refreshPermission() 自动重试。
    func start() {
        guard eventTap == nil else { return }
        guard PermissionManager.isTrusted else {
            LogStore.shared.add("未获得辅助功能授权，拦截未启动（请在系统设置中授权）")
            return
        }

        // 只关心 keyDown；会话级 tap 才能修改/丢弃事件
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        // 通过 userInfo 传递 self，避免 C 回调闭包捕获被隔离的 self
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<KeyboardInterceptor>
                    .fromOpaque(refcon).takeUnretainedValue()
                return interceptor.eventTapCallback(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            LogStore.shared.add("事件 tap 创建失败（权限或系统限制）")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        LogStore.shared.add("键盘拦截已启动")
    }

    /// 停止并释放事件 tap
    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        LogStore.shared.add("键盘拦截已停止")
    }

    /// C 回调（运行在主 RunLoop 上）。
    /// 工程默认 MainActor 隔离，此处显式 nonisolated，
    /// 再用 MainActor.assumeIsolated 切回主线程处理（回调本身在主 RunLoop，安全且零开销）。
    private nonisolated func eventTapCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统可能因超时/权限变化自动禁用 tap：收到事件即重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap = self.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                LogStore.shared.add("事件 tap 被系统禁用，已自动恢复")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        return MainActor.assumeIsolated {
            if self.handle(keyCode: keyCode, flags: flags) {
                return nil // 丢弃事件：前台 App 收不到
            }
            return Unmanaged.passUnretained(event)
        }
    }

    /// 决策：返回 true 表示拦截（丢弃事件）
    private func handle(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let state = AppState.shared

        // 录制模式：捕获组合键并生成规则，不拦截
        if state.isRecording {
            state.handleRecording(keyCode: keyCode, flags: flags)
            return false
        }

        guard state.masterEnabled else { return false }

        // 自身 / 白名单内的前台 App 恒放行
        let front = NSWorkspace.shared.frontmostApplication
        let frontID = front?.bundleIdentifier
        if frontID == AppState.selfBundleID || state.isWhitelisted(frontID) {
            return false
        }

        guard let rule = state.matchRule(keyCode: keyCode, flags: flags) else { return false }

        // 防日志刷屏：同一组合 1 秒内只记录一次（拦截行为不受影响）
        let now = Date().timeIntervalSince1970
        if keyCode != lastBlockedKey || flags != lastBlockedFlags || now - lastBlockedTime > 1.0 {
            lastBlockedKey = keyCode
            lastBlockedFlags = flags
            lastBlockedTime = now
            let appName = front?.localizedName ?? "未知应用"
            LogStore.shared.add("拦截 \(rule.display)（前台 \(appName)）")
        }

        if state.beepOnBlock {
            NSSound.beep()
        }
        return true
    }
}
