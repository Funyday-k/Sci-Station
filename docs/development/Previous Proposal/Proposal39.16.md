# 任务书 39.16：AI Lab 写回体验与真实回放收口

更新时间：2026-05-07
状态：Implemented / Validation In Progress
优先级：S1 / Release Gate Hardening
承接：P39.15 已完成本地 Markdown 渲染、Wiki 写回路径扩展、预算放大与 empty response fallback；本轮收口 P39.15 明确剩余的 UI 审批三段式、continuation 复用、DOMPurify 本地打包与 ResearchWorkspace 真实回放。

---

## 1. P39.15 完成状态

已完成并通过 `swift run SciStationCoreTestRunner`：

- AI Lab assistant Markdown 气泡接入 `ChatMarkdownWebView`，最近 20 条 assistant rich bubble 使用本地 WebKit renderer，旧气泡回退 legacy text。
- `MarkdownPreviewView` 改为加载 `ChatRenderer.bundle/doc-preview.html`，不再访问 jsdelivr CDN。
- `write_markdown_plan` 扩展到 `wiki/plans|papers|notes|projects`，新增 `write_wiki_markdown` 别名，`wiki/papers/<id>.md` 校验 paper index。
- Plan 非 JSON 写回回复降级为“未确认的写回草稿”。
- Empty response / budget fallback 在无工具结果但有上下文时也生成可见 final Markdown，并保存 provider fallback draft。
- Agent loop 默认预算：20 steps、80 tool calls、1M context、384K per-tool output、1M accumulated tool text；LLM 默认 `max_tokens` 为 384K。
- Settings → AI Lab 增加 Tool Budget 配置与 Reset。

---

## 2. 本轮目标

1. **写回 UI 三段式**：Permission Dock 对 `write_markdown_plan` / `write_wiki_markdown` 显示“批准并写入 / 仅保存草稿 / 拒绝”，其中“仅保存草稿”生成 `.draft.md` 或保存到 drafts store，并在 chat timeline 明确展示。
2. **写入完成反馈**：工具审批写入完成后，chat timeline 插入可点击的 workspace-relative target path，支持直接打开 `wiki/papers/<id>.md`。
3. **Continuation 复用**：识别“继续 / go on / continue”，把上一 run 的 paper/tool evidence 摘要注入下一轮 system/user context，避免重新读完整 paper。
4. **DOMPurify 本地打包**：把 pinned `dompurify.min.js` 加入 `ChatRenderer.bundle`，`doc-preview.html` 先 sanitize 再渲染；更新 `BUNDLING.md` 同步步骤。
5. **ResearchWorkspace 回放**：重跑 P39.15 中 5 个曾经失败的 prompt，并记录 MT07/MT99 manual run 文件。

---

## 3. 实施任务

### [P39.16.1] Permission Dock 草稿按钮

文件：`Sci-Station/UI/AILabWorkspaceView.swift`、`Sci-Station/App/AppViewModel.swift`、`Sci-Station/Agent/AgentRuntimeSummaries.swift`。

- 对 writeback tool item 显示 body preview、target path、risk。
- 增加“仅保存草稿”动作：不 resume tool execution，不写最终 target；保存到 `.sci-station/agent/drafts.json` 或 `wiki/drafts/<slug>.draft.md`。
- 拒绝写入时保留 assistant draft，状态文案不再只有 failure。

### [P39.16.2] 写入完成后打开目标

文件：`Sci-Station/App/AppViewModel.swift`、`Sci-Station/UI/AILabWorkspaceView.swift`。

- 从 `AgentToolResult.modifiedPaths` / payload `target_path` 生成 timeline link。
- 点击 link 打开对应 Markdown editor 或 Finder fallback。
- 对 `wiki/papers/<id>.md` 与 Generate Wiki Page 的同路径行为做一次 manual 验证。

### [P39.16.3] Continue / go on 上下文注入

文件：`Sci-Station/Agent/AgentPaperIntentRouter.swift`、`Sci-Station/App/AppViewModel.swift`、`Sci-Station/Agent/SciStationAgentService.swift`。

- 新增 continuation intent。
- 从 active thread 最近 run 提取 toolResults，按 paper id / heading / source path 生成短摘要。
- 作为下一轮 system/user context 注入，不重复全量 `read_paper`。

### [P39.16.4] DOMPurify 本地 sanitizer

文件：`Sci-Station/Resources/ChatRenderer.bundle/`、`Sci-Station/UI/MarkdownPreviewView.swift`。

- 将 pinned `dompurify.min.js` 加入 bundle。
- `doc-preview.html` 使用本地 DOMPurify sanitize `marked.parse(markdown)` 输出。
- 确认断网时没有 jsdelivr/CDN 请求。

### [P39.16.5] Manual Gate 与真实回放

- 新建 `docs/development/manual-tests/runs/2026-05-07_P39.15_AILabMarkdownWritebackBudget.md`。
- 执行 MT07-P39.15-01..08 与 MT99-P39.15-01..06。
- ResearchWorkspace 重跑：
  - `evaporation rate?`
  - `继续`
  - `写进wiki里`
  - `对这个文章做一个总结放进wiki里`
  - `第三篇文章里的蒸发率公式是什么？`

---

## 4. 验收标准

1. Writeback Permission Dock 能明确选择批准、保存草稿或拒绝；保存草稿不执行 workspace target 写入。
2. 批准写入后 chat timeline 显示 target path，并能打开对应 Markdown 页面。
3. “继续 / go on” 使用上一轮证据摘要，至少不重新触发完整 4 次以上 paper read。
4. Markdown Preview 使用本地 DOMPurify + marked + KaTeX，断网不访问 CDN。
5. P39.15 manual run 文件完成，ResearchWorkspace 曾失败 prompt 至少 4/5 变为 completed 或 visible fallback。
6. `swift run SciStationCoreTestRunner` 与 Xcode app build 通过。

---

## 5. Implementation Notes

本轮已实施：

- Permission Dock 对 writeback 工具显示 target/body/risk 预览，并提供“批准并写入 / 仅保存草稿 / 拒绝”三段式动作；“仅保存草稿”写入 `wiki/drafts/<slug>.draft.md`，不 resume 原工具。
- Timeline 从 `modified_paths` / `target_path` / `draft_path` 提取 workspace-relative path，并提供打开入口；Markdown 目标进入 Wiki editor，其他目标走 Finder fallback。
- `AgentPaperIntentRouter` 新增 continuation intent；AI Lab 对“继续 / go on / continue”把上一 run 的 tool evidence 摘要注入 conversation context，避免默认重新完整读取论文。
- `ChatRenderer.bundle` 加入 pinned `dompurify.min.js`（DOMPurify 3.4.2）；`doc-preview.html` 在 `marked.parse` 后、KaTeX render 前进行 sanitize。
- 新增 manual run 记录：`docs/development/manual-tests/runs/2026-05-07_P39.15_AILabMarkdownWritebackBudget.md`。

待最终人工确认：

- ResearchWorkspace 5 个真实 prompt 的 GUI 回放仍需在 app 内执行并补齐结果。
- Xcode app build 仍需在本机 Xcode scheme 下确认。

---

## 6. Questions

1. “仅保存草稿”目标更偏向 `.sci-station/agent/drafts.json`，还是用户可见的 `wiki/drafts/<slug>.draft.md`？
2. `wiki/papers/<id>.md` 写回应默认 replace，还是如果文件存在则 append 到 `## AI Summary`？
3. Continuation 摘要注入保留多少上一轮 evidence 更合适：最近 3 条 toolResults，还是按 paper id 合并后的 8K 字符上限？
