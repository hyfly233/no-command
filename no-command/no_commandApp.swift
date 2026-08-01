//
//  no_commandApp.swift
//  no-command
//
//  no-command：菜单栏常驻的全局快捷键保护工具。
//  拦截 ⌘Q / ⌘W / ⌃⌘Q / ⌃⌘W（及自定义组合），防止误触退出、关窗、锁屏。
//

import SwiftUI

@main
struct no_commandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("no-command", systemImage: "keyboard") {
            MenuView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
