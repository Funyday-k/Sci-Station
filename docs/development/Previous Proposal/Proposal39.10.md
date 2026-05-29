下面是我建议的 **新版 P39.10 / P39.11 / P39.12 三份任务书**，用于 **替换原来的 P39.10 和 P39.11**，并新增 P39.12。
这版不再把 UI、发布门禁、论文读取、provider 协议问题割裂处理，而是按真实故障链路重新排序：

1. **P39.10：先修 AI Lab 核心可对话能力**
2. **P39.11：再修论文读取、索引、legacy 路径和 paper QA**
3. **P39.12：最后做 UI、诊断、隐私、release gate 收口**

---

# 任务书 39.10：AI Lab 核心对话、工具循环与 thinking-mode Provider 稳定性修复

更新时间：2026-05-07
状态：Implemented / Validated
优先级：S1 / Release Blocking
替换范围：替代原 P39.10 中“UI polish 优先”的定位，把核心对话稳定性提前为 P39.10。

---

## 1. 背景

当前用户反馈中最严重的问题是：AI Lab 工具已经执行，例如 `list_papers`、`search_papers`，但模型无法继续生成最终回答，并报错：

```text
LLM request failed with HTTP 400:
The reasoning_content in the thinking mode must be passed back to the API.
```

源码显示，底层 `LLMChatMessage` 已经支持 `reasoningContent`，并编码为 `reasoning_content` [3]。OpenAI-compatible provider 也已经具备解析和回传 `reasoning_content` 的能力，本地证据包中已有对应测试记录 [2]。

但是 `AgentLoopRunner.executePaperPreflightIfNeeded()` 当前会在模型请求前主动运行 deterministic paper preflight，并构造 synthetic assistant tool-call message：

```swift
let assistantMessage = LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
```

这条消息带 `toolCalls`，但没有真实 `reasoningContent` [12]。对 DeepSeek / Qwen 这类 thinking-mode provider 来说，这可能违反其 tool-call replay 协议，导致后续请求被拒绝。

因此，P39.10 的核心目标不是 UI，而是 **保证 AI Lab 能稳定完成“用户问题 -> 工具读取 -> 模型最终回答”的闭环**。

---

## 2. 本轮目标

1. 修复 DeepSeek / Qwen thinking-mode 下工具回合后的 HTTP 400。
2. 保留 deterministic preflight，但不再把 preflight 伪装成 provider-native assistant tool transcript。
3. 确保 provider-native tool call 的 `reasoning_content` 不丢失。
4. 工具读取成功但 provider 失败时，必须给出可见、可重试、可诊断的 fallback。
5. 确保 Swift Loop 是最小稳定 runtime；sidecar 不可用时不阻断 AI Lab 普通使用。

---

## 3. 实施任务

### [P39.10.1] 重构 paper preflight 消息注入方式

当前 preflight 会把工具调用写入：

```text
assistant(tool_calls) -> tool(result)
```

这会造成 synthetic assistant tool-call transcript。

应改为：

```text
deterministic preflight tool results -> evidence context message
```

建议新增：

```swift
public struct AgentPreflightEvidenceEnvelope: Codable, Hashable, Sendable {
    public var toolName: String
    public var toolCallID: String
    public var argumentsJSON: String
    public var result: AgentToolResultWireFormat
}
```

preflight 执行结果仍写入：

- timeline
- session events
- run steps
- tool results

但发给 provider 的上下文改为普通 `user` 或 `system` evidence message：

```swift
messages.append(LLMChatMessage(
    role: .user,
    content: """
    Sci-Station deterministic preflight evidence has already been read from local read-only tools.
    Use this evidence to answer the latest user question.
    Do not treat it as provider-native tool-call transcript.

    \(evidenceJSON)
    """
))
```

禁止 preflight 再追加：

```swift
LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
```

---

### [P39.10.2] 增加 provider request sanitizer

在调用 provider 前，对 `LLMProviderRequest.messages` 做防御检查：

```swift
if message.role == .assistant,
   !message.toolCalls.isEmpty,
   message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
    // 对 thinking-mode provider 阻断或降级
}
```

验收要求：

- synthetic assistant tool-call message 不得进入 DeepSeek / Qwen thinking-mode 请求；
- provider-native assistant tool-call message 若来自真实模型，必须保留 `reasoningContent`。

---

