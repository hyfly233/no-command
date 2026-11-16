# Repository Guidelines

macOS menu-bar utility (Swift / SwiftUI, 10 source files, zero dependencies) that installs a session-level `CGEventTap` and **drops** keystrokes matching a shortcut rule (`⌘Q`, `⌘W`, `⌃⌘Q`, `⌃⌘W`, `⌥⌘Q` presets plus user-recorded combos), so a live demo / game / kiosk session cannot quit, close, or lock the machine. Per-app whitelist by bundle id; master toggle as escape hatch.

Read `README.md` — it is accurate and bilingual-authoritative on behavior, limits, and the manual verification checklist.

## Architecture & Data Flow

Single-process, no network, no persistence beyond `UserDefaults`. Four singletons, three layers:

```
MenuBarExtra ─► MenuView ─────────┐
Window("设置", id:"settings") ─► SettingsView ─┬─► AppState.shared   (config + whitelist + recording)
                                               └─► LogStore.shared    (200-entry in-memory ring + os.Logger)
AppDelegate ──► AppState.refreshPermission() ──► KeyboardInterceptor.shared.start() ──► CGEventTap
                                                          │
                                     tap callback ──► handle() ──► decision: drop or pass
```

### The interception path (the only control flow that matters)

`KeyboardInterceptor.start()` (`no-command/KeyboardInterceptor.swift:39`) creates the tap: `.cgSessionEventTap` + `.headInsertEventTap` + `.defaultTap`, keyDown only (`:47-62`), attached to `CFRunLoopGetCurrent()` in `.commonModes` (`:73`). Self is smuggled to the C callback as an opaque `userInfo` pointer (`:49`).

`eventTapCallback` is `nonisolated` (`:93`) and hops back with `MainActor.assumeIsolated` (`:96`, `:110`). `handle(keyCode:flags:)` (`:119`) decides **in this exact order**:

1. `isRecording` → feed `AppState.handleRecording`, **pass** (`:123-126`)
2. `!masterEnabled` → **pass** (`:128`)
3. frontmost app in whitelist → **pass** (`:131-135`)
4. `AppState.matchRule(...)` returns nil → **pass** (`:137`)
5. front app is self and rule is bare `⌘W` (keyCode 13, no ⌃/⌥/⇧) → **pass** (`:141-144`)
6. otherwise → throttle (same key+flags within 1.0 s logs/beeps once, `:149`), `LogStore.shared.add(...)`, optional `NSSound.beep()`, **return true ⇒ event dropped** (`:159`, nulled at `:112`)

Adding a rule or a bypass means inserting into this ladder — order is behavior, not style.

The menu uses `.menuBarExtraStyle(.window)` on purpose: `.menu` renders non-`Toggle` content (status dot, captions, wrappable log text) as disabled menu items — greyed out or dropped entirely. Anything visual in `MenuView` depends on the `.window` style.

### Patterns to preserve

- **Manual `@Published` + `didSet` → `UserDefaults`, never `@AppStorage`.** Documented reason (`no-command/AppState.swift:8-9`): `@AppStorage` does not fire `objectWillChange`, so the menu and the settings window would desync. Keep new persisted state on the same pattern: property + `didSet` write + read in `init`.
- **No dependency injection, no `EnvironmentObject`.** Views hold `@ObservedObject private var state = AppState.shared`; the interceptor reaches state via `AppState.shared` (`:120`). Do not introduce an alternate injection path.
- **Preset enablement lives in `enabledPresetIDs`, not `ShortcutRule.isEnabled`** (`AppState.swift:26`, `:64`). Custom rules use `isEnabled`. New presets must append to `presets` with a fixed UUID (`…0001`–`…0005`); `knownPresetIDs` back-fill (`:98-104`) auto-enables them exactly once on upgrade.
- **UI status is derived, never re-judged.** `AppState.interceptorState` (`AppState.swift`) folds master toggle + accessibility grant + `KeyboardInterceptor.shared.isRunning` into `InterceptorState`; the menu, the settings banner, and the log tab all render that one value. Do not add a second `permissionGranted ? … : …` check in a view — a granted permission with a failed `tapCreate` must read as `notReady`, not as healthy.
- **keyCode is physical.** `ShortcutRule.keyName(for:)` (`no-command/Models.swift:59-136`) is a 60-case explicit table validated against Carbon `kVK_ANSI_*`; never derive labels from ASCII or the alphabet.
- **`ShortcutRule.matches` is exact-modifier matching** (`Models.swift:34-41`): required flags must be down *and* unrequired flags must be up, so `⌥⌘Q` is not read as `⌘Q`.

## Key Directories

