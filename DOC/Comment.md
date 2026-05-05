下面给出两部分内容：

1. **基于 P33 已完成状态，对 P34 的修改意见。**
2. **起草 P35 任务书。**

总体判断：**P33 已经把 P34 dependency gate 做实了，P34 现在可以从“设计 sidecar”进入“实现 sidecar MVP”。但 P34 仍建议再做一次范围收敛：P34 专注 fake sidecar、stdio JSON-RPC、真实 sidecar handshake、LLMProxy、read-only Gateway、FTS evidence 与单篇论文精读；把 related work / gap planning 的 production 化、embedding、citation critic、代码 sandbox、正式 Python bundle 全部放到 P35 或之后。** P33 完成记录已经明确 event envelope、schema migration、run directory、persistent ledger、ToolHost、MCP Gateway、deterministic safety policy 与 Skill loader core 均已落地，并且 SwiftPM 与 Xcode build 均通过 [1]。P34 启动记录也确认 P33 dependency gate 已通过，下一步应按 fake sidecar、stdio JSON-RPC、Python package skeleton、LLMProxy/MCP read-only tools、FTS 与单篇论文精读推进 [2]。

---

# 一、对 P34 的修改意见

## 1. P34 现在应该改成“执行型任务书”，不要再保留过多讨论性内容

P34 已经写得比较成熟，但现在 P33 已完成，P34 的开头可以从“若 P33 gate 通过”改成“P33 gate 已通过”。目前 P34 已经在 P34.0 标记 P33 dependency gate 完成，并说明不需要兼容 P32 legacy pending 文件 [2]。建议进一步把 P34 的主线压成：

```text
P34-M1: Fake sidecar + stdio JSON-RPC harness
P34-M2: Real sidecar initialize/health + lifecycle events
P34-M3: Swift LLMProxy + Gateway read-only tools
P34-M4: FTS index + AgentEvidenceRef bridge
P34-M5: 单篇论文精读 workflow
```

P34 不应再试图在同一轮里把 related work 与 gap planning 做成 production graph。P34 现在已写明 related work / gap planning 可先用 sample/fake/beta graph，不阻塞 MVP [2]。这个判断应该保留并强化。

---

## 2. P34.0a fake sidecar 应增加“协议 golden fixtures”验收

P34 已要求 fake sidecar 使用 JSON fixture 文件驱动事件序列，避免测试逻辑写死在 Python 代码里 [2]。建议再补一条：

```text
Fake sidecar fixtures 同时作为协议 golden fixtures。
Swift 侧解析后应生成稳定的 AgentRuntimeEventEnvelope 序列快照。
```

建议新增测试：

```text
langGraphRuntimeReplaysGoldenFixtureRunSuccess
langGraphRuntimeReplaysGoldenFixtureApprovalResume
langGraphRuntimeRejectsInvalidFixtureSchemaVersion
langGraphRuntimeCanonicalizesSidecarLocalSequence
```

理由：P33 已经固定 runtime event 使用 `event.type + event.payload` wire-format，并且 Swift Host 是 sequence owner [1]。P34 fake sidecar 现在正好应该把这个协议固化成回归测试。

---

## 3. P34.2 需要明确 JSON-RPC request/response correlation 与并发模型

P34 已要求 stdio JSON-RPC 支持双向调用，Swift 到 sidecar 包括 `sidecar.initialize/health` 与 `agent.start/resume/cancel/checkpoint`，sidecar 到 Swift 包括 `runtime.event/tools.list/tools.call/resources.read/llm.respond` 等 [2]。但还应补充：

```text
所有 JSON-RPC request 必须有唯一 id。
response 必须按 id correlation，不依赖返回顺序。
stdio transport 支持 interleaved request/response/event。
runtime.event 可以作为 notification 或 request，但必须明确 ack 语义。
```

建议 MVP 简化为：

```text
- runtime.event 使用 JSON-RPC notification，无需 sidecar 等待 ack。
- tools.call / resources.read / llm.respond 使用 JSON-RPC request-response。
- agent.start 返回 accepted 后，后续进度通过 runtime.event notification 推送。
```

