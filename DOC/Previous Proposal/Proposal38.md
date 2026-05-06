# 任务书 38：Artifact Lifecycle、Draft Inbox、Evidence Inspector 与 Permission Dock V2

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

当前主要缺口是 artifact draft 生命周期仍偏临时：用户可以看到 draft，但缺少统一 Draft Inbox、审批历史、保存前 diff、evidence inspector、stale/missing evidence 再检查、保存失败恢复和保存后的 lineage。P38 要把“AI 产出”从一次性结果推进为可复核、可批准、可保存、可追溯的工作对象。

## 2. 本轮目标

1. 定义统一 `ArtifactDraft` / `ArtifactRecord` / `ArtifactApproval` schema V1。
2. 新增 Draft Inbox：集中展示 AI Lab 产生但尚未保存/拒绝/归档的 drafts。
3. 建立 artifact lifecycle 状态：draft、needs_review、approved、saving、saved、rejected、archived、stale、error。
4. 保存前提供 save mode、diff / target path preview / overwrite warning / evidence health。
5. 新增 Evidence Inspector：从 artifact draft 查看 evidenceRefs、source jump、stale/missing warning、retrieval trace excerpt。
6. Permission Dock V2 支持 artifact 保存审批、todo draft 审批和批量 accept/reject。
7. 保存后写入 lineage metadata，记录 run_id、artifact_id、evidence ids、retrieval trace hash、approval timestamp。
8. 保持 sidecar 不直接写 workspace；所有保存动作继续由 Swift host 执行并可撤销或恢复。
9. 支持 Edit before save：用户可在 Review 面板编辑 draft，保存后记录 edited_before_save。
10. 定义 Draft Inbox index 损坏时的恢复路径：App 不崩溃，并可从 run artifacts 尝试 rebuild。
11. 明确 unsupported core claim / missing core evidence 的阻止或 low-confidence confirmation 规则。

## 2.1 实现约束

1. Artifact draft 必须是 derived proposal，不是用户原始资料；保存前不得覆盖用户文件。
2. Sidecar 只能提出 artifact draft 和 approval request，不得直接写 target file。
3. 保存前必须展示 target path、保存模式、是否新建/追加/替换/覆盖、diff summary、evidence health 和 overwrite warning。
4. Draft Inbox 不保存 prompt/response 明文；只保存 artifact content、redacted run metadata 和 evidence/retrieval references。
5. Evidence Inspector 默认不展示完整 query/prompt；只展示 redacted trace excerpt、score/reason、source path/line/page。
6. 保存后的 lineage metadata 不得包含 API key、Keychain、`.env`、provider raw response 或完整 prompt。
7. Rejected draft 必须可从 Inbox 隐藏，但 run directory/debug artifact 仍保持可审计。
8. P38 不做多人协作、云同步、全文版本控制系统或复杂 conflict resolver。
9. P38 不依赖 sqlite-vec native path 或真实 embedding provider call；Evidence Inspector 可使用 P37 deterministic fallback + retrieval trace v2 作为测试基础。

## 2.2 状态机与保存约束

```text
ArtifactStatus:
- draft
- needsReview
- approved
- saving
- saved
- rejected
- archived
- stale
- error
```

状态转换规则：

```text
created -> draft -> needsReview -> approved -> saving -> saved
draft / needsReview -> rejected / archived / stale / error
saved -> stale / reopened_for_review
error -> needsReview / rejected
```

保存约束：

```text
1. Approve & Save 必须先进入 saving；写入成功后才能标记 saved。
2. 保存失败不得丢失 draft，不得错误标记 saved。
3. Draft 与 saved ArtifactRecord 必须通过 artifact_id / saved_record_id / run_id 双向关联。
4. Rejected draft 默认从 Inbox 隐藏，但 run artifacts 保留。
5. Archived draft 可从 Archived filter 找回。
6. 保存前必须展示 target path、保存模式、diff summary、evidence health 和 overwrite warning。
7. 用户可 Edit before save；编辑后更新 content_hash，并在 approval history 中记录 edited_before_save。
8. 保存后的 lineage metadata 不得包含 API key、Keychain、.env、provider raw response、prompt/response 明文。
```

## 2.3 保存目标与 diff 最小规则

P38 保存目标限定为三类，不做任意文件写入：

```text
Wiki:
- create new page
- append section
- replace section with artifact marker

Paper note:
- append AI note section
- update generated section only
- never overwrite user-written whole paper.md without explicit confirmation

Todo:
- create tasks after approval
- batch approve/reject
- duplicate detection
```

最小 diff 规则：

```text
new file:
  显示将创建的路径和全文预览。

append section:
  显示插入位置、section title、追加内容。

replace generated block:
  显示 old generated block 与 new generated block 的 line diff。

overwrite:
  必须二次确认，并默认不推荐。
```

