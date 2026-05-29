# 任务书 15：Agent Panel V1、审批与运行历史

更新时间：2026-04-29

## 1. 本轮结论

任务书 14 已完成项目-论文关系 UI 主数据源切换：Library Inspector 和右键菜单的项目归属、核心文章、pin、项目内用途和项目内文件夹写入 `ProjectPaperLinkRepository`，`Paper.projectIDs` / `coreProjectIDs` 保留为兼容镜像。Project Overview 的 Core Papers 也已接入关系层 pin/order 排序。

下一阶段应进入 Agent Panel V1。底层 Agent kernel 已在任务书 11/12 建立：snapshot、planner、plan parser、tool registry、写入工具审批、run logger 和 Copilot Bridge exporter 已存在，但 AI Lab 仍只是 LLM 配置和路径说明页，用户还不能在 App 内输入 goal、生成 plan、逐项审批工具调用或查看 run history。

任务书 15 的目标是把已有 Agent 底座做成一个可实际使用、默认 plan-only、写入前显式确认的 UI 工作流。结合本轮 macOS 设计审阅意见，本轮 Agent Panel 不追求增加更多工具，而是优先补齐一个清晰、可恢复、符合 Mac 用户预期的工作流：用户知道当前上下文是什么、模型准备做什么、哪些操作会写入文件、批准后发生了什么、历史记录在哪里。

## 2. 当前代码基线

- `AgentWorkspaceContextBuilder` 已能生成 root/current project/project papers/project todos/available tools snapshot。
- `AgentPromptBuilder`、`AgentPlanner`、`AgentPlanParser` 已具备 plan JSON 生成与解析路径。
- `AgentToolRegistry` 与 `AgentToolExecutor` 已有 tool definition、requires confirmation 和执行结果模型。
- `CreateTodoAgentTool` 与 `UpdatePaperClassificationAgentTool` 已存在，并能默认使用 current project context。
- `AgentRunLogger` 可写 root `.sci-station/agent/runs.jsonl`。
- `AgentCopilotBridgeExporter` 可导出 root `.sci-station/agent/copilot-bridge/` 文件。
- `AILabWorkspaceView` 目前只展示 provider/model/projects/papers、DeepSeek 设置入口和 agent 路径说明，尚无 goal 输入、plan-only 运行、tool call 审批或 run history。

## 3. 本轮产品原则

1. **默认只生成计划。** 用户点击生成后只得到 plan，不自动执行任何写入工具。
2. **写入前逐项确认。** `requires_confirmation` 的 tool call 必须单独勾选批准，未批准项不能执行。
3. **上下文必须可见。** Agent Panel 在输入 goal 前后都要展示 root、current project、project papers、open todos 和 available tools 摘要。
4. **错误留在局部 UI。** LLM 配置缺失、API key 缺失、网络失败、解析失败、工具失败都应显示在 Agent Panel 内，不能用全局崩溃式流程中断 workspace。
5. **运行可审计。** plan-only、tool execution、bridge export 都要留下可追踪记录或明确路径。
6. **不扩大工具面。** 本轮只把已有 `create_todo` 与 `update_paper_classification` 做成审批闭环。

## 4. 目标

### 目标 A：AI Lab 内的 Agent Panel

- 在全局 AI Lab 中新增 Agent Panel 区域。
- 提供自然语言 goal 输入。
- 展示当前 root、current project、project papers、project open todos 和可用工具摘要。
- 默认以 plan-only 模式运行，不自动执行写入工具。
- Goal 输入区需要有空状态提示、执行中 disabled 状态和局部错误提示。

### 目标 B：Plan 生成与展示

- 调用现有 `SciStationAgentService` / planner 生成 `AgentPlan`。
- 展示 plan title、summary、risk、steps 和 tool calls。
- 展示每个 tool call 的 tool name、requires confirmation、arguments 和预期影响。
- Plan JSON 解析失败时显示可恢复错误，不清空用户 goal。
- LLM 配置缺失或 API key 缺失时给出可恢复状态，不让 UI 崩溃。

### 目标 C：工具调用审批与执行

- 对 `requires_confirmation` 的 tool call 提供逐项批准/取消。
- 支持 approve-and-run 已批准工具。
- `requires_confirmation == false` 的只读工具如存在，可在 UI 中标记为不需要审批；本轮不新增自动执行路径。
- 执行结果显示 success/error、message、modified paths。
- 执行完成后刷新 Todo、Library 和当前项目上下文。

### 目标 D：Run History 与 Copilot Bridge

- 每次 plan-only 或执行运行都写入 `.sci-station/agent/runs.jsonl`，包含 current project id。
- AI Lab 显示最近 run history 摘要：goal、mode、status、current project、时间。
- 支持导出 Copilot Bridge prompt 和 manifest，并在 UI 中显示导出路径。
- JSONL 中单条损坏不应阻止最近有效记录展示。

## 5. 执行任务

1. 审阅 `SciStationAgentService`、`AgentTools`、`AgentRunLogger` 和 `AgentCopilotBridgeExporter` 的现有 API，确认 UI 可复用哪些方法。
2. 补齐 Agent service 的 UI-facing 方法：
   - 生成当前 workspace snapshot。
   - 生成 plan-only run 并写 run log。
   - 按批准集合执行 tool calls。
   - 读取最近 run history。
   - 导出 Copilot Bridge prompt/manifest。
