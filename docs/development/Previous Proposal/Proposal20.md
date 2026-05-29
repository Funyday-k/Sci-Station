# 任务书 20：AI Lab Thread 管理与计划复用 V1

更新时间：2026-04-29

## 1. 本轮结论

任务书 19 已完成 AI Lab 对话优先与 Thread 化准备：conversation scope 跟随 Sidebar 当前项目，AI Lab 首屏以 compact header、thread strip、prompt composer 和 timeline 为主；`AgentThread` 与 `.sci-station/agent/threads.jsonl` 已落地，New Chat 会先创建 session-only pending thread，并在第一次成功 plan 后写入 thread log；prompt draft 目前按 project/thread key 保存在 App session 内；Agent Panel 细节、Context、Current Plan、Tool Calls、History 和 Copilot Bridge 统一收进折叠区；Agent workspace 路径、run log、thread log、Copilot Bridge、LLM settings 等诊断信息已集中到 Settings。

下一阶段不应急于启用连续 autonomous loop。当前最需要补齐的是 thread 的日常管理能力：用户需要能重命名 thread、清理或归档无用 thread、把历史 run 归并到明确 thread，并让 prompt draft 在应用重启或切换项目后更可靠地恢复。

因此任务书 20 的主线是：把 AI Lab thread 从“可记录的内部模型”推进到“可管理、可整理、可复用的对话单元”，同时继续保持 plan-only 与写入工具逐项审批的安全边界。

## 2. 当前代码基线

- `AgentThread` 已在 `Sci-Station/Agent/AgentModels.swift` 中定义，包含 thread id、project id、title、ordered run ids、created/updated timestamps。
- `AgentThreadRepository` 已在 `Sci-Station/Agent/AgentThreadRepository.swift` 中使用 `.sci-station/agent/threads.jsonl` 做 upsert、按 project 过滤和 updatedAt 排序。
- `SciStationAgentService` 已暴露 `threads(in:projectID:)` 和 `upsertThread(_:in:)`。
- `AppViewModel.agentConversationProjectID` 跟随 Sidebar 当前项目。
- `AppViewModel` 已维护 `agentThreads`、`activeAgentThreadID`、`pendingAgentThread`、`pendingAgentThreadsByProject` 和 session-only `agentGoalDrafts`。
- `generateAgentPlan()` 与 `executeApprovedAgentTools()` 会通过 `attachRunToActiveThread()` 把新 run 追加到当前 thread。
- `AILabWorkspaceView` 已有 thread strip、New Chat、prompt composer、Thread Timeline、Conversation History 和 disabled Auto Run Loop。
- `AgentRunHistoryView` 目前主要用于打开历史 run，还没有“归并到 thread”或“从 run 创建 thread”的入口。
- `Tools/SciStationCoreTestRunner/main.swift` 已覆盖 run history project filtering 与 `AgentThreadRepository` upsert/filter 基础行为。

## 3. 执行任务

### 3.1 Thread 管理模型

1. 扩展 thread 管理语义：
   - 支持重命名 thread。
   - 支持归档或隐藏 thread。
   - 支持删除空 pending thread。
2. 优先采用软归档策略，而不是物理删除历史记录：
   - 建议给 `AgentThread` 增加 `isArchived` 或 `archivedAt`。
   - 默认 thread strip 隐藏 archived threads。
   - Settings 或 History 区可保留查看 archived threads 的后续入口。
3. 保持旧 `threads.jsonl` 兼容：
   - 新字段必须有默认值。
   - 已存在的 thread 行仍可读取。
4. 不迁移、不重写 `runs.jsonl`，run history 继续作为事实日志。

### 3.2 Thread UI 管理入口

1. 在 AI Lab thread strip 中为 active/saved thread 提供轻量管理入口：
   - Rename Thread。
   - Archive Thread 或 Hide Thread。
   - 对空 pending thread 提供 Discard Draft。
2. 重命名时避免大弹窗优先：
   - 可使用小型 inline 编辑、popover 或 sheet。
   - 空标题自动回退为 `New Chat` 或最近 run 的 plan title。
3. 归档当前 thread 后：
   - 自动切换到同 project 下最近未归档 thread。
   - 若没有可用 thread，则回到空状态或创建新的 pending New Chat。
4. UI 文案继续强调 conversation 跟随 Sidebar 当前项目。

### 3.3 历史 Run 归并入口

1. 在 Conversation History 中区分：
   - 当前 thread runs。
   - 同 project 但尚未归入任何 thread 的 legacy/orphan runs。
2. 为 orphan run 提供整理入口：
   - Create Thread from Run。
   - Add Run to Current Thread。
3. 归并时只更新 `threads.jsonl` 中的 ordered run ids，不修改 `runs.jsonl`。
4. 若 run 的 `current_project_id` 与当前 Sidebar project 不一致，应禁止归并并显示说明。
5. 新建 thread 时 title 优先使用 run.plan.title，其次使用 run.goal 截断标题。

### 3.4 Prompt Draft 持久化评估

1. 将当前 session-only `agentGoalDrafts` 升级为 workspace 级持久化，建议新增 `.sci-station/agent/drafts.json` 或 `drafts.jsonl`。
2. draft key 继续使用 project/thread 组合：
   - global conversation 使用 `global`。
   - pending thread 使用 pending thread id。
   - saved thread 使用 thread id。
