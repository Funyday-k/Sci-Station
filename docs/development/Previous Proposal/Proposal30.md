# 任务书 30：AI Lab Agent Platform Completion

更新时间：2026-05-02（方向重定）

> 本轮任务在原版基础上整体重写。原计划聚焦 MinerU UX 回归与 workspace 清理，但用户实测发现 AI Lab 当前 agent 在三个核心维度都不达标：输出质量、工具自主调用、对话历史的工作区语义。任务书 30 重新对齐为「补齐 agent 功能」，把任务书 28-29 留下的 platform 中间件骨架推到能用的状态，并据此调整下一轮任务节奏。

## 1. 背景与三个用户报告问题

1. **输出不可读 / 公式无法渲染 / agent 流程不完整**。AI Lab 回答以纯文本块呈现：没有自然段落、没有 GFM 渲染、$...$ 与 $$...$$ 不渲染、未先思考是否调用工具，而是把所选论文 markdown 一股脑塞进 prompt。用户期望的形态是 OpenCode 那样：模型先评估问题 → 决定要不要 `read_paper`、`read_paper_section`、`search_papers` → 拿到工具结果再继续。
2. **system prompt / skill / hooks 不完善**。当前 prompt 不要求 markdown 段落、不要求 LaTeX 公式分隔符、不引导优先调用工具；skill 只在 UI 显示元数据；hooks 只是几条提醒文案；MCP 只在设置面板可视化，没接入 agent 执行。
3. **工作区切换会改变可见对话历史**。用户期望 workspace 仅作为对话的「分类标签 / 过滤器」，但目前切换 `Test_Workspace` 与 `Test2` 会切到完全不同的 `threads.jsonl` 文件，等同于强分区。

## 2. 现状根因（已经过代码验证）

- **Tool loop**：`SciStationAgentService.run` 仅做单次 LLM call → `AgentPlanParser` 从模型 JSON 中读取 `tool_calls` → 用户审批后 `AgentToolExecutor.execute`，**没有 model → tool_result → model 的回环**。`Sci-Station/Agent/SciStationAgentService.swift:103-145, 163-205`、`Sci-Station/Agent/AgentPlanner.swift:25-90`。
- **Wire-format**：`AgentPlanner` 的 `LLMProviderRequest` 默认 `tools: []`，工具 schema 只复制到 system prompt 文本里（`Sci-Station/LLM/LLMProvider.swift:99-107`、`Sci-Station/Agent/AgentPromptBuilder.swift:58-134`），没有走真正的 OpenAI/Anthropic 工具协议。
- **论文注入**：`AgentWorkspaceContextBuilder.snapshot` 会把所选 / 包含的 `paper.md` 全文（默认 10k 字、knowledge 模式 120k 字）拼进 `workspace_context` JSON，每轮都 preflight 一次（`Sci-Station/Agent/AgentWorkspaceContextBuilder.swift:8-9, 64-119`）。完全没有「按需取段」的工具。
- **Markdown / 数学渲染**：聊天气泡 `AgentMarkdownBubbleText` 用 `try? AttributedString(markdown:)`（`Sci-Station/UI/AILabWorkspaceView.swift:995-1018`），不支持完整 GFM、不支持 LaTeX，也无 fallback。
- **System prompt**：`AgentPromptBuilder.buildSystemPrompt`（`Sci-Station/Agent/AgentPromptBuilder.swift:58-134`）只规定 JSON schema，没有要求段落、列表、`$...$` / `$$...$$` 公式风格，也没有「先用工具再回答」的策略。
- **Skill / Hook / MCP**：`AgentSafetyPreset.defaultHooks()`（`Sci-Station/Agent/AgentModels.swift:624-650`）是四条 reminder；skill loader 只解析 metadata，没读 SKILL.md body；MCP 只在 `AgentRuntimeSummaries.swift` 做状态展示，未对接 `AgentToolExecutor`。
- **Threads 存储**：`AgentThreadRepository` 写入 `{workspace.rootURL}/.sci-station/agent/threads.jsonl`（`Sci-Station/Agent/AgentThreadRepository.swift:5-12`、`Sci-Station/Workspace/ResearchRoot.swift:80-93`）。`AppViewModel.loadWorkspaceData` → `loadResearchRoot` → `refreshAgentState` 会随 workspace 切换而重新装载 root 与 thread 列表（`Sci-Station/App/AppViewModel.swift:3749-3987`）。这就是用户看到的「分区错觉」。
- **Streaming**：仅在 conversation 模式下走 `responseDeltaHandler` → `AgentVisibleResponseExtractor.visibleText` → 单一 streaming 气泡（`AppViewModel.swift:2847-2890`）。Plan 模式无 streaming。

