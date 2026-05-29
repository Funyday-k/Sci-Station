# P41 Module Customization Settings 手动测试记录

日期：2026-05-08
执行者：GitHub Copilot（自动化与构建验证）；真实 GUI spot check 待人工补跑

## 自动化 / 构建

```text
swift run SciStationCoreTestRunner：通过
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build：通过
get_errors（P41 编辑 Swift / SwiftUI 文件）：无错误
```

备注：Xcode build 仍输出既有 `ChatMarkdownWebView` / `MarkdownPreviewView` WebKit actor-isolation warning，非 P41 新增。

## MT11-P41 状态

| ID | 状态 | 备注 |
|---|---|---|
| MT11-P41-01 | Pending GUI | 自动化覆盖 15 modules registry；真实 Settings → Modules 打开待补测 |
| MT11-P41-02 | Covered by automation / Pending GUI | `moduleSettingsViewModelTogglePinPersistsOrder`、YAML save/load 覆盖持久化；真实 toggle 点击待补测 |
| MT11-P41-03 | Covered by automation / Pending GUI | `moduleSettingsViewModelEnableModuleRequiresDependencies` 与 `moduleSettingsViewModelEnableDependenciesEnablesAllAncestors` 覆盖 |
| MT11-P41-04 | Covered by automation / Pending GUI | `moduleSettingsViewModelDisablingDependencyHidesRoutes` 覆盖 route/workflow gating |
| MT11-P41-05 | Covered by automation / Pending GUI | pin 持久化和 Xcode build 覆盖；真实 sidebar 顺序待补测 |
| MT11-P41-06 | Covered by automation / Pending GUI | `workspaceModuleDirectoryRepairerRequiresPermissionApproval` 覆盖 approve/deny |
| MT11-P41-07 | Covered by automation / Pending GUI | repairer writePaths guard 已实现；真实错误文案待补测 |
| MT11-P41-08 | Covered by automation / Pending GUI | `moduleSettingsViewModelOverrideOnlyAffectsTargetProject` 覆盖 target-project-only merge |
| MT11-P41-09 | Covered by automation / Pending GUI | `workspaceModuleConfigurationStoreNotifiesObserversAtomically` 覆盖 watcher；外部编辑 GUI 待补测 |
| MT11-P41-10 | Pending GUI | reset-to-template 已实现并通过 Xcode build；真实确认流待补测 |

## 结论

P41 代码路径和自动化验证通过，可以进入 P42。release/对外演示前需补跑 MT11 GUI spot check，尤其是 Settings → Modules 中 toggle、pin、repair、project override 的真实点击流。