### [P39.10.3] 保留 provider-native tool loop 的 reasoningContent

当前 provider-native loop 已经写了：

```swift
reasoningContent: response.message.reasoningContent
```

该路径应保留并增加测试 [12]。

新增测试：

```text
agentLoopRunnerPreservesReasoningContentForNativeToolCalls
openAIProviderPassesReasoningContentBackWithToolCalls
thinkingModePayloadRejectsAssistantToolCallsWithoutReasoning
```

---

### [P39.10.4] 修复 session event 中 reasoningContent 丢失隐患

当前 `appendAssistantEvent()` 只在 tool call 存在时编码 `message.toolCalls` [12]。如果未来从 session events 重建消息，会丢失 `reasoningContent`。

建议改为：

```swift
struct AgentAssistantMessageEventPayload: Codable {
    var content: String
    var reasoningContent: String?
    var toolCalls: [AgentToolCall]
}
```

并把 assistant event payload 改为完整 assistant message 摘要，而不是只存 tool calls。

---

### [P39.10.5] 统一 provider failure 可见 fallback

当前 `visibleProviderFailureResult()` 已经能在工具读取完成但 provider 失败时生成可见中文 fallback [12]。需要强化为产品路径：

```text
模型没有返回最终回复，但本次工具读取已经完成。
- 模型
- 失败原因
- 已使用工具
- 最后工具结果摘要
- 操作：重试 / 复制诊断 / 展开详情
```

要求：

- provider HTTP 400 不再表现为“没有回复”；
- 用户能看到工具已经读了什么；
- 可重试；
- 可复制脱敏诊断。

---

### [P39.10.6] Runtime fallback 状态明确化

`SidecarRuntimeCoordinator` 当前在 sidecar 不可用时会 fallback 到 Swift Loop [9]。P39.10 不要求修 sidecar，但要求：

- sidecar unavailable 不阻断 Swift Loop；
- fallback reason 在 diagnostics 中可见；
- UI 不应把 sidecar unavailable 显示成 AI Lab 全局不可用。

---

## 4. 验收标准

1. 使用 DeepSeek / Qwen thinking-mode 时，论文工具读取后不再出现：

```text
reasoning_content in the thinking mode must be passed back
```

2. provider request payload 中不再存在无 `reasoning_content` 的 synthetic assistant tool-call message。
3. `list_papers -> search_papers -> read_paper_section/read_paper -> final answer` 可以完整闭环。
4. provider 失败后有可见 fallback，而不是空回复。
5. Swift Loop 可作为稳定 fallback。
6. session event / run directory 不丢失重建运行所需的 assistant message 元信息。

---

## 5. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议新增自动化测试：

```text
agentLoopRunnerPreflightDoesNotEmitSyntheticAssistantToolTranscript
agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning
agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext
agentLoopRunnerPreservesReasoningContentForNativeToolCalls
agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools
```

手动测试：

```text
MT07-P39.10-01: DeepSeek thinking-mode 普通中文问候
MT07-P39.10-02: DeepSeek thinking-mode 列论文
MT07-P39.10-03: DeepSeek thinking-mode 第一篇论文摘要
MT07-P39.10-04: DeepSeek thinking-mode 蒸发率公式
MT07-P39.10-05: provider HTTP 400 后显示 fallback 和 retry
MT07-P39.10-06: sidecar unavailable -> Swift Loop fallback
```

---

## 6. 非目标

```text
不做 UI 全面 polish。
不修 legacy raw/papers 索引。
不做 release gate。
不新增多模态读图。
```

## 7. 本轮完成记录

更新时间：2026-05-07
状态：Implementation complete; validation passed.

已完成：

- deterministic paper preflight 不再注入 synthetic `assistant(tool_calls) -> tool(result)` provider transcript；preflight 工具结果改为普通 user evidence context。
- 新增 `AgentPreflightEvidenceEnvelope`，保留 tool name、call id、arguments 和 stable V1 tool result wire format。
- provider-native tool loop 继续保留真实模型返回的 `reasoningContent`，并新增 thinking-mode 回放测试。
- 新增 `LLMProviderRequestSanitizer`，对 DeepSeek/Qwen thinking-mode replay 中缺失 `reasoning_content` 的 assistant tool-call message 进行阻断，避免坏 payload 进入 provider。
- assistant session event payload 改为保存 content、reasoning_content、tool_calls，降低未来 replay 丢失 reasoning metadata 的风险。
- provider failure fallback 增加 retry / copy redacted diagnostics / expand details 操作提示，并保留已读取工具结果摘要。
- sidecar unavailable -> Swift Loop fallback 的 coordinator 测试增加 unavailable sidecar 场景，确保 fallback reason 可见且不阻断 Swift Loop。

