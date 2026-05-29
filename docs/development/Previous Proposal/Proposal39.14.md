# 任务书 39.14：AI Lab Debug 回放、索引重建与 Writeback Fallback

更新时间：2026-05-07
状态：Partial PASS / Follow-up Split
优先级：S1 / Release Candidate Hardening
承接：P39.13 修复 archived thread 复活、第三篇论文序数路由、heading 优先读取，并新增 AI Lab Debug mode。

---

## 1. 背景

P39.13 已把用户截图中的两个确定性 UI/工具链问题收口：归档线程不再作为当前对话复活，“第三篇文章”能解析为第三篇并且 `read_paper_section` 优先按 heading 读取。Debug mode 也开始把 AI Lab 操作、输入、输出和工具结果写到 workspace-local JSONL。

ResearchWorkspace 日志仍暴露两个后续风险：embedding index 显示 `chunks=0` 且 `.sci-station/index/embeddings/manifest.json` 缺失；“写进 wiki 里”遇到 provider JSON parse failure 时没有 deterministic writeback fallback。

---

## 2. 本轮目标

1. 在 Debug mode 基础上增加可打开/复制/回放的最近事件视图，降低下次读日志成本。
2. 修复 selected source rebuild 后 `chunks=0` 的可见诊断和 rebuild contract。
3. 为 provider JSON parse failure 增加 writeback-safe fallback：不静默写 workspace，但能保留草稿、证据和下一步操作。
4. 完成 P39.13 manual UI run，并把 ResearchWorkspace 真实问题标记为 PASS / CONDITIONAL PASS / BLOCKED。

---

## 3. 实施任务

### [P39.14.1] Debug log viewer / export

- AI Lab 增加最近 Debug events 面板或 popover，显示 event、timestamp、runID/threadID、payload summary。
- 提供 Copy Debug Tail 和 Open Log 两个操作。
- 继续保持 redaction，不展示 Keychain/API key。

### [P39.14.2] Embedding chunks=0 diagnosis

- 检查 `.sci-station/index/embeddings` 的实际布局和 manifest 生成路径。
- Rebuild Selected Source 后必须给出 indexed chunks、skipped reason 或 explicit failure。
- 对 sqlite-vec unavailable deterministic fallback，确认 FTS fallback 是否应该生成 chunks 计数或单独显示 source lines count。

### [P39.14.3] Provider JSON parse writeback fallback

- 当 provider 返回不可解析 JSON 且用户目标是“写进 wiki/保存/append”时，保留 read-only evidence 和 assistant draft。
- 写操作仍需 Permission Dock 审批，不做静默写入。
- Error UI 给出 Retry、Copy Debug Tail、Create Draft Plan 三个 recovery path。

### [P39.14.4] Manual release gate

- 执行 `docs/development/manual-tests/runs/2026-05-07_P39.13_DebugArchivePaperRouting.md`。
- 补充 ResearchWorkspace 复现步骤、结果截图路径和残余风险。
- 继续运行 `swift run SciStationCoreTestRunner` 与 Xcode app build。

---

## 4. 验收标准

1. Debug mode 不需要离开 App 就能查看最近关键事件和复制尾部日志。
2. selected source rebuild 后不再只显示 `chunks=0` 而没有 actionable reason。
3. Provider JSON parse failure 不丢失证据和草稿，且 writeback 仍受审批保护。
4. P39.13 manual run 有明确结论。

---

## 5. Questions

1. Debug event viewer 是否只放 AI Lab，还是也放 Settings 的 AI Lab Runtime 区？
2. `chunks=0` 时是否接受 deterministic fallback 使用 `paper.md` line slices 作为临时 evidence count？
3. Writeback fallback 的草稿应写到 wiki draft 文件，还是只存在 run artifact/Debug log 中等待审批？

---

## 6. 2026-05-07 执行记录

本轮从 ResearchWorkspace debug logs 复核到三个真实问题：

- AI Lab 对话气泡把 assistant/user event 的 `payload_json` 原样显示在正文下方，导致 Markdown 回复后追加大段 JSON。
- `openPaperMarkdown` 会切到 Wiki，但 Wiki loader 只扫描 `wiki/`，因此 `library/papers/.../paper.md` 已存在时仍显示空编辑区。
- `.sci-station/index/embeddings` 为空时只显示 `chunks=0` 的通用提示，没有说明 selected source 实际已存在且非空。

已完成修复：

- `AgentSessionTimelineItem` 对 user/assistant message 隐藏 raw payload preview，保留 tool/permission/debug 事件 payload 预览用于审计。
- `MarkdownRepository` 增加按 relative path 加载单个 Markdown 文档；`AppViewModel.loadMarkdownDocuments` 在打开 library paper `paper.md` 时把外部文档加入当前 Markdown selection，修复“跳到 Wiki 后为空”。
- `AppViewModel` 的 retrieval diagnostic 增加 selected source exists / directory / bytes / lines；`chunks=0` hint 会区分缺失、空文件、目录、已存在非空但未 rebuild；Rebuild Source 完成消息也带 chunks/hint。
- 增加核心测试覆盖：chat timeline 不渲染 raw user/assistant payload；MarkdownRepository 可加载 `library/papers/.../paper.md`。

验证结果：

- PASS：`swift run SciStationCoreTestRunner`
- PASS：`xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`
- NOT RUN：完整 ResearchWorkspace 手动 UI run、截图归档和 provider writeback 审批链路仍留到 P39.15。