# Agents Anywhere — iOS 17 降级构建

把 [anywhere-labs/Agents-Anywhere](https://github.com/anywhere-labs/Agents-Anywhere) 的 iOS 客户端从
官方要求的 **iOS 26.5** 降到 **iOS 17.0** 部署目标，用 GitHub Actions 的 macOS runner 交叉编译，
产出未签名 IPA，供越狱设备通过 TrollStore Lite 安装。

- 构建仓库：https://github.com/6907665-afk/agents-anywhere-ios17
- 产物：`AgentsAnywhere-ios17.ipa`（Bundle ID `com.agentsanywhere.app`，`MinimumOSVersion = 17.0`）
- 目标设备：iPhone 15 Pro / iOS 17.0.3 (21A360) / Dopamine rootless

## 为什么不能直接装 App Store 版

App Store 上架版本 `minimumOsVersion = 26.5`（iTunes Lookup 实测），GitHub Release 只有
dmg/exe/apk，没有 IPA。TrollStore 无法解密 App Store 的加密二进制，所以只能从源码重新编译。

## 降级改造清单

工程层面：

| 位置 | 改动 |
| --- | --- |
| `project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET` 26.5 → 17.0 |
| `Package.swift` | `.iOS("26.5")` → `.iOS(.v17)` |
| `Packages/Textual/Package.swift` | `.iOS(.v18)` → `.iOS(.v17)` |

新增兼容层（`Views/Components/`、`Domain/Common/`）：

| 文件 | 替代的 API |
| --- | --- |
| `AACompatibility.swift` | `glassEffect` / `GlassEffectContainer` / `glassEffectID` / `.buttonStyle(.glass[Prominent])` / `scrollEdgeEffectStyle` / `onScrollVisibilityChange` |
| `AAScrollBridge.swift` | `ScrollPosition`、`onScrollPhaseChange`、`onScrollGeometryChange`（用 `UIScrollView` KVO + pan 手势还原） |
| `AALockedValue.swift` | `Synchronization.Mutex`（iOS 18）→ `NSLock` |
| `Packages/Textual/.../SizeObserver.swift` | `onGeometryChange` / `onScrollGeometryChange` |

其余逐点替换：`Group(subviews:)`、`@Entry`、`NavigationSubtitle`、`ToolbarItem(.subtitle)`、
`safeAreaBar`、`ConcentricRectangle`、`UIGestureRecognizerRepresentable`、`TextRenderer`、
`Button(role: .close/.confirm)`、`defaultScrollAnchor(_:for:)`、`scrollTargetBehavior(.viewAligned(limitBehavior:))` 等。

启动路径：`AgentsAnywhereApp` 先提交一个轻量首帧占位，再挂载 `RootView`，避免 scene-update
watchdog 在 10 秒窗口内判定启动失败。

## 构建

`.github/workflows/ios-build.yml`，push 到 `main` 或手动 `workflow_dispatch`：

- runner：`macos-26`
- `SWIFT_OPTIMIZATION_LEVEL="-Onone"`（必须，见下）
- `ENABLE_DEBUG_DYLIB=NO`、`ENABLE_PREVIEWS=NO`
- 产物打包成 `Payload/Agents Anywhere.app` 的 IPA 并上传 artifact

本地安装（越狱设备，TrollStore Lite）：

```powershell
. C:\Users\Administrator\.dsh\ios-jb\env.ps1
python C:\Users\Administrator\.dsh\ios-jb\scripts\install_ipa.py <IPA路径>
```

## 已知问题

1. **只能用 `-Onone` 编译。** Xcode 26.6（Swift 6.3.3）在 `-O` 下编译本项目会在 SIL 优化期崩溃
   （`EarlyPerfInliner` / `Mem2Reg` pass，泛型 `@MainActor` 类的析构与标准库泛型实例化），
   多个崩溃点无法逐个绕过；`-sil-disable-pass=EarlyPerfInliner` 只能把崩溃点推到下一处。
2. **Xcode 26.0.1（Swift 6.2）无法启用。** 该版本在构建前置检查里要求与 `iphonesimulator`
   SDK 23A339 匹配的 runtime，而 runner 只装了 23C54/23E254a/23F77，加 `-sdk iphoneos26.0`、
   `SUPPORTED_PLATFORMS=iphoneos`、`-destination generic/platform=iOS` 均无法跳过。
3. **`-Onone` 产物启动很慢。** 首帧占位可以过 watchdog，但 `RootView` 整棵树在无优化下渲染
   需要极长时间（实测主线程持续满载、70 秒内被系统回收），暂不视为可长期使用。

## 后续可行方向

- 在 runner 上安装匹配 iOS 26.0 的 simulator runtime 后改用 Xcode 26.0 + `-O`。
- 或者继续消除 `-O` 崩溃面：把剩余的泛型 `@MainActor` 类（如 `StableViewModel<Model>`）
  改为非泛型/用 `DispatchWorkItem` 承载闭包，逐个把崩溃点清零。
- 或者把主 target 拆成 SPM 包，对渲染热路径单独开 `-O`、其余保持 `-Onone`。
