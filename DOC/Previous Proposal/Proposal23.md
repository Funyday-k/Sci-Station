# 任务书 23：AI Lab Agent Platform Runtime UI V1

更新时间：2026-05-01

## 1. 本轮结论

任务书 22 已完成 Swift-native Agent Platform core 第一版，并补齐 `.sci-ai/` AI 配置分层：`.sci-ai/sci-station/` 保存可进 GitHub 的 Sci-Station product preset，`.sci-ai/workspace.local/` 保存本机工作区 AI bridge 配置且不进 GitHub；`.claude/` 和 `.mcp.json` 作为外部 agent 兼容 bridge 文件同样不进 GitHub。

下一阶段应把 Agent Platform core 真正接入 AI Lab Runtime UI：目前 AI Lab 已显示 core/provider/preset/permission/hook/MCP 状态摘要，但还缺少可操作的 permission dock、hook activity、MCP server 状态、session event timeline、preset manager 和 Provider V2 adapter 流程。

任务书 23 的主线是：让用户在 AI Lab 中看见并控制 agent runtime，而不是只看到 plan/run 结果。第一版仍保持保守安全模型：不启用无限 Auto Run Loop，不放宽 workspace 写入审批，不把本机 secrets 写入 tracked preset。

## 2. 当前代码基线

- Agent Platform core models 已进入 `Sci-Station/Agent/AgentModels.swift`。
- `AgentToolDefinition` 已支持 identifier、display name、input schema version、permission key 和 output policy。
- `AgentPermissionEvaluator` 与 `AgentSafetyPreset` 已支持 allow / ask / deny 和危险命令/敏感路径匹配。
- `AgentHookEngine` 已支持 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`Stop`、`SubagentStop` 的纯逻辑模型。
- `AgentSessionEventLogger` 已写入 `.sci-station/agent/session_events.jsonl`，并与 `runs.jsonl` 并行。
- `SciStationAgentService` 已在 plan-only 和 approved execution 时写入 session event。
- Provider V2 skeleton 已支持 messages、tools、model options、response tool calls 和 stream event protocol。
- AI Lab Details 已显示 Agent Platform 状态摘要。
- `.sci-ai/sci-station/presets/research-core/` 已提供 tracked product preset。
- `.sci-ai/workspace.local/`、`.claude/`、`.mcp.json` 已被 gitignore 视为本机 AI 配置。

## 3. 执行任务

### 3.1 Session Event Timeline

1. 在 AppViewModel 中读取当前 thread / run 对应的 `AgentSessionEvent`。
2. AI Lab timeline 支持显示：
   - user message
   - assistant summary
   - permission requested / resolved
   - tool call completed / failed
   - hook result
3. 损坏 JSONL 行继续跳过，不影响历史读取。
4. Timeline 第一版只读展示，不提供 event 手工编辑。

### 3.2 Permission Dock

1. 将当前 Tool Calls / Approvals 升级为 permission dock：
   - allow once
   - deny
   - correction feedback
   - session-scoped approval 草案入口
2. Dock 展示每个 tool call 的：
   - permission key
   - risk
   - matched rule / default policy
   - modified path preview
3. 写入工具继续默认 ask；read-only 工具可显示 auto-allow 状态，但仍可审计。
4. 不实现永久 workspace allowlist 写入，除非用户明确确认后续策略。

### 3.3 Hook Activity

1. AI Lab 显示当前启用 hooks：
   - `SessionStart`
   - `PreToolUse`
   - `PostToolUse`
   - `Stop`
2. 每次 plan 或 execution 后展示 hook results：
   - injected context
   - warnings
   - block / ask decisions
   - validation reminders
3. Hook 结果进入 session event log，和 timeline 可交叉引用。
4. Hook 必须可见、可禁用、可审计。

### 3.4 MCP Server 状态

1. AI Lab 显示 product preset MCP 与 local workspace MCP 的区别：
   - `.sci-ai/sci-station/` tracked templates
   - `.sci-ai/workspace.local/` local actual settings
2. MCP server 状态至少显示：
   - enabled / disabled
   - local command or remote URL
   - allowed tools
   - timeout
   - credential reference count
3. 写入或外部 side effect MCP tools 仍必须进入 permission layer。
4. 本轮不要求真正启动 MCP server；先完成 UI 和配置边界。

### 3.5 Preset Manager

1. 读取 `.sci-ai/sci-station/presets/research-core/plugin.json` 并在 AI Lab 显示 preset summary。
2. 支持展示：
   - commands
   - skills
   - hooks
   - MCP servers
   - validation issues
3. Settings 或 AI Lab Details 中增加 preset section 草案。
4. Local overrides 只能写入 `.sci-ai/workspace.local/` 或 `.sci-station/agent/` 的非敏感状态，不修改 tracked preset。

### 3.6 Provider V2 Adapter Flow