## 3. 设计大方向：把 OpenCode 的 agent 内核移植到 Swift

OpenCode 的核心抽象（`opencode-dev/packages/opencode/src/{agent,session,tool,permission,plugin,skill,mcp}`）和 Claude Code Plugin Spec（`claude-code-main/plugins/plugin-dev/skills/*`）一起，给我们一组可移植的契约：

1. **Session = 仅一份 append-only 事件流**：`UserMessage` / `AssistantMessage`（带 reasoning、text、tool_call、tool_result parts）/ `Permission*` / `HookResult` / `CompactionSummary`。
2. **真正的 tool loop**：`session/processor.ts` 在每轮 `assistant` 事件结束后，若 `finish_reason === "tool-use"` 则执行工具、把 `tool_result` 注回 messages 再发起下一轮，直到 `finish_reason === "end"` 或 `max-steps` / cancellation 命中。
3. **Tool registry**：每个 tool 单文件（`tool/read.ts` 等）声明 schema、provider-aware description、output truncation；agent profile 决定哪些工具暴露给模型。
4. **Provider abstraction**：streaming 协议、不同 provider 用不同 description / schema 适配（`provider/transform.ts`）。
5. **Permission**：`allow|ask|deny` × pattern，session 内一次性批准 vs 全局 always 都有路径；UI 通过 SSE 暴露 permission request。
6. **Hooks**：`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Stop` / `SubagentStop` / `Notification` / `PreCompact`，stdout/stderr/exit-code/JSON envelope 三种回执。
7. **Skill 三级渐进披露**：tier-1 metadata 常驻 system prompt；tier-2 SKILL.md body 在匹配时加载；tier-3 references/scripts 由模型按需读取或执行。
8. **Workspace = filter，不是 partition**：OpenCode 的 session 与 storage 都按 user-data root（不是 cwd）持久化，`session.directory` 只是元数据；切目录不会丢失会话。

## 4. 阶段化计划

任务书 30 不可能一次吞完。把工作切成三个阶段，每阶段独立可验证、可发版。**Phase 1 是本轮交付目标**，Phase 2 / 3 在后续任务书继续推进。

### Phase 1（本轮）：把 agent 跑成「会用工具的对话」

- [P1.1] **Markdown + 数学渲染**：替换 `AgentMarkdownBubbleText`，使其能正确渲染段落、列表、代码块、引用，并把 `$...$` 与 `$$...$$` 转成可读公式（首选 SwiftUI 内嵌一个轻量 `WKWebView` + KaTeX；备选 `swift-markdown` + 自己渲染数学占位为单色字体片段）。要求：用户消息保持气泡布局；助手消息渲染分块、可拷贝、流式更新过程中能局部 patch（不闪屏）。
- [P1.2] **真 Tool Loop**：在 `SciStationAgentService` 旁新建 `AgentLoopRunner`（actor），实现 `model → tool_call → tool_result → model` 多轮：
  - 用 `LLMStreamingChatProvider.streamResponse` 走 OpenAI 工具协议（`tools` 参数 + `tool_choice: auto` + `tool_call` 增量事件）。
  - 每轮的事件落到 `AgentSessionEventLogger`（已有），UI 渲染流式 assistant 气泡 + tool_call 卡片 + tool_result 折叠。
  - bound：`maxSteps` 默认 8、`maxToolCalls` 默认 16、用户可随时点 `停止`。
  - 把单次 plan 模式保留为 fallback，但默认启用 loop。
