//
//  LogStore.swift
//  no-command
//
//  no-command：拦截日志。
//  os.Logger 输出到系统日志（便于 log stream 观察），同时保留内存环形缓冲供菜单/设置窗口展示。
//

import Combine
import Foundation
import os

/// 日志存储：os.Logger + 内存环形缓冲（上限 200 条）
@MainActor
final class LogStore: ObservableObject {

    static let shared = LogStore()

    private let logger = Logger(subsystem: "com.hyfly.no-command", category: "interceptor")
    private let capacity = 200

    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    /// 追加一条日志
    func add(_ message: String) {
        let entry = LogEntry(time: Date(), message: message)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        // privacy: .public 允许 log show / log stream 读取
        logger.info("\(message, privacy: .public)")
    }

    /// 清空内存日志（不影响系统日志）
    func clear() {
        entries.removeAll()
    }
}
