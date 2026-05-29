# 任务书 39.8：AI Lab 对话状态机、Run 生命周期与可恢复架构收口

更新时间：2026-05-07

完成状态：Implementation complete；SwiftPM、AgentRuntime pytest、Xcode build passed；GUI retry/approval click spot check 转入 P39.10/P39.11。

> P39.5 到 P39.7 已连续修复 thread/project 归属、provider schema、fallback、Permission Dock 与真实模型回归问题，但代码仍呈现“UI 状态、run 记录、session event、runtime pause、thread 归属”多套事实源并存。AI Lab 要变得完全可用，首先必须把对话生命周期收敛为一套可测试状态机：用户消息、流式回复、工具调用、审批、失败、重试、归档、切换 thread 都必须有同一套状态迁移和持久化语义。

## 1. 背景

本轮代码审阅发现的架构风险：

```text
1. `AppViewModel` 同时维护 `agentGoal`、`agentPendingUserPrompt`、`agentStreamingResponseText`、`agentCurrentRun`、`agentSessionEvents`、`agentRunHistory`、`activeAgentThreadID`，状态迁移分散在 UI action 中。
2. `AgentConversationTimelineView` 在有 session events 时只显示 events，否则才显示 runs，历史 run 与 event replay 不是同一个时间线模型。
3. `recordFailedRun` 能保存 user message 与 inline failure，但没有一等的 retry intent、failure category 或可恢复 checkpoint。
4. Conversation mode、Assistant mode、Plan mode 走不同路径：Swift tool loop、JSON planner、executeApprovedPlan 的状态语义不完全一致。
5. Permission Dock 当前依赖 `agentCurrentRun` 与全局 approval sets，审批状态不是明确的 timeline pending interaction。
6. Stop / cancel 主要落为 UI 状态和 failed run，尚未形成可审计的 cancelled/retryable 状态。
7. P39.7 原计划要求 provider empty/error run 暴露 runtime、provider/model、失败原因、最后工具摘要和可重试路径；该要求并入本任务书。
8. P39.7 原计划要求 Permission Dock 出现在对话时间线并在完成后消失；其生命周期状态并入本任务书，视觉设计细节转入 P39.10。
```

这些问题会导致用户看到“消息已发但不知道算不算保存”“工具审批后不知道 run 是否继续”“切换对话后旧状态泄漏或丢失”等体验。P39.8 专门修状态机，不扩大新 AI 能力。

## 2. 本轮目标

1. 定义 AI Lab canonical conversation state machine，覆盖 empty、draft、submitting、streaming、waitingApproval、failedRetryable、cancelled、completed、archived。
2. 让 thread timeline 以 session events / run events 为唯一展示事实源，run summary 只作为派生视图。
3. 将 retry 变成一等操作：失败 run 可以重试同一 prompt、保留原失败记录、新 run 与旧 run 可区分。
4. 统一 Chat / Assistant / Plan 的 run lifecycle metadata：mode、runtime、provider/model、context_scope、project_id、enabled tools、failure category、retry_of_run_id。
5. 让 Permission Dock 成为 timeline 中的 pending interaction，而不是独立依赖当前全局选择状态的浮动面板。
6. 建立状态迁移自动化测试和最小 GUI 手测矩阵。
7. 将 P39.7 的 provider failure diagnostics 和 retry/recovery polish 纳入状态机验收。

## 3. 实施任务

- [x] [P39.8.1] Conversation state model。
  - 新增或整理 `AgentConversationState` / `AgentRunLifecycleState`，明确 UI 可见状态与持久化状态。
  - 把 `isPlanningAgentRun`、`isExecutingAgentTools`、pending prompt、streaming response、current run pause reason 归并到可推导状态。
  - 定义状态迁移表：send、stream delta、tool call、approval required、approve、deny、cancel、provider failure、retry、archive、thread switch。

- [x] [P39.8.2] Timeline-first rendering。
  - `AgentConversationTimelineView` 不再在 events 与 runs 之间二选一；所有 run 都能生成 user/assistant/tool/approval/failure/cancelled timeline items。
  - 对没有 session events 的旧 run，提供 deterministic migration/projection，而不是回退成 run card。
  - 当前 streaming 内容作为 transient tail item，完成后必须落入 session event。

