# 任务书 16：Mac 基础体验第一阶段

更新时间：2026-04-29

## 1. 本轮结论

任务书 15 已完成 Agent Panel V1：AI Lab 可输入 goal、生成 plan-only 计划、逐项审批写入工具、执行已批准工具、显示结果、读取 run history，并导出 Copilot Bridge prompt/manifest。

下一阶段不继续扩大 Agent 能力，而是按 `docs/development/Comment.md` 的设计审阅意见进入 Mac 基础体验补齐。目标是先处理低风险、高体感、可验证的系统行为：菜单命令、快捷键、搜索入口、Reader/Wiki 保存体验、删除文案、关键图标按钮可访问性和空状态下一步操作。

任务书 16 的目标是把审阅意见转成可落地的一条一条任务指导，先完成第一阶段 Mac 基础体验，不做大规模 Sidebar/Table/Window 重构。

## 2. 当前代码基线

- 主界面已是三栏 `NavigationSplitView`，Sidebar 仍是自定义 view。
- `Sci_StationApp.swift` 已有部分菜单命令，但命令体系不完整。
- Library 仍是自定义 header + `ScrollView` + `LazyVStack`，尚未迁移 `Table`。
- Wiki 编辑器支持 Source / Preview / Split 和 snippets，但 `Cmd+S`、dirty indicator、切换未保存确认仍不足。
- PDF Reader 已有搜索、页码、缩放和右侧面板，但 Reader 搜索尚未系统化绑定 `Cmd+F`/Find Next/Previous。
- Settings 已有 macOS Settings scene，但页面仍是长表单。
- Agent Panel V1 已完成，后续应先保持稳定，不在本轮扩大工具面。

## 3. 本轮原则

1. **先补系统预期，不重写核心架构。** 本轮聚焦菜单、快捷键、局部文案、可访问性和空状态。
2. **先做可验证行为。** 每条任务都要有可手动检查或核心验证方式。
3. **不引入大控件迁移。** Library `Table`、Sidebar `List(selection:)`、多窗口 Reader 留到后续任务书。
4. **不改变数据格式。** 本轮不迁移 YAML schema，不移动用户文件。
5. **错误留在局部。** 搜索、保存、删除、导出等操作失败时应显示对应页面状态或已有 alert，不吞错。

## 4. 执行任务

### 4.1 菜单与命令第一批

1. 审阅 `Sci_StationApp.swift` 当前 `commands`。
2. 补齐最小命令组：
   - Workspace：Create Workspace、Open Workspace、Reveal Workspace in Finder。
   - Paper：Import PDF、Add by Identifier、Open in Reader、Open External PDF、Reveal Paper in Finder、Export BibTeX。
   - View/Navigate：Search Library、Toggle Inspector 或 Reader Sidebar（若已有状态可接入）。
   - Wiki：Save Wiki Page。
3. 为关键命令绑定快捷键：
   - `Cmd+O` 打开 workspace。
   - `Cmd+N` 新建项目；Create Workspace 保留 toolbar 和 Workspace 菜单入口，不占用 `Cmd+N`。
   - `Cmd+I` 打开/聚焦 Inspector 或执行现有 inspector toggle。
   - `Cmd+F` 聚焦当前页面搜索。
   - `Cmd+S` 只保存当前 Wiki/Markdown draft；Library metadata 继续使用现有回车/保存按钮流程。
4. 命令 disabled 条件必须与 UI 按钮一致，不能让无 workspace/无 selected paper 时触发失败。

### 4.2 Library 搜索与删除文案

1. 将 Library 搜索入口接入 `.searchable` 或提供 `Cmd+F` 聚焦现有搜索框。
2. 搜索框 placeholder 明确说明搜索范围：title、author、tag、identifier、abstract。
3. 当前过滤条件用 chip/summary 显示：Project、Folder、Tag、query。
4. 修正删除确认文案：
   - 不再提旧 `raw/papers`。
   - 显示实际 `paper.paperDirectoryRelativePath`。
   - 文案统一为“从 workspace 中删除该论文目录”。
5. 删除菜单、Inspector 删除按钮和确认弹窗文案保持一致。

### 4.3 Wiki 编辑体验第一批

1. 为 Wiki 编辑接入 `Cmd+S` 保存当前 Markdown。
2. 增加 dirty indicator：当前 draft 与已加载文档不一致时，在标题或工具栏显示 Unsaved。
3. 切换 Markdown 页面前，如果当前页有未保存改动，至少提供确认或阻止静默丢弃。
4. 保存失败时保留用户 draft，不清空编辑器。
5. 手动检查 Source、Preview、Split 三种模式下保存行为一致。

### 4.4 PDF Reader 搜索快捷键

1. 审阅 `EmbeddedPDFReaderView` 的搜索状态和 PDFKit find 能力。
2. 将 Reader 内 `Cmd+F` 绑定到搜索字段/搜索面板。
3. 增加 Find Next / Find Previous 快捷入口，优先使用 `Cmd+G` / `Shift+Cmd+G`。
4. 搜索状态至少显示“找到匹配 / 无匹配”局部状态，结果计数本轮不强求。
5. 不在本轮实现缩略图/Outline/选中文本创建 note。

### 4.5 可访问性与 icon-only 按钮