| Path | Purpose |
|---|---|
| `no-command/` | All app sources + `Assets.xcassets`; membership is implicit via `PBXFileSystemSynchronizedRootGroup` — a new file in this folder is compiled with no pbxproj edit |
| `no-command.xcodeproj/` | Single target `no-command`, no `.xcscheme` committed |
| `scripts/` | `package.sh` (build→verify→zip/dmg), `render_icon.swift` (regenerates all 10 AppIcon PNGs) |
| `build/`, `dist/` | Build output and release artifacts, both gitignored |
| `graphify-out/` | Knowledge-graph artifacts, gitignored; query it rather than grepping for structure questions |

## Development Commands

```bash
# Debug build
xcodebuild -project no-command.xcodeproj -scheme no-command -configuration Debug -derivedDataPath build build

# Run
open build/Build/Products/Debug/no-command.app

# Release zip + dmg (verifies signature and Info.plist; does NOT sign or notarize)
./scripts/package.sh

# Install locally
cp -R build/Build/Products/Release/no-command.app /Applications/

# Watch interception logs (the fastest end-to-end proof)
log stream --predicate 'subsystem == "com.hyfly.no-command"'

# Regenerate the icon set (run from repo root; default output path is CWD-relative)
swift scripts/render_icon.swift
```

There is no lint, formatter, or test command — see **Testing & QA**.

`xcodebuild` needs the scheme `no-command`, which is only *autocreated* by Xcode because no shared scheme is committed; a pristine clone may need `xcodebuild -target no-command` or one Xcode open first.

## Code Conventions & Common Patterns

- **Language:** Chinese prose in comments, logs, UI strings, and test expectations; English for identifiers and API names. Match this — new user-visible strings and `LogStore` messages are Chinese.
- **File header:** every Swift file opens with the block comment `//  <File>.swift` / `//  no-command` / `//  no-command：<one-line purpose>` (see `KeyboardInterceptor.swift:1-13`). Keep it when adding files.
- **Sections:** `// MARK: - <Chinese label>` groups members inside a type (`AppState.swift:24,54,76,124,200`) and types inside a file (`SettingsView.swift:26,114,183`).
- **Ordering inside a type:** `static let shared` → other `static let` → stored properties → computed → `private init` → MARK-grouped API → `private` helpers last.
- **Access control:** all singletons seal init (`private init() {}`); published state that only the store may mutate is `@Published private(set)` (`LogStore.swift:24`); view sub-structs are `private struct` (`SettingsView.swift:28,116,185`).
- **Formatting:** 4 spaces, K&R braces, one-liner `guard ... else { return }` where it fits.
- **Concurrency:** every stateful type is `@MainActor`; the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (Swift 5 language mode, no `-strict-concurrency`). Only one `DispatchQueue` exists (`MenuView.swift:100`, window-front retry).
- **Error handling style:** log-and-continue. `try?` in three places (`AppState.swift:106,113,247`), the last silently drops a failed save; `fatalError` only in the icon script. No `NSAlert`/`.alert` anywhere — failures surface as an inline `Label` plus a `LogStore` line.
- **Value types:** models are `struct` + `Codable`/`Equatable`/`Identifiable`; no classes in `Models.swift`.

## Important Files

