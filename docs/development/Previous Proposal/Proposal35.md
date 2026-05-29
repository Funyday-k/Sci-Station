# 任务书 35：Research Workflow Production、Citation Critic、Embedding RAG 与 Sidecar 产品化

更新时间：2026-05-05

> 本任务书承接任务书 34。P34 完成 fake sidecar、stdio JSON-RPC、真实 sidecar handshake、Swift LLMProxy、Gateway read-only tools、FTS evidence index V1 与单篇论文精读 workflow MVP 后，P35 的目标不是继续扩基础协议，而是把科研 workflow 从 MVP 推向可长期使用：增强 retrieval，生产化 related work / gap planning，引入 citation critic，改善 evidence UI 与 sidecar 运行体验，并为后续 code sandbox / embedding / multi-agent 打基础。

## 1. 背景

完成任务书 33 后，Sci-Station 已经具备长期 agent 协议边界：

```text
AI Lab UI
  -> ExternalAgentRuntime
  -> LegacySwiftAgentRuntime / LangGraphAgentRuntime
  -> SciStationToolHost / AgentMCPGateway
  -> Swift Permission Layer
  -> Repository / Local Research Root
```

任务书 34 已在此基础上完成 sidecar MVP：

```text
fake sidecar
stdio JSON-RPC
real sidecar initialize / health
Swift LLMProxy
Gateway read-only tools
FTS evidence index V1
AgentEvidenceRef bridge
single-paper reading workflow
```

P35 的重点是把“能跑”变成“对科研真正有用、可审计、可恢复、可迭代”。P34 gate 已通过：`swift run SciStationCoreTestRunner`、`python -m pytest AgentRuntime/tests` 与 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 均已完成验证。

## 2. 本轮目标

1. 将 P34 的单篇论文精读 workflow 产品化，支持更稳定的结构化笔记、证据跳转、todo 草稿与 Wiki 写入审批。
2. 将 related work 和 gap planning 从 sample/beta graph 提升为 production workflow。
3. 新增 citation critic / evidence critic 节点，检查 claim 是否有 evidence、引用是否过期、证据是否支持结论。
4. 在 FTS V1 基础上加入可选 embedding retrieval V1，但保留 FTS-only fallback。
5. 改善 evidence UI：artifact draft、Wiki citation block、source jump、stale evidence warning。
6. 完善 sidecar crash recovery、run replay、debug bundle 与用户可读错误提示。
7. 产品化 sidecar runtime selector、health panel 与 fallback 策略。
8. 不做 shell/python/code execution，不做完整 sandbox，不让 sidecar 获得 workspace 写权限。

## 3. 实施任务

- [x] [P35.0] P34 completion gate。
  - 确认 P34 强制 MVP 验收均已完成：fake sidecar golden fixtures、real sidecar initialize/health、Swift LLMProxy、Gateway read-only tools、FTS V1、AgentEvidenceRef bridge、单篇论文精读 MVP。
  - 确认 P34 输出资产存在：`AgentRuntime/` skeleton、stdio JSON-RPC transport、`LangGraphAgentRuntime`、`SidecarProcessSupervisor`、`SciStationGatewayClient`、FTS index V1、`paper_reading` graph MVP。
  - 若 P34 缺项，优先补齐 P34 gate，不在 P35 中重写基础协议。

- [x] [P35.1] 单篇论文精读 workflow 产品化。
  - 在 P34 `paper_reading` graph 基础上增强节点：

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

  - 最低要求：contributions 至少 3 条 evidence-backed claim；methods 至少 2 条 evidence-backed claim；limitations 至少 2 条，可 low confidence，但必须说明来源。
  - 每条 evidence 必须可跳转到 `relative_path + line range`。
  - 无 `paper.md` 或证据不足时，不生成伪精读，只生成“需要转换/OCR/补全文本”的任务草稿。

- [x] [P35.2] Related work workflow production。
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

  - 验收：至少按主题聚类，而不是按论文逐篇罗列；每个主题至少 2 个 evidence-backed claims。
  - citation critic 能发现无证据段落，并要求 graph 重写或降级置信度。
  - 写入前必须通过 Swift Permission Dock；sidecar 不直接写 `related_work.md`。

- [x] [P35.3] Research gap / task planning workflow production。
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

  - gap 必须区分 evidence-backed gap、inferred gap、user-assumption。
  - todo draft 必须含 priority、related paper/project、reason、optional due date。
  - 不自动创建 todo，必须经 Swift approval；如果现有 tasks 已有相同目标，必须提示可能重复。

