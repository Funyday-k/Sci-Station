# 任务书 39.6：AI Lab 全流程限次稳定化与 Chat/Runtime 阻塞修复

更新时间：2026-05-07

完成状态：Implementation complete；SwiftPM、AgentRuntime pytest、Xcode build passed；真实 GUI/provider 回归转入 P39.7。

> 本任务书承接 P39.5。P39.5 已修复一批 AI Lab 交互和持久化问题，但最新手动截图显示 AI 框架仍不能稳定完成真实对话：Chat 模式会被 provider tool schema 拒绝、Assistant/Plan 模式把可读回复误判为非结构化失败、LangGraph/SwiftLoop 输出链路不一致、论文阅读回答质量不足，并且 UI 仍有 workspace 范围文案、复制按钮位置、默认审批信息暴露等体验问题。P39.6 的目标是在有限迭代次数内完成 AI 全链路 P0/S1 修复，不继续扩大 P40 创建向导范围。

## 1. 背景

最新反馈与截图暴露的问题：

```text
图1 / 图4: Chat 模式发送普通问候后失败，provider 返回 HTTP 400；create_todo 的工具 schema 不是 JSON Schema object。
图2: “项目里都有什么文章？列一下”虽能列出论文，但随后出现“AI 返回内容不是结构化 JSON”的失败提示。
图3: “第一篇文章的蒸发率公式是什么？”只显示搜索/工具过程，没有给出符合问题要求的最终公式解释。
图4: 选择 LangGraph 后不能稳定输出内容。
图5: 真实对话出现 “LLM provider returned an empty response”，用户没有拿到可用回答。
图6: 使用 SwiftLoop 时仍不能稳定输出最终内容。
补充: 顶部出现 Workspace 选项让用户误以为多了一个 workspace。
补充: AI 回复复制按钮应该放在对话气泡结尾，而不是消息头部。
补充: 默认 auto-allow 审批信息不应显示在时间线；对话框只需要说明实际用了哪些工具。
```

这些问题说明 AI Lab 不是单点 bug，而是 provider schema、planner fallback、runtime fallback、event-to-UI 映射、prompt/tool-loop 质量和手动验证体系同时不稳。P39.6 必须按全流程排查，而不是继续只修 UI 表象。

## 2. 本轮目标

1. 修复 Chat 模式无法正常对话的 P0 阻塞，确保普通问候、项目论文列表、论文内容追问都有可见回答或清楚 inline failure。
2. 修复 OpenAI-compatible / DeepSeek tool schema：所有 provider-native tools 的 `parameters` 必须是合法 JSON Schema object。
3. 修复 Assistant/Plan 模式对可读非 JSON 回复的失败误报；非结构化但可读内容应转为可见 AI 回复。
4. 修复 LangGraph 选择与 SwiftLoop fallback：sidecar 不健康时不再先卡在不可用 sidecar，必须立即走 SwiftLoop 并给出可见 fallback 说明。
5. 修复 SwiftLoop 工具调用后无最终回答的问题，工具结果必须继续进入最终答复，或生成明确的缺失原因。
6. 收敛 AI Lab UI 文案：`Workspace` 改为“全工作区”运行范围，解释它不是另一个 workspace。
7. 将 AI 回复复制按钮移动到回复气泡结尾，复制 Markdown/plain text。
8. 默认 auto-allow 审批事件不显示在对话时间线；只显示工具开始/完成/失败和真正需要用户审批的写入。
9. 建立 P39.6 AI 全流程手动回归，用同一批问题覆盖 Chat、Assistant、LangGraph、SwiftLoop。

## 2.1 限次迭代策略

P39.6 采用最多 3 轮内部修复迭代，每轮必须有可验证产物：

```text
Iteration 1: P0 热修。修复 schema、非 JSON fallback、runtime fallback、UI 明显误导，并跑 SwiftPM。
Iteration 2: 输出质量。围绕“列论文”“第一篇蒸发率公式”“总结第一篇文章”修 prompt/tool-loop/event 映射。
Iteration 3: Runtime parity。对 SwiftLoop 与 LangGraph/Auto fallback 做同题回归，补齐手动记录和 release-blocking 清单。
```

若 3 轮后仍有真实 provider 不稳定，必须把剩余问题归类为 provider/sidecar/模型质量/应用代码，并保留最小可用 SwiftLoop fallback，而不是继续无边界试错。

## 3. 已完成热修

- [x] [P39.6.1] Provider-native tool schema normalization。
	- `OpenAICompatibleProvider` 将旧简写 schema（如 `{"title":"string"}`）转换为合法 JSON Schema object。
	- 生成 `type: object`、`properties`、`required`、array items、enum 等基础字段。
	- 防止 DeepSeek/OpenAI-compatible provider 因 `parameters.type` 缺失或为 null 直接 HTTP 400。