否则后面 sidecar 一边等 `llm.respond`，一边发 event，很容易出现 stdio transport 死锁或顺序假设错误。

---

## 4. P34.3 建议新增 sidecar supervisor，而不是把 Process 管理塞进 Runtime 本体

P34 计划新增 `LangGraphAgentRuntime.swift`，用 `Process` 启动 Python sidecar [2]。建议拆成两个 Swift 类型：

```swift
public actor SidecarProcessSupervisor {
    func start() async throws -> SidecarConnection
    func stop() async
    func restart() async throws -> SidecarConnection
    func health() async -> SidecarHealth
}

public actor LangGraphAgentRuntime: ExternalAgentRuntime {
    private let supervisor: SidecarProcessSupervisor
}
```

这样好处是：

- `LangGraphAgentRuntime` 专注 runtime 协议。
- `SidecarProcessSupervisor` 专注 Python 路径、环境变量、stderr 收集、崩溃检测、超时、重启。
- P35 如果做 packaging / bundle Python，不会污染 runtime 逻辑。

P34 可以先做最小 supervisor，但应该在任务书里规定边界。

---

## 5. P34.4 LLMProxy 需要加入 redaction 与 usage 落库策略

P34 已要求 sidecar 不持有 API key，所有模型调用通过 Swift LLMProxy，且 `llm.respond` 显式携带 `toolCallPolicy`，默认 `disabled` [2]。建议再补：

```text
LLMProxy request/response 落盘前必须走 P33 AgentRedactionPolicy。
usage 可以落 events/debug，但 prompt/response 默认不落盘。
llm.respond 的 modelOptions 只能包含非敏感字段，不得传 API key、credential ref 原文。
```

P34 已规定 debug prompts/responses 默认不写盘，显式开启后也必须 redacted，并复用 P33 redaction policy [2]。这条应该扩展到 LLMProxy 的 request/response event。

---

## 6. P34.5 FTS index 建议增加“只读资源读取限额与截断策略”

P34 已规定 Python 默认不接收真实 file URL，而是通过 `resources/list_indexable_documents` 与 `resources/read` 获取内容；`chunks.sqlite` writer 是 sidecar，Swift 提供授权文档清单、资源读取与 write lock 协调 [2]。建议新增：

```text
resources/read 必须支持 maxBytes / maxCharacters。
单个文档超限时返回 truncated 标记或分片读取。
FTS chunker 只索引允许的文本类型与大小范围。
```

建议 schema：

```json
{
  "resource_id": "paper:demo:paper.md",
  "maxBytes": 1048576,
  "range": null
}
```

返回：

```json
{
  "resource_id": "paper:demo:paper.md",
  "content": "...",
  "content_hash": "sha256:...",
  "truncated": false,
  "encoding": "utf-8"
}
```

原因：Materials 可能包含大文件、数据文件或生成输出，P34 如果不加读取限额，sidecar FTS 建索引可能拖垮 UI。

---

## 7. P34.6 Evidence bridge 应明确 evidence id 的稳定生成规则

P34 已要求 stable tool result JSON、FTS retriever、artifact draft 与 final Wiki citation block 通过同一 `AgentEvidenceRef` 串联 [2]。建议补：

```text
AgentEvidenceRef.id = sha256(source_type + source_id + relative_path + start_line + end_line + source_hash)
```

或者：

```text
chunk_id 作为 evidence ref 主键，claim-evidence 关系另有 edge id。
```

并明确：

```text
同一个 run 内 evidence id 必须稳定。
source_hash 变化后 evidence 视为 stale。
artifact draft 只能引用当前 evidence table 中存在的 evidence id。
```

这会让 UI 可以从 Wiki 草稿跳回论文段落。

---

## 8. P34.7 单篇论文精读 workflow 建议增加“无 paper.md 时的降级路径”

当前仓库支持 PDF 导入后生成 `paper.md`，但实际使用中有些 paper.md 可能为空、未 OCR、未转换或只有模板。P34 单篇精读依赖 `paper.md`、annotations、FTS chunk [2]。建议加降级：

