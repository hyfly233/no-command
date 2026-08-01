# no-command — macOS 菜单栏快捷键保护工具（开发计划）

> 目标：菜单栏常驻工具，全局拦截 `⌘Q` / `⌘W` / `⌃⌘Q` / `⌃⌘W`，防止误触退出/关窗/锁屏。
> 附带功能：菜单开关、App 白名单、快捷键配置、拦截日志。
> 本计划评审确认后开始实现。按用户工作流：不 git commit，改动留工作区，交付时附验证清单。

---

## 1. 现状（已核实）

| 项 | 现状 | 结论 |
|---|---|---|
| Xcode 工程 | `no-command.xcodeproj`（Xcode 26.6 模板，objectVersion 77） | 可用，不需要 xcodegen |
| 工程组织 | `PBXFileSystemSynchronizedRootGroup`（文件系统同步分组） | **新增 .swift 文件只需放入 `no-command/` 目录，自动进 target，无需手改 pbxproj** |
| Bundle ID | `com.hyfly.no-command` | 保持不变（TCC 授权与 bundle id/签名绑定，改了会掉权限） |
| 签名 | 开发团队 `8MFNJGDG8Z`，Automatic | 自动签名身份稳定，重编译不掉辅助功能授权 |
| App Sandbox | `ENABLE_APP_SANDBOX = YES`（模板默认） | **必须改为 NO**，否则事件 tap 与辅助功能授权均不可用 |
| 现有代码 | `no_commandApp.swift`（WindowGroup）+ `ContentView.swift`（Hello world） | 将删除，替换为 MenuBarExtra 结构 |

部署目标 `MACOSX_DEPLOYMENT_TARGET = 26.5`，Swift 5 语言模式 + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（默认主线程隔离，注意 CGEventTap 回调的并发处理，见 §5）。

## 2. 产品行为

| 场景 | 行为 |
|---|---|
| 前台 App 按 `⌘Q` | 丢弃事件，App 不退出；记录日志（可选提示音） |
| 前台 App 按 `⌘W` | 丢弃事件，窗口不关闭；记录日志 |
| 前台 App 按 `⌃⌘Q` | 尽力拦截锁屏（⚠️ 系统安全层可能抢先处理，见 §5） |
| 前台 App 按 `⌃⌘W` | 丢弃事件，拦截"关闭所有窗口"类操作 |
| 前台 App 在白名单内 / 就是 no-command 自身 | 放行，不拦截 |
| 总开关关闭 | 全部放行（紧急逃生口） |

## 3. 技术方案