新增/更新自动化覆盖：

```text
openAIProviderRejectsThinkingModeToolReplayWithoutReasoning
agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools
agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext
agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning
agentLoopRunnerPreservesReasoningContentForNativeToolCalls
sidecarRuntimeCoordinatorResolvesHealthAndSelection
```

验证结果：

```bash
swift run SciStationCoreTestRunner
# Passed. Initial rerun hit a transient "input file was modified during the build" race; immediate rerun passed.

xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
# Passed. Existing WebKit actor-isolation warnings remain in ChatMarkdownWebView.swift and are outside P39.10 scope.
```

---

# 任务书 39.11：论文读取、检索索引、legacy raw/papers 迁移与 Paper QA 稳定性修复

更新时间：2026-05-07
状态：Proposed
优先级：S1 / Release Blocking
替换范围：替代原 P39.11 的“发布门禁优先”定位，把论文问答链路修复提前为 P39.11。

---

## 1. 背景

当前用户反馈中，论文读取失败主要有四类问题：

### 1. legacy `raw/papers` 不可索引（不需要修复，目前已经按照新的目录去管理论文了）

---

### 2. `search_papers` 是字面搜索，不是语义搜索

`search_papers` 当前逐行执行：

```swift
line.range(of: query, options: options)
```

所以如果用户问：

```text
第一篇论文的摘要是什么
```

而 query 被处理成：

```text
论文的摘要是什么
```

在 `paper.md` 里搜不到是预期行为 [23]。

---

### 3. 摘要问题没有稳定 fallback

`AgentPaperIntentRouter` 能识别“第一篇”，会得到 `ordinalIndex = 0` [6]。但对“摘要”没有稳定映射为 `Abstract` section，导致仍可能走中文整句 search [6]。

`AgentLoopRunner` 当前逻辑中，如果 `read_paper_section` 可用，但没有 heading / line，就不会 fallback 到 `read_paper(page: 1)` [12]。

---

### 4. 图表、公式、图2/图3读取受 PDF 转 Markdown 质量限制

README 明确说明，高质量 PDF-to-Markdown 依赖 MinerU；没有 token 时使用 PDFKit fallback [34]。代码中也显示 MinerU 失败或无 token 时会走 `pdfkit_fallback` [32]。PDFKit fallback 主要读取 PDF 文本层，无法可靠读取图片、扫描页、复杂公式图和图表。

---

## 2. 本轮目标

1. 修复 `raw/papers/.../paper.md` 不可索引问题。
2. 建立 legacy raw paper 到 `library/papers` 的迁移路径。
3. 修复“第一篇论文摘要是什么”这类自然语言问题。
4. 修复 search 空结果后不读取正文的策略缺口。
5. 增强 `list_papers` payload，优先利用 metadata abstract。
6. 明确 PDFKit fallback / MinerU / 图像不可读边界。
7. 让检索索引状态可解释。

---

## 3. 实施任务



### [P39.11.3] 摘要意图识别

在 `AgentPaperIntentRouter.classify()` 中增加：

```swift
let wantsAbstract = containsAny(lowercased, ["abstract", "摘要"])
```

当用户问：

```text
第一篇论文的摘要是什么
```

应输出：

```swift
AgentPaperIntent(
    kind: .sectionSummary,
    ordinalIndex: 0,
    query: "abstract summary 摘要",
    sectionHint: "Abstract"
)
```

如果中文论文，也兼容：

```text
摘要
```

---

### [P39.11.4] search 空结果 fallback 到 read_paper

当前逻辑是：

```text
if read_paper_section available:
    if heading -> read section
    else if line -> read line range
else if read_paper available:
    read page 1
```

需要改成：

```swift
var didReadBody = false

if availableToolNames.contains("read_paper_section") {
    if let heading, heading != "Document" {
        // read section
        didReadBody = true
    } else if let line {
        // read line range
        didReadBody = true
    }
}

if !didReadBody, availableToolNames.contains("read_paper") {
    // read page 1
}
```

