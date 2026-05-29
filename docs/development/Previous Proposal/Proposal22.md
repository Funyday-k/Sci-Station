# 任务书 22：Sci-Station Agent Platform 预设化迁移 V1

更新时间：2026-05-01

## 1. 本轮结论

任务书 21 已完成 Library Table V2 与 GitHub Copilot SDK 接口适配第一版，并在追加修订中完成当前工作区的 Claude Code 轻量预设：`SessionStart` / `PreToolUse` hooks、agent platform skill、research workflow skill，以及受限到本仓库的 filesystem MCP 配置。

下一阶段应正式进入 Sci-Station Agent Platform V1：吸收 OpenCode 的运行时架构和 Claude Code 插件生态，但保持 Sci-Station 的 Swift-native、本地优先和可审计安全边界。OpenCode 和 Claude Code 仓库只作为研究参考，不进入生产依赖路径。

任务书 22 的主线是：把当前 AI Lab 从「plan-only + tool approval + thread history」推进到可扩展 agent 平台底座，优先完成核心模型、权限规则、hook engine、plugin/skill/command schema、MCP 配置边界和 session event log 设计；UI 只做必要入口和状态展示，不急于实现无限自动循环或完整多端 server。

## 2. 当前代码基线

- AI Lab 已支持 Codex-style conversation、thread strip、prompt composer、timeline、plan-only、逐项 tool approval、run history、thread draft 持久化和 Copilot Bridge export。
- `AgentRun`、`AgentPlan`、`AgentPlanStep`、`AgentToolDefinition`、`AgentToolExecutor`、`AgentThread` 等基础模型已存在。
- `LLMProvider` 当前仍以单次 completion 为主，GitHub Copilot SDK adapter 已有 experimental 配置、token 分类、Keychain 保存和 OAuth relay 边界。
- workspace 写入工具仍通过用户逐项批准执行，Auto Run Loop 继续 disabled。
- 当前工作区已有 `.claude/settings.json`、`.claude/hooks/`、`.claude/skills/` 和 `.mcp.json`，可作为 Sci-Station 内置 preset 的原型。
- OpenCode 参考重点是 `agent`、`session`、`tool registry`、`permission`、`MCP`、`provider` 和 client/server 边界。
- Claude Code 参考重点是 plugin manifest、commands、agents、skills、hooks、settings、MCP preset、validator 和安全治理。

## 3. 执行任务

### 3.1 Agent Platform 架构文档

1. 新增或更新 Agent Platform 设计文档，明确：
   - Sci-Station 采用 Swift-native Agent Core。
   - OpenCode 是运行时架构参考。
   - Claude Code 插件是生态、hooks、skills、MCP preset 和安全治理参考。
   - `opencode-dev`、`claude-code-main`、`everything-claude-code-main` 不作为生产依赖。
2. 记录核心边界：
   - App/UI 层负责展示和用户交互。
   - Agent Core 负责 session、tool、permission、hook、provider、plugin。
   - Keychain 继续保存 API key、Copilot token、MCP OAuth token 等敏感值。
3. 将当前 `.claude` workspace presets 标记为产品化原型，而不是最终运行时。

### 3.2 核心模型 V1

1. 在 `Sci-Station/Agent` 或可进入 SwiftPM 验证的 core 边界中设计第一批模型：
   - `AgentProfile`
   - `AgentMode`
   - `SubagentProfile`
   - `AgentPermissionRule`
   - `AgentPermissionDecision`
   - `AgentHookDefinition`
   - `AgentHookEvent`
   - `AgentPluginManifest`
   - `AgentCommandTemplate`
   - `AgentSkillManifest`
   - `AgentSessionEvent`
   - `MCPServerConfiguration`
2. 保持现有 `AgentRun`、`AgentThread`、`runs.jsonl`、`threads.jsonl` 可读，不做破坏性迁移。
3. 模型字段优先覆盖稳定语义，不急于实现所有 UI。

### 3.3 权限规则与 Tool Registry

1. 将现有 tool definition 扩展为更明确的 registry：
   - tool id / display name / description
   - input schema version
   - permission key
   - read/write/network/external side effect risk
   - output truncation policy
2. 引入 allow / ask / deny 权限规则：
   - 按工具类型匹配。
   - 按 shell command pattern 匹配。
   - 按 workspace path pattern 匹配。
   - 支持 session-scoped approval 和 persistent rule 草案。
3. 现有写入工具仍默认 ask，不因新 registry 放宽。
4. dangerous shell、敏感路径和疑似 secret 的规则可先从当前 `.claude/hooks/sci_station_guard.py` 抽象为 Swift 原生 matcher。

### 3.4 Hook Engine V1