1. 审阅 Sidebar、Reader toolbar、Library row actions、Materials actions 中的 icon-only buttons。
2. 对每个 icon-only button 补 `.accessibilityLabel` 或使用 `Label`。
3. `.help` 不替代 accessibility label；两者都可以保留。
4. 对 destructive icon action 增加明确 label，例如 Delete Paper、Remove Link、Clear Filter。

### 4.6 空状态下一步操作

1. Library 空状态提供 Import PDF、Add by Identifier、Clear Filters。
2. Wiki 空状态提供 Create/Open default project overview 或 Open Wiki Folder。
3. Materials 空状态提供 Reveal Folder、Open Workspace in VS Code、Refresh。
4. Projects 空状态提供 New Project。
5. Agent Panel 空 plan 状态保持 goal 输入和 Generate Plan Only 可见。

## 5. 验收标准

1. 菜单栏包含第一批 Workspace/Paper/View/Wiki 命令，且 disabled 状态合理。
2. `Cmd+F` 在 Library 聚焦搜索，在 PDF Reader 聚焦 reader search。
3. `Cmd+S` 可保存当前 Wiki/Markdown draft。
4. 删除论文确认文案不再出现 `raw/papers`，并显示实际相对路径。
5. 关键 icon-only buttons 都有 accessibility label。
6. Library/Wiki/Materials/Projects 空状态提供直接下一步按钮。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 6. 非目标

- 不在本轮把 Library 迁移为 `Table` 或 `NSTableView`。
- 不在本轮把 Sidebar 改成 `List(selection:)` / `OutlineGroup`。
- 不在本轮实现多窗口、独立 Reader window 或窗口恢复。
- 不在本轮重做 Settings 分栏/toolbar tabs。
- 不在本轮新增 Agent tools 或多轮 Agent loop。

## 7. 风险与约束

- `Cmd+S` 在不同页面的语义要清楚：本轮只在 Wiki 页面保存 Markdown；Library Inspector 仍通过回车或 Save Metadata 按钮保存。
- `Cmd+F` 的焦点目标随当前页面变化，避免全局 search 与 Reader search 抢焦点。
- 删除文案修正不能改变真实删除策略；若当前删除仍是直接删除目录，应如实说明。
- 可访问性补充应尽量不改变布局。

## 8. 建议拆分顺序

1. 先做文案和 accessibility label，风险最低。
2. 再做 Library 搜索聚焦与 filter summary。
3. 再做 Wiki `Cmd+S` 与 dirty indicator。
4. 再做 Reader `Cmd+F` / Find Next / Previous。
5. 最后整理菜单命令，统一 disabled 条件和手动验证。

## 9. Question

1. `Cmd+N` 第一版绑定 New Project，并保留 toolbar / Workspace 菜单中的 Create Workspace。
2. `Cmd+S` 本轮只在 Wiki/Markdown 使用；Library metadata 继续用回车或 Save Metadata 按钮保存。
3. Reader 搜索结果计数本轮不重要，由实现自行决定；最低要求是 `Cmd+F` 聚焦和无匹配提示。
4. 空状态外部打开行为采取保守实现：Finder/VS Code 可作为非破坏性下一步入口，写入或 destructive 操作仍需确认。

## 10. 2026-04-29 完成记录

本轮已完成任务书 16 的主体目标：Mac 基础体验第一阶段已落地，范围按用户确认收束为 `Cmd+N = New Project`、`Cmd+S` 只保存 Wiki/Markdown、Reader 搜索计数不强制、空状态外部打开采取保守非破坏性入口。

- `Sci_StationApp.swift` 新增 Workspace、Paper、View、Wiki 第一批菜单命令：New Project、Open Workspace、Import PDF、Add by Identifier、Open in Reader、Open External PDF、Reveal Paper in Finder、Export BibTeX、Search、Find Next/Previous、Show Inspector、Save Wiki Page。
- `Cmd+N` 绑定 New Project；`Cmd+O` 打开 workspace；`Cmd+F` 根据当前页面聚焦 Library 搜索或 PDF Reader 搜索；`Cmd+G` / `Shift+Cmd+G` 触发 Reader Find Next/Previous；`Cmd+S` 只保存 Wiki/Markdown。
- Library 搜索框 placeholder 扩展为 title、author、tag、identifier、abstract，并增加 Project / Folder / Tag / Search chip 摘要。
- Library 删除确认文案不再提 `raw/papers`，改为显示实际 `paperDirectoryRelativePath`。
- Wiki 编辑器新增 Unsaved indicator，切换页面前会提示丢弃未保存 draft；保存失败不清空 draft。
- PDF Reader 搜索栏支持快捷键聚焦、Find Next/Previous 和局部“Match found / No matches”状态。
- Sidebar 与 Reader toolbar/side rail 的关键 icon-only buttons 增加 accessibility label。
- Library、Wiki、Materials、Projects 的空状态增加直接下一步操作。

本轮验证：

- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：通过。

保留边界：本轮未迁移 Library `Table`，未改 Sidebar `List(selection:)`，未做多窗口/独立 Reader，未重做 Settings 分区，也未扩大 Agent 工具面。

## 11. 下一轮入口

下一轮任务书见 [docs/development/Proposal17.md](Proposal17.md)。
