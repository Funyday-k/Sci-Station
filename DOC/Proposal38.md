# 任务书 38：Artifact Lifecycle、Draft Inbox 与 Evidence Inspector

更新时间：2026-05-06

> 本任务书承接任务书 37。P37 已完成 embedding persistent store 基础、deterministic fallback、Swift embedding proxy、retrieval index status UI、hybrid retrieval trace schema 和 retrieval/debug privacy boundary。P38 的目标不是继续扩展检索底座，而是把 sidecar / Swift loop 产生的 artifact draft 变成可审阅、可批准、可保存、可追溯的产品化工作流。

## 1. 背景

P35-P37 已建立以下基础：

```text
paper_reading / related_work / gap_planning artifact drafts
critic_report / evidence.json / retrieval_trace.json run artifacts
AgentEvidenceRef sourceJump line target and PDF page mapping
debug bundle zip and redaction manifest
embedding fallback store and retrieval index status
Swift host-owned permission and sidecar safety boundary
```

当前主要缺口是 artifact draft 生命周期仍偏临时：用户可以看到 draft，但缺少统一 Draft Inbox、审批历史、保存前 diff、evidence inspector、stale/missing evidence 再检查和保存后的 lineage。P38 要把“AI 产出”从一次性结果推进为可复核的工作对象。

## 2. 本轮目标

1. 定义统一 `ArtifactDraft` / `ArtifactRecord` / `ArtifactApproval` schema V1。
2. 新增 Draft Inbox：集中展示 AI Lab 产生但尚未保存/拒绝/归档的 drafts。
3. 建立 artifact lifecycle 状态：draft、needs_review、approved、saved、rejected、stale、error。
4. 保存前提供 diff / target path preview / overwrite warning / evidence summary。
5. 新增 Evidence Inspector：从 artifact draft 查看 evidenceRefs、source jump、stale/missing warning、retrieval trace excerpt。
6. Permission Dock V2 支持 artifact 保存审批、todo draft 审批和批量 accept/reject。
7. 保存后写入 lineage metadata，记录 run_id、artifact_id、evidence ids、retrieval trace hash、approval timestamp。
8. 保持 sidecar 不直接写 workspace；所有保存动作继续由 Swift host 执行并可撤销或恢复。

## 2.1 实现约束

1. Artifact draft 必须是 derived proposal，不是用户原始资料；保存前不得覆盖用户文件。
2. Sidecar 只能提出 artifact draft 和 approval request，不得直接写 target file。
3. 保存前必须展示 target path、是否新建/覆盖、diff summary 和 evidence health。
4. Draft Inbox 不保存 prompt/response 明文；只保存 artifact content、redacted run metadata 和 evidence/retrieval references。
5. Evidence Inspector 默认不展示完整 query/prompt；只展示 redacted trace excerpt、score/reason、source path/line/page。
6. 保存后的 lineage metadata 不得包含 API key、Keychain、`.env`、provider raw response 或完整 prompt。
7. Rejected draft 必须可从 Inbox 隐藏，但 run directory/debug artifact 仍保持可审计。
8. P38 不做多人协作、云同步、全文版本控制系统或复杂 conflict resolver。

## 3. 实施任务

- [ ] [P38.1] Artifact lifecycle schema V1。
  - 新增 `ArtifactDraft`、`ArtifactRecord`、`ArtifactApproval`、`ArtifactEvidenceHealth` model。
  - 字段至少包含 artifact_id、run_id、kind、title、target_path、content_hash、status、created_at、updated_at、evidence_ids、retrieval_trace_hash、approval history。
  - 支持 paper note、related work wiki、research plan wiki、todo drafts。

- [ ] [P38.2] Draft Inbox store。
  - 在 Research Root 内保存 redacted draft index。
  - 推荐路径：`.sci-station/agent/drafts/`。
  - 支持 list、get、update status、archive/reject、delete derived draft。
  - 不作为用户原始资料唯一来源，可删除并由 run artifacts 重新导入。

- [ ] [P38.3] Draft Inbox UI。
  - AI Lab 增加 Draft Inbox panel 或 tab。
  - 显示 draft kind、title、target path、status、created time、evidence health、source run。
  - 提供 Review、Approve & Save、Reject、Archive、Open Run Directory。
  - 空状态、error 状态和 stale 状态必须可理解。

- [ ] [P38.4] Save preview and diff。
  - 保存前展示 target path、existing file status、diff summary。
  - 新建文件、追加 section、覆盖文件分别给出明确文案。
  - 覆盖或冲突时需要二次确认。
  - 保存失败不得丢失 draft。

- [ ] [P38.5] Evidence Inspector。
  - Artifact review 中可展开 evidence list。
  - 每条 evidence 显示 source path、line range / PDF page、fresh/stale/missing、quote snippet、score/reason。
  - 支持 source jump。
  - 支持查看 redacted retrieval trace excerpt。

- [ ] [P38.6] Permission Dock V2。
  - 将 artifact save、todo draft creation、wiki write 纳入统一 approval surface。
  - 支持批量 accept/reject todo drafts。
  - Approval result 写入 artifact approval history。
  - 用户拒绝后 draft 状态变 rejected，不重复弹出。

- [ ] [P38.7] Saved artifact lineage。
  - 保存到 wiki/paper note/todo 后写入最小 lineage metadata。
  - Wiki citation block 或 sidecar metadata 中保留 artifact_id、run_id、evidence ids、retrieval_trace_hash。
  - 后续打开 saved artifact 时可回到 source run 或 Evidence Inspector。

