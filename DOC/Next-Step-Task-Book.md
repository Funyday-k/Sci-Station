# Sci-Station 下一阶段任务书

更新时间：2026-04-29

## 1. 当前阶段结论

任务书 12 已按当前代码重新审阅并更新，并完成关键收尾：新论文默认进入 `library/papers`、旧 `raw/papers` 兼容读取、独立项目-论文关系仓库、Agent root/current project context 和核心验证覆盖。

任务书 13 已完成旧论文库迁移工作流的第一版：Settings 的 Library 区域能显示 legacy paper 数量、ready/conflict 计数和目标路径预览，并支持用户确认后复制 ready 条目到 `library/papers`，跳过冲突并写出 JSON 迁移报告。

任务书 14 已完成项目-论文关系 UI 主数据源切换：Library Inspector 和右键菜单的项目归属、核心文章、pin、项目内用途和项目内文件夹写入 `ProjectPaperLinkRepository`，Project Overview 的 Core Papers 已优先使用关系层 pin/order 排序。

任务书 15 已完成 Agent Panel V1：AI Lab 支持 goal 输入、plan-only 生成、逐项审批写入工具、执行结果、run history 和 Copilot Bridge 导出。

任务书 16 已完成 Mac 基础体验第一阶段：第一批菜单命令和快捷键、Library 搜索与删除文案、Wiki 保存与未保存提示、Reader 搜索快捷键、可访问性和空状态下一步操作已落地。

迁移收束见 [DOC/Proposal13.md](Proposal13.md)，关系 UI 收束见 [DOC/Proposal14.md](Proposal14.md)，Agent Panel 收束见 [DOC/Proposal15.md](Proposal15.md)，Mac 基础体验收束见 [DOC/Proposal16.md](Proposal16.md)，下一轮执行方案见 [DOC/Proposal17.md](Proposal17.md)。

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
- AI Lab 已提供 Agent Panel V1：plan-only、tool approval、tool results、recent run history 和 Copilot Bridge export。
- Mac 基础体验第一阶段已完成：菜单命令、`Cmd+N` New Project、`Cmd+F` 搜索、`Cmd+S` Wiki 保存、Reader Find Next/Previous、删除文案、accessibility label 和空状态操作。
- `LegacyPaperMigrationService` 已能生成 `raw/papers` 到 `library/papers` 的 dry-run 计划，并执行 copy-only 迁移报告。
- 下一轮聚焦 Library 原生表格体验 V1：SwiftUI `Table`、排序模型、selection 同步、右键菜单和批量导出准备。

## 3. 下一阶段主线

```text
Global Research Root
  -> Safe Legacy Paper Migration
  -> Project-Paper Link UI
  -> Agent Panel V1
  -> Mac Foundation UX
  -> Native Library Table
  -> Project Lifecycle Controls
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

- 在全局 AI Lab 下显示 Agent Panel。
- 展示 root、current project、project papers、project todos 和可用工具。
- 支持 plan-only、工具审批、执行结果和 run history。
- 支持 Copilot Bridge 导出。

### 4.4 Mac 基础体验

- 补齐第一批菜单命令和快捷键。
- Library 搜索接入系统预期入口，并修正删除确认文案。
- Wiki 支持 `Cmd+S` 保存和 dirty indicator。
- PDF Reader 支持 `Cmd+F` 搜索聚焦和 Find Next/Previous。
- 关键 icon-only buttons 增加 accessibility label。
- Library/Wiki/Materials/Projects 空状态提供下一步操作。

### 4.5 项目生命周期

### 4.5 Library 原生表格

- 优先用 SwiftUI `Table` 替换自定义 Library 列表。
- 增加 title、authors、year、updated、rating、priority、status 排序。
- 保持 selected paper / Inspector 同步。
- 保留单篇论文右键菜单。
- 建立多选 selection set 和低风险批量 BibTeX 导出准备。

### 4.6 项目生命周期

- 项目归档/取消归档。
- 项目排序和拖拽重排。
- 保守删除策略：第一版优先归档，不做物理删除。

## 5. 建议优先级

1. 按 [DOC/Proposal17.md](Proposal17.md) 推进 Library 原生表格体验 V1。
2. 优先建立排序模型和 SwiftUI `Table` 显示层。
3. 保持 selected paper / Inspector / 单篇右键菜单稳定。
4. 建立多选 selection set 与低风险批量 BibTeX 导出准备。
5. 后续再推进 Sidebar List/Outline、多窗口 Reader、Settings 分区和项目生命周期控制。

## 6. 验收标准

1. 用户能看到当前 root 是否还有 legacy `raw/papers` 论文。
2. 用户能确认并执行一次迁移到 `library/papers`。
3. 迁移报告写入 root 可见位置。
4. Library 不重复显示同一 paper id。
5. UI 修改项目-论文关系会更新 `library/project_paper_links.yaml`。
6. Agent Panel 能基于当前项目生成计划。
7. Agent Panel 能逐项批准写入工具。
8. Agent run log 含 current project id。
9. 菜单命令、`Cmd+F`、`Cmd+S`、删除文案和空状态符合 [DOC/Proposal16.md](Proposal16.md) 的第一阶段要求。
10. Library 原生表格、排序和 selection 行为符合 [DOC/Proposal17.md](Proposal17.md) 的 V1 要求。
11. SwiftPM Core Test Runner 通过。
12. Xcode macOS build 通过。

## 7. Question

1. Library V1 是否接受先使用 SwiftUI `Table`，若遇到限制再后续改 `NSTableView` wrapper？建议接受。
2. 多选批量操作本轮是否只做 selection 和 BibTeX export，批量编辑留后续？建议本轮只做低风险批量导出。
3. 排序偏好是否写入 workspace preferences？建议写入，保持 workspace 级行为一致。
4. 如果 Table 迁移影响现有列拖拽排序，是否允许本轮暂停列拖拽、保留 Settings 中的列配置？建议允许，优先系统表格行为。