```text
如果 paper.md 不存在或内容过短:
- 读取 meta.yaml / abstract / annotations.md。
- 如果有 PDF 但无 Markdown，返回 artifactDraft 说明需要先转换/OCR，不做无来源总结。
- 可生成 todo draft: “Convert/OCR paper to markdown”。
```

这对科研平台很重要，避免 agent 在没有证据时胡写精读笔记。

---

## 9. P34 验收标准建议拆成“强制验收”和“可选验收”

当前 P34 验收标准较多，共 14 条 [2]。建议拆分：

### 强制验收

```text
1. Fake sidecar fixtures 通过。
2. LangGraphAgentRuntime 可启动 fake sidecar 并解析 event envelope。
3. Real sidecar initialize/health 通过，失败可 fallback。
4. LLMProxy 可完成一次 redacted llm.respond。
5. Gateway read-only tools 可从 sidecar 调用。
6. FTS index 可通过 Swift resources 快照建立并检索 line range/source_hash/chunk_id。
7. 单篇论文精读生成 artifact draft + evidenceRefs。
8. Approval 写入仍由 Swift ToolHost/Repository 执行，sidecar 不写 workspace。
```

### 可选或 beta 验收

```text
related work beta
gap planning beta
ToolCallingNode provider-native toolCalls
真实 LangGraph graph 完整 crash resume
Python packaging
```

这样开发时不会被非 MVP 项拖慢。

---

## 10. P34 完成后应该为 P35 留出明确接口

P34 完成时应输出：

```text
- AgentRuntime/ Python package skeleton
- fake sidecar fixtures
- stdio JSON-RPC transport
- LangGraphAgentRuntime + SidecarProcessSupervisor
- LLMProxy bridge
- SciStationGatewayClient
- FTS index V1
- AgentEvidenceRef bridge
- paper_reading graph
```

这些正好成为 P35 的输入。P35 不应该再重写 sidecar 基础设施，而应该在 P34 之上做 workflow production 化与检索增强。

---

# 二、任务书 35 草案

下面是建议的 P35 任务书内容。

---

# 任务书 35：Research Workflow Production、Citation Critic、Embedding RAG 与 Sidecar 产品化

更新时间：2026-05-05

> 本任务书承接任务书 34。P34 已完成 fake sidecar、真实 sidecar handshake、Swift LLMProxy、Gateway read-only tools、FTS evidence index V1 与单篇论文精读 workflow MVP 后，P35 的目标不是继续扩基础协议，而是把科研 workflow 从 MVP 推向可长期使用：增强 retrieval，生产化 related work / gap planning，引入 citation critic，改善 evidence UI 与 sidecar 运行体验，并为后续 code sandbox / embedding / multi-agent 打基础。

---

## 1. 背景

完成 P33 后，Sci-Station 已经具备长期 agent 协议边界：

```text
AI Lab UI
  -> ExternalAgentRuntime
  -> LegacySwiftAgentRuntime / LangGraphAgentRuntime
  -> SciStationToolHost / AgentMCPGateway
  -> Swift Permission Layer
  -> Repository / Local Research Root
```

P33 已完成 P32 provisional schema migration、runtime event envelope、run directory、persistent ledger、ToolHost、MCP Gateway、deterministic safety policy 与 Skill loader core，并通过 SwiftPM 与 Xcode 验证 [1]。

P34 将在此基础上完成 sidecar MVP：

```text
fake sidecar
stdio JSON-RPC
real sidecar initialize/health
Swift LLMProxy
Gateway read-only tools
FTS evidence index V1
AgentEvidenceRef bridge
single-paper reading workflow
```

P35 的重点是把“能跑”变成“对科研真正有用、可审计、可恢复、可迭代”。

---

## 2. 本轮目标

