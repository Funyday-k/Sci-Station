# 任务书 19：AI Lab 对话优先与 Thread 化准备

更新时间：2026-04-29

## 1. 本轮结论

任务书 18 已完成 AI Lab Codex-style 会话体验 V1：Global / Project conversation、timeline、prompt composer、New Chat、历史 run 打开、可折叠 Context / Plan / Tool Calls / History，以及按 `current_project_id` 过滤 run history 已落地。

用户对下一轮方向的回答：

1. 继续完善 AI Lab 多轮对话，把 run history 升级为更明确的 thread。
2. 连续 agent loop 暂不启用，但需要预留 UI/接口，显示为不可点击并说明原因。
3. Project conversation scope 应跟随 Sidebar 当前项目，不在 AI Lab 内再放独立项目选择器。
4. AI Lab 首屏必须以对话框为主，压缩顶部信息卡；Agent Panel 细节放进折叠区；Agent workspace 路径和同类诊断信息统一移入 Settings。

因此任务书 19 的主线是：让 AI Lab 打开即进入对话，项目上下文由 Sidebar 决定，管理/路径/诊断信息退到 Settings 和折叠区。

## 2. 当前代码基线

- `AppViewModel.agentConversationProjectID` 跟随当前 Sidebar project。
- `AILabWorkspaceView` 首屏已压缩为 compact header + prompt composer + timeline。
- Agent details 已收进 `Agent Panel Details` 折叠区。
- `Auto Run Loop` 入口已预留但 disabled，提示未来连续 agent loop 仍需安全审批模型。
- Agent run log 和 Copilot Bridge 路径已移入 Settings 的 Settings Files 区域。
- Plan-only 和 approved tools 安全模型继续保留。

## 3. 执行任务

### 3.1 Thread 模型准备

1. 设计 Agent thread 数据模型：
   - thread id。
   - project id。
   - title。
   - ordered run ids。
   - created/updated timestamps。
2. 决定 thread 存储位置，建议 `.sci-station/agent/threads.jsonl` 或 `threads.yaml`。
3. 保持与现有 `runs.jsonl` 兼容，不迁移或重写历史 run。
4. UI 中将 current conversation 逐步从“最近 run 列表”过渡为 thread timeline。

### 3.2 对话输入体验

1. 支持 Cmd+Enter 或按钮发送 prompt。
2. 支持 prompt draft 按 project/thread 保存，避免切换项目后丢失草稿。
3. 当前 thread 无 run 时显示更明确的空状态和示例 prompt。
4. 让 New Chat 真正创建新 thread，而不是只清空当前 run。

### 3.3 Agent Loop 预留

1. 保留 disabled `Auto Run Loop` UI。
2. 增加说明：连续执行会在未来版本中要求显式开关、工具权限策略和停止条件。
3. 为未来 service 层增加轻量 options 或 enum 占位，但本轮不执行循环。

### 3.4 Settings 整合

1. 将 workspace 路径、Agent run log、Copilot Bridge、LLM settings、workspace preferences、markdown snippets 等路径集中在 Settings。
2. 工作页面只显示当前任务需要的信息，不显示大段路径或诊断详情。
3. Settings 可逐步拆分为 General / Library / AI / Advanced，但本轮可先在现有长页中整理。

### 3.5 验证与文档

1. 增加 thread repository 或 thread mapping 的核心验证。
2. 更新 README 的 AI Lab 说明。
3. 更新 `DOC/Next-Step-Task-Book.md`。
4. 运行 `swift run SciStationCoreTestRunner`。
5. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不在本轮真正启用 autonomous continuous loop。
- 不允许未审批 workspace 写入自动执行。
- 不引入外部网络工具。
- 不重构 Sidebar 为系统 List/Outline。
- 不处理 Library Table V2。

## 5. 验收标准

1. AI Lab 打开后首屏以 prompt composer 和 timeline 为主。
2. Conversation project scope 跟随 Sidebar 当前项目。
3. Agent details 和历史管理不挤占首屏。
4. Auto Run Loop 有禁用入口和说明。
5. Agent/Workspace 路径信息集中在 Settings。
6. 如果进入 thread 模型实现，旧 runs history 仍可读取。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 6. Question

1. Thread 存储是否使用 `threads.jsonl`，每行一个 thread 记录？建议使用 JSONL，和 runs log 保持一致。
2. New Chat 是否必须立即创建 thread 文件记录，还是第一次成功 plan 后再落盘？建议第一次成功 plan 后落盘。
3. Prompt draft 是否需要持久化到 workspace，还是先做 session 内保存？建议先做 session 内保存。
4. Auto Run Loop 的未来权限策略是否采用“只自动执行 read-only tools，写入工具仍逐项审批”？建议是。

## 7. 完成记录

完成时间：2026-04-29

本轮按用户确认后的方向完成 AI Lab 对话优先与 thread 化准备：

- AI Lab conversation scope 继续跟随 Sidebar 当前项目，不再在 AI Lab 内提供独立项目选择器。
- 新增 `AgentThread` 数据模型，包含 thread id、project id、title、ordered run ids、created/updated timestamps。
- 新增 `AgentThreadRepository`，使用 `.sci-station/agent/threads.jsonl` 存储，每行一个 thread 记录，并保持 `runs.jsonl` 不迁移、不重写。
- `New Chat` 先创建 session-only pending thread，第一次成功生成 plan 后才写入 `threads.jsonl`。
- prompt draft 按 project/thread key 保存在 App session 内，切换项目或 thread 时尽量保留当前草稿。
- AI Lab 首屏新增 thread strip，可查看和切换当前 project 下的 saved threads；timeline 改为优先显示当前 thread 的 ordered runs，旧 run history 仍作为无 thread 历史的 fallback。
- Send / Generate Plan 支持 `Cmd+Enter` 快捷键。
- disabled `Auto Run Loop` 入口保留，并明确未来策略为只自动执行 read-only tools，workspace 写入仍需逐项审批。
- Settings Files 增加 Agent Threads 路径，并继续集中展示 Agent Run Log、Copilot Bridge、Workspace Preferences、LLM Settings、Markdown Snippets 等路径。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
