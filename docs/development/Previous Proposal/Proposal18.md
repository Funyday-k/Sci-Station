# 任务书 18：AI Lab Codex-style 会话体验 V1

更新时间：2026-04-29

## 1. 本轮结论

任务书 17 已完成 Library 原生表格体验 V1：论文列表切换为 SwiftUI `Table`，排序状态写入 workspace preferences，selection set 支持单选/多选，Inspector 多选摘要、Copy Citation、Copy BibTeX 和选择集 BibTeX 导出已落地。

用户本轮希望 AI 功能向 Codex 的交互逻辑对齐：AI Lab 不应只是一次性 goal/plan 表单，而应更像一个按上下文组织的对话工作台。关键方向包括：

- 以“对话”为主入口，保留 plan-only 和 approved tools 的安全执行模型。
- 增加可折叠的上下文、计划、工具调用和历史区，避免 AI Lab 页面过长。
- 不同项目应有不同对话上下文，至少能按 project 查看/继续最近 agent runs。
- 继续把 workspace 写入动作放在显式审批之后，不改变安全边界。

因此任务书 18 改为 AI Lab Codex-style 会话体验 V1，Library Table V2 顺延到后续任务书。

## 2. 当前代码基线

- `AILabWorkspaceView` 当前包含 DeepSeek 设置入口、Agent Panel 和 Agent Workspace 路径说明。
- Agent Panel 当前是单个 `agentGoal` 文本框、Generate Plan Only、Run Approved Tools 和 Export Copilot Bridge。
- `AgentRun` 已记录 `currentProjectID`，run log 写入 `.sci-station/agent/runs.jsonl`。
- `AgentWorkspaceSnapshot` 已包含 current project、project papers、project open todos 和工具定义。
- `SciStationAgentService` 已支持 plan-only 与 execute-approved 两种模式。
- `AppViewModel.refreshAgentState()` 当前只加载最近 5 条 run history。

## 3. 执行任务

### 3.1 任务书修订与范围确认

1. 将任务书 18 从 Library Table V2 改为 AI Lab Codex-style 会话体验 V1。
2. 在文档中记录 Library Table V2 顺延，不丢失后续任务。
3. 保持本轮非目标清晰：不实现真正多轮自动 agent loop，不绕过 tool approval。

### 3.2 项目会话模型

1. 在 App/ViewModel 层增加 Agent conversation project scope：
   - 支持 Global conversation。
   - 支持每个 active project 的 project conversation。
2. 生成 plan、执行 approved tools、导出 Copilot Bridge 时使用当前 conversation scope 作为 agent project context。
3. 读取更多 agent run history，并按 `currentProjectID` 过滤当前会话。
4. 支持 New Chat：清空当前 prompt、current run、approval 和状态消息，但保留历史。
5. 支持从历史 run 打开/继续查看旧计划。

### 3.3 Codex-style AI Lab UI

1. 将 Agent Panel 从“表单 + 多个 GroupBox”调整为对话式布局：
   - 顶部显示 conversation scope selector。
   - 中间显示当前会话 timeline。
   - 底部或当前区域显示 prompt composer。
2. 增加可折叠区域：
   - Context。
   - Current Plan。
   - Tool Calls / Approvals。
   - Recent Runs / Conversation History。
   - Copilot Bridge export details。
3. 当前 run 应像 assistant response 一样展示 summary、risk、steps 和 final response draft。
4. 工具调用继续逐项 approve，执行结果显示在可折叠 Tool Calls 中。

### 3.4 测试与文档

1. 增加必要的核心验证，覆盖 project-scoped agent run history 或 run log 过滤逻辑。
2. 更新 README 的 AI Lab 功能说明。
3. 更新 `docs/development/Next-Step-Task-Book.md`。
4. 运行 `swift run SciStationCoreTestRunner`。
5. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不在本轮实现真正持续多轮 autonomous agent loop。
- 不在本轮允许未审批 workspace 写入工具自动执行。
- 不在本轮增加外部网络搜索工具。
- 不在本轮重写 AgentPlanner prompt 格式，除非 UI 需要小幅补充。
- Library Table V2、批量编辑和 Quick Look 顺延。

## 5. 验收标准

1. AI Lab 可以选择 Global 或某个 Project conversation。
2. 不同 project conversation 能显示各自 recent runs。
3. 生成 plan / 执行 approved tools / Copilot Bridge 使用当前 conversation project context。
4. AI Lab 主要内容有可折叠 Context、Plan、Tool Calls、History 等区域。
5. New Chat 可清空当前 prompt/current run，但不删除历史。
6. Plan-only 和 tool approval 安全模型不回退。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 6. Question

1. 下一轮是否继续完善 AI Lab 多轮对话，比如把每个 run 组成更明确的 thread？建议继续。
2. 是否需要真正的“连续执行直到完成”agent loop？建议暂不做，先保持 plan/approve/run。
3. Project conversation 是否应该自动跟随 Sidebar 当前项目，还是允许 AI Lab 独立选择？建议允许 AI Lab 独立选择。
4. Library Table V2 是否顺延为任务书 19？建议顺延。

## 7. 完成记录

完成时间：2026-04-29

本轮按用户要求将任务书 18 从 Library Table V2 调整为 AI Lab Codex-style 会话体验，并完成 V1：

- AI Lab 支持 Global conversation 和每个 active project 的 Project conversation。
- Generate Plan、Run Approved Tools 和 Export Copilot Bridge 改为使用当前 AI Lab conversation project context。
- Agent run history 读取数量从最近 5 条扩展到最近 50 条，并按 `current_project_id` 过滤当前 conversation。
- 增加 New Chat，清空当前 prompt/current run/approval/status，但不删除历史。
- 支持从 Conversation History 打开旧 run 查看。
- AI Lab 页面增加 timeline，并将 Context、Current Plan、Tool Calls / Approvals、Conversation History、Copilot Bridge Export 改为可折叠区域。
- `AgentRunLogger` 增加 project conversation 过滤能力，核心验证覆盖 Global / Project run history 过滤。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