1. 定义 hook 生命周期：
   - `SessionStart`
   - `UserPromptSubmit`
   - `PreToolUse`
   - `PostToolUse`
   - `Stop`
   - `SubagentStop`
2. 第一版优先实现纯逻辑 hook matcher 与结果模型：
   - allow / ask / deny
   - additional context
   - warning message
   - validation reminder
3. `SessionStart` 可注入 workspace、current project、selected paper、enabled presets 和安全边界。
4. `PreToolUse` 可拦截危险命令、敏感写入、外部副作用。
5. `Stop` 可提醒本轮修改了代码/数据但未记录验证。
6. Hook 必须可见、可禁用、可审计，不做隐藏自动化。

### 3.5 Preset、Plugin、Skill 与 Command

1. 设计 Sci-Station 内置 preset registry：
   - `research-core`
   - `security-and-secrets`
   - `library-curator`
   - `proposal-draft`
   - `code-and-data-review`
2. 设计 `.sci-station/agent/plugins/{plugin}/` 草案结构：
   - `plugin.json`
   - `commands/`
   - `agents/`
   - `skills/`
   - `hooks/`
   - `mcp.json` 或 `mcp.yaml`
3. 第一批 command template：
   - `/paper-review`
   - `/proposal-draft`
   - `/experiment-plan`
   - `/library-curate`
   - `/code-data-review`
4. Skill 采用 progressive disclosure：
   - `SKILL.md` 保持短小。
   - `references/` 放长说明和迁移参考。
   - `scripts/` 只放确定性校验或转换工具。
5. 增加 manifest / hook / skill / command schema 的验证器草案。

### 3.6 MCP 配置边界

1. 设计 MCP server 配置模型：
   - local command server
   - remote HTTP/SSE server
   - enabled
   - timeout
   - allowed tools
   - headers / token reference
2. workspace 文件只保存非敏感配置和 secret reference。
3. token、OAuth refresh token、API key 进入 Keychain 或明确安全后端。
4. 默认 MCP preset 保守启用，只读优先；写入或外部副作用工具必须进入 permission layer。
5. 当前 `.mcp.json` 只作为本仓库 Claude Code 原型，后续应迁移到 Sci-Station UI 管理的配置。

### 3.7 Session Event Log 与 AI Lab UI 演进

1. 在不破坏 `runs.jsonl` 的前提下，设计 append-only session event log：
   - user message
   - assistant message / delta
   - reasoning summary
   - tool call started / completed / failed
   - permission requested / granted / denied
   - hook result
   - compaction / summary
2. AI Lab UI 第一版只增加必要状态：
   - 当前 agent profile / provider / preset summary。
   - 权限请求状态更清晰。
   - hook warning / block 结果可见。
   - MCP server enabled 状态可见。
3. 保留当前 thread 和 draft 体验，不重写用户历史。

### 3.8 Provider V2 方案

1. 设计新的 provider protocol，支持：
   - streaming
   - message history
   - tool definitions
   - model options
   - provider-specific options
   - cancellation
2. OpenAI-compatible / DeepSeek 与 GitHub Copilot SDK experimental provider 都应能适配该边界。
3. 本轮可先完成协议与 adapter skeleton，不要求真实 Copilot SDK 替换现有 plan 生成路径。

### 3.9 测试与验证

1. 为以下纯逻辑增加 `SciStationCoreTestRunner` 覆盖：
   - permission rule matching
   - hook matcher
   - plugin manifest parse / validation
   - skill frontmatter parse / validation
   - MCP config serialization，不序列化 secret value
   - session event append / replay
   - tool registry risk metadata
2. 保持当前 workspace preset 校验：
   - `.claude/hooks/*.py` 可编译。
   - `.claude/settings.json` 可解析。
   - `.mcp.json` 可解析。
3. 更新 README 与 `docs/development/Next-Step-Task-Book.md`。
4. 运行 `swift run SciStationCoreTestRunner`。
5. 若改动 App/UI，运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不把 OpenCode 的 TypeScript/Bun runtime 作为 Sci-Station 主路径生产依赖。
- 不把 Claude Code 插件仓库作为完整 agent runtime 使用。
- 不复制 Claude Code 插件的大段实现或文案，只借鉴结构与模式。
- 不启用无限 Auto Run Loop。
- 不放宽 workspace 写入、shell、MCP side effect 和外部网络动作的审批。
- 不把 API key、Copilot token、MCP token、OAuth refresh token 或 client secret 写入 workspace 明文文件。
- 不强制替换现有 OpenAI-compatible / DeepSeek provider。
- 不在本轮实现完整 subagent 并行调度或多端 server。

## 5. 验收标准

