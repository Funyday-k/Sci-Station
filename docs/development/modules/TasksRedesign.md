# 任务（Tasks / Todo）模块重构

> 目标：把原始的 Todo UI 重构为成熟的任务管理体验，参考 Apple 提醒事项 / Things 3 等设计。

## 用户提出的 6 点要求

1. **自定义 Tag**：专门的任务 tag（与论文 tag 类似），可自定义颜色等。
2. **类型优先的新建任务流程**：点「新建任务」后先选类型：
   - **常规任务**：日历 icon 日期按钮（默认灰、点击变蓝）→ 旁边一列预设（今天/明天/本周末/下周 + 自定义）→ 自定义日期用日历组件，默认今天起，可多次点击选日期段；tag；项目归属；备注；重要级（红旗，最高 3 面）。
   - **论文阅读**：日期按钮（同上）；项目（默认本项目）；选择论文（弹出论文选择子页，默认本项目论文）；tag；重要级。
3. **过滤器**：用一个过滤 icon，点击在 icon 旁弹出小组件（**不是子页面**），可按 tag、任务类型过滤；项目内默认本项目，但可切换查看其他项目。
4. **尽量用明显的 icon 替代文字**。
5. 基于以上，开发**主页与项目主页的小组件**。
6. 流程：可用 subagent 加速；每完成一件事更新本 doc；用 preview，按优秀 UI 交互标准自审。

## 设计参考（来自图 2/3 与 web 调研）

- **Apple 提醒事项**：左侧彩色智能列表卡片（今天/计划/全部/旗标/紧急/完成）；任务行内联「添加日期 / 添加位置 / # 标签 / 旗标」icon 操作；日期弹出建议列表（今天/明天/本周末/下周/自定义→日历）。
- **Things 3**：Jump Start 弹窗集中调度；轻量、键盘友好、icon 化操作。
- **通用成熟模式**：类型先选 → 渐进披露字段；快速预设 + 自定义兜底；标签彩色 chip；优先级用旗标/圆点；过滤用 popover 而非整页。

## 架构决策

- **数据层在 `Sci-Station/Tasks/`**（SPM 编译 + 可测试）；**SwiftUI 在 `Sci-Station/UI/`**（仅 Xcode 编译，无需改 `Package.swift`）。
- **任务 Tag**：独立存储于 `tasks/todo_tags.yaml`，复用 `TagDefinition`（name/colorHex/textColorHex），新增 `TodoTagRepository`（镜像 `TagRepository`）。
- **日期段**：`TodoItem` 新增 `startDate: Date?`；`dueDate` 作为主/结束日期。单日预设 → `startDate=nil`，区间 → `startDate..dueDate`。
- **重要级红旗**：`Priority`（low/medium/high/urgent）映射旗数 low=1/medium=2/high=3，urgent 视觉=3 红旗（保留以兼容提醒事项导入）。
- **日期预设**：`TodoDatePreset`（today/tomorrow/thisWeekend/nextWeek）+ 自定义，纯函数可测。

## 进度

- [x] 基线 UI（见用户截图，图 1/4 当前 Tasks 页与新建任务弹窗）。
- [x] 参考调研（Apple 提醒事项 + web）。
- [x] 数据层：`TodoItem.startDate`（日期段）+ `TodoRepository` 编解码；`Priority.flagCount`/`fromFlagCount`（`TodoPriorityFlags.swift`）；`TodoDatePreset`；`TodoTagRepository` + `ResearchWorkspace.todoTagsDefinitionURL`（`tasks/todo_tags.yaml`）+ 种子文件；`AppViewModel` 接线（`todoTagDefinitions`/`availableTodoTagDefinitions`/`upsertTodoTag`/`deleteTodoTag`，`addTodo`/`updateTodo` 新增 startDate/tags/relatedPaperIDs）。
- [x] 新建任务（类型优先）composer（`UI/Tasks/TaskComposerView.swift`）：类型选择器 → 标题 → 日期(`TaskDateField`：灰/蓝按钮 + 预设 + 自定义范围日历 `TaskRangeCalendar`) + 标签(`TaskTagPickerField`，多选 + 内联建标签带配色) + 项目菜单 + 红旗优先级(`TodoPriorityFlagsView`) + 备注；论文阅读类型显示关联论文区。
- [x] 论文选择子页（`UI/Tasks/TaskPaperPickerView.swift`，默认本项目，可切全部 + 搜索）。
- [x] 过滤 popover（`UI/Tasks/TaskFilterButton.swift`）：类型 + 标签 + 项目范围（本项目默认，可切其他/全部），icon 触发的小浮层（非整页）。
- [x] icon 化工具栏/行：`TodoDashboardWidget` 工具栏改为 icon；`TodoRowView`/`TodoCardView` 改为展示型（kind 图标 + 红旗 + 彩色标签 chip + 日期段），编辑改为打开新 composer。
- [x] 构建（xcodebuild 成功）+ 核心测试（`SciStationCoreTestRunner` 全过）+ preview 自审（composer / 日期面板渲染正常）。
- [x] **主页 / 项目主页小组件**：`TodoSummary` 扩展 kind/startDate/tags（向后兼容 Codable）；`ProjectDashboardSnapshot` 新增 `openTodos`（`ProjectDashboardAggregator` 取前 5 条按 dueThenPriority 排序）；Today 小组件新增 `HomeTodoWidgetRow`（kind 图标 + 红旗 + 日期段 + 彩色标签）；`HomePanels.HomeTodoRow` 升级并设为 internal；`ProjectDashboardPanel` 任务卡改为展示前 4 条 openTodos。
- [x] 任务 tag 集中管理：`UI/Tasks/TodoTagManagerView.swift`（名称 + 配色 swatch + Hex + 预览 + 增删改），从任务工具栏 tag 图标入口打开；composer/过滤器仍支持内联新建。
- [x] 模型层测试（`SciStationCoreTestRunner`，全过）：`todoDatePresetResolvesRelativeDates`、`todoPriorityFlagMappingRoundTrips`、`todoRepositoryPersistsDateRange`、`todoTagRepositoryRoundTripsDefinitions`。

## 状态：6 点要求全部完成

构建（xcodebuild）成功；核心测试全过；composer / 日期面板 / 标签管理 preview 自审通过。后续可选打磨：范围日历的视觉高亮、reading 任务的论文 chip 富显示、深色模式细节。

## 已新增/改动文件

- 新增模型：`Tasks/TodoPriorityFlags.swift`、`Tasks/TodoDatePreset.swift`、`Tasks/TodoTagRepository.swift`。
- 改动模型：`Tasks/TodoItem.swift`、`Tasks/TodoRepository.swift`、`Workspace/ResearchWorkspace.swift`、`App/AppViewModel.swift`。
- 新增 UI：`UI/Tasks/TaskComposerComponents.swift`、`TaskDateField.swift`、`TaskTagPicker.swift`、`TaskPaperPickerView.swift`、`TaskComposerView.swift`、`TaskFilterButton.swift`、`TodoTagManagerView.swift`。
- 改动 UI：`UI/DashboardViews.swift`（`TodoDashboardWidget`/`TodoRowView`/`TodoCardView` 重写，移除内联编辑与旧 composer）；`UI/Home/HomePanels.swift`、`UI/Home/Widgets/HomeWidgetDashboardView.swift`、`UI/Home/ProjectDashboardPanel.swift`（小组件升级）。
- 改动模型：另含 `Workspace/HomeSnapshot.swift`、`Workspace/ProjectDashboardAggregator.swift`（`TodoSummary` 扩展 + `openTodos`）。
