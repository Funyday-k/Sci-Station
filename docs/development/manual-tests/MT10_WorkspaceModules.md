# MT10：Workspace Module / Template 手动测试

更新时间：2026-05-05

## 目标

验证 WorkspaceTemplate、WorkspaceModule、模板创建、模块配置、目录预览、禁用模块和修复缺失目录等能力。

## 适用触发点

- P36 执行 template foundation / wizard skeleton 时必须执行 MT10 partial。
- P39-P41 做完整 module registry / creation wizard / customization settings 时执行完整 MT10。

## 前置条件

- Empty Workspace 可用于新建测试。
- Standard Workspace 可用于 legacy migration 测试。
- Broken Workspace 可用于 missing directory repair 测试。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT10-01 | 创建 Minimal Workspace | 生成最小目录和 settings/workspace_modules.yaml |
| MT10-02 | 创建 Literature Review Workspace | 生成 Library/Wiki/Projects 等默认模块目录 |
| MT10-03 | 创建 Theory Research Workspace | P40/P54 前可 skipped |
| MT10-04 | 创建 Code Research Workspace | P40/P55 前可 skipped |
| MT10-05 | 创建 Writing Project Workspace | P40/P56 前可 skipped |
| MT10-06 | Custom 勾选模块 | P40 前可 skipped |
| MT10-07 | 预览目录结构 | 创建前能看到关键目录与 settings 文件 |
| MT10-08 | 创建后 settings/workspace_modules.yaml 正确 | enabled modules、directories、routes、workflows、permissions 可读 |
| MT10-09 | 禁用模块后 Sidebar 入口隐藏 | P41 前可 skipped；禁用不删除数据 |
| MT10-10 | 禁用模块不删除已有数据 | 用户文件仍存在 |
| MT10-11 | 依赖缺失时显示 warning | 缺依赖不崩溃 |
| MT10-12 | Repair missing directories | 缺失目录可补齐，不覆盖用户文件 |

## P40 Workspace Creation Wizard Gate

P40 收口时执行以下补充用例；如果当前环境不能驱动原生 macOS GUI，必须在 run report 中标记 GUI pending，并用 `SciStationCoreTestRunner` 覆盖 resolver / generation / safety 行为。

| ID | 标题 | 期望 |
|---|---|---|
| MT10-P40-01 | Empty Workspace opens Creation Wizard | 欢迎页 Create Workspace 打开单窗口 wizard |
| MT10-P40-02 | Settings -> Workspace opens Creation Wizard | Settings / Research Root 的 Create Root 打开同一 wizard |
| MT10-P40-03 | Minimal template preview matches generated files | 预览 enabled modules / directories / settings files 与创建后的 `workspace_modules.yaml` 一致 |
| MT10-P40-04 | Literature Review preview matches generated files | Literature Review 预览与实际写入一致 |
| MT10-P40-05 | Future templates are disabled | Code / Theory / Writing 显示 coming later，不可选择，不默认启用 |
| MT10-P40-06 | Existing target path is safe | 非空未知目录被阻止；existing Research Root / legacy workspace 不删除用户文件 |
| MT10-P40-07 | Privacy confirmation is required | 未勾选 privacy / AI setup confirmation 前 Create And Open disabled |
| MT10-P40-08 | AI Lab copy is bounded | AI Lab 启用文案不暗示 provider credentials、sidecar 或 AI run 已配置完成 |

## P36 Partial Scope

P36 至少执行：

```text
MT10-01
MT10-02
MT10-07
MT10-08
MT10-10
```

允许 P36 skipped：

```text
MT10-03 到 MT10-06
MT10-09
MT10-11
MT10-12
```

## 阻塞问题

```text
S0: 创建/迁移 workspace 删除用户数据；错误覆盖用户文件
S1: Minimal/Literature Review 无法创建；module settings 未写入；旧 workspace 迁移不可用
```