- [x] [P39.6.2] Planner readable fallback。
	- `AgentPlanner` 在 Plan/Assistant 模式下收到可读非 JSON 回复时，不再直接抛出“非结构化 JSON”错误。
	- 可读内容会落为 `AgentPlan.finalResponseDraft`，作为普通 AI 回复显示。
	- partial JSON 仍按原规则隐藏，避免把半截 schema 暴露给用户。

- [x] [P39.6.3] Runtime selection fallback。
	- `SidecarRuntimeCoordinator` 只在 effective runtime 是 LangGraph 时才尝试 sidecar。
	- 用户选择 LangGraph 但 sidecar health 不可用时，立即 fallback 到 Swift Loop，并保留 fallback reason。

- [x] [P39.6.4] AI Lab conversation UI cleanup。
	- 顶部上下文菜单中的 `Workspace` 改为“全工作区”，表达为运行范围而不是新增 workspace。
	- AI 回复复制按钮移动到回复气泡底部结尾。
	- 默认 auto-allow 工具审批事件不再写入 planning timeline；真正等待用户审批的写入仍显示。

- [x] [P39.6.5] Focused core regression。
	- 新增 provider schema normalization 测试。
	- 新增 Assistant 非 JSON 可读回复 fallback 测试。
	- `swift run SciStationCoreTestRunner` 已通过。

## 4. 本轮实施任务

- [x] [P39.6.6] Chat mode end-to-end smoke repair。
	- Provider-native tool schema normalization 已覆盖 DeepSeek/OpenAI-compatible `parameters.type=object` 要求，避免普通 Chat 因写入工具 schema 失败。
	- `recordFailedRun` 与 SwiftLoop provider failure fallback 会保留 user message、失败原因和可见 inline failure；真实 provider GUI smoke 转入 P39.7。
	- 普通问题不改变写入审批边界；read-only 与 write tool 仍按 Permission Dock 规则分流。

- [x] [P39.6.7] Paper-reading answer quality repair。
	- Prompt builder 已要求 ordinal/“第一篇”论文先 `list_papers` 解析目标，再走 `search_papers -> read_paper_section -> final answer`。
	- 公式类问题要求最终回答包含公式、局部符号上下文和 paper title/id/path；未命中时说明搜索路径。
	- 新增 core regression 覆盖 list/search/read 后最终 Markdown 公式与来源输出。

- [x] [P39.6.8] SwiftLoop final-response reliability。
	- `AgentLoopRunner` 现在在工具成功后继续请求模型；若 provider 抛出 empty response 或返回空 final，会生成可见 assistant fallback。
	- fallback 包含 model、失败原因、已使用工具和最后一个工具结果摘要，并以 `providerUnavailable` pause reason 保留结构化状态。
	- `LegacySwiftAgentRuntime` 与 `SciStationAgentService` 会把该 fallback 作为可见 final/inline failure 进入 timeline，而不是只停在工具过程。

- [x] [P39.6.9] LangGraph / Auto fallback parity。
	- 现有 fixture regression 保持 sidecar unavailable、crash after approval、golden success、approval resume 的 timeline/persistence 行为。
	- `SciStationAgentService` 对 loop pause title/completion 状态做了非审批区分，避免 provider failure 被显示成“等待工具审批”。
	- 真实 sidecar ready/unavailable GUI 矩阵转入 P39.7 live parity。

- [x] [P39.6.10] Approval/event display cleanup。
	- read-only auto-allow 不进入 Permission Dock 审批噪音。
	- 工具完成 timeline 现在使用“已使用工具：tool_name”这类简洁说明，完整工具结果仍保存在 payload/audit 中。
	- 写 workspace / external side effect / risky action 仍按默认 ask 安全边界处理。

- [x] [P39.6.11] AI Lab manual-test record。
	- 已新增 `docs/development/manual-tests/runs/2026-05-07_P39.6_AILabFullFlow.md`。
	- 记录了自动化覆盖、GUI/live provider 待补测项、剩余风险与新增 regression。
	- 下一轮真实 provider GUI 回归已写入 `docs/development/Proposal39.7.md`。

## 5. 非目标

```text
不做 P40 Workspace Creation Wizard。
不新增 provider 或改模型凭证系统。
不把 LangGraph sidecar 改成生产唯一 runtime；SwiftLoop 仍是最小可用 fallback。
不取消写入审批；只隐藏默认 auto-allow 的噪音。
不引入 OpenCode/Claude Code 作为生产依赖。
不做完整 AI Lab 信息架构重设计。
```

## 6. 验收标准