1. 将 P34 的单篇论文精读 workflow 产品化，支持更稳定的结构化笔记、证据跳转、todo 草稿与 Wiki 写入审批。
2. 将 related work 和 gap planning 从 sample/beta graph 提升为 production workflow。
3. 新增 citation critic / evidence critic 节点，检查 claim 是否有 evidence、引用是否过期、证据是否支持结论。
4. 在 FTS V1 基础上加入可选 embedding retrieval V1，但保留 FTS-only fallback。
5. 改善 evidence UI：artifact draft、Wiki citation block、source jump、stale evidence warning。
6. 完善 sidecar crash recovery、run replay、debug bundle 与用户可读错误提示。
7. 产品化 sidecar runtime selector、health panel 与 fallback 策略。
8. 不做 shell/python code execution，不做完整 sandbox，不让 sidecar 获得 workspace 写权限。

---

## 3. 实施任务

### [P35.1] 单篇论文精读 workflow 产品化

- 在 P34 paper reading graph 基础上增强节点：

```text
load_paper_context
retrieve_sections
extract_contributions
extract_methods
extract_experiments
extract_limitations
extract_open_questions
draft_structured_note
critic_check_evidence
approval
```

- 输出结构固定为：

```text
# Paper Note

## TL;DR
## Contributions
## Method
## Experiments
## Limitations
## Open Questions
## Relevance to Current Project
## Follow-up Todos
## Evidence
```

- 最低要求：
  - contributions 至少 3 条 evidence-backed claim。
  - methods 至少 2 条 evidence-backed claim。
  - limitations 至少 2 条，可 low confidence，但必须说明来源。
  - 每条 evidence 可跳转到 `relative_path + line range`。
  - 无 `paper.md` 或证据不足时，不生成伪精读，只生成“需要转换/OCR/补全文本”的任务草稿。

---

### [P35.2] Related work workflow production

- 将 P34 的 related work beta graph 升级为 production graph。
- 节点：

```text
load_project_overview
list_core_papers
retrieve_candidate_evidence
cluster_by_theme
build_evidence_matrix
draft_related_work_sections
citation_critic
style_rewrite
approval
```

- 草稿产物：

```text
projects/{project-id}/wiki/related_work.md
.sci-station/agent/runs/{run_id}/evidence.json
```

- 输出结构：

```text
# Related Work

## Scope
## Theme 1
## Theme 2
## Theme 3
## Comparison Table
## Research Gap Summary
## Evidence Matrix
```

- 验收：
  - 至少按主题聚类，而不是按论文逐篇罗列。
  - 每个主题至少 2 个 evidence-backed claims。
  - citation critic 能发现无证据段落，并要求 graph 重写或降级置信度。
  - 写入前必须通过 Swift Permission Dock。
  - sidecar 不直接写 `related_work.md`。

---

### [P35.3] Research gap / task planning workflow production

- 将 P34 的 gap planning beta graph 升级为 production graph。
- 节点：

```text
load_project_context
load_core_papers
load_existing_tasks
retrieve_gap_evidence
synthesize_research_gaps
propose_hypotheses
propose_experiments
generate_todo_drafts
critic_check_actionability
approval
```

- 草稿产物：

```text
projects/{project-id}/wiki/research_plan.md
todo drafts
```

- 输出结构：

```text
# Research Plan

## Current Context
## Candidate Gaps
## Hypotheses
## Proposed Experiments
## Milestones
## Todo Drafts
## Evidence
```

- 验收：
  - gap 必须区分 evidence-backed gap、inferred gap、user-assumption。
  - todo draft 必须含 priority、related paper/project、reason、optional due date。
  - 不自动创建 todo，必须经 Swift approval。
  - 如果现有 tasks 已有相同目标，必须提示可能重复。

---

### [P35.4] Citation Critic / Evidence Critic

新增通用 critic 子图：

```text
input: draft_artifact + evidence_table
output: critic_report + revised_draft 或 approval_blocker
```

检查项：

1. 每个科研 claim 是否有 evidence。
2. evidence 是否来自允许 source。
3. evidence line range 是否存在。
4. source_hash 是否与当前文件一致。
5. quote 是否过长。
6. claim 是否过度推断。
7. 同一 evidence 是否被滥用支持多个不相关 claim。
8. 是否存在 unsupported superlative，如 “best”、“significantly”、“state-of-the-art”。