| 需求 | 方案 | 说明 |
|---|---|---|
| 全局键盘拦截 | `CGEventTap`，`tap: .cgSessionEventTap`、`place: .headInsertEventTap`、`eventsOfInterest: keyDown`，回调 `return nil` 丢弃事件 | CoreGraphics.framework；会话级 tap 可修改/丢弃事件 |
| 权限 | **辅助功能（Accessibility）**：`AXIsProcessTrusted()` 检查，引导跳转 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` | 会话级 tap 需要辅助功能；「输入监控」只适用于只监听不改写的 listen tap，本项目不需要 |
| 前台 App 判断 | `NSWorkspace.shared.frontmostApplication`（bundleIdentifier + localizedName） | 白名单匹配用 bundle id |
| 配置持久化 | `@AppStorage`（UserDefaults） | 各开关、白名单 JSON、提示音开关 |
| 日志 | `os.Logger`（subsystem `com.hyfly.no-command`）+ 内存环形缓冲（上限 200 条） | 菜单/设置窗口内可查看，可清空 |
| 菜单栏 | SwiftUI `MenuBarExtra`（SF Symbol `keyboard`）+ `Settings` 场景（macOS 14+ `SettingsLink` 打开设置窗口） | LSUIElement 隐藏 Dock 图标 |
| 白名单管理 | 设置窗口内列出正在运行的 App（勾选加入/移出），也可手动输入 bundle id | |

## 4. 快捷键定义（ANSI 按键码）

| 组合 | keyCode | modifiers 判定 | 系统含义 | 预期可拦截性 |
|---|---|---|---|---|
| `⌘Q` | 12 (Q) | command，且 **无** control/option | 退出 App | ✅ 可靠 |
| `⌘W` | 13 (W) | command，且 **无** control/option | 关闭窗口 | ✅ 可靠 |
| `⌃⌘Q` | 12 (Q) | command + control | 锁屏 | ⚠️ 尽力拦截，实测验证 |
| `⌃⌘W` | 13 (W) | command + control | App 内"关闭全部窗口" | ✅ 可靠（无全局系统级处理，tap 先于 App 收到） |

> 说明：keyCode 是物理键位，不受输入法/键盘布局影响（中文输入法下 `⌘Q` 依然 keyCode 12）。

## 5. 系统限制与对策（诚实标注）

| # | 限制 | 对策 |
|---|---|---|
| L1 | `⌃⌘Q` 锁屏属于系统安全快捷键，事件可能被 WindowServer/安全子系统提前处理，普通用户态 App **无法保证拦截** | 照常实现（注册为可配置项），运行时实测；若无效，在设置窗口标注"系统限制，可能无效"，并在 README 说明替代方案（系统设置改快捷键 / Karabiner-Elements） |
| L2 | 密码输入、sudo、任何 **安全输入模式（Secure Input）** 下的按键事件不会进入事件 tap（防键盘记录设计） | 无法拦截，README 注明；不尝试绕过 |
| L3 | App Sandbox 开启时无法使用会话级事件 tap、无法获得辅助功能授权 | 关闭沙箱（`ENABLE_APP_SANDBOX = NO`），保持自动签名 |
| L4 | 事件 tap 回调是 C 函数（nonisolated），而工程默认 MainActor 隔离 | 用 `userInfo` 传 self（`Unmanaged.passUnretained`），回调内 `MainActor.assumeIsolated` 切回主线程再处理（回调本身跑在主 RunLoop 上，安全） |
| L5 | tap 可能因超时/权限变化被系统自动禁用（收到 `.tapDisabledByTimeout` / `.tapDisabledByUserInput`） | 回调中检测到即重新 `CGEvent.tapEnable` |
| L6 | 若用 ad-hoc 签名（`-s -`），每次重编译签名身份变化 → TCC 授权失效，需重新授权 | 本工程用开发团队自动签名，身份稳定，不踩此坑 |
| L7 | 菜单栏 App 自身被激活时（点菜单）不应拦截自己的 `⌘Q` | 前台是自身 bundle id 时恒放行；另提供菜单「退出 no-command」入口 |

## 6. 功能清单（优先级）

### P0 — 可运行的骨架（✅ 已完成）
- [x] 工程配置：关闭沙箱；`INFOPLIST_KEY_LSUIElement = YES`；`CFBundleDisplayName = no-command`
- [x] 删除模板 `ContentView.swift`、重写 `no_commandApp.swift` 为 MenuBarExtra 结构（保留文件名，避免动工程引用）
- [x] `KeyboardInterceptor`：事件 tap 创建/启用/停用、tapDisabled 自恢复、四组合判定
- [x] `PermissionManager`：辅助功能状态检查 + 引导跳转系统设置 + 前台激活时自动重查
- [x] 菜单栏 UI 最小版：总开关、四组合开关、权限状态、退出

### P1 — 完整功能（✅ 已完成）
- [x] `AppState`：@Published + UserDefaults 配置模型（总开关、4 个快捷键开关、提示音、白名单）
- [x] 白名单：前台 App bundle id 匹配放行；设置窗口列出运行中 App 勾选管理 + 手动输入
- [x] 设置窗口（`Settings` 场景）：快捷键配置、白名单管理、权限引导
- [x] 日志：os.Logger + 环形缓冲，设置窗口内查看 + 清空；拦截时记录「时间 / 组合 / 前台 App / 放行或拦截」
- [x] 拦截提示音开关（NSSound.beep，默认关）

### P2 — 增强
- [x] 自定义快捷键组合录制（录制模式下按任意组合键存为规则，Esc 取消）— 用户选定方案 B，已实现
- [ ] 开机自启（`SMAppService.mainApp`，macOS 13+）— 未做，需要时再加
- [ ] 打包发布脚本（Release + 公证说明）— 未做，需要时再加

## 7. 文件结构（全部在 `no-command/` 目录，自动进 target）

| 文件 | 职责 |
|---|---|
| `no_commandApp.swift` | `@main`，MenuBarExtra 场景 + Settings 场景 + AppDelegate 适配（激活策略） |
| `Models.swift` | `ShortcutKind` 枚举（名称/keyCode/修饰键/是否启用）、日志条目结构 |
| `AppState.swift` | ObservableObject，@AppStorage 配置 + 白名单 + 运行中 App 列表 |
| `KeyboardInterceptor.swift` | CGEventTap 生命周期 + 按键判定 + 放行/拦截决策（核心） |
| `PermissionManager.swift` | AXIsProcessTrusted 检查 + 跳转设置 + 状态回调 |
| `LogStore.swift` | os.Logger 封装 + 内存环形缓冲（ObservableObject） |
| `MenuView.swift` | MenuBarExtra 内容（紧凑版：总开关、四组合、状态、设置、退出） |
| `SettingsView.swift` | 设置窗口（快捷键、白名单、权限引导、日志） |
| `Info.plist`（可省） | 无特殊键；全部用 `INFOPLIST_KEY_*` 生成 |

## 8. 实施步骤（顺序）

1. **工程配置**：patch pbxproj → `ENABLE_APP_SANDBOX = NO`（Debug/Release）、`INFOPLIST_KEY_LSUIElement = YES`、`INFOPLIST_KEY_CFBundleDisplayName = no-command`
2. **核心**：`Models.swift` → `LogStore.swift` → `PermissionManager.swift` → `KeyboardInterceptor.swift` → `AppState.swift`
3. **UI**：`MenuView.swift` → `SettingsView.swift` → 重写 `no_commandApp.swift`
4. **构建验证**：`xcodebuild -project no-command.xcodeproj -scheme no-command -configuration Debug -derivedDataPath build build`，零报错
5. **冒烟运行**：启动 App，验证菜单栏图标、权限状态显示、日志输出（`log stream` 订阅 subsystem）
6. **拦截实测**（需用户授权后）：按 §9 清单逐项验证

## 9. 验证清单（交付后用户执行）

```bash
# 1. 构建
xcodebuild -project no-command.xcodeproj -scheme no-command -configuration Debug -derivedDataPath build build
# 2. 启动
open build/Build/Products/Debug/no-command.app
# 3. 授权：菜单栏图标 → 权限状态 ⚠️ → 点击打开系统设置 → 辅助功能 → 勾选 no-command（若授权成功状态变 ✓）
# 4. 实测：
#    - 打开任意 App（如 Chrome），按 ⌘Q → App 不退出，日志出现拦截记录
#    - 按 ⌘W → 窗口不关闭，日志出现拦截记录
#    - 按 ⌃⌘Q → 观察是否锁屏（记录真实结果，L1 风险项）
#    - 按 ⌃⌘W → 不触发关闭全部窗口
#    - 关闭总开关 → ⌘Q 恢复正常退出
#    - 将 Chrome 加入白名单 → Chrome 前台时 ⌘Q 正常退出
#    - 在 no-command 菜单打开状态按 ⌘Q → no-command 正常退出（自身放行）
# 5. 日志订阅
log stream --predicate 'subsystem == "com.hyfly.no-command"'
```

## 10. 待确认问题

1. **快捷键配置范围**：
   - 方案 A：仅 4 个预设组合的开关（⌘Q / ⌘W / ⌃⌘Q / ⌃⌘W）—— 基础版，工作量小
   - 方案 B：A + 自定义组合录制（在设置里点"录制"，按下任意组合键保存为自定义拦截规则）—— 更灵活，工作量明显增大
2. 产品名用 no-command（菜单栏标题），工程名/bundle id 保持 `no-command` 不动 —— 默认如此，有异议请指出
3. 拦截时是否需要桌面级提示（浮窗/通知）？默认仅日志 + 可选提示音，不做浮窗（避免过度设计）