3. 在 `AppViewModel` 增加 agent goal、isPlanning、isExecuting、current plan、tool approval state、tool results、run history、bridge export status、agent local error 等状态。
4. 在 workspace 打开、项目切换、plan 生成、tool 执行后刷新 Agent context 与最近 run history。
5. 在 `AILabWorkspaceView` 中新增 Agent Panel：
   - Goal 输入和 plan-only 按钮。
   - 当前 context 摘要。
   - 可用 tools 摘要。
   - Copilot Bridge export 按钮与导出路径。
6. 增加 Plan Summary UI：
   - title / summary / risk。
   - steps 列表。
   - tool calls 列表。
   - 每个 tool call 的 arguments 以可读 key-value 或 JSON 摘要展示。
7. 增加 Tool Approval UI：
   - 每条 `requires_confirmation` tool call 独立 toggle。
   - 未批准写入工具保持 disabled / skipped。
   - approve-and-run 只执行已批准项。
8. 增加 Tool Result UI，展示 success/error、message、modified paths，并在执行后刷新 Todo、Library、项目关系和 Agent context。
9. 增加 Run History UI，至少显示最近 5 条有效记录：goal、mode、status、current project、时间。
10. 增加 Core Test Runner 覆盖：
    - plan-only run log 写入 current project id。
    - approved tool execution 能写入 expected data。
    - 未批准写入工具不会执行且有 skipped 结果。
    - Copilot Bridge 导出 prompt/manifest 路径存在。
    - 损坏 JSONL 行不会阻止读取最近有效 run。
11. 更新 `README.md` / `docs/development/Next-Step-Task-Book.md`，并在本任务书追加完成记录。
12. 运行 `swift run SciStationCoreTestRunner`。
13. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。

## 6. 验收标准

1. 用户能在 AI Lab 输入 goal 并生成 plan-only 计划。
2. Agent Panel 能展示当前 root/current project/project papers/project todos/available tools 摘要。
3. Plan UI 能展示 steps、tool calls、risk 和 requires confirmation 状态。
4. `create_todo` 与 `update_paper_classification` 只有在用户批准后才执行。
5. 执行结果会显示 success/error 和 modified paths。
6. 每次 run 写入 root `.sci-station/agent/runs.jsonl`，并包含 current project id。
7. 用户能从 AI Lab 导出 Copilot Bridge prompt/manifest，并看到导出路径。
8. SwiftPM Core Test Runner 通过。
9. Xcode macOS build 通过。

## 7. 非目标

- 不在本轮增加大量新 Agent tools；优先把现有 `create_todo` 和 `update_paper_classification` 做成完整闭环。
- 不接入或读取 VS Code Copilot 内部 token。
- 不默认上传论文全文；planner prompt 只发送已有 snapshot 摘要。
- 不在本轮实现项目归档/删除策略。
- 不在本轮实现自动连续执行、多轮 Agent loop、文件自由写入或 shell tool。

## 8. 风险与约束

- Agent Panel 必须默认 plan-only，写入工具必须显式审批。
- Cloud LLM 失败、配置缺失、网络失败都应留在 UI 状态内，不应破坏 workspace 数据。
- Tool arguments 需要用 typed parser 和 tool registry 校验，不能让模型直接写文件。
- Run history 追加写入应保持 JSONL 可恢复：单条损坏不应阻止后续 UI 显示最近有效记录。

## 9. Question

1. Agent Panel V1 是否优先只支持内置 LLM plan-only，还是同轮加入 Copilot Bridge 导出按钮？建议同轮加入导出按钮，但 plan 导入可留后续。
2. Tool call 审批 UI 是按每条 tool call 勾选，还是按风险分组批量批准？建议第一版逐条勾选。
3. Run history 第一版是否只读最近 5 条 JSONL，还是需要完整历史浏览和过滤？建议先最近 5 条。
4. 生成 plan 时是否允许发送论文摘要/abstract？建议第一版只发送 paper title、tags、status、priority、project relation 和 todo 摘要。

## 10. 2026-04-29 完成记录

本轮已完成任务书 15 的主体目标：AI Lab 已从 LLM 配置说明页扩展为可实际操作的 Agent Panel V1，默认 plan-only，写入工具逐项审批，run history 和 Copilot Bridge 导出形成闭环。

- `AgentPlan` 新增可选 `title`、`risk` 与 `steps` 字段，旧 plan JSON 仍可兼容解析。
- `SciStationAgentService` 新增 UI-facing API：snapshot、tool definitions、执行已有 plan 的 approved tool calls、读取最近 run history、导出 Copilot Bridge。
- `AgentRunLogger` 新增最近历史读取，并跳过损坏 JSONL 行，避免单条坏记录阻断 UI。
- `AppViewModel` 新增 Agent Panel 状态：goal、context snapshot、tool definitions、current run、approval set、tool results、run history、bridge export、局部状态和局部错误。
- `AILabWorkspaceView` 新增 Agent Panel：goal 输入、context/tools 摘要、plan-only、逐项 approval、approve-and-run、tool result、bridge export path、最近 5 条 run history。
- 执行 approved tools 后会刷新 workspace 数据，确保 Todo、Library、项目关系和 Agent context 同步。
- Core Test Runner 新增 plan-only log/current project、approved execution、未批准写入不执行、bridge export、损坏 JSONL 容错覆盖。

本轮验证：

- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：通过。

保留边界：本轮不新增更多 Agent tools，不实现自动多轮 Agent loop，不接入 Copilot 内部 token，不让 Agent 自由写文件或执行 shell。

## 11. 下一轮入口

下一轮任务书见 [docs/development/Proposal16.md](Proposal16.md)。