输出：

```json
{
  "unsupported_claims": [],
  "stale_evidence": [],
  "weak_evidence": [],
  "overclaims": [],
  "required_revisions": [],
  "can_request_approval": true
}
```

验收：

- 如果 artifact 中存在无 evidence 的核心 claim，不能直接进入 final approval。
- 用户可以选择“仍然保存为 low confidence draft”，但 UI 必须显示 warning。
- critic report 写入 run directory。

---

### [P35.5] Embedding retrieval V1，可选启用

在 FTS V1 基础上新增 embedding 检索，但必须保留 FTS-only fallback。

支持配置：

```text
embedding.enabled
embedding.provider
embedding.model
embedding.dimension
embedding.store = sqlite-vec | lancedb | qdrant-local
```

MVP 推荐：

```text
sqlite-vec 或 LanceDB local
```

边界：

- embedding API key 仍由 Swift Keychain / LLMProxy 管理。
- sidecar 不持有 embedding API key。
- embedding request 走 Swift `embedding.respond` 或 `embedding.embed` proxy。
- embedding index 只索引 Swift 授权快照。
- 未配置 embedding 时 workflow 继续使用 FTS。

混合检索策略：

```text
candidate = FTS topK + embedding topK
rerank by metadata/project/paper/core tags
dedupe by chunk_id
return evidence refs
```

验收：

- FTS-only 与 embedding-enabled 两种路径均通过测试。
- embedding index schema version 可迁移。
- source_hash 变化后 embedding chunk 标记 stale 或重建。

---

### [P35.6] Evidence UI 与 source jump

增强 AI Lab / Wiki / artifact preview：

- Artifact draft 中 evidenceRefs 可展开。
- 点击 evidence 跳转到：
  - paper.md line range；
  - wiki page line range；
  - annotations.md；
  - 如果源是 PDF 且有页码映射，则跳转 PDF Reader 页。
- 显示：
  - source title；
  - relative path；
  - heading；
  - line range；
  - confidence；
  - stale / missing warning。
- Wiki citation block 可折叠。
- 保存 artifact 后保留 evidence metadata。

验收：

- 单篇论文精读 artifact 中点击 evidence 可定位到源文本。
- source_hash 变化后 UI 显示 stale evidence。
- 不存在的 source 显示 missing source warning，而不是崩溃。

---

### [P35.7] Sidecar run replay 与 debug bundle

新增 run replay 能力：

```text
.sci-station/agent/runs/{run_id}/
├── replay.json
├── critic_report.json
├── retrieval_trace.json
└── debug_bundle.zip 可选生成
```

要求：

- 默认不保存 prompt/response 明文。
- 用户显式开启 debug 后保存 redacted prompt/response。
- debug bundle 不包含 API key、private path、`.env`、Keychain 内容。
- run replay 可重新渲染 timeline，不一定重新调用模型。

验收：

- 已完成 run 可在 AI Lab 重新打开并重放 timeline。
- sidecar crash 后可查看最后成功 checkpoint。
- debug bundle 生成前显示包含文件清单与隐私提示。

---

### [P35.8] Sidecar Runtime UI 产品化

新增或增强 Settings / AI Lab runtime panel：

- Runtime selector：
  - Swift Loop
  - LangGraph Sidecar
  - Auto fallback
- Health status：
  - Python version
  - sidecar version
  - protocol/schema version
  - dependency check
  - last crash
  - fallback reason
- Controls：
  - Restart sidecar
  - Open run directory
  - Export debug bundle
  - Disable sidecar for this workspace

验收：

- sidecar unavailable 时用户能看到明确原因。
- fallback 到 Legacy Swift runtime 时 UI 明确提示，不静默降级。
- runtime selector 不影响已完成 run 的回放。

---

### [P35.9] Tests

#### Swift CoreTestRunner

新增：

