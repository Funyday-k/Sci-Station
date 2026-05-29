# 任务书 39.15：AI Lab 全流程修复 — Markdown 渲染、写回 Wiki、上下文预算与离线预览

更新时间：2026-05-07
状态：Implemented / Awaiting Xcode + Manual Gate
优先级：S0 / Release Blocker (用户反馈：AI Lab 不可用)
承接：P39.13 收口归档/序数/Debug；P39.14 修复 chat raw payload、`paper.md` 打开为空、`chunks=0` 诊断；本轮针对 ResearchWorkspace 实测日志暴露的“写回 wiki 失败、回答用大段 LaTeX 看不到、Tool budget 提前结束”三类用户体验问题做系统修复。

---

## 1. 背景与用户反馈

用户在 ResearchWorkspace（`/Users/funyday/Documents/ResearchWorkspace`）多次实测后反馈：

> 我目前对于 AI Lab 的功能实现表示非常不满意，同时 markdown 渲染也有问题，我交给他任务，无法正常完成。

读取该 workspace 下的 18 条 run（`/.sci-station/agent/runs.jsonl`）、AI Lab 会话事件（`session_events.jsonl`）、Debug 日志（`.sci-station/debug/app_events.jsonl`）和单次 run 的 `events.jsonl`，可以把“AI Lab 不可用”的体感拆成下面 4 个独立但互相放大的 bug。

| # | 用户主诉 | 真实失败/降级 | 证据来源 |
|---|---|---|---|
| A | “公式看不见，给的回答里全是 `$$…$$`” | AI Lab 聊天气泡只走 `AttributedString(markdown:)`，KaTeX/GFM table/fenced code 全部丢失 | `Sci-Station/UI/AILabWorkspaceView.swift:1319-1353`；`ChatMarkdownWebView.swift` 在产品代码中 0 处调用 |
| B | “任务无法正常完成（写进 wiki 里、写进 wiki / 总结放进 wiki）” | 3 次 `provider_error`，分别是 JSON parse failure 与 LLM empty response；写回路径只允许 `wiki/plans/`，且 plan 模式没有降级到 draft+审批 | `runs.jsonl` 里 run `…073e783f`、`…df80327b`、`…c687b2a1`；`AgentBuiltInTools.swift:441-526`；`AgentPlanParser.swift:12-30` |
| C | “继续 / evaporation rate? 中间就停了” | `Agent loop stopped because context or tool result budget was exceeded`：默认 `maxAccumulatedToolResultCharacters = 40_000`、`maxSteps = 8` 对论文 QA 太紧 | `runs.jsonl` 里 run `…17cfc12cc4eb`、`…7e08a153d2d8`；`AgentLoopModels.swift:486-501` |
| D | “Wiki / Library 打开 paper.md 时公式也乱” | `MarkdownPreviewView` 走 `cdn.jsdelivr.net` 拉 KaTeX/marked，且没有用本地已经打包的 `ChatRenderer.bundle/`；离线、严格网络策略或 hardened-runtime 沙盒下都会回落到纯文本 | `Sci-Station/UI/MarkdownPreviewView.swift:44-145`；`Sci-Station/Resources/ChatRenderer.bundle/` |

四类问题加在一起的体感，就是用户截图里看到的：明明 agent 的 `final_response` 在 JSONL 里是格式化非常好的 Markdown + KaTeX，但 UI 里看不见公式、看不见表格；写 wiki 失败时 chat 里只有一行红字“运行失败”，没有保留 draft 也没有可审批入口；多读两次论文就被 budget 切断。

---

## 2. 本轮目标

用户实施意见（2026-05-07）：

1. `wiki/papers/<id>.md` 与现有 Generate Wiki Page 共用路径可以接受，本轮按同一路径实现。
2. 多个 chat bubble 同时使用 WebKit 时，当前先采用最近 20 条 assistant rich Markdown 气泡上限，旧气泡回退 legacy text。
3. Tool/context 限制直接调大：`maxSteps = 20`，context/累计工具文本 = 1M，单次工具输出 = 384K，LLM 默认 `max_tokens = 384K`。