| File | Why it matters |
|---|---|
| `no-command/KeyboardInterceptor.swift` | The tap, the decision ladder, throttle, self-heal on `.tapDisabledByTimeout`/`.tapDisabledByUserInput` (`:95-103`) |
| `no-command/AppState.swift` | Single source of truth: presets, 6 `UserDefaults` keys, whitelist, recording, `refreshPermission()` (`:163`) |
| `no-command/Models.swift` | `ShortcutRule` (match/display/keyName), `LogEntry`, `RunningApp`, `WhitelistEntry` |
| `no-command/no_commandApp.swift` | `@main`, `MenuBarExtra(.window)`, `Window("设置", id: "settings")` |
| `no-command/MenuView.swift` | Menu surface + `openSettings()`/`bringSettingsWindowFront` (`:87`, `:94`) |
| `no-command/SettingsView.swift` | Three tabs (selection bound to `AppState.settingsTab`), status banner, whitelist search + add feedback, auto-scrolling log list |
| `no-command/LogStore.swift` | `os.Logger(subsystem: "com.hyfly.no-command", category: "interceptor")`, `static let capacity = 200` (referenced by the log tab's counter) |
| `no-command/UIState.swift` | `InterceptorState` (running/paused/unauthorized/notReady, with shared text + color), `SettingsTab`, `WhitelistAddResult` |
| `no-command/PermissionManager.swift` | `AXIsProcessTrusted()`, System Settings deep links (`:26-27`) |
| `no-command/AppDelegate.swift` | Launch + activation hooks that retry permission/interceptor start |
| `no-command.xcodeproj/project.pbxproj` | All build config; there is no checked-in `Info.plist`, `.entitlements`, or `Package.swift` |
| `scripts/package.sh` | Release pipeline (signature verification only) |

### Build settings that constrain code

`MACOSX_DEPLOYMENT_TARGET = 26.5`, `SWIFT_VERSION = 5.0`, `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_LSUIElement = YES` (no Dock icon) and `CFBundleDisplayName = no-command`, `PRODUCT_BUNDLE_IDENTIFIER = com.hyfly.no-command`, `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`, `DEVELOPMENT_TEAM = 8MFNJGDG8Z`, `CODE_SIGN_STYLE = Automatic`.

**Sandbox must stay disabled and signing must stay on the same team.** A session-level event tap plus Accessibility authorization requires it; the Accessibility grant is keyed to bundle id + signing identity, so an ad-hoc (`codesign -s -`) build re-triggers authorization on every rebuild.

### Coupled literals — change all or nothing

- Settings window: `openWindow(id: "settings")` (`MenuView.swift`), `Window("设置", id: "settings")` (`no_commandApp.swift`), and the title predicate `$0.title == "设置"` (`MenuView.swift`). Renaming the title silently breaks bring-to-front; it then just opens unfocused.
- Settings tabs: `TabView(selection: $state.settingsTab)` tags must match the `SettingsTab` cases, and `MenuView.openSettings(_:)` sets that value before `openWindow`. Adding a tab means updating `SettingsTab`, the `.tag`, and the menu entries.
- Self-protection: `AppState.selfBundleID` (`AppState.swift:22`) is used both to refuse adding self to the whitelist (`:147`) and to grant the bare-`⌘W` pass-through (`KeyboardInterceptor.swift:141-142`).
- Keycode `13` for `⌘W` also appears as a preset (`AppState.swift:32`) and in the self-exception check.

### Known traps

- `MainActor.assumeIsolated` (`KeyboardInterceptor.swift:96,110`) **traps** if the tap ever fires off-main; the safety relies on the run-loop attachment being on the main thread.
- `start()` is a silent no-op off-main: `CFRunLoopGetCurrent()` would attach the source to a run loop that never spins. Keep callers `@MainActor`.
- `Unmanaged.passUnretained(self)` (`:49`) is sound only because the interceptor is a never-deallocated singleton.
- `KeyboardInterceptor.stop()` has **no caller**; there is no runtime off-switch other than `masterEnabled`.
- `SettingsView.swift:11` doc comment says "Settings 场景" but the scene is `Window`; `no_commandApp.swift:21-24` documents why (`SettingsLink` is broken under `MenuBarExtra`).

## Runtime/Tooling Preferences

- Xcode 26.x / macOS 26.x toolchain (`objectVersion = 77`, `LastUpgradeCheck = 2660`). Swift 5 language mode — do not migrate to Swift 6 strict concurrency without treating the `assumeIsolated`/singleton design as part of the change.
- No package manager, no SPM, no third-party code. Keep it that way; all linkage is implicit through `import`.
- Shell scripts are bash with `set -euo pipefail` and are run from the repo root; `render_icon.swift` runs via `swift scripts/render_icon.swift` and depends on AppKit being available (macOS only).
- Xcode GUI artifacts (`xcuserdata/`) are gitignored; never hand-edit `project.pbxproj` unless adding a build setting — source files are picked up from the folder automatically.

## Testing & QA

**There is no automated test suite, no CI, no lint config, and no test target.** The pbxproj has exactly one `PBXNativeTarget` (application); there is no `.github/`, `Makefile`, `fastlane/`, `.swiftlint.yml`, `Package.swift`, or `*.xctestplan`.

Verification is therefore manual and evidence-based. Use `README.md:58-71` as the acceptance checklist, driven by the log stream:

```bash
log stream --predicate 'subsystem == "com.hyfly.no-command"'
```

Expected observable signals, all emitted by `LogStore.add`:

| Signal | Source |
|---|---|
| `辅助功能已授权，键盘拦截启动` | `AppState.swift:173` |
| `键盘拦截已启动` | `KeyboardInterceptor.swift:75` |
| `拦截 ⌘Q（前台 <App>）` and the app does **not** quit | `KeyboardInterceptor.swift:154` |
| no log line while a whitelisted app is frontmost, and `⌘Q` works there | whitelist branch `:133` |
| `事件 tap 被系统禁用，已自动恢复` after sleep/lock | `:100` |
| `事件 tap 创建失败（权限或系统限制）` | `:64` |

Checks to run before claiming a change works: Debug build succeeds; the app launches with no Dock icon; `⌘Q` is blocked in a non-whitelisted app; `⌘Q` passes in a whitelisted app; the master toggle passes everything; a recorded combo round-trips through `UserDefaults` (relaunch). For UI work, also confirm the status reads `拦截中` only when the tap actually exists, `已暂停` when the master toggle is off, and that the menu footer buttons land on their intended tab. For release-related changes, also run `./scripts/package.sh` and confirm it prints `签名校验通过` plus the three `PlistBuddy` values.

Do not expect `⌃⌘Q` to be blockable — that is a documented system limitation (`README.md:81`), not a regression. Same for Secure Input fields.
