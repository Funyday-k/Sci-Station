# Sci-Station 下一阶段任务书

更新时间：2026-04-29

## 1. 当前阶段结论

任务书 12 已按当前代码重新审阅并更新，并完成关键收尾：新论文默认进入 `library/papers`、旧 `raw/papers` 兼容读取、独立项目-论文关系仓库、Agent root/current project context 和核心验证覆盖。

任务书 13 已完成旧论文库迁移工作流的第一版：Settings 的 Library 区域能显示 legacy paper 数量、ready/conflict 计数和目标路径预览，并支持用户确认后复制 ready 条目到 `library/papers`，跳过冲突并写出 JSON 迁移报告。

任务书 14 已完成项目-论文关系 UI 主数据源切换：Library Inspector 和右键菜单的项目归属、核心文章、pin、项目内用途和项目内文件夹写入 `ProjectPaperLinkRepository`，Project Overview 的 Core Papers 已优先使用关系层 pin/order 排序。

任务书 15 已完成 Agent Panel V1：AI Lab 支持 goal 输入、plan-only 生成、逐项审批写入工具、执行结果、run history 和 Copilot Bridge 导出。

任务书 16 已完成 Mac 基础体验第一阶段：第一批菜单命令和快捷键、Library 搜索与删除文案、Wiki 保存与未保存提示、Reader 搜索快捷键、可访问性和空状态下一步操作已落地。

任务书 17 已完成 Library 原生表格体验 V1：Library 列表切换为 SwiftUI `Table`，排序状态写入 workspace preferences，selection set 支持单选/多选，Inspector 多选摘要、Copy Citation、Copy BibTeX 和选择集 BibTeX 导出已落地；列拖拽和任意列顺序恢复因 SwiftUI `Table` 限制暂停到后续。

任务书 18 已按用户方向改为 AI Lab Codex-style 会话体验 V1：AI Lab 支持 Global/Project conversation 选择、按项目过滤 run history、对话 timeline、New Chat、打开历史 run，以及可折叠 Context、Plan、Tool Calls、History 和 Copilot Bridge 区域；plan-only 和 tool approval 安全模型保持不变。

任务书 19 已完成 AI Lab 对话优先与 Thread 化准备：conversation scope 改为跟随 Sidebar 当前项目，AI Lab 首屏压缩为 compact header + thread strip + prompt composer + timeline，Agent Panel 细节统一收到折叠区；`AgentThread` 与 `.sci-station/agent/threads.jsonl` 已落地，New Chat 首次成功 plan 后落盘，prompt draft 先做 session 内保存，Auto Run Loop 预留 disabled 入口并记录 read-only 自动/写入审批策略，Agent workspace 路径和同类诊断信息移入 Settings。

任务书 20 已完成 AI Lab Thread 管理与计划复用 V1：thread 重命名、归档/隐藏、空 pending draft 丢弃、历史 orphan run 手动归并、thread-level prompt draft 持久化到 `.sci-station/agent/drafts.json`、历史 prompt 复制到 New Chat，以及未来 Auto Run Loop 权限/停止条件说明均已落地。

迁移收束见 [DOC/Proposal13.md](Proposal13.md)，关系 UI 收束见 [DOC/Proposal14.md](Proposal14.md)，Agent Panel 收束见 [DOC/Proposal15.md](Proposal15.md)，Mac 基础体验收束见 [DOC/Proposal16.md](Proposal16.md)，Library 原生表格收束见 [DOC/Proposal17.md](Proposal17.md)，AI Lab 会话体验见 [DOC/Proposal18.md](Proposal18.md)，Thread 化准备见 [DOC/Proposal19.md](Proposal19.md)，下一轮执行方案见 [DOC/Proposal20.md](Proposal20.md)。

## 2. 当前代码基线

- 全局研究根目录和多项目 registry 已存在。
- Home 与 Sidebar 已支持多项目。
- Todo 已支持项目归属和全局视图。
- 新导入论文默认进入 `library/papers`。
- 旧 `raw/papers` 继续兼容读取，避免破坏旧 workspace。
- `library/project_paper_links.yaml` 已保存项目-论文关系。
- `PaperRepository` 会桥接关系仓库与旧 paper metadata 字段。
- Library Inspector 与 paper context menu 的项目关系编辑已直接写入 `ProjectPaperLinkRepository`。
- `ProjectPaperLink` 已支持 `is_pinned` 与 `sort_order`，旧 YAML 可兼容读取。
- Agent snapshot 和工具上下文已包含 root/current project。
- AI Lab 已提供 Codex-style 会话 V1：conversation 跟随 Sidebar 当前项目、thread strip、workspace-persisted draft、plan-only、tool approval、tool results、thread timeline、prompt composer、可折叠上下文/计划/工具/历史和 Copilot Bridge export。
- Mac 基础体验第一阶段已完成：菜单命令、`Cmd+N` New Project、`Cmd+F` 搜索、`Cmd+S` Wiki 保存、Reader Find Next/Previous、删除文案、accessibility label 和空状态操作。
- `LegacyPaperMigrationService` 已能生成 `raw/papers` 到 `library/papers` 的 dry-run 计划，并执行 copy-only 迁移报告。
- Library 原生表格体验 V1 已完成：SwiftUI `Table`、排序模型、selection 同步、右键菜单、Copy Citation/Copy BibTeX 和批量 BibTeX 导出准备。
- AI Lab Thread 管理与计划复用 V1 已完成；下一轮建议优先转向 Library Table V2，项目生命周期控制作为后续候选保留。