- [x] [P35.4] Citation Critic / Evidence Critic。
  - 新增通用 critic 子图：

```text
input: draft_artifact + evidence_table
output: critic_report + revised_draft 或 approval_blocker
```

  - 检查每个科研 claim 是否有 evidence、evidence 是否来自允许 source、line range 是否存在、source_hash 是否与当前文件一致、quote 是否过长、claim 是否过度推断、同一 evidence 是否被滥用支持多个不相关 claim。
  - 检查 unsupported superlative，例如 `best`、`significantly`、`state-of-the-art`。
  - 输出：

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

  - 如果 artifact 中存在无 evidence 的核心 claim，不能直接进入 final approval。
  - 用户可以选择“仍然保存为 low confidence draft”，但 UI 必须显示 warning。
  - critic report 写入 run directory。

- [x] [P35.5] Embedding retrieval V1，可选启用。
  - 在 FTS V1 基础上新增 embedding 检索，但必须保留 FTS-only fallback。
  - 支持配置：

```text
embedding.enabled
embedding.provider
embedding.model
embedding.dimension
embedding.store = sqlite-vec | lancedb | qdrant-local
```

  - MVP 推荐 `sqlite-vec` 或 LanceDB local。
  - embedding API key 仍由 Swift Keychain / LLMProxy 管理，sidecar 不持有 embedding API key。
  - embedding request 走 Swift `embedding.respond` 或 `embedding.embed` proxy。
  - embedding index 只索引 Swift 授权快照；未配置 embedding 时 workflow 继续使用 FTS。
  - 混合检索策略：

```text
candidate = FTS topK + embedding topK
rerank by metadata/project/paper/core tags
dedupe by chunk_id
return evidence refs
```

  - FTS-only 与 embedding-enabled 两种路径均通过测试；embedding index schema version 可迁移；source_hash 变化后 embedding chunk 标记 stale 或重建。

- [x] [P35.6] Evidence UI 与 source jump。
  - 增强 AI Lab / Wiki / artifact preview：artifact draft 中 evidenceRefs 可展开。
  - 点击 evidence 跳转到 `paper.md` line range、wiki page line range、`annotations.md`，或在有页码映射时跳转 PDF Reader 页。
  - 显示 source title、relative path、heading、line range、confidence、stale / missing warning。
  - Wiki citation block 可折叠；保存 artifact 后保留 evidence metadata。
  - 单篇论文精读 artifact 中点击 evidence 可定位到源文本；source_hash 变化后 UI 显示 stale evidence；不存在的 source 显示 missing source warning，而不是崩溃。

- [x] [P35.7] Sidecar run replay 与 debug bundle。
  - 新增 run replay 能力：

```text
.sci-station/agent/runs/{run_id}/
├── replay.json
├── critic_report.json
├── retrieval_trace.json
└── debug_bundle.zip 可选生成
```

  - 默认不保存 prompt/response 明文；用户显式开启 debug 后保存 redacted prompt/response。
  - debug bundle 不包含 API key、private path、`.env`、Keychain 内容。
  - run replay 可重新渲染 timeline，不一定重新调用模型。
  - 已完成 run 可在 AI Lab 重新打开并重放 timeline；sidecar crash 后可查看最后成功 checkpoint；debug bundle 生成前显示包含文件清单与隐私提示。

- [x] [P35.8] Sidecar Runtime UI 产品化。
  - 新增或增强 Settings / AI Lab runtime panel。
  - Runtime selector：

```text
Swift Loop
LangGraph Sidecar
Auto fallback
```

  - Health status：

```text
Python version
sidecar version
protocol/schema version
dependency check
last crash
fallback reason
```

  - Controls：

```text
Restart sidecar
Open run directory
Export debug bundle
Disable sidecar for this workspace
```

  - sidecar unavailable 时用户能看到明确原因；fallback 到 Legacy Swift runtime 时 UI 明确提示；runtime selector 不影响已完成 run 的回放。

- [x] [P35.9] Tests。
  - Swift CoreTestRunner 新增：

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

  - Python tests 新增：