- [x] [P39.8.3] Retry as first-class action。
  - `AgentRun` metadata 增加 `retryOfRunID`、`failureCategory`、`retryablePrompt` 或等价结构。
  - 失败气泡底部提供“重试”动作，重试时复制原 prompt、原 context、runtime selector、enabled tool snapshot。
  - retry 后旧 run 保留，timeline 显示“从 run X 重试”，新 run 独立记录。
  - 吸收 P39.7：provider empty response、HTTP error、malformed response 都必须能进入 retryable failure card。

- [x] [P39.8.4] Cancel / stop durability。
  - Stop 后必须持久化 `run_cancelled` 或 failed/cancelled event，保留 user message 与 partial assistant response。
  - 如果用户尚未发送，仅停止 streaming 不应丢 composer draft。
  - CancellationError 与 provider failure 分开显示，避免“停止”被误判为系统错误。

- [x] [P39.8.5] Pending approval persistence。
  - Permission Dock 的 pending approval 来自 `AgentPendingToolCall` / runtime event，而不是只从 `agentCurrentRun.plan.toolCalls` 派生。
  - 切换 thread 后 pending approval 不泄漏到其它 thread；回到原 thread 可继续 approve/deny。
  - 审批完成、拒绝或 run 失败后 pending dock 自动消失，但保留审计事件。
  - 吸收 P39.7：Permission Dock 不再固定在 composer 上方，状态来源必须是当前 conversation pending interaction。

- [x] [P39.8.6] Mode parity contract。
  - Chat / Assistant / Plan 都必须写入相同基础 run metadata 和 session events。
  - 同一个 prompt 在不同 mode 下可以策略不同，但失败、retry、thread attach、event replay 规则一致。
  - 明确 Conversation mode 是否允许写工具 pause/resume；若允许，文案和状态必须与 Plan mode 一致。

- [x] [P39.8.7] State-machine regression suite。
  - Swift CoreTestRunner 增加 send -> provider failure -> retry、send -> approval -> approve -> completed、send -> cancel、thread switch with pending approval。
  - 手动测试覆盖 thread A/B 切换、归档、重启 App 后 replay、retry 失败 run。

## 4. 非目标

```text
不重写 provider 或 LangGraph runtime。
不新增工具能力。
不做完整视觉重设计；P39.10 负责 UI 规范与渲染。
不取消写入审批。
不进入 P40 Workspace Creation Wizard。
```

## 5. 验收标准

1. 任何发送过的用户消息，在成功、失败、取消、切换 thread、重启 App 后都可在 timeline 复查。
2. 失败 run 有明确 failure category、inline message 和重试入口；重试不覆盖旧 run。
3. Stop / Cancel 不显示为普通 provider 错误，不丢 partial assistant response。
4. Pending approval 属于当前 thread timeline；切换到其它 thread 不显示旧审批 dock。
5. Chat / Assistant / Plan 的 run metadata 字段完整一致。
6. 旧 run 即使缺少 session events，也能投影为可读 timeline。
7. SwiftPM CoreTestRunner、AgentRuntime pytest、Xcode build 通过，或交付记录写明环境阻塞。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

新增手测：

```text
MT07-P39.8-01: 发送后 provider failure -> user message、failure、retry 持久化
MT07-P39.8-02: 点击 retry -> 新 run 创建，旧 failed run 保留
MT07-P39.8-03: read-only 工具后 provider empty -> timeline 有工具摘要、fallback、retry
MT07-P39.8-04: write tool -> pending approval -> 切换 thread -> 不泄漏 dock -> 回原 thread 可继续审批
MT07-P39.8-05: Stop streaming -> cancelled event 与 partial response 可见
MT07-P39.8-06: 重启 App -> active thread timeline 完整恢复
MT07-P39.8-07: Archived thread 只读 replay，不显示可执行 pending dock
```

## 7. 交付记录

```text
完成日期：2026-05-07
Git commit：未提交
自动化测试结果：
- `swift run SciStationCoreTestRunner`：PASS
- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests`：PASS，28 passed
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：PASS
手动测试报告：docs/development/manual-tests/runs/2026-05-07_P39.8_AILabStateMachine.md
剩余风险：GUI retry button、Permission Dock approve/deny click、thread switch with live pending approval 仍需交互式 App spot check；视觉重构转入 P39.10，live provider/runtime gate 转入 P39.11。
是否允许进入 P39.9：允许。
```