## 3. 下一阶段主线

```text
Global Research Root
  -> Safe Legacy Paper Migration
  -> Project-Paper Link UI
  -> Agent Panel V1
  -> Mac Foundation UX
  -> Native Library Table
  -> Codex-style AI Lab + Threads
  -> AI Lab Thread Management V1
  -> Library Table V2 / Project Lifecycle Controls
```

## 4. 主要目标

### 4.1 旧论文库迁移

- 检测 `raw/papers` legacy paper。
- 提供 dry-run 迁移计划。
- 展示冲突、目标路径和迁移报告。
- 用户确认后迁移到 `library/papers`。
- 保证迁移后同一 paper id 不重复显示。

### 4.2 项目-论文关系 UI

- UI 编辑项目归属和核心文章时优先写入 `ProjectPaperLinkRepository`。
- 保留 `Paper.projectIDs` / `coreProjectIDs` 作为兼容镜像。
- 增加项目内用途、文件夹、pin/order 等关系层字段。
- Project Overview 的 Core Papers 使用关系层 pin/order 排序。

### 4.3 Agent Panel V1

- 在全局 AI Lab 下显示 Codex-style Agent Panel。
- 支持 Global/Project conversation，按 project context 生成计划和执行 approved tools。
- 展示 root、conversation project、project papers、project todos 和可用工具。
- 支持 plan-only、工具审批、执行结果、timeline 和按项目过滤的 run history。
- 支持 Copilot Bridge 导出。

### 4.4 AI Lab Thread 管理

- Thread 可重命名、归档/隐藏，并保留旧 `threads.jsonl` 兼容读取。
- 历史 orphan run 可手动整理为新 thread，或加入当前同 project thread。
- Prompt draft 从 session 保存评估升级为 workspace 持久化。
- 历史 plan 可复用 prompt，但不自动执行工具。
- Auto Run Loop 继续保持 disabled，只补权限矩阵和停止条件说明。

### 4.5 Mac 基础体验

- 补齐第一批菜单命令和快捷键。
- Library 搜索接入系统预期入口，并修正删除确认文案。
- Wiki 支持 `Cmd+S` 保存和 dirty indicator。
- PDF Reader 支持 `Cmd+F` 搜索聚焦和 Find Next/Previous。
- 关键 icon-only buttons 增加 accessibility label。
- Library/Wiki/Materials/Projects 空状态提供下一步操作。

### 4.6 Library 原生表格

- SwiftUI `Table` 已替换自定义 Library 列表。
- title、authors、year、updated、rating、priority、status 排序已写入 workspace preferences。
- selected paper / Inspector 同步、多选摘要和选择集 BibTeX 导出已完成。
- 单篇论文右键菜单已保留，并新增 Copy Citation / Copy BibTeX。
- 后续需要继续处理列顺序/列宽、Table header 原生排序细节和更多批量编辑。

### 4.7 项目生命周期

- 项目归档/取消归档。
- 项目排序和拖拽重排。
- 保守删除策略：第一版优先归档，不做物理删除。

## 5. 建议优先级

1. 下一轮优先转向 Library Table V2：列顺序/列宽、选择集批量编辑和 Quick Look。
2. 若用户更需要项目治理，则转向项目生命周期控制：归档/取消归档、项目排序和更保守的删除策略。
3. AI Lab 后续可继续增加更多工具、计划导入和可选多轮 Agent loop，但 continuous loop 仍需单独审批模型。
4. Auto Run Loop 继续保持 disabled，不进入自动连续执行实现。

## 6. 验收标准

1. 用户能看到当前 root 是否还有 legacy `raw/papers` 论文。
2. 用户能确认并执行一次迁移到 `library/papers`。
3. 迁移报告写入 root 可见位置。
4. Library 不重复显示同一 paper id。
5. UI 修改项目-论文关系会更新 `library/project_paper_links.yaml`。
6. Agent Panel 能基于 Sidebar 当前项目生成计划。
7. Agent Panel 能逐项批准写入工具。
8. Agent run log 含 current project id，并能按 project conversation 过滤。
9. AI Lab thread 可重命名、归档/隐藏，且旧 `threads.jsonl` 记录兼容读取。
10. 历史 orphan run 可手动归并到同 project thread，且不重写 `runs.jsonl`。
11. Prompt draft 可在切换 project/thread 后恢复；若实现持久化，重启后也可恢复。
12. Auto Run Loop 仍保持 disabled，并说明未来权限矩阵与停止条件。
13. 菜单命令、`Cmd+F`、`Cmd+S`、删除文案和空状态符合 [DOC/Proposal16.md](Proposal16.md) 的第一阶段要求。
14. Library 原生表格、排序和 selection 行为符合 [DOC/Proposal17.md](Proposal17.md) 的 V1 要求。
15. SwiftPM Core Test Runner 通过。
16. Xcode macOS build 通过。

## 7. Question

1. 任务书 21 是否转向 Library Table V2？建议优先处理列顺序/列宽、选择集批量编辑和 Quick Look。
2. 如果不做 Library Table V2，是否转向项目生命周期控制？建议先做归档/取消归档和项目排序，不做物理删除。
3. AI Lab 下一轮是否需要更多工具或计划导入？建议等 Library Table V2 收口后再继续。
4. Auto Run Loop 是否继续保持 disabled，只保留说明？建议保持 disabled。