Paper note 中由 AI 生成并可被后续更新替换的内容应优先使用 artifact marker，例如：

```html
<!-- sci-station:artifact id=xxx start -->
generated content
<!-- sci-station:artifact id=xxx end -->
```

## 2.4 Evidence Health 规则

```text
ArtifactEvidenceHealth:
- total_evidence_count
- fresh_count
- stale_count
- missing_count
- unsupported_claim_count
- weak_evidence_count
- retrieval_trace_available: true/false
- source_jump_available_count
- overall_status: healthy / warning / blocked
```

状态规则：

```text
healthy:
  有 evidence，且无 missing / unsupported core claim。

warning:
  有 stale evidence 或 weak evidence，但用户可选择保存。

blocked:
  核心 claim 无 evidence，或 evidence source missing，或 source jump metadata 全部丢失。
```

`unsupported core claim` 默认阻止 Approve & Save，除非用户选择 Save as low-confidence draft。`stale evidence` 显示 warning 但不一定阻止。`missing core evidence` 强警告；如果是核心 evidence，默认阻止或要求 low-confidence confirmation。

## 3. 实施任务

- [ ] [P38.1] Artifact lifecycle schema V1。
  - 新增 `ArtifactDraft`、`ArtifactRecord`、`ArtifactApproval`、`ArtifactEvidenceHealth` model。
  - 字段至少包含 artifact_id、run_id、kind、title、target_path、save_mode、content_hash、status、created_at、updated_at、evidence_ids、retrieval_trace_hash、approval history、saved_record_id。
  - 支持 paper note、related work wiki、research plan wiki、todo drafts。
  - `ArtifactApproval` 记录 action、timestamp、edited_before_save、low_confidence、failure/partial_failure metadata。

- [ ] [P38.2] Draft Inbox store。
  - 在 Research Root 内保存 redacted draft index。
  - 推荐路径：`.sci-station/agent/drafts/`。
  - 支持 list、get、update status、archive/reject/restore、delete derived draft。
  - 不作为用户原始资料唯一来源，可删除并由 run artifacts 重新导入。
  - Draft Inbox index 损坏时，App 不崩溃，UI 显示 rebuild/recover 提示，并可从 `.sci-station/agent/runs/` 或对应 run directory 重建 draft list。
  - 无法恢复的 draft 标记为 orphaned / error。

- [ ] [P38.3] Draft Inbox UI。
  - AI Lab 增加 Draft Inbox panel 或 tab。
  - 显示 draft kind、title、target path、status、created time、evidence health、source run。
  - 提供 Review、Edit before save、Approve & Save、Save as low-confidence draft、Reject、Archive、Restore、Open Run Directory。
  - 默认 Inbox 隐藏 rejected / archived；提供 Archived filter。
  - 空状态、error 状态和 stale 状态必须可理解。

- [ ] [P38.4] Save preview and diff。
  - 保存前展示 target path、save mode、existing file status、diff summary、evidence health。
  - 新建文件、追加 section、replace generated block、覆盖文件分别给出明确文案。
  - 覆盖或冲突时需要二次确认。
  - 保存失败不得丢失 draft。
  - 用户编辑 draft 后更新 content_hash，保存内容必须为编辑后版本。

- [ ] [P38.5] Evidence Inspector。
  - Artifact review 中可展开 evidence list。
  - 每条 evidence 显示 source path、line range / PDF page、fresh/stale/missing、quote snippet、score/reason。
  - 支持 source jump。
  - 支持查看 redacted retrieval trace excerpt。
  - 计算 `ArtifactEvidenceHealth`，并区分 healthy / warning / blocked。
  - unsupported core claim / missing core evidence 默认阻止直接 Approve & Save，或要求 low-confidence confirmation。

- [ ] [P38.6] Permission Dock V2。
  - 将 artifact save、todo draft creation、wiki write 纳入统一 approval surface。
  - 支持批量 accept/reject todo drafts。
  - Approval result 写入 artifact approval history。
  - 用户拒绝后 draft 状态变 rejected，不重复弹出。
  - Approve & Save 尽量原子化：target file 写入失败时不得标记 saved；lineage 写入失败时必须显示 partial save warning；todo 批量部分失败时显示 partial failure list。

- [ ] [P38.7] Saved artifact lineage。
  - 保存到 wiki/paper note/todo 后写入最小 lineage metadata。
  - Wiki citation block 或 sidecar metadata 中保留 artifact_id、run_id、evidence ids、retrieval_trace_hash。
  - Draft.status = saved 后写入 saved_record_id；ArtifactRecord 指向 target_path 并保留 approval history 引用。
  - 后续打开 saved artifact 时可回到 source run、Evidence Inspector 或 approval history。