- [P1.3] **按需读论文工具**：替换无条件 paper 注入。
  - 新增 `list_papers`（按 project / tag / paper_id 列出）、`read_paper`（读 `paper.md` 全文，自动分页 + 返回每页的开始/结束 token 估算）、`read_paper_section`（按 markdown heading 路径或 byte range 读片段）、`search_papers`（在 paper.md 内做关键词检索，返回带行号的命中段）。
  - `AgentWorkspaceContextBuilder.snapshot` 默认只塞 metadata（标题/作者/年份/已转换状态/是否在知识库勾选），不再塞 markdown 全文；只有当 `mode == legacy` 或上下文为空时才回退到旧的 excerpt。
  - 在 system prompt 显式说明「需要论文内容时调用 `read_paper` / `read_paper_section`」。
- [P1.4] **Prompt + Skill 三级披露**：
  - 重写 `AgentPromptBuilder`：要求 markdown 段落、行内公式 `$...$`、行间公式 `$$...$$`、引用论文时附 `paper_id` 或文件路径；明确「优先工具调用、再合成回答」；语言遵循用户最近一条消息。
  - 实装 skill loader：扫 `~/.claude/skills/`、`{root}/.claude/skills/`、`Sci-Station/.claude/skills/`，解析 frontmatter 注入 tier-1 metadata，把命中的 SKILL.md body 作为 system 段加载，scripts/ 由 `Skill` 工具按需调用。
- [P1.5] **Hook 命名与运行**：把 `AgentHookEventName` 对齐 Claude Code 拼写（`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Stop` / `SubagentStop` / `Notification` / `PreCompact`）。新增三条确定性安全 hook：
  - 提交 prompt 前正则扫 `sk-…` / `ghp_…` / `AKIA…` 等明文密钥（`UserPromptSubmit`，命中 → block + 提示）；
  - `PreToolUse` 拦截写入 `~/.ssh`、`~/.aws`、`*.env`；
  - `PostToolUse` 在 modified_paths 命中工作区外路径时记录红色审计行。
- [P1.6] **Threads 工作区即标签**：把 `AgentThreadRepository` 的写入路径迁到「research base」（`~/Library/Application Support/Sci-Station/agent/threads.jsonl` 或选定的 user research root，统一一处）。`AgentThread` 增字段 `workspaceID: String?` / `workspaceName: String?` 作为标签；UI 增加一个「按工作区过滤」开关，但默认显示全部线程。提供一次性迁移：扫历史每个 workspace 的 `.sci-station/agent/threads.jsonl`，合并到全局文件，老文件保留为 `threads.legacy.jsonl` 以便回滚。
- [P1.7] **测试**：在 `SciStationCoreTestRunner` 中新增 case：
  - `agentLoopRunnerCallsToolThenContinues`（mock provider，第一轮返回 tool_call，第二轮返回最终 markdown）；
  - `readPaperToolReturnsRequestedSection`；
  - `agentSnapshotDoesNotEmbedMarkdownByDefault`；
  - `agentThreadRepositoryGlobalStoreFiltersByWorkspaceID`；
  - `agentThreadRepositoryMigratesPerWorkspaceLegacy`；
  - `agentSafetyHookBlocksSecretInPrompt`；
  - `agentMarkdownRendererPreservesParagraphsAndMath`（纯模型层）。

### Phase 2（下一轮）：MCP、Subagents、Compaction

- 把 `AgentRuntimeSummaries` 里的 MCP server 状态接进真正的 client（local stdio + remote streaming），暴露其工具到 loop（默认 ask；UI 在 dock 里展示来源）。
- 引入 hidden agents：`title-generator`、`compaction-summarizer`、`research-explorer`，对应 OpenCode 的 plan/build/explore/general/hidden。
- 上下文 overflow 时启用 compaction 摘要（OpenCode `session/compaction.ts` 思路）。

### Phase 3（再下一轮）：Plugin 包形态 & 命令面板

- 落地 plugin manifest（`.claude-plugin/plugin.json` 兼容），让 `commands` / `agents` / `skills` / `hooks` / `mcpServers` 可整包安装到 `~/.sci-station/plugins/` 或 workspace local。
- 在 AI Lab 增加 `/` 命令面板（`commands` 渲染）。
- 与 Cursor/OpenCode 共享 skill bundle 的可能性（写一个 importer 脚本而不是产线依赖）。