3. draft 写入应节流或在关键时机保存，避免 TextEditor 每次输入都频繁写磁盘。
4. 切换 project/thread、New Chat、生成 plan 成功、App 关闭前应尽量保存当前 draft。
5. 成功生成 plan 后可保留 draft，直到用户清空或开始新 prompt；不要自动丢弃用户输入。

### 3.5 计划复用与 Copilot Bridge

1. 从历史 run 打开计划时，继续保留 plan、risk、steps、tool calls 和 final response draft 的可读展示。
2. 对历史 plan 增加 Reuse Prompt 或 Duplicate to New Chat 入口：
   - 将历史 run.goal 填入当前 prompt。
   - 不自动执行工具。
3. Copilot Bridge 导出继续使用当前 prompt 和当前 project context。
4. 不在本轮实现真正跨 thread 的 plan diff 或 merge。

### 3.6 Auto Run Loop 安全边界文档化

1. 继续保留 disabled Auto Run Loop UI。
2. 在任务书或 README 中补充未来权限矩阵草案：
   - read-only tools 可在用户开启后自动执行。
   - writesWorkspace tools 仍需逐项审批。
   - externalSideEffect tools 默认禁止自动执行。
3. 起草停止条件但不实现 loop：
   - 最大轮数。
   - 最大工具调用数。
   - 连续失败停止。
   - 写入审批等待时停止。
   - 用户手动 stop。

### 3.7 验证与文档

1. 增加 `AgentThreadRepository` 核心验证：
   - 旧 JSONL 无新字段仍可读取。
   - rename/upsert 不复制重复 thread。
   - archived thread 默认不出现在 active thread 列表。
   - ordered run ids 保持顺序且不重复。
2. 增加 draft repository 或 draft mapping 的核心验证。
3. 如实现 orphan run 归并，增加“只更新 thread，不修改 run log”的验证。
4. 更新 README 的 AI Lab 后续能力说明。
5. 更新 `docs/development/Next-Step-Task-Book.md`。
6. 运行 `swift run SciStationCoreTestRunner`。
7. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不在本轮启用 autonomous continuous loop。
- 不放宽 workspace 写入工具审批。
- 不自动执行 external side effect 工具。
- 不引入外部网络搜索工具。
- 不处理 Library Table V2、列宽/列顺序持久化或 Quick Look。
- 不处理项目生命周期控制、项目归档、项目排序或删除策略。
- 不重构 Sidebar、窗口模型或 Settings 总体信息架构。

## 5. 验收标准

1. 用户可以在 AI Lab 中重命名 saved thread。
2. 用户可以归档或隐藏不需要的 saved thread，thread strip 默认只显示未归档 thread。
3. 用户可以丢弃空 pending New Chat draft。
4. 用户可以从历史 orphan run 创建新 thread，或把同 project orphan run 加入当前 thread。
5. 历史 `runs.jsonl` 不被迁移、不被重写，旧 run history 仍可读取。
6. 旧 `threads.jsonl` 记录即使缺少新增字段也能兼容读取。
7. prompt draft 可在切换 project/thread 后恢复；若本轮实现持久化，重启 App 后也能恢复。
8. 从历史 run 打开 plan 后，可复用 prompt 到当前或新 thread，但不会自动执行工具。
9. Auto Run Loop 仍保持 disabled，并展示未来权限与停止条件说明。
10. SwiftPM Core Test Runner 通过。
11. Xcode macOS build 通过。

## 6. Question

1. Thread 删除策略是否采用软归档，而不是物理删除 `threads.jsonl` 行？建议采用软归档。
2. Prompt draft 持久化是否使用 `.sci-station/agent/drafts.json`，而不是写入 workspace preferences？建议使用独立 drafts 文件，避免偏好文件承担会话内容。
3. 历史 orphan run 是否自动提示归并，还是只在 History 中提供手动整理入口？建议先手动整理。
4. Reuse Prompt 是覆盖当前 prompt，还是创建 New Chat 后填入？建议提供 Duplicate to New Chat，避免覆盖当前草稿。
5. 任务书 21 是否继续 AI Lab，还是转向 Library Table V2 或项目生命周期控制？建议如果任务书 20 完成顺利，任务书 21 转向 Library Table V2。

## 7. 完成记录

完成时间：2026-04-29

本轮按任务书 20 完成 AI Lab Thread 管理与计划复用 V1：

- `AgentThread` 增加 `archived_at` 与归档语义，旧 `threads.jsonl` 缺少新字段时仍可读取。
- `AgentThreadRepository` 默认只返回未归档 thread，并保留 all thread 读取能力；归档不会重写或迁移 `runs.jsonl`。
- AI Lab thread strip 增加 saved thread 右键 Rename / Archive，pending New Chat 增加 Discard Draft。
- Conversation History 拆分为 Current Thread Runs 和 Unthreaded Project Runs；orphan run 可手动创建新 thread 或加入当前同 project thread。
- 历史 run 增加 Duplicate Prompt to New Chat，复用 prompt 但不自动执行工具。
- 新增 `.sci-station/agent/drafts.json`，prompt draft 按 project/thread key 持久化，并通过轻量 debounce 避免每次输入立即写磁盘。
- README 与 `docs/development/Next-Step-Task-Book.md` 已同步 AI Lab thread 管理完成状态。
- 核心验证增加 archived thread 兼容读取、active/all thread 行为和 prompt draft 持久化。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
