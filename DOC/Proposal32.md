# 任务书 32：AI Lab AgentLoopRunner 真 Tool Loop

更新时间：2026-05-02

> 本任务书承接任务书 31。P31 已完成按需读论文工具、metadata-only workspace snapshot、paper-tool prompt 指令和折叠工具审计 UI。下一轮目标是推进任务书 30 的 P1.2：让 AI Lab 从“只生成计划/手动执行工具”升级为可观察、可停止、有上限的多步 tool loop。

## 1. 已验证状态

1. `list_papers`、`read_paper`、`read_paper_section`、`search_papers` 已注册为只读工具，默认不需要审批。
2. `AgentWorkspaceContextBuilder.snapshot` 默认 metadata-only，不再把论文正文直接塞进 prompt。
3. `AgentPromptBuilder` 已要求模型需要论文正文时先计划调用 paper tools。
4. AI Lab runtime 事件行已能折叠展示思考摘要、工具参数和工具结果。
5. `swift run SciStationCoreTestRunner` 已通过 P31 新增 case。

## 2. 本轮目标

实现一个最小可用但边界清晰的 `AgentLoopRunner`：

1. 支持 `model -> tool_call -> tool_result -> model` 多轮运行。
2. 每一步都写入 append-only `AgentSessionEventLogger`，UI 可看到 assistant text、tool_call、tool_result、permission/hook 事件。
3. 默认启用硬上限：`maxSteps`、`maxToolCalls`、失败计数、用户停止。
4. 写盘/外部副作用工具继续审批；只读 paper tools 可自动执行。
5. 先保留现有 plan-only / execute-approved 作为 fallback，不破坏现有模式。

## 3. 实施任务

- [P32.1] 梳理当前 `AgentPlanner` / `LLMProviderRequest.tools` / `OpenAIStreamDeltaParser` / `AgentToolExecutor` 的能力边界，确定首版 loop 走哪条 wire-format。
- [P32.2] 新建 `AgentLoopRunner` actor 与 `AgentLoopPolicy` 执行入口，接入 `AgentWorkspaceSnapshot`、filtered tool definitions、conversation history、hook engine、permission 策略。
- [P32.3] 实现最小 loop：模型产出 tool calls 后执行允许的工具，把 tool results 作为下一轮上下文重新请求模型，直到最终 markdown 或上限命中。
- [P32.4] 把 loop 事件写入 `AgentSessionEventLogger`：`user_message`、`assistant_message`、`reasoning_summary`、`tool_call_started`、`tool_result`、`permission_requested`、`hook_result`、`stop`。
- [P32.5] 更新 `SciStationAgentService.run` / `AppViewModel.generateAgentPlan` 的调用路径：Assistant 模式优先走 loop，Plan/Conversation fallback 保留。
- [P32.6] 更新 AI Lab UI 状态：运行中可停止；tool call/result 卡片随事件增量出现；最终回答继续走 GFM + KaTeX 渲染。
- [P32.7] 补 CoreTestRunner：`agentLoopRunnerCallsPaperToolThenContinues`、`agentLoopRunnerStopsAtMaxSteps`、`agentLoopRunnerRequiresApprovalForWrites`、`agentLoopRunnerLogsToolEvents`。
- [P32.8] 运行验证：`get_errors`、`swift run SciStationCoreTestRunner`、`xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- [P32.9] 更新 `DOC/Proposal30.md`、`DOC/chat.md`，并写下一轮任务书（预计 P1.4 Prompt + Skill loader 或 P1.5 safety hooks）。

## 4. 验收标准

1. Mock provider 第一轮返回 `read_paper_section` tool call，runner 自动执行只读工具，第二轮 provider 收到 tool result 并返回最终 markdown。
2. UI 可观察到 tool call 和 tool result 折叠卡片，最终回答中的 `$$...$$` 仍由 KaTeX 渲染。
3. 写 workspace 的工具在未审批时不会执行，且会产生 permission/audit 事件。
4. Loop 命中 `maxSteps` 或 `maxToolCalls` 时停止并给出可读原因，不会无限循环。
5. CoreTestRunner 和 Xcode app build 均通过。

## 5. 已知边界

- 首版可以先复用现有 JSON plan/tool_calls 协议做 loop vertical slice；provider-native tool calling 和 streaming tool-call delta 可作为增强项。
- 本轮不做 MCP tool loop 接入；MCP 仍属任务书 30 Phase 2。
- 本轮不把 session/run logs 全局化；P1.6 的 threads 全局化边界仍存在。
- 本轮不做完整插件/skill loader；如需 skill context，留给 P1.4。

## 6. Questions

1. Wire-format 首版选哪条：A. 直接做 OpenAI/Anthropic 原生 tool calling；B. 先复用当前 JSON `tool_calls` 做 loop vertical slice，再替换 provider-native。推荐 B，能最快让 paper tools 真正跑起来。
2. Assistant 模式默认是否立即启用 loop？推荐启用，但保留 Plan 模式作为只生成计划的安全 fallback。
3. 只读 paper tools 是否继续 auto-allow？推荐继续 auto-allow；写盘工具继续 ask。
4. 命中 loop 上限时 UI 文案要偏工程还是偏用户？推荐用户可读：“已达到本轮工具调用上限，已停止；你可以缩小问题或继续下一轮。”