1. Chat 模式发送“你好”必须返回自然语言回答，不触发 `create_todo` schema HTTP 400。
2. “项目里都有什么文章？列一下”必须显示论文列表，不再追加非结构化 JSON 错误。
3. “第一篇文章的蒸发率公式是什么？”必须给出公式/上下文/来源，或说明确实未找到并列出搜索路径。
4. 选择 LangGraph 时，如果 sidecar 可用则正常输出；不可用则快速 fallback SwiftLoop，并有可见 fallback reason。
5. 使用 SwiftLoop 时，read-only 工具运行后必须产生最终 AI 回复或 inline failure，不能只停在工具结果。
6. 顶部不再显示令人误解的 `Workspace` 选项；“全工作区”明确表示运行范围。
7. AI 回复复制按钮位于回复气泡结尾，复制内容为 Markdown/plain text。
8. 默认 auto-allow 审批信息不出现在时间线；真正需要审批的写入仍进入 Permission Dock。
9. SwiftPM CoreTestRunner、AgentRuntime pytest、Xcode app build 通过，或交付记录写明环境阻塞。

## 7. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充：

```text
get_errors for edited SwiftUI/App files
manual AI Lab Chat mode with Swift Loop
manual AI Lab Chat mode with LangGraph Sidecar
manual AI Lab Chat mode with Auto fallback while sidecar unavailable
manual inspection of .sci-station/agent/runs and session events after empty provider response
```

## 8. 手动测试计划

```text
MT07-P39.6-01: Chat / SwiftLoop / “你好” -> 有自然语言回答，无 HTTP 400。
MT07-P39.6-02: Chat / SwiftLoop / “项目里都有什么文章？列一下” -> 列出 3 篇论文，无非结构化 JSON 错误。
MT07-P39.6-03: Chat / SwiftLoop / “第一篇文章的蒸发率公式是什么？” -> 使用搜索/阅读工具并给出最终公式回答。
MT07-P39.6-04: Assistant / SwiftLoop / “项目里都有什么文章？” -> 可读非 JSON 回复显示为 AI 回复，不显示失败卡。
MT07-P39.6-05: LangGraph Sidecar ready / “你好” -> 正常 final response。
MT07-P39.6-06: LangGraph Sidecar unavailable / “你好” -> 快速 fallback SwiftLoop，有可见 fallback reason。
MT07-P39.6-07: Auto fallback / paper-reading prompt -> sidecar ready 与 unavailable 都有可见输出。
MT07-P39.6-08: 写入 todo/wiki prompt -> Permission Dock 出现，批准后继续或显示 inline failure。
MT07-P39.6-09: read-only search/read prompt -> 不显示审批 dock，只显示工具使用与最终回答。
MT07-P39.6-10: AI 回复气泡底部复制按钮 -> 复制 Markdown/plain text。
MT07-P39.6-11: 顶部运行范围菜单 -> “全工作区”与项目名不再被理解为两个 workspace。
MT07-P39.6-12: provider empty response fixture -> user message 与 failure run 持久化，可 retry。
```

阻塞验收的问题等级：

```text
S0: App crash；未经审批写 workspace；用户消息丢失；secret/debug bundle 泄漏。
S1: Chat 不能普通对话；provider schema 400；LangGraph/SwiftLoop 无可见输出；read-only 工具后无最终回答；论文内容问题答非所问。
S2: 复制按钮、范围文案、状态提示、工具使用说明等体验问题。
```

## 9. 交付记录

```text
完成日期：2026-05-07
Git commit：未提交
自动化测试结果：
- `get_errors` for edited Agent/App/Test files：PASS，无诊断
- `swift run SciStationCoreTestRunner`：PASS（2026-05-07）
- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests`：PASS，28 passed
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：PASS
手动测试报告：`docs/development/manual-tests/runs/2026-05-07_P39.6_AILabFullFlow.md`
下一任务书：`docs/development/Proposal39.7.md`
已知问题：真实 provider / GUI runtime 手动回归尚未在非交互环境执行；已转入 P39.7 live provider release gate。
推迟事项：P40 Workspace Creation Wizard、P41 Module Settings enable/disable UX。
```

## 10. Questions

1. P39.6 是否先冻结 P40，直到 Chat / SwiftLoop / LangGraph 三条 AI 主路径通过 MT07-P39.6？当前建议：是。
2. 对 provider empty response，是否允许 App 生成“模型空回复 + 最后工具结果摘要”的可见 fallback，而不是只显示错误？当前建议：是。
3. 对论文公式类问题，是否把“没有读取到 paper.md/没有命中公式”视为合格输出，只要它列出搜索路径和原因？当前建议：是。
4. 是否把 SwiftLoop 定为 release-blocking 最小可用 runtime，LangGraph 只在 sidecar health ready 时启用？当前建议：是。
5. P39.6 完成后是否单独做一次 AI Lab 真实模型录屏/截图手测，再进入 P40？当前建议：是。