- [ ] [P38.8] Tests。
  - Swift CoreTestRunner 覆盖 draft store CRUD、status transition、save preview diff、reject/archive/restore、edit before save、lineage metadata、evidence health stale/missing/unsupported、Draft Inbox recovery、save failure no data loss。
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
不做通用任意文件写入
不做复杂 Markdown semantic diff
不保存 prompt/response 明文
不做完整 background indexing queue
不继续扩展 sqlite-vec native optimization
```

## 5. 验收标准

1. AI Lab run 产生的 artifact draft 能进入 Draft Inbox。
2. Draft Inbox 能展示 pending/rejected/archived/saving/saved/stale/error 等状态，并支持 review、edit、approve/save、low-confidence save、reject/archive/restore。
3. 保存前用户能看到 target path、save mode、diff/overwrite summary 和 evidence health。
4. Evidence Inspector 能展示 evidenceRefs、source jump、stale/missing warning 和 redacted retrieval trace excerpt。
5. Permission Dock V2 能处理 artifact save 和 todo draft approvals；sidecar 仍无 workspace 写权限。
6. 保存后的 artifact 写入 lineage metadata，可回到 source run / evidence / approval history。
7. Draft/debug/lineage 文件不包含 API key、Keychain、`.env`、provider raw response 或 prompt/response 明文。
8. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。
9. P38 指定手动测试完成，且没有未解决的 S0/S1 问题。
10. Draft Inbox index 损坏时，不影响 App 启动，并可从 run artifacts 尝试恢复。
11. Approve & Save 写入失败时，draft 保持可审阅状态，不丢失内容，不错误标记 saved。
12. 用户可在保存前编辑 draft，保存后 lineage 记录 edited_before_save。
13. rejected 与 archived 状态语义区分清楚，默认 Inbox 不显示 rejected/archived。
14. unsupported core claim 或 missing core evidence 时，Approve & Save 默认阻止或要求 low-confidence confirmation。
15. 保存后的 wiki / paper note / todo 能回到 source run、Evidence Inspector 和 approval history。

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
manual save preview for append section and replace generated block
manual edit-before-save content_hash validation
manual Draft Inbox recovery test from run artifacts
manual stale evidence test after source_hash change
manual save failure / partial failure validation
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
MT07-P38-04: Edit before save 后 content_hash 更新，保存内容为编辑后版本
MT07-P38-05: Draft Inbox index 损坏后 App 不崩溃，并显示 rebuild/recover 提示
MT09-P38-01: Evidence Inspector shows source path/line/page and stale state
MT09-P38-02: Approve & Save writes wiki artifact with lineage metadata
MT09-P38-03: Todo draft approval creates tasks only after user approval
MT09-P38-04: Overwrite target path requires confirmation and preserves draft on failure
MT09-P38-05: Draft/debug/lineage privacy scan contains no secret or prompt/response plaintext
MT09-P38-06: unsupported core claim 阻止直接 Approve & Save
MT09-P38-07: stale evidence 允许保存但显示 warning
MT09-P38-08: missing core evidence 默认阻止保存或要求 low-confidence confirmation
MT09-P38-09: 保存中断/失败后 draft 不丢失，状态不错误变为 saved
MT09-P38-10: saved artifact 可跳回 source run 和 Evidence Inspector
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

P38 不依赖 sqlite-vec native path 或 real embedding provider call。P38 的 Evidence Inspector、Evidence Health 与 Draft Inbox 可使用 P37 deterministic fallback、persistent deterministic index 和 retrieval trace v2 作为测试基础。

## 10. Decisions

1. P38 优先实现 Draft Inbox、Evidence Inspector、Permission Dock V2 和 saved artifact lineage；Workspace Module Registry 继续放到 P39。
2. P38 保存目标限定为 wiki、paper note 和 todo drafts；任意文件写入、code/data/output 写入推迟到后续特化模块，并继续经过 Swift host + Permission Dock。
3. P38 使用 line-based textual diff 作为保存前预览；Markdown semantic diff、section-aware diff、citation-aware diff 延后。
4. Rejected draft 默认只从 Inbox 默认视图隐藏，不删除 run artifacts；P38 同时区分 Reject 与 Archive。
5. P38 继续保持 sidecar no-write 边界；所有 artifact save、todo creation、wiki write、paper note update 都必须由 Swift host 执行，并通过 Permission Dock V2 审批。

## 11. Questions

1. P38 的最小 UI 入口是否放在 AI Lab 内作为 Draft Inbox tab，而 Project Dashboard / Home 只显示摘要入口？当前建议为是。
2. Low-confidence save path 是否需要单独写入可见 warning block，还是只写 lineage metadata？当前建议为两者都做最小版本。
3. Artifact marker 是否先只用于 generated block 替换，用户手写 section 不自动插入 marker？当前建议为是。
4. Draft recovery 失败产生的 orphaned draft 是否默认隐藏在 error filter 中？当前建议为是。
