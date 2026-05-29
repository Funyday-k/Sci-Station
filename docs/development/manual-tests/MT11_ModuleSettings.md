# MT11：Module Settings 手动测试

更新时间：2026-05-08

## 目标

验证 P41 Settings → Modules 对 `settings/workspace_modules.yaml` 的读写闭环：enable / disable / pin / dependency chain / directory repair / project override / external refresh / debug event。

## 前置条件

- 已运行 `swift run SciStationCoreTestRunner`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 使用 P40 创建的 Literature Review 或 Minimal Research Root。
- 打开 Settings → Modules 前先确认 `settings/workspace_modules.yaml` 存在。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT11-P41-01 | 打开 Settings → Modules | 列表显示全部 15 个内置模块；enabled / disabled / dependency hidden 状态正确；顶部 summary 与 Workspace 摘要一致 |
| MT11-P41-02 | 启用 `code` 模块 | 依赖满足时 toggle 立即生效；`workspace_modules.yaml` 中 `code.enabled: true`；记录 `module_settings.toggle` |
| MT11-P41-03 | 启用 `recommendation` | 直接启用被 dependency warning 阻止；点击 `Enable Dependencies` 后 `citation-graph` 与 `recommendation` 单次链式启用；记录 `module_settings.toggle_chain` |
| MT11-P41-04 | 关闭 `wiki` | Wiki route / project tab 隐藏；依赖它的 enabled 模块显示 warning；不自动改回用户文件 |
| MT11-P41-05 | Pin `tasks` 并上下移动 | Project sidebar 优先显示 pinned 模块对应 tab；`pinned: true` 和模块顺序重启后保留；记录 `module_settings.pin` |
| MT11-P41-06 | Repair 缺失 required directory | 确认弹窗出现；批准后创建目录并刷新 badge；取消后不写入；记录 `module_settings.repair` |
| MT11-P41-07 | Repair 非 writePaths 路径 | Repair 被拒绝，UI 显示原因，不创建目录 |
| MT11-P41-08 | Project A override Calendar off | Project A 的 Calendar tab 隐藏；Project B 保持 workspace default；清除 override 后 fallback |
| MT11-P41-09 | 外部编辑 `workspace_modules.yaml` | App 不重启刷新 Modules 页面与 sidebar gating；不合法 schema 保留上次合法 UI 状态并展示 warning |
| MT11-P41-10 | Reset to template default | 确认后恢复当前 workspace template 默认 enabled set；记录 `module_settings.reset_to_template` |

## 回归检查

```text
MT99-P41-01: Settings → Workspace 仍显示只读 Workspace Modules summary。
MT99-P41-02: Settings → Modules 可打开，不影响 Settings → AI Lab / Library / Tasks。
MT99-P41-03: Project sidebar 根据 workspace config 与 project override 刷新，无需重启。
MT99-P41-04: 关闭 Library / Wiki / Tasks 后，对应主入口隐藏且 fallback section 不崩溃。
MT99-P41-05: `.sci-station/debug/app_events.jsonl` 中 module_settings.* payload 不含绝对路径、paper/wiki 内容或 secret。
```

## 阻塞判定

```text
S0: toggle/repair/override 导致用户文件删除、secret 写入 workspace、App crash。
S1: Settings → Modules 无法打开；workspace_modules.yaml 写坏导致 workspace 无法恢复；project override 串项目。
```