```text
paperReadingWorkflowProducesEvidenceBackedDraft
relatedWorkWorkflowClustersByTheme
gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting
citationCriticBlocksUnsupportedClaims
evidenceRefsJumpToSourceLineRange
sidecarRuntimeSelectorPersistsAndFallbacks
runReplayLoadsTimelineFromRunDirectory
embeddingFallbackUsesFTSWhenDisabled
```

#### Python tests

新增：

```text
test_paper_reading_graph_evidence_minimums
test_related_work_theme_clustering
test_gap_planning_todo_schema
test_citation_critic_blocks_unsupported_claim
test_hybrid_retriever_dedupes_chunk_ids
test_stale_evidence_detection
test_run_replay_redaction
```

#### Fixture tests

- 使用 P34 fake sidecar fixtures。
- 新增 sample workspace：
  - 3 篇 paper.md；
  - 1 个 project；
  - project core papers；
  - wiki/project overview；
  - existing todos。

---

### [P35.10] 验证与交付记录

必须运行：

```bash
swift run SciStationCoreTestRunner
python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

手动验证：

1. 单篇论文精读生成 evidence-backed note。
2. Related work 生成主题聚类草稿。
3. Gap planning 生成 research plan 与 todo drafts。
4. Citation critic 能阻断无证据 claim。
5. Evidence UI 可以跳转源文本。
6. Sidecar crash 后可 fallback 或恢复。
7. Debug bundle 不含敏感信息。

---

## 4. 非目标

- 不做 shell/python/code execution sandbox。
- 不让 sidecar 获得 workspace 写权限。
- 不让 sidecar 直接读取 Keychain 或持有 API key。
- 不发布 plugin marketplace。
- 不要求 embedding 默认开启。
- 不做完整多 agent 自主协作。
- 不做远程 MCP OAuth。
- 不做云端同步。

---

## 5. 验收标准

1. 单篇论文精读 workflow 达到 production 质量，生成结构化 note、evidenceRefs、todo drafts，并通过 citation critic。
2. Related work workflow 能基于 project core papers 生成主题化 related work 草稿，并包含 evidence matrix。
3. Gap planning workflow 能生成 evidence-backed gaps、hypotheses、experiment proposals 与 todo drafts。
4. Citation critic 能阻断或标记 unsupported / stale / weak evidence claims。
5. Embedding retrieval V1 可选启用；未启用时 FTS-only fallback 正常。
6. Evidence UI 能从 artifact draft 跳转到源文件 line range。
7. Sidecar run replay 可重放 timeline。
8. Sidecar runtime panel 能显示 health、fallback reason、restart/export controls。
9. 所有 workspace 写入仍必须经 Swift Permission Dock，由 Swift ToolHost/Repository 执行。
10. SwiftPM、Python tests、Xcode build 均通过。

---

## 6. 建议执行顺序

```text
P35-A: Citation Critic / Evidence Critic
P35-B: Paper Reading workflow 产品化
P35-C: Evidence UI/source jump
P35-D: Related Work production graph
P35-E: Gap Planning production graph
P35-F: Run replay/debug bundle
P35-G: Runtime UI 产品化
P35-H: Embedding retrieval V1
```

其中 P35-A 到 P35-C 是最优先的，因为它们直接提升 P34 的单篇论文精读质量。Embedding 可以靠后，不要阻塞 workflow production。

---

# 三、最终建议

我建议你对 P34 做一次小修改后就进入执行：

```text
1. 把 P34 明确改成执行型任务书：P33 gate 已通过，不再讨论兼容 P32 legacy。
2. 强化 fake sidecar golden fixtures。
3. 明确 JSON-RPC correlation、notification/request-response 语义。
4. 增加 SidecarProcessSupervisor。
5. 为 resources/read 增加读取限额与截断策略。
6. 为 AgentEvidenceRef 增加稳定 id 与 stale 判断。
7. 为单篇论文精读增加 paper.md 缺失/过短降级路径。
8. 将验收拆成强制 MVP 与 beta 项。
```

P35 则建议定位为：

> **把 P34 的 sidecar MVP 变成真正可用于科研写作与项目规划的 production agent workflow：citation critic、related work、gap planning、evidence UI、run replay、runtime panel 与可选 embedding。**