## 5. Phase 1 验收标准

1. AI Lab 在 conversation 模式下，模型遇到「请基于 Garani 论文第 5 节给出蒸发率公式」时，可观察到至少一次 `read_paper_section` 工具调用记录（permission auto-allow 或 ask 都可），且最终回答里 `$$ ... $$` 被正确渲染为公式而不是原文字符串。
2. 切换 `Test_Workspace` 与 `Test2`（即使其中一个并未保存过任何线程），AI Lab 可见到同一份对话历史，并且每条线程显示对应的 workspace 标签；用户可在线程列表点击「仅显示当前工作区」后过滤。
3. 在 prompt 中粘贴 `sk-` / `ghp_` 开头的明文密钥后回车，hook 立即阻止发送并提示「检测到疑似密钥，已拦截」。
4. `Skill` panel 中至少 `sci-station-agent-platform` 与 `sci-station-research-workflow` 两个 SKILL.md 的 body 在命中关键词时进入 system prompt（可在 hook activity 看到 `SessionStart` 事件附 skill 名）。
5. `swift run SciStationCoreTestRunner` 全绿，新增 7 个 case 全部通过。
6. `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
7. 启动 App 后回归 Phase 1 之外的关键路径（Library 转换 / Settings / Wiki / Tasks）至少一次烟雾测试，确认未被回归打坏。

## 6. 非目标

- 不重写 LLM provider 实现（沿用 `OpenAICompatibleProvider`，仅扩展工具协议字段）。
- 不引入向量数据库或全文索引（`search_papers` 用 `String.contains` + 行号即可）。
- 不实装 plugin marketplace UI（Phase 3 再做）。
- 不做完整 GUI 自动化测试。
- 不绕过用户审批：所有 `risk == .writesWorkspace` / `.externalSideEffect` 的工具默认 `ask`。
- 不引入无界限自动循环：`maxSteps`、`maxToolCalls`、cancellation、失败计数全部硬上限。

## 7. 实施顺序建议

1. P1.1 Markdown+math 渲染（独立、即时可视收益）。
2. P1.6 Threads 工作区即标签 + 迁移（独立，且解锁后续 UI 调整）。
3. P1.3 按需读论文工具集合（先把工具调用形成的协议跑通）。
4. P1.2 AgentLoopRunner（依赖 P1.3 的工具与 P1.1 的渲染才能展示）。
5. P1.4 Prompt + Skill loader。
6. P1.5 Hook 安全条 + 命名对齐。
7. P1.7 测试随每个子项一起补齐，最后跑全量。

## 8. 已确认参考代码（移植对照）

- OpenCode session 处理：`opencode-dev/packages/opencode/src/session/{processor.ts,llm.ts,message-v2.ts,instruction.ts}`。
- OpenCode 工具：`opencode-dev/packages/opencode/src/tool/{read.ts,write.ts,grep.ts,glob.ts,registry.ts,task.ts,skill.ts}`。
- OpenCode 权限：`opencode-dev/packages/opencode/src/permission/`。
- OpenCode skill：`opencode-dev/packages/opencode/src/skill/`。
- Claude Code plugin spec：`claude-code-main/plugins/plugin-dev/skills/{plugin-structure,hook-development,skill-development,command-development,agent-development,mcp-integration}/`。
- 安全 hook 范例：`claude-code-main/plugins/security-guidance/hooks/security_reminder_hook.py`。

## 9. 已决策项（2026-05-02）

1. **Threads 全局 store 路径**：`~/Library/Application Support/Sci-Station/agent/`（macOS 标准目录）。`AgentThread` 增加 `workspaceID` / `workspaceName` 标签字段，UI 默认显示全部线程，可一键过滤当前工作区。
2. **聊天渲染器**：嵌入轻量 `WKWebView` + KaTeX（marked.js + KaTeX auto-render），保持纯 SwiftUI 包装，离线（资源进 bundle）。后续若稳定再评估替换为纯原生。
3. **只读论文工具默认批准**：`read_paper` / `read_paper_section` / `search_papers` / `list_papers` 默认 `allow`（permissionKey = `paper.read`），写盘工具继续 `ask`。
4. **密钥拦截动作**：`UserPromptSubmit` hook 命中明文密钥（`sk-…` / `ghp_…` / `AKIA…` 等正则）时直接 block 发送，UI 弹红条提示。

## 10. 完成记录

- 2026-05-02：方向重定，§1-§8 重写完成；§9 决策 1-4 已落地。
- 2026-05-02：**P1.1 完成**。新增 `Sci-Station/Resources/ChatRenderer.bundle/`（KaTeX 0.16.11 + marked 14.1.3 + 自写 `index.html`，已落盘 `BUNDLING.md` 升级指引）；新增 `Sci-Station/UI/ChatMarkdownWebView.swift` 通过 `NSViewRepresentable` + `WKWebView` 暴露持久 `setChatState` JS bridge，复用 web view 做流式增量更新，URL 从 bundle 加载（`Bundle.main.url(forResource: "ChatRenderer", withExtension: "bundle")`）；`AILabWorkspaceView.AgentMarkdownBubbleText` 改路由到新渲染器，旧 `AttributedString` 走 fallback；`Package.swift` exclude `Resources/`；`AgentPromptBuilder` 在 conversation/plan 两条路径都补充了 GFM 段落 + `$...$` / `$$...$$` 数学公式格式约束；`swift run SciStationCoreTestRunner` 通过，`xcodebuild ... build` 通过，`ChatRenderer.bundle` 在 App `Contents/Resources/` 中保持 `fonts/` 子目录完整。后续待补：在 SciStationCoreTestRunner 加一条 prompt 格式化规则的快照（被运行中的 `StrReplace` 安全 hook 拦截，下一轮 UI 验证或 hook 调整后再加）。
- 2026-05-02：**P1.6 完成**。`AgentThread` 增加 `workspaceID` / `workspaceName` 标签字段；`AgentThreadRepository` 从 workspace-local `.sci-station/agent/threads.jsonl` 迁到 macOS 标准全局 store `~/Library/Application Support/Sci-Station/agent/threads.jsonl`，并支持按 `workspaceID` 过滤、upsert 自动补 workspace 标签、legacy 文件一次性迁移到全局 store 后归档为 `threads.legacy.jsonl`；`AppViewModel` 默认加载全局线程列表，新增「当前工作区」过滤状态，新建/追加/重命名/归档线程时保持 workspace 标签；AI Lab 顶部 thread strip 增加 Current workspace 开关与 workspace 标签副标题，侧边栏 thread 行也显示 workspace 标签；Settings 的 Agent Threads 路径改为全局 store。`SciStationCoreTestRunner` 新增并通过 `agentThreadRepositoryGlobalStoreFiltersByWorkspaceID`、`agentThreadRepositoryMigratesPerWorkspaceLegacy`，并更新 legacy archive 测试使用注入 store，避免测试写入真实 Application Support。验证：`swift run SciStationCoreTestRunner` 通过，`xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
- 2026-05-02：**P1.3 完成**。默认 agent registry 新增 `list_papers`、`read_paper`、`read_paper_section`、`search_papers` 四个只读论文工具（`risk == readOnly`，`permissionKey == paper.read`）；`AgentWorkspaceContextBuilder.snapshot` 默认改为 metadata-only，不再把选中/知识库论文的 `paper.md` 或 PDF 正文无条件塞进 prompt，同时保留 `AgentPaperContextPolicy.legacyExcerpts` 作为调试/兼容 fallback；`AgentPromptBuilder` 明确要求模型在需要论文正文、公式、章节、方法或证据时先计划调用 paper tools，并在引用时带 `paper_id` 或相对路径；AI Lab runtime 事件行已支持展开查看工具参数/结果和可审计思考摘要。CoreTestRunner 覆盖：`agentPaperReadToolsReturnSectionsAndSearchMatches`、`agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault`、`agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext`、`agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext`。验证：`swift run SciStationCoreTestRunner` 通过，`xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
- P1.7：与 P1.1/P1.3/P1.6 相关的测试部分完成；剩余 P1.2/P1.4/P1.5 对应 case 待随各子项落地。
- P1.2 / P1.4 / P1.5：未完成，下一轮优先 P1.2 AgentLoopRunner。
