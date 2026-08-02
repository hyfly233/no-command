# no-command — macOS 菜单栏快捷键保护工具

菜单栏常驻工具，全局拦截 `⌘Q` / `⌘W` / `⌃⌘Q` / `⌃⌘W`（以及自定义组合键），防止误触退出应用、关闭窗口、锁屏。适用于直播/游戏/演示/防误操作场景。

## 功能

- **预设拦截**：⌘Q（退出应用）、⌘W（关闭窗口）、⌃⌘Q（锁屏）、⌃⌘W（关闭全部窗口）
- **自定义组合录制**：设置窗口点「录制新组合」，按任意组合键即生成拦截规则
- **App 白名单**：白名单内的前台应用不拦截（按 bundle id 匹配）
- **总开关**：一键全部放行（紧急逃生口）
- **拦截日志**：系统日志（`log stream`）+ 设置窗口内实时查看
- **提示音**：可选，拦截时播放系统提示音

## 构建与运行

```bash
# 构建（Debug）
xcodebuild -project no-command.xcodeproj -scheme no-command -configuration Debug -derivedDataPath build build

# 运行
open build/Build/Products/Debug/no-command.app
```

## 首次使用：授权辅助功能

会话级事件 tap 需要「辅助功能」权限（不是「输入监控」）：

1. 启动 App，点击菜单栏 ⌨️ 图标
2. 菜单中显示「需要辅助功能授权」→ 点击「打开系统设置…」
3. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 **no-command**
4. 回到 App 后状态自动变为「辅助功能已授权」（应用激活时自动检测）

> 授权与 bundle id + 签名身份绑定。本工程使用开发团队自动签名（`8MFNJGDG8Z`），重编译不会掉授权。若换成 ad-hoc 签名（`codesign -s -`），每次重编译都会要求重新授权。

## 验证清单

| # | 操作 | 预期 |
|---|---|---|
| 1 | 打开任意应用（如 Chrome），按 `⌘Q` | 应用不退出，日志出现「拦截 ⌘Q」 |
| 2 | 按 `⌘W` | 窗口不关闭 |
| 3 | 按 `⌃⌘Q` | 观察是否锁屏（⚠️ 系统限制，可能无效，见下） |
| 4 | 按 `⌃⌘W` | 不触发关闭全部窗口 |
| 5 | 关闭总开关后按 `⌘Q` | 恢复正常退出 |
| 6 | 将某应用加入白名单，该应用前台按 `⌘Q` | 正常退出 |
| 7 | no-command 自身（设置窗口前台）按 `⌘Q` | 被拦截：设置窗口不关闭、App 不退出（⌘W 可正常关窗口） |
| 8 | 设置 → 录制新组合，按 `⌥⌘F` | 生成规则 ⌥⌘F，此后该组合被拦截；Esc 取消录制 |

系统日志观察：

```bash
log stream --predicate 'subsystem == "com.hyfly.no-command"'
```

## 已知限制（系统行为，非缺陷）

| 限制 | 说明 |
|---|---|
| `⌃⌘Q` 锁屏可能无法拦截 | 属系统安全快捷键，事件可能被 WindowServer/安全层提前处理，普通用户态 App 无法保证拦截。若无效，可改用系统设置修改该快捷键，或使用 Karabiner-Elements |
| 安全输入模式无法拦截 | 密码框、sudo 等安全输入（Secure Input）下的按键不进入事件 tap（防键盘记录设计），`⌘Q` 等在该场景不可拦截 |
| 必须关闭沙箱 | App Sandbox 会阻止会话级事件 tap 与辅助功能授权；本工程已关闭 |
| 需要辅助功能权限 | 未授权时拦截不生效，App 菜单与设置窗口会提示引导授权 |

## 技术要点

- 拦截：`CGEventTap`（`.cgSessionEventTap` + `.headInsertEventTap` + keyDown），命中规则返回 `nil` 丢弃事件
- 键位：keyCode 为物理键位（Q=12、W=13），不受键盘布局/输入法影响
- 自恢复：tap 被系统自动禁用（`.tapDisabledByTimeout` / `.tapDisabledByUserInput`）时自动重新启用
- 并发：工程默认 MainActor 隔离，C 回调通过 `userInfo` 传 self + `MainActor.assumeIsolated` 切回主线程