这样即使 `search_papers` 返回空，也能读第一页或摘要区域。

---

### [P39.11.5] `list_papers` payload 增加 abstract

当前 `paperPayload()` 没有包含 abstract [23]。但 `AgentPaperSnapshot` 和 Paper metadata 有 abstract 字段 [24]。

建议增加：

```swift
"abstract": .string(paper.abstract ?? "")
```

这样用户问摘要时，如果 `meta.yaml` 已有 abstract，模型可以直接回答或先引用 metadata abstract，再决定是否读取正文。

---

### [P39.11.6] 检索索引状态解释优化

当前默认 embedding identity 是：

```text
provider=swift-proxy
model_id=deterministic-fallback-v1
dimension=32
```

这是 deterministic fallback，不是真正高质量 embedding [8]。

UI 文案应区分：

```text
Ready: chunks > 0
Fallback: deterministic fallback / FTS-like weak retrieval
Error: selected source is not indexable
Disabled: embedding disabled; tools use FTS-only retrieval
```

如果出现：

```text
chunks=0
```

应提示：

```text
当前没有可检索文本块。请确认 paper.md 存在、路径可索引，并重新构建索引。
```

---

### [P39.11.7] paper.md 可读性检查

新增按钮：

```text
Check paper.md
```

检查项：

```text
paper.md 是否存在
paper.md 是否为空
extraction_engine 是 mineru_api 还是 pdfkit_fallback
是否包含 Abstract / 摘要
是否包含 Figure / Fig.
是否包含 $$ display math
是否有 figures/mineru assets
```

如果是 `pdfkit_fallback`，显示：

```text
当前 paper.md 来自 PDFKit fallback。图片、扫描页、复杂公式、图表可能不可读。建议配置 MinerU 或手动补充图注/公式到 annotations.md。
```

---

## 4. 验收标准

1. `raw/papers/.../paper.md` 不再触发：

```text
Selected source is not indexable
```

2. legacy raw paper 要么能迁移，要么能直接索引。
3. “第一篇论文的摘要是什么”必须稳定走：

```text
list_papers -> read_paper_section(Abstract) 或 read_paper(page: 1) -> final answer
```

4. search 空结果不会直接中断正文读取。
5. `list_papers` payload 包含 `abstract`。
6. 用户能看懂图2/图3读不到的原因。
7. `Rebuild Source` 后 `chunks > 0` 或给出明确错误原因。

---

## 5. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议新增自动化测试：

```text
authorizedResourceProviderIndexesLegacyRawPaperMarkdown
embeddingIndexControllerRebuildsLegacyRawPaperSource
legacyRawPaperMigrationCopiesToLibraryPapers
agentPaperIntentRouterMapsAbstractToAbstractSection
agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch
listPapersPayloadIncludesAbstract
paperMarkdownQualityInspectorDetectsPDFKitFallback
```

手动测试：

```text
MT07-P39.11-01: raw/papers 论文 Rebuild Source
MT07-P39.11-02: raw/papers -> library/papers 迁移
MT07-P39.11-03: 第一篇论文摘要
MT07-P39.11-04: 蒸发率公式
MT07-P39.11-05: search 空结果后 fallback read page 1
MT07-P39.11-06: PDFKit fallback paper.md 可读性提示
MT07-P39.11-07: MinerU 转换后图表资源存在
```

---

## 6. 非目标

```text
不实现多模态直接读图。
不接入新的远程 embedding provider。
不重写 PaperRepository。
不做 AI Lab UI 全面 polish。
不做最终 release gate。
```

---

# 任务书 39.12：AI Lab UI、诊断、隐私与发布门禁整合收口

更新时间：2026-05-07
状态：Proposed
优先级：S1 / Release Gate
新增任务书：承接原 P39.10 UI polish 与原 P39.11 release gate，但放到核心链路修复之后。

---

## 1. 背景

原 P39.10 重点是 UI：Markdown / LaTeX 渲染、气泡布局、Permission Dock、错误卡、SourceBlock 等 [35]。
原 P39.11 重点是 release gate：真实 provider matrix、runtime matrix、diagnostics bundle、privacy scan、manual evidence record [36]。

这两部分仍然必要，但必须放在 P39.10 / P39.11 核心修复之后。否则 UI 再好，AI Lab 仍可能：