1. 保持现有 `LLMProvider.complete` 路径可用。
2. 为 AI Lab plan path 设计 Provider V2 adapter：
   - message history
   - tool definitions
   - model options
   - cancellation
3. OpenAI-compatible provider 可先提供 adapter wrapper。
4. GitHub Copilot SDK experimental provider 仍不替换主路径，除非连接状态明确且用户选择。

### 3.7 `.sci-ai` 配置验证

1. `SciStationCoreTestRunner` 继续验证 tracked `.sci-ai` product preset。
2. 增加 local-vs-tracked 边界验证：
   - tracked preset 不含 raw secret values。
   - local workspace config path 被 gitignore 排除。
   - root `.claude/` 和 `.mcp.json` 不进入 tracked set。
3. README 和任务书同步 `.sci-ai` 约定。

### 3.8 测试与验证

1. 增加 session event timeline 的纯逻辑测试。
2. 增加 permission dock view model / summary 纯逻辑测试。
3. 增加 hook activity summary 纯逻辑测试。
4. 增加 MCP server status summary 纯逻辑测试。
5. 运行 `swift run SciStationCoreTestRunner`。
6. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不启用无限 Auto Run Loop。
- 不让 workspace 写入、shell、MCP side effect 或外部网络动作绕过 permission layer。
- 不把 API key、OAuth token、refresh token、client secret、private key 或机器私有凭据写入 `.sci-ai/sci-station/`。
- 不把 OpenCode runtime 作为生产依赖。
- 不把 Claude Code 插件仓库作为完整 runtime 使用。
- 不在本轮实现完整 MCP server 启动/健康检查协议。
- 不强制替换现有 OpenAI-compatible / DeepSeek provider。

## 5. 验收标准

1. AI Lab timeline 能显示当前 run/session 的 session events。
2. Permission dock 能展示 tool risk、permission key、approval 状态和 matched/default policy。
3. Hook activity 能展示启用 hooks 与本轮 hook results。
4. MCP status 能区分 tracked product template 与 local workspace config。
5. Preset manager 能读取并展示 `.sci-ai/sci-station/presets/research-core/plugin.json`。
6. Tracked `.sci-ai/sci-station/` 不含 raw secret values。
7. `.sci-ai/workspace.local/`、`.claude/`、`.mcp.json` 不进入 GitHub tracked set。
8. Provider V2 adapter flow 有可测试 skeleton，现有 provider 路径保持兼容。
9. Existing `runs.jsonl` / `threads.jsonl` history 仍可读取。
10. `swift run SciStationCoreTestRunner` 通过。
11. Xcode macOS build 通过。

## 6. Question

1. Permission dock 先只支持 allow once / deny / correction feedback，并保留 session-scoped approval 草案入口；不做 persistent allowlist。
2. MCP 本轮只做状态展示与配置边界，不启动 server。
3. Provider V2 先通过 OpenAI-compatible wrapper 接入 skeleton，不强制切换 Copilot SDK。
4. Preset manager 的 local overrides 只允许写 `.sci-ai/workspace.local/` 或 `.sci-station/agent/` 的非敏感状态；本轮未写 tracked preset override。
5. 项目生命周期控制不简单推迟，而是重新审议其合理边界：它应作为项目级可见状态轨道与 agent runtime 交叉引用，不应变成自动推进项目或绕过审批的执行循环；详细规划进入任务书 24。

## 7. 完成记录

已完成。

- AI Lab timeline 已读取当前 thread / run 对应的 `AgentSessionEvent`，显示 user message、assistant summary、permission requested/resolved、tool completed/failed 和 hook result；损坏 JSONL 行仍由 logger 跳过。
- Tool Calls / Approvals 已升级为 Permission Dock，展示 permission key、risk、matched/default policy、path preview、allow once、deny、correction feedback 与 session-scoped approval 草案入口；未实现 persistent allowlist。
- Hook Activity 已展示 `SessionStart`、`PreToolUse`、`PostToolUse`、`Stop`，支持临时禁用，并将 hook result 写入 session event log。
- MCP Server 状态已区分 `.sci-ai/sci-station/` tracked product template 与 `.sci-ai/workspace.local/` local config，展示 enabled、endpoint、allowed tools、timeout 和 credential reference count；未启动 MCP server。
- Preset Manager 已读取 `.sci-ai/sci-station/presets/research-core/plugin.json`，展示 commands、skills、hooks、MCP servers 和 validation issues。
- Provider V2 已补 OpenAI-compatible chat wrapper 与 adapter flow model，现有 `LLMProvider.complete` plan path 保持兼容。
- `.sci-ai` 验证已覆盖 tracked preset 无 raw secret-looking values、local workspace config 与 root bridge 文件 gitignore/git tracked 边界。
- README 已同步 AI Lab runtime UI 与 `.sci-ai` 约定。
- 已新增纯逻辑测试：session event timeline、permission dock summary、hook activity summary、MCP status summary、Provider V2 wrapper payload、`.sci-ai` boundary validation。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