```text
test_paper_reading_graph_evidence_minimums
test_related_work_theme_clustering
test_gap_planning_todo_schema
test_citation_critic_blocks_unsupported_claim
test_hybrid_retriever_dedupes_chunk_ids
test_stale_evidence_detection
test_run_replay_redaction
```

  - Fixture tests 复用 P34 fake sidecar fixtures。
  - 新增 sample workspace：3 篇 `paper.md`、1 个 project、project core papers、wiki/project overview、existing todos。

- [x] [P35.10] 验证与交付记录。
  - 必须运行：

```bash
swift run SciStationCoreTestRunner
python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

  - 手动验证：单篇论文精读生成 evidence-backed note；related work 生成主题聚类草稿；gap planning 生成 research plan 与 todo drafts；citation critic 能阻断无证据 claim；evidence UI 可以跳转源文本；sidecar crash 后可 fallback 或恢复；debug bundle 不含敏感信息。

## 4. 非目标

- 不做 shell/python/code execution sandbox。
- 不让 sidecar 获得 workspace 写权限。
- 不让 sidecar 直接读取 Keychain 或持有 API key。
- 不发布 plugin marketplace。
- 不要求 embedding 默认开启。
- 不做完整多 agent 自主协作。
- 不做远程 MCP OAuth。
- 不做云端同步。

## 5. 验收标准

1. 单篇论文精读 workflow 达到 production 质量，生成结构化 note、evidenceRefs、todo drafts，并通过 citation critic。
2. Related work workflow 能基于 project core papers 生成主题化 related work 草稿，并包含 evidence matrix。
3. Gap planning workflow 能生成 evidence-backed gaps、hypotheses、experiment proposals 与 todo drafts。
4. Citation critic 能阻断或标记 unsupported / stale / weak evidence claims。
5. Embedding retrieval V1 可选启用；未启用时 FTS-only fallback 正常。
6. Evidence UI 能从 artifact draft 跳转到源文件 line range，并显示 stale / missing source warning。
7. Sidecar run replay 可重放 timeline，debug bundle 默认不含敏感信息。
8. Sidecar runtime panel 能显示 health、fallback reason、restart/export controls。
9. 所有 workspace 写入仍必须经 Swift Permission Dock，由 Swift ToolHost/Repository 执行。
10. SwiftPM、Python tests、Xcode build 均通过，或交付记录明确列出环境阻塞。

## 6. 建议执行顺序

```text
P35-A: Citation Critic / Evidence Critic
P35-B: Paper Reading workflow 产品化
P35-C: Evidence UI / source jump
P35-D: Related Work production graph
P35-E: Gap Planning production graph
P35-F: Run replay / debug bundle
P35-G: Runtime UI 产品化
P35-H: Embedding retrieval V1
```

其中 P35-A 到 P35-C 是最优先的，因为它们直接提升 P34 的单篇论文精读质量。Embedding 可以靠后，不阻塞 workflow production。

## 7. Questions

1. P35 是否确认先做 `Citation Critic -> Paper Reading production -> Evidence UI/source jump`？当前建议为确认，先把 P34 的单篇论文精读做成可靠科研写作闭环。
2. Related work 与 gap planning 的 production 顺序是否按 related work 优先？当前建议为 related work 先行，因为 evidence matrix 与 citation critic 可直接复用到 gap planning。
3. Embedding retrieval V1 是否保持可选且靠后？当前建议为可选启用，FTS-only fallback 必须始终可用。
4. Sidecar Runtime UI 与 run replay 是否放在 embedding 之前？当前建议为放在 embedding 之前，优先改善可恢复性与用户可理解性。

## 8. P35 交付记录

本轮已完成 P35 Production V1：Python sidecar 增加 citation/evidence critic、结构化 paper reading note、related work 主题聚类、research gap/todo draft、hybrid retriever 与 run replay/debug bundle；Swift Core 增加 citation critic report、embedding config、evidence source jump、run replay/debug manifest 与 runtime selector 持久化；AI Lab/Settings 增加 runtime health/fallback 面板与 evidence 展开/source open 控件。

验证已完成：

```bash
python -m pytest AgentRuntime/tests
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

P35 留给 P36 深化的边界：runtime selector 已持久化并显示 fallback，但默认 AI Lab 运行路径仍以现有 Swift runtime 为主；sidecar health panel 已产品化为可理解状态，但 live restart/export zip 需要接入真实 supervisor session；embedding V1 已具备配置、fallback 与混合去重测试，持久化 sqlite-vec/LanceDB store 与 Swift embedding proxy 的真实模型调用放入下一轮。
