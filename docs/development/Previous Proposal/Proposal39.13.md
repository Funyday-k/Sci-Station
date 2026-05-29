# 任务书 39.13：AI Lab 归档线程、第三篇论文路由与 Debug 模式收口

更新时间：2026-05-07
状态：Implemented / Automation Passed / Manual UI Pending
优先级：S1 / Release Candidate Hardening
承接：P39.12 修复 AI Lab provider 提前终止、Figure 2 图注读取、source health、paper.md health、诊断脱敏和 release gate 文档；本轮根据 ResearchWorkspace 日志和用户截图反馈继续收口。

---

## 1. 背景

P39.12 已把“AI 为什么提前终止”和“图 2 读不到”的主要路径收口到代码层：DeepSeek thinking-mode replay、context/tool budget fallback、figure caption read fallback、balanced JSON plan parsing，以及 AI Lab / Library 的可操作 health UI。

用户在 ResearchWorkspace 继续反馈三个 release-blocking 问题：归档所有对话后主面板仍显示已归档内容；“第三篇文章”未正确定位到第三篇，而是复用了 selected source；`read_paper_section` 同时收到 heading 和 line range 时返回文档开头；同时需要一个 Debug 模式，在打开后把软件中的操作、输入和输出写入本地日志，便于下一轮定位 provider JSON parse / chunks=0 问题。

---

## 2. 本轮目标

1. 修复 archived thread 不能从选择、open run、fallback history 或 pinned state 复活为当前对话。
2. 修复论文序数 intent：支持 `第三篇` / `第 3 篇` / `third paper` 等 1-10 序数，并从 retrieval query 中移除序数噪声。
3. 修复 `read_paper_section` 参数优先级：当 heading 非空时优先读取 heading section，line range 只作为无 heading 时的显式 fallback。
4. 新增 workspace-local Debug mode：开关持久化到 `settings/workspace_preferences.yaml`，日志写入 `.sci-station/debug/app_events.jsonl`，记录 AI Lab 操作、输入、输出、工具结果和错误，并复用 redaction contract。
5. 补充核心自动化测试和 AI Lab 手动测试范围。

---

## 3. 实施任务

### [P39.13.1] ResearchWorkspace log diagnosis

- 读取 `/Users/funyday/Documents/ResearchWorkspace/.sci-station/agent/session_events.jsonl`、`runs.jsonl`、`drafts.json`。
- 确认 `chunks=0` / deterministic fallback / selected source / provider JSON parse failure 的真实日志链路。
- 确认 `.sci-station/index/embeddings/manifest.json` 缺失，作为 P39.14 index/retrieval follow-up。

### [P39.13.2] Archived thread hardening

- `selectAgentThread(_:)` 阻止 archived thread 成为 active thread。
- `openAgentRun(_:)` 只绑定 non-archived thread；archived-only run 不复活主会话。
- `agentConversationRuns` 在没有 active thread 时只展示 orphan runs，避免 archived thread runs 通过 project fallback 重现。
- pinned thread restore 只保留当前可见 non-archived thread。
- archived thread drafts 不恢复到 composer。

### [P39.13.3] Third-paper and section read routing

- `AgentPaperIntentRouter` 支持中文数字、阿拉伯数字、英文序数 1-10。
- `searchQuery` 移除 `第三篇文章` / `third paper` 等序数片段，避免污染 retrieval query。
- `ReadPaperSectionAgentTool` 改为 heading 优先，只有 heading 缺失时才按 `start_line/end_line` 读取。

### [P39.13.4] Debug mode logging

- `WorkspacePreferences.agentDebugLoggingEnabled` 持久化到 workspace preferences。
- 新增 `AppDebugEventLogger`，写入 `.sci-station/debug/app_events.jsonl`。
- Debug mode 记录 prompt submit、run output、tool results、fail/cancel、thread select/archive/open、runtime/context 变化。
- UI 在 AI Lab 和 Settings 中提供 Debug mode toggle 与 Logs 打开入口。
- 日志 payload 复用 `AgentRunDirectoryStore.redactedDebugPayload`，避免 API key、token、secret 和完整本机路径进入日志。

### [P39.13.5] Validation

- `swift run SciStationCoreTestRunner`：PASS。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：PASS。
- `docs/development/manual-tests/MT07_AILab.md` 已增加 P39.13 手动测试范围。

---

## 4. 验收标准

1. 归档所有对话后 AI Lab 不再显示 archived thread 的历史内容或草稿。
2. “第三篇文章/third paper/第 3 篇论文”能解析为 ordinal index 2，并限制到 resolved paper id。
3. `read_paper_section` 同时收到 heading 和 line range 时返回 heading section。
4. Debug mode 打开后生成 `.sci-station/debug/app_events.jsonl`，包含输入、输出、工具结果和操作事件，且敏感信息脱敏。
5. 核心自动化测试覆盖新增行为并通过。

---

## 5. Questions

1. P39.14 是否优先修复 `chunks=0` / embedding manifest 缺失，让 selected source rebuild 后有强制可见结果？
2. Provider JSON parse failure 是否需要进入 deterministic writeback fallback，而不是只显示 provider_error？
3. Debug mode 是否需要扩大到 Library / Wiki / Tasks 的所有非 AI 操作，还是先以 AI Lab release gate 为准？
4. Chat 本地图片渲染策略是否继续放到 P39.14 处理？