1. **AI Lab Markdown 渲染**：让 `final_response` 真正经过 `ChatRenderer.bundle/`（KaTeX + marked + GFM）渲染，离线可用，公式 / 表格 / 代码块全可见。
2. **写回 Wiki 全链路**：在 plan 模式下补一条“writeback safe-fallback”，遇到 provider JSON parse 失败或 empty response 不再吞掉用户上文；同时把写入路径从 `wiki/plans/` 扩展到 `wiki/papers/<paper_id>.md` / `wiki/notes/...`，仍然走 Permission Dock 审批。
3. **Tool / 上下文预算**：把论文 QA 默认预算调到“一次能读完 2-3 段 + 一篇 paper page-1”的水平；预算耗尽时不要直接 `provider_error`，而要把已读到的工具证据合成 final response。
4. **离线 Markdown 预览**：让 `MarkdownPreviewView` 复用 `ChatRenderer.bundle/`（或同等的本地资源），不再依赖 CDN。
5. **核心测试 + ResearchWorkspace 真实复现路径**：每个修复都要有自动化覆盖，并补一条 MT07 用例，避免回归。

---

## 3. 证据 — 来自 ResearchWorkspace 的日志

### 3.1 全部 18 个 run 的真实分布

```text
1  failed provider_error  「我的论文有什么」          → 请先填写 LLM API Key
2  completed              「你好」
3  completed              「第三篇文章里的蒸发率公式是什么？」  ← Markdown + 公式回答
4  completed              「evaporation rate?」
5  failed provider_error  「evaporation rate?」      → context/tool budget exceeded
6  failed provider_error  「继续」                   → context/tool budget exceeded
7  completed              「总结一下第三篇文章」
8  failed provider_error  「写进wiki里」              → JSON 无法解析
9  completed              「第三篇文章里的蒸发率的表达式是什么」
10 completed              「都有什么文章？」
11 completed              「第三篇的文章的蒸发率公式是什么」
12 failed provider_error  「对这个文章做一个总结放进wiki里」 → LLM empty response
13 failed provider_error  「对这个文章做一个总结放进wiki里」 → LLM empty response
14 completed              「简单的给我一个计算蒸发率的公式」
15 completed              「公式是什么？」
16 completed              「公式是什么？」
17 completed              「公式是什么？」
18 completed              「蒸发率的公式是什么？」
```

8 / 18 是失败 run；剩下 10 个 “completed” 的 run 在 `events.jsonl` 中虽然产生了高质量 Markdown + KaTeX，但 UI 端 chat 气泡渲染层把 `$$…$$`、表格、列表统统打回原形，所以即便服务端成功，用户主观也会觉得“没成功”。

### 3.2 Bug A — 渲染降级到 `AttributedString(markdown:)` 的代码定位

```1319:1353:Sci-Station/UI/AILabWorkspaceView.swift
private struct AgentMarkdownBubbleText: View {
    @EnvironmentObject private var appModel: AppViewModel

    let markdown: String
    let isError: Bool

    var body: some View {
        let fontSize = appModel.workspacePreferences.agentChatFontSize
        AgentMarkdownLegacyText(markdown: markdown, fontSize: fontSize, isError: isError)
    }
}

private struct AgentMarkdownLegacyText: View {
    let markdown: String
    let fontSize: Double
    let isError: Bool

    private var attributedText: AttributedString? {
        try? AttributedString(markdown: markdown)
    }
    // ...
}
```

`Sci-Station/UI/ChatMarkdownWebView.swift` 提供了基于 WebKit + 本地打包 KaTeX 0.16.11 + marked 14.1.3 的渲染器（`Sci-Station/Resources/ChatRenderer.bundle/`），但全代码库只有 `BUNDLING.md` 文档提到，**没有任何 view 调用** `ChatMarkdownWebView(markdown:fontSize:isError:)`。所以：