1. Agent Platform 设计文档明确 OpenCode / Claude Code / Sci-Station 三者边界。
2. 第一批 agent platform core models 可编译，并有纯逻辑验证。
3. 现有 `AgentRun`、`AgentThread`、`runs.jsonl` 和 `threads.jsonl` 仍可读取。
4. Tool registry 能表达工具风险、permission key 和输出策略。
5. Permission rule 支持 allow / ask / deny，并能按工具、命令和路径匹配。
6. Hook model 支持 `SessionStart`、`PreToolUse`、`PostToolUse` 和 `Stop` 的第一版语义。
7. 当前 `.claude` preset 的安全规则能映射到 Swift 原生 matcher 草案。
8. Plugin manifest、skill frontmatter、command template 和 MCP config 至少有 parser / validator 草案。
9. MCP 配置不会把 secret value 序列化到 workspace。
10. AI Lab 能显示当前 agent/provider/preset 状态，且 hook/permission 结果可审计。
11. Provider V2 方案能覆盖 streaming、messages、tools、model options 和 cancellation。
12. `swift run SciStationCoreTestRunner` 通过。
13. 如涉及 App/UI，Xcode macOS build 通过。

## 6. Question

1. 任务书 22 是否先完成 core models、permission、hook、plugin/MCP schema，再重构 AI Lab UI？建议是。
2. Session event log 是否应与现有 `runs.jsonl` 并行一段时间，而不是立即替换？建议并行。
3. MCP 第一版是否默认只读优先，写入和外部 side effect 都走 permission layer？建议是。
4. Provider V2 本轮是否只做协议和 adapter skeleton，不真实替换 plan 生成路径？建议是。
5. OpenCode 子进程 bridge 是否暂缓，先做 Swift-native core？建议暂缓。

## 7. 完成记录

完成时间：2026-05-01

本轮按任务书 22 完成 Sci-Station Agent Platform 预设化迁移 V1 的 Swift-native core 第一版：

- 扩展 `AgentToolDefinition`，新增 stable identifier、display name、input schema version、permission key、output policy，并为 read/write/network/external side effect 风险提供默认确认策略。
- 新增 Agent Platform core models：`AgentProfile`、`AgentMode`、`SubagentProfile`、`AgentPermissionRule`、`AgentPermissionDecision`、`AgentHookDefinition`、`AgentHookEvent`、`AgentPluginManifest`、`AgentCommandTemplate`、`AgentSkillManifest`、`MCPServerConfiguration` 和 `AgentSessionEvent`。
- 新增 `AgentPermissionEvaluator` 与 `AgentSafetyPreset`，第一版覆盖 allow / ask / deny、工具/命令/路径/risk 匹配，并把当前 `.claude/hooks/sci_station_guard.py` 中的危险命令和敏感路径规则映射到 Swift 原生 matcher。
- 新增 `AgentHookEngine`，支持 `SessionStart`、`PreToolUse`、`PostToolUse`、`Stop`、`UserPromptSubmit` 和 `SubagentStop` 的纯逻辑结果模型。
- 新增 plugin / skill / command / MCP schema 草案与 `AgentPluginValidator`；skill frontmatter 可解析，MCP header 只保存 credential reference，不保存原始授权值。
- 新增 `AgentSessionEventLogger`，写入 `.sci-station/agent/session_events.jsonl`，与现有 `runs.jsonl` 并行，不替换旧 history。
- 新增 Provider V2 skeleton：message history、tool specification、model/provider options、response tool calls、stream event protocol；现有 `LLMProvider.complete` 保持兼容。
- `SciStationAgentService` 已在 plan-only 和 approved execution 时写入 session event log，包含 user message、assistant summary、permission request 和 tool completion/failure 事件。
- AI Lab Details 增加 Agent Platform 状态区，显示 core、provider、presets、permission、hooks 和 MCP 配置分层状态。
- 新增 `.sci-ai/` AI 配置分层：`.sci-ai/sci-station/` 保存可进 GitHub 的 Sci-Station product preset，`.sci-ai/workspace.local/` 保存本机工作区 AI 配置且被 gitignore 排除；`.claude/` 和 `.mcp.json` 作为本机 bridge 文件同样不进 GitHub。
- 新增 `.sci-ai/sci-station/presets/research-core/`，包含 plugin manifest、research/agent skills、safety hook rules 和 MCP server template。
- 更新 README 与 `docs/development/Next-Step-Task-Book.md` 的 Agent Platform 状态。

验证：

- `.sci-ai` 下 JSON 配置均可解析。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。

未纳入本轮：

- AI Lab 目前只显示 Agent Platform 状态摘要，尚未提供完整 permission dock / hook activity 交互面板。
- 未启用真实多轮 Auto Run Loop。
- 未接入 OpenCode 子进程 bridge。
- 未替换现有 plan 生成 provider 路径。