- [ ] [P38.8] Tests。
  - Swift CoreTestRunner 覆盖 draft store CRUD、status transition、save preview diff、reject/archive、lineage metadata、evidence health stale/missing。
  - Python tests 覆盖 artifact draft payload schema、run artifact import、retrieval trace hash/redaction。
  - Xcode build 必须通过。

- [ ] [P38.9] 手动测试与交付记录。
  - 按 `DOC/ManualTestProtocol.md` 执行本轮手动测试。
  - 必须执行：MT07 AI Lab partial、MT09 Evidence / Artifact、MT99 partial regression。
  - 更新或新增 Draft Inbox / Evidence Inspector 用例。
  - 手动测试报告写入：`DOC/manual-tests/runs/YYYY-MM-DD_P38_ArtifactLifecycle.md`。

## 4. 非目标

```text
不做云同步或多人协作
不做完整 Git-like version control
不做全 workspace artifact graph/recommendation
不做远程 MCP OAuth
不让 sidecar 直接写 workspace
不保存 prompt/response 明文
不做完整 background indexing queue
不继续扩展 sqlite-vec native optimization
```

## 5. 验收标准

1. AI Lab run 产生的 artifact draft 能进入 Draft Inbox。
2. Draft Inbox 能展示 pending/rejected/saved/stale 等状态，并支持 review、approve/save、reject/archive。
3. 保存前用户能看到 target path、diff/overwrite summary 和 evidence health。
4. Evidence Inspector 能展示 evidenceRefs、source jump、stale/missing warning 和 redacted retrieval trace excerpt。
5. Permission Dock V2 能处理 artifact save 和 todo draft approvals；sidecar 仍无 workspace 写权限。
6. 保存后的 artifact 写入 lineage metadata，可回到 source run / evidence。
7. Draft/debug/lineage 文件不包含 API key、Keychain、`.env`、provider raw response 或 prompt/response 明文。
8. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。
9. P38 指定手动测试完成，且没有未解决的 S0/S1 问题。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充 targeted validation：

```text
get_errors for edited Swift / SwiftUI files
manual inspection of draft index files for redaction
manual save preview for new file and overwrite path
manual stale evidence test after source_hash change
debug bundle scan for no draft prompt/response plaintext
```

## 7. 手动测试计划

本任务书完成后必须执行：

```text
MT07 AI Lab partial
MT09 Evidence / Artifact full partial
MT99 Release Regression partial
```

P38 新增或重点手动测试用例：

```text
MT07-P38-01: AI Lab run creates Draft Inbox item
MT07-P38-02: Draft Inbox review opens save preview
MT07-P38-03: Reject/archive draft hides it without deleting run artifacts
MT09-P38-01: Evidence Inspector shows source path/line/page and stale state
MT09-P38-02: Approve & Save writes wiki artifact with lineage metadata
MT09-P38-03: Todo draft approval creates tasks only after user approval
MT09-P38-04: Overwrite target path requires confirmation and preserves draft on failure
MT09-P38-05: Draft/debug/lineage privacy scan contains no secret or prompt/response plaintext
MT99 partial regression: workspace open, AI Lab, Settings, Wiki save, Tasks, debug bundle
```

允许跳过：

```text
Full interactive overwrite conflict matrix: 如果无法准备多个 conflict fixture，可保留最小 overwrite confirmation 测试。
PDF page source jump: 如果测试 fixture 缺少 page mapping，可记录 fixture 缺口并以 Markdown line jump 覆盖。
```

阻塞验收的问题等级：

```text
S0: secret 泄漏、sidecar 直接写 workspace、保存覆盖未确认、数据丢失、App crash
S1: Draft Inbox 主路径不可用、Approve & Save 不工作、Evidence Inspector 无法显示 evidenceRefs、Permission Dock 审批失效
```

## 8. 交付记录

完成实现后补充：

```text
完成日期：
Git commit：
自动化测试结果：
手动测试报告：DOC/manual-tests/runs/YYYY-MM-DD_P38_ArtifactLifecycle.md
已知问题：
推迟到 P39 的事项：Workspace Module Registry、custom module install/disable UX、graph/recommendation follow-up
```

## 9. P37 完成态与剩余风险

P37 已完成并验证：

```text
EmbeddingStore protocol and chunk schema
deterministic fallback persistent store
preferred sqlite-vec path with fallback when extension unavailable
Swift embedding.embed / embedding.respond proxy contract
source_hash / text_hash normalized hashing and stale detection
hybrid retrieval trace schema v2 with redacted query hash
Settings / AI Lab retrieval status and rebuild actions
debug bundle exclusion for embedding index files
SwiftPM CoreTestRunner / Python pytest / Xcode build
```

P37 剩余风险：

```text
sqlite-vec native extension path 未在当前环境手动验证，因为 sqlite_vec=False。
provider-backed real embedding API call 未执行，P37 以 Swift proxy contract 和 deterministic fallback 验收。
交互式 macOS UI 点击未在工具环境执行，P37 手动报告为 CONDITIONAL PASS。
```

## 10. Questions

1. P38 是否优先实现 Draft Inbox + Evidence Inspector，而不是直接进入 Workspace Module Registry？当前建议为是。
2. Artifact 保存策略是否先支持 wiki/paper note/todo drafts 三类，不做通用任意文件写入？当前建议为是。
3. 保存前 diff 是否先做 line-based textual diff，复杂 Markdown semantic diff 延后？当前建议为是。
4. Rejected draft 是否默认保留 run artifacts、仅从 Inbox 隐藏？当前建议为是，保证可审计。
5. P38 是否继续保持 sidecar no-write 边界，所有保存动作由 Swift host + Permission Dock V2 执行？当前建议为是。