- provider 400；
- 论文读不到；
- `raw/papers` 不可索引；
- `search_papers` 搜中文整句失败；
- 工具完成但最终回答为空。

因此 P39.12 是 AI Lab 进入 P40 前的最终收口任务。

---

## 2. 本轮目标

1. AI Lab 主对话界面可长期阅读。
2. Markdown / LaTeX / 表格 / 代码块正确渲染。
3. 工具事件、来源、审批、错误统一为可读卡片。
4. Runtime / Hook / MCP / Sidecar / Embedding 诊断默认折叠。
5. diagnostics bundle 可定位问题但不泄漏 key、Authorization、完整 prompt/response 或私有论文全文。
6. 建立 release checklist，明确是否允许进入 P40。

---

## 3. 实施任务

### [P39.12.1] AI 气泡启用 ChatRenderer / KaTeX

原任务指出：`ChatMarkdownWebView` 和 `ChatRenderer.bundle` 已经具备 marked + KaTeX 能力，但 AI 气泡仍在 legacy renderer 路径 [35]。

应改为：

```swift
if ChatMarkdownResources.isAvailable {
    ChatMarkdownWebView(markdown: markdown)
} else {
    AgentMarkdownLegacyText(markdown: markdown)
}
```

验收内容：

```text
inline math
display math
GFM table
code block
long path
Chinese paragraph
```

公式示例：

```text
$$
E_{\odot} = \sum_i \int_0^{R_{\odot}} s(r)n_{\chi}(r)4\pi r^2dr
$$
```

不得显示为转义长串。

---

### [P39.12.2] 建立 AI Lab UI Design Spec

新增：

```text
docs/development/AILabUIDesignSpec.md
```

至少定义：

```text
UserBubble
AssistantBubble
ToolEventRow
ApprovalCard
ErrorRetryCard
SourceBlock
RuntimeBadge
ComposerDock
EmptyState
DiagnosticsDisclosure
```

普通用户默认中文；内部诊断可保留英文，但必须折叠。

---

### [P39.12.3] Tool result SourceBlock

`search_papers`、`read_paper`、`read_paper_section` 已经返回 structured `payload` [23]。P39.12 要把 raw JSON 转成可读 source block。

对 `paper_search`：

```text
来源：paper_id / title / source / line / heading
片段：snippet
操作：打开 paper.md / 打开 PDF 页 / 复制引用
```

对 `paper_section`：

```text
来源：title / paper_id / source / heading / lines
正文：content 摘要
操作：展开全文 / 打开来源
```

---

### [P39.12.4] ApprovalCard 替代 Permission Dock

原 P39.10 已要求 Permission Dock 改为 timeline card [35]。

新卡片命名：

```text
待确认操作
```

显示：

```text
工具名
用途
读/写性质
风险等级
目标路径
参数摘要
允许一次
拒绝并停止
拒绝并继续
修改参数
```

审批完成后折叠为 audit row，不继续占据 composer 上方空间。

---

### [P39.12.5] ErrorRetryCard

统一 provider failure、tool failure、runtime fallback 错误展示。

示例：

```text
标题：模型生成失败，但工具读取已完成
原因：HTTP 400 / empty response / provider timeout
已使用工具：list_papers, search_papers, read_paper_section
最后工具摘要：...
操作：重试 / 复制诊断 / 展开详情
```

P39.10 中 `visibleProviderFailureResult()` 生成的 fallback 应接入这个 UI 卡片 [12]。

---

### [P39.12.6] 归档线程 UI 防御

`AgentThreadRepository.allThreads()` 默认 `includeArchived: true` [18]。
`SciStationAgentService.allThreads(in:)` 当前没有暴露 `includeArchived` 参数，会直接调用默认全集 [31]。

建议改为：

```swift
public func allThreads(
    in root: ResearchRoot,
    includeArchived: Bool = false
) async throws -> [AgentThread] {
    try await threadRepository.allThreads(in: root, includeArchived: includeArchived)
}
```

普通 AI Lab UI 必须使用：

```swift
includeArchived: false
```

点击 AI Lab 时增加防御：

```swift
if activeAgentThread?.isArchived == true {
    activeAgentThreadID = nil
    pendingAgentThread = nil
}
```

归档线程相关 draft 也建议清理：