- 行内 `$E_{\odot}$` 直接以 `$E_{\\odot}$` 字面量显示。
- `$$ … \tag{6} $$` 公式块原样存在。
- GFM 表格 `| 符号 | 含义 |` 退化成竖线分隔的纯文本行。
- ` ```python ` 代码块边界变成普通文本。

### 3.3 Bug B — 写回 wiki 三类失败

`runs.jsonl` 里写回相关 run 的具体 `plan.summary`：

```text
agent-run-…073e783f  「写进wiki里」              → "AI 返回的 JSON 无法解析：The data couldn't be read because it isn't in the correct format."
agent-run-…df80327b  「对这个文章做一个总结放进wiki里」 → "LLM provider returned an empty response."
agent-run-…c687b2a1  「对这个文章做一个总结放进wiki里」 → "LLM provider returned an empty response."
```

成因有 3 层：

1. **路径不可达**：`WriteMarkdownPlanAgentTool` 是当前唯一的 workspace-write 工具，强制 `relative_path` 必须以 `wiki/plans/` 开头（`Sci-Station/Agent/AgentBuiltInTools.swift:492-505`）。用户希望写到 `wiki/papers/garani2017-dark-matter-sun.md`、`wiki/notes/...` 都不被允许；模型无路可走，要么放弃，要么生成被拒的 path。
2. **plan 模式严格 JSON**：`AgentPlanner.parsedPlan` → `AgentPlanParser` 对 plan 模式（`allowsPlainTextResponse=false`）必须收到合法 JSON；模型在“写到 wiki”这种隐式 follow-up 上很容易回成纯 Markdown，触发 `invalidJSON("...isn't in the correct format")` 失败。
3. **empty response 直接吞 draft**：`AgentLoopRunner` 在 `response.toolCalls.isEmpty && content.isEmpty` 时调用 `visibleProviderFailureResult`；但 `visibleProviderFailureResult` 仅在 `toolResults` 不为空时才生成 fallback 文案（`AgentLoopRunner.swift:951-981`）。如果模型一开始就空回（如 reasoning_content-only 的模型、或者模型还没决定调用工具就被截断），fallback path 不触发，run 直接 `provider_error`，draft 文案、上一步的“总结”全部丢失。

### 3.4 Bug C — Tool 预算太紧

```486:512:Sci-Station/Agent/AgentLoopModels.swift
public nonisolated init(
    maxSteps: Int = 8,
    maxToolCalls: Int = 16,
    maxContextCharacters: Int = 80_000,
    maxToolResultCharactersPerCall: Int = 12_000,
    maxAccumulatedToolResultCharacters: Int = 40_000,
    autoApproveReadOnly: Bool = true,
    allowProviderNativeTools: Bool = true
) {
```

实际 ResearchWorkspace run `…17cfc12cc4eb`（“evaporation rate?”）的 `plan.steps`：

```text
Step 1: tools list_papers
Step 2: tools search_papers
Step 3: tools read_paper            ← 8000 字符
Step 4: tools search_papers
Step 5: tools read_paper_section    ← 12000 字符
Step 6: tools search_papers
Step 7: tools read_paper_section    ← 12000 字符
Step 8: tools read_paper            ← 8000 字符
Step 9: Agent loop stopped because context or tool result budget was exceeded.
```

`8000+12000+12000+8000 = 40_000` 正好等于 `maxAccumulatedToolResultCharacters` 默认值 → 9 步直接被切。`继续`（run `…7e08a153d2d8`）只跑了 5 步就被切，因为 history 里已经累计了上一轮的 tool 输出。

### 3.5 Bug D — Markdown Preview 走 CDN

```44:145:Sci-Station/UI/MarkdownPreviewView.swift
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css">
…
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/contrib/auto-render.min.js"></script>
```

调用方包括 `MarkdownEditorView` (Wiki 编辑/预览)、`MaterialsView`、`ProjectOverviewView`。一旦离线、被防火墙拦截或 hardened-runtime 配合更严格的 sandbox 时，900 ms 超时后回落到 `pre.fallback`，公式 / 数学 / 表格全没。已经在 `ChatRenderer.bundle/` 离线打包好的 KaTeX 0.16.11 + marked 14.1.3 + auto-render 没有被复用。

---

## 4. 实施任务

### [P39.15.1] AI Lab 聊天气泡接入 ChatMarkdownWebView（Bug A）

文件：`Sci-Station/UI/AILabWorkspaceView.swift`、`Sci-Station/UI/ChatMarkdownWebView.swift`。

- 把 `AgentMarkdownBubbleText` 改成：当 `ChatMarkdownResources.isAvailable` 时使用 `ChatMarkdownWebView(markdown: detail, fontSize: fontSize, isError: isError)`；否则才走 `AgentMarkdownLegacyText` 兜底（保留它给单元测试 host 用）。
- 测试 host（SciStationCoreTestRunner）继续走 legacy 分支；`ChatMarkdownResources.isAvailable` 决定。
- `streamingResponse`、`pendingPrompt`（user message）也复用 `ChatMarkdownWebView`：
  - user message 仍可走轻量；但 assistant message + final_response_draft 必须走 web view。
- 给 web view 增加 `selectionTextProvider`（已有 `webView.allowsMagnification` / `selectable`），并让“复制”按钮直接复制 `markdown` 源串（已实现，无回归）。
- 验证 `evaluateJavaScript` push 增量时与 `streamingResponse` 同步无回退闪烁。

风险：`WKWebView` 在大量气泡叠加时内存占用上升；通过 `dismantleNSView` + `userContentController.removeScriptMessageHandler` 路径已有清理（见 `ChatMarkdownWebView.swift:30-54`），但要补一个“最多保留最近 N 条 web bubble，老消息回退到 legacy text”的策略以保证滚动顺畅。

### [P39.15.2] Wiki Writeback Safe Fallback + 路径扩展（Bug B）

#### B-1 把 wiki 写回路径白名单从 `wiki/plans/` 扩到“wiki/{plans|papers|notes|projects}”

文件：`Sci-Station/Agent/AgentBuiltInTools.swift`。

- 把 `WriteMarkdownPlanAgentTool` 拆/扩成 `WriteWikiMarkdownAgentTool`（保留旧 `write_markdown_plan` 名字以兼容 plan 模式 mode allowedToolNames），允许的目录前缀：
  - `wiki/plans/`（计划，原行为）
  - `wiki/papers/`（按论文 id 写一篇 wiki，例如 `wiki/papers/garani2017-dark-matter-sun.md`）
  - `wiki/notes/`（自由 note）
  - `wiki/projects/`（项目 wiki）
- 拒绝逃逸：保留 `..` / 绝对路径 / 非 `.md` 检查；新增 paper id 校验（必须存在于当前 workspace 的 `paper_index.yaml`）。
- `risk: writesWorkspace`，`requiresConfirmation: true` 不变；通过 Permission Dock 审批。

#### B-2 plan 模式 JSON parse 失败 → draft + retry path

文件：`Sci-Station/Agent/AgentPlanParser.swift`、`Sci-Station/Agent/AgentPlanner.swift`、`Sci-Station/App/AppViewModel.swift`。

- `AgentPlanParser` 已经有 `AgentVisibleResponseExtractor.visibleText`；扩成：
  - 如果 response 不含合法 JSON 但本身是 Markdown，且 mode == plan 且 user_goal 命中 writeback 关键词（“写进”、“写到”、“写入”、“放进”、“save to”、“add to”），不立刻报错，而是返回一个 fallback `AgentPlan`：
    - `title = "未确认的写回草稿"`
    - `summary = visibleText`（即模型纯文本）
    - `tool_calls = []`（必要时 best-effort 通过 `AgentPaperIntentRouter` 解出目标 path 并预填一个 `write_markdown_plan` call，但保持 `requiresConfirmation: true`）
    - `final_response_draft = visibleText`
- 用户在 AI Lab 看到的不是“运行失败”，而是“草稿就绪 + 写入审批”按钮。

#### B-3 LLM empty response 不丢草稿

文件：`Sci-Station/Agent/AgentLoopRunner.swift`。

- 把 `visibleProviderFailureResult` 的 `guard !toolResults.isEmpty else { return nil }` 改成 `guard !toolResults.isEmpty || !messages.isEmpty else { return nil }`，允许在空 toolResults 时仍合成一个 final markdown：
  - 复用最近一次 user message 与 assistant message 作 context，提示“provider 返回空回复，但保留了你上一轮的 summary draft，可重试 / 复制 / 调小 prompt”。
  - 同时把 draft 保存到 `.sci-station/agent/drafts.json`，避免下一次 New Chat 又丢。

#### B-4 写回 UI：草稿 / 审批 / 写入三段式

文件：`Sci-Station/UI/AILabWorkspaceView.swift`。

- 当某个 run 的 `plan.tool_calls` 含 `write_markdown_plan` / `write_wiki_markdown` 时：
  - 在 timeline 里显示“拟写入路径 + body 预览（折叠）”，复用现有 `AgentRuntimeEventRow.payloadPreview`。
  - 给“批准并写入 / 仅保存草稿 / 拒绝”三个按钮（现有 Permission Dock 只有 allow/deny；本轮加“仅保存草稿到 .draft.md”的 saveDraft path，复用 `LLMWritebackService.LLMWritebackMode.saveDraft`）。
  - 写入完成后在 chat 内插入“已写入 wiki/papers/…md（点击打开）”链接条目。

### [P39.15.3] 论文 QA 默认预算 + budget 触发后的 graceful summarization（Bug C）

文件：`Sci-Station/Agent/AgentLoopModels.swift`、`Sci-Station/Agent/AgentLoopRunner.swift`、`Sci-Station/Workspace/WorkspacePreferences.swift`。

- 把 `AgentLoopOptions` 默认值调整为：
  - `maxSteps: 20`
  - `maxToolCalls: 80`
  - `maxContextCharacters: 1_000_000`
  - `maxToolResultCharactersPerCall: 384_000`
  - `maxAccumulatedToolResultCharacters: 1_000_000`
  - `LLMConfiguration.maxTokens: 384_000`
- 把这 5 个值暴露成 `WorkspacePreferences.agentLoopBudget`（schema_version 升级 +1，向后兼容默认值），UI 在 Settings → AI Lab 加一段“高级 / 工具预算”可调。
- `continueLoop` 在 budget 触发分支已有 `visibleLoopBudgetResult`；要改为：
  - 即便 `toolResults` 为空也 fallback（同 B-3）。
  - fallback 文案带“已截断证据 + 建议下一步问题”指引，而不是只一行错误。
- 对 follow-up “继续” / “go on” 命令，`AgentPaperIntentRouter` 增加 continuation 识别，把上一 run 的 toolResults 按 paper id 摘要后以 system message 形式 inject，避免重新跑全套 read_paper。

### [P39.15.4] 离线 Markdown Preview（Bug D）

文件：`Sci-Station/UI/MarkdownPreviewView.swift`、`Sci-Station/UI/ChatMarkdownWebView.swift`、`Sci-Station/Resources/ChatRenderer.bundle/`。

- 把 `MarkdownPreviewView` 改成 `loadFileURL(...)` 模式：
  - 加一个新的 `MarkdownDocPreview/index.html`（可与 chat renderer 共用 marked.min.js / katex.min.js / katex.min.css，新增 `dompurify.min.js` 离线版到 bundle），或者把现有 `index.html` 抽象成 `chat.html` + `doc.html` 两个模板。
  - `<script src="marked.min.js">` / `<script src="katex.min.js">` / `<link href="katex.min.css">` 全部改本地相对路径。
  - `body` 渲染外加 `baseURL`（论文目录）以便 `figures/...` 图片相对路径不再失效。
- CDN URL 完全移除（用 `WebFetch` 或 `network.client.outgoing` 检测时不再有 jsdelivr.net 出站）。
- 无网络 / 严格 sandbox 下也能渲染数学公式 + 表格 + 代码块。

### [P39.15.5] 测试与 Manual Gate

#### 自动化（`Tools/SciStationCoreTestRunner/main.swift` 与 Swift Tests）

新增覆盖：

1. `WriteWikiMarkdownAgentToolTests`：白名单允许 `wiki/papers/<id>.md`、`wiki/notes/foo.md`，拒绝 `wiki/../etc.md`、绝对路径、非 paper id。
2. `AgentPlanParserWritebackFallbackTests`：当 plan mode 收到纯 Markdown response 且 goal 含“写进 wiki”时，返回 fallback plan（保留 visibleText 作 final_response_draft）。
3. `AgentLoopRunnerEmptyResponseFallbackTests`：模拟 provider empty response + 空 toolResults，确认 final markdown 仍包含上一轮 draft 与 retry hint。
4. `AgentLoopBudgetDefaultsTests`：默认 budget 至少能跑完 list_papers → 2× read_paper → 2× read_paper_section 不被截断。
5. `ChatMarkdownWebViewIntegrationTests`：在 host 可用时返回 web view；不可用时返回 legacy；fontSize / isError 正确传递。

#### Manual UI（`docs/development/manual-tests/MT07_AILab.md` + `runs/2026-05-07_P39.15_*.md`）

新增条目（追加到 P39.15 子段）：

```text
MT07-P39.15-01: AI Lab 聊天气泡里 $$E_{\odot}=...$$ 渲染为公式，不再是字面量
MT07-P39.15-02: 表格 | 符号 | 含义 | 渲染为表格，不再是竖线纯文本
MT07-P39.15-03: ```python``` 代码块在气泡内有等宽字体 + 边框
MT07-P39.15-04: 输入“总结这篇文章并写入 wiki/papers/<id>.md”，Permission Dock 出现，批准后真的产生 wiki/papers/<id>.md
MT07-P39.15-05: provider 故意返回空回复时，AI Lab 出现“provider 返回空回复 + 保留草稿”而不是“运行失败”
MT07-P39.15-06: 论文 QA 连续 6+ 次 read_paper / read_paper_section 不被 budget 切断；超过 budget 时 fallback final answer 而非 provider_error
MT07-P39.15-07: 离线打开 Wiki 编辑器中含 $$...$$ 的 paper.md，公式仍能渲染
MT07-P39.15-08: 删除工作区/网络断开后，Markdown Preview 不再去 jsdelivr.net；本地 KaTeX/marked 仍工作
```

ResearchWorkspace 真实回放（每个修复都要在该工作区真复现）：

1. 运行 run 5/6 的相同 prompt，确认 budget 足够 / 截断时也有回答。
2. 运行 run 12/13 的“总结放进 wiki 里”，确认走 Permission Dock，未审批时 draft 仍保留、审批后真正写入。
3. 离线（关 WiFi）打开 Wiki 中任意含公式的 paper.md，确认公式与表格正确。

### [P39.15.6] 文档与回归

- 更新 `docs/development/manual-tests/MT99_ReleaseRegression.md`：在 “AI Lab markdown” 与 “wiki writeback” 段落明确把以上 8 条作为 release blocker。
- 更新 `Sci-Station/Resources/ChatRenderer.bundle/BUNDLING.md`：标注既给 chat 也给 doc preview 共用，并加一节“dompurify.min.js 同步”。

---

## 5. 验收标准

1. AI Lab chat 气泡里 `$E$` / `$$...$$` / GFM 表格 / 代码块都正确渲染（MT07-P39.15-01..03 通过）。
2. “总结这篇文章并写入 wiki” 在用户审批后真的产出 `wiki/papers/<id>.md`，未审批时 draft 不丢失（MT07-P39.15-04..05 通过）。
3. 论文 QA 连续多次工具调用不被 budget 提前切断；budget 真的耗尽时 fallback 文案而非 `provider_error`（MT07-P39.15-06 通过）。
4. Wiki 编辑预览离线状态下数学公式仍渲染；进程级 outgoing 网络无 jsdelivr.net（MT07-P39.15-07..08 通过）。
5. `swift run SciStationCoreTestRunner` 与 `xcodebuild` 全绿。
6. `runs.jsonl` 真实回放：5 个曾经 `provider_error` 的 prompt 重跑，至少 4 个变成 `completed`，剩下 1 个也只是因模型选择问题，不是 budget / parser / empty fallback 缺失。

---

## 5.1 本轮实施记录（2026-05-07）

已完成：

- AI Lab assistant 气泡接入 `ChatMarkdownWebView`，最近 20 条 assistant rich Markdown 气泡使用 WebKit，本地资源不可用或超出上限时回退 legacy text。
- `MarkdownPreviewView` 改为加载 `ChatRenderer.bundle/doc-preview.html`，移除 jsdelivr CDN，复用本地 `marked.min.js`、`katex.min.js`、`auto-render.min.js` 与 `katex.min.css`。
- `WriteWikiMarkdownAgentTool` 新增，`write_markdown_plan` 兼容保留；路径白名单扩到 `wiki/plans/`、`wiki/papers/`、`wiki/notes/`、`wiki/projects/`，`wiki/papers/<id>.md` 校验当前 paper index。
- Plan 非 JSON 写回回复通过 `AgentPlanParser.writebackFallbackPlan` 变为“未确认的写回草稿”，不再直接 JSON parse failure。
- Empty provider response / context budget fallback 支持无工具结果但有上下文的可见 final Markdown，并在 provider fallback 时写入 `.sci-station/agent/drafts.json`。
- `AgentLoopOptions` 与 `LLMConfiguration.maxTokens` 默认值按用户意见放大；Settings → AI Lab 增加 Tool Budget 编辑与 Reset。
- `swift run SciStationCoreTestRunner` 已通过。

明确转入 P39.16 的剩余项：

- Permission Dock 三段式“批准并写入 / 仅保存草稿为 .draft.md / 拒绝”的专门 UI 仍需收口；本轮保留现有审批与草稿仓库 fallback。
- Follow-up “继续 / go on” 的上一轮 toolResults 摘要注入尚未实现。
- `dompurify.min.js` 尚未打入 bundle；当前 doc preview 已无 CDN，但 sanitizer 仍作为 P39.16 安全强化项。
- ResearchWorkspace 真实回放和断网手动验证需在 Xcode build 后执行并记录 run 报告。

---

## 6. Questions / 风险

1. 已决：`wiki/papers/<id>.md` 与现有 Generate Wiki Page 共用同一路径，本轮由 paper id 校验保护。
2. 已决：当前先采用 20 条 assistant rich Markdown 气泡上限，旧气泡回退 legacy text；如手动测试发现 WebKit 内存异常，再做 LRU/pool。
3. 已决：预算按用户意见调大，并在 Settings → AI Lab → Tool Budget 暴露 reset。
4. 待 P39.16：写回 UI 的“仅保存草稿为 .draft.md”、continuation 摘要注入、DOMPurify 本地打包与 ResearchWorkspace 回放报告。

---

## 7. 与 P39.14 的关系

- P39.14 修复了：chat raw payload preview、library `paper.md` 打开后跳 Wiki 为空、`chunks=0` 诊断。
- P39.15 不重做这些；只在 timeline 里增加 wiki writeback approval / draft 行（P39.14 已有 raw payload 隐藏，writeback draft 复用同一渲染器）。

---

## 8. 关键代码定位（评审参考）

- AI Lab 聊天气泡降级：`Sci-Station/UI/AILabWorkspaceView.swift:1319-1353`
- 离线 chat renderer：`Sci-Station/UI/ChatMarkdownWebView.swift`、`Sci-Station/Resources/ChatRenderer.bundle/index.html`
- 写回工具：`Sci-Station/Agent/AgentBuiltInTools.swift:441-526`
- Plan 解析：`Sci-Station/Agent/AgentPlanParser.swift:1-77`、`AgentPlanner.swift:99-118`
- Loop budget：`Sci-Station/Agent/AgentLoopModels.swift:486-512`、`AgentLoopRunner.swift:660-700`
- Fallback 文案：`Sci-Station/Agent/AgentLoopRunner.swift:896-1022`
- CDN Markdown 预览：`Sci-Station/UI/MarkdownPreviewView.swift:36-149`
- 用户 loop policy：`Sci-Station/App/AppViewModel.swift:3676-3688`