```swift
removeDraft(projectID: thread.projectID, threadID: thread.id)
```

---

### [P39.12.7] Runtime diagnostics disclosure

普通 header 只显示：

```text
模式
范围
状态
模型简称
```

高级诊断折叠：

```text
provider/model
runtime selection
effective runtime
sidecar health
hooks
MCP
embedding status
tools enabled
run id
thread id
```

sidecar unavailable 要显示为：

```text
已回退到 Swift Loop
```

而不是“AI Lab 不可用”。

---

### [P39.12.8] Diagnostics bundle

基于 `AgentRunDirectoryStore` 现有 debug bundle / redaction 设计 [14]，正式接入 UI。

默认允许导出：

```text
app_version
run_id
thread_id
provider_kind
model_id
base_url_domain_only
runtime_selection
effective_runtime
sidecar_health
embedding_status
enabled_tools
tool_sequence
failure_category
last_tool_summary
redacted_error_message
```

默认禁止导出：

```text
API key
Authorization
Bearer token
完整 prompt
完整 response
完整 paper.md
完整 tool payload content
.env
Keychain
私有路径清单
```

README 也明确要求 API keys、OAuth tokens、client secrets、private research data 不应进入仓库或构建产物，LLM key 和 MinerU token 应保存到 Keychain [34]。

---

### [P39.12.9] Release checklist

新增：

```text
docs/development/AILabReleaseChecklist.md
docs/development/manual-tests/runs/YYYY-MM-DD_P39.12_AILabReleaseGate.md
```

结论必须三选一：

```text
允许进入 P40
暂缓进入 P40
仅允许 P40 非 AI 可见部分
```

---

## 4. 验收标准

1. AI 回复 Markdown、列表、表格、代码块、inline math、display math 可读。
2. 中文长回答不是一整段墙。
3. 工具结果显示为 SourceBlock，不再主要展示 raw JSON。
4. 审批操作作为 timeline card 展示，审批后折叠为 audit row。
5. provider failure 有 retry 和 copy diagnostics。
6. Runtime/Hook/MCP/Sidecar/Embedding 信息默认折叠。
7. 归档全部线程后，点击 AI Lab 不再显示已归档聊天。
8. diagnostics bundle 不含 API key、Authorization、完整私密文本。
9. release checklist 给出明确 P40 结论。

---

## 5. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

手动测试矩阵：

```text
MT07-P39.12-01: 普通中文聊天
MT07-P39.12-02: 论文列表
MT07-P39.12-03: 第一篇论文摘要
MT07-P39.12-04: 蒸发率公式，含 display math
MT07-P39.12-05: 图2/图3不可读时给出 paper.md/MinerU/PDFKit 解释
MT07-P39.12-06: Tool SourceBlock 展开/折叠
MT07-P39.12-07: 写 wiki 等待确认
MT07-P39.12-08: provider failure retry
MT07-P39.12-09: sidecar unavailable -> Swift Loop fallback
MT07-P39.12-10: 全部归档后打开 AI Lab 不显示归档线程
MT07-P39.12-11: 复制诊断无 secret
MT07-P39.12-12: 900px 窄窗口布局不破
MT07-P39.12-13: 深色模式可读
MT07-P39.12-14: App restart 后 thread/run replay 正常
```

---

## 6. 非目标

```text
不新增 AI 工作流。
不实现多模态直接读图。
不强制 LangGraph 成为唯一 runtime。
不把 AI Lab 默认开放给所有新 workspace。
不导出包含 secret 或完整用户资料的 debug bundle。
```

---

# 推荐执行顺序

```text
P39.10 -> P39.11 -> P39.12
```

原因：

1. **P39.10 先保证 AI Lab 能完成对话闭环**
   否则 DeepSeek thinking-mode 仍可能在工具后 HTTP 400。

2. **P39.11 再保证论文真的能读、能索引、能回答摘要/公式**
   否则 AI Lab 能说话，但不能可靠做论文问答。

3. **P39.12 最后做 UI、诊断、隐私和 release gate**
   这一步决定是否允许进入 P40。

最终 gating 建议：

```text
P39.10 未通过：AI Lab 不可进入 P40。
P39.11 未通过：AI Lab 不能作为论文问答功能对外试用。
P39.12 未通过：AI Lab 只能保留实验入口，不能作为默认可见模块。
```