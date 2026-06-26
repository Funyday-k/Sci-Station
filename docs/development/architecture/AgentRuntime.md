# AI Lab 与 Agent Runtime 架构

AI Lab 是可选能力。没有 LLM provider 或 API key 时，Sci-Station 的本地论文、Wiki、Tasks、Recommendation 等主路径仍应可用。当前生产默认 runtime 是 Swift Loop；Python/LangGraph sidecar 仍是实验性路径，主要用于原型、测试编排和后续重型 workflow 验证。

## 分层

```text
Swift App
├── Agent/      工具定义、权限、运行记录、debug events、UI 状态
├── LLM/        OpenAI-compatible provider 配置和调用抽象
└── UI/         AI Lab、timeline、approval、collaboration status、diagnostics

AgentRuntime/
├── sidecar runtime 原型（experimental）
├── UI test runner
└── Python 测试夹具
```

## Runtime 定位

- Swift Loop 是生产默认路径，负责普通 AI Lab 对话、工具计划、权限判断、工具执行状态、Prompt snapshot 和 run ledger。
- `AgentRuntime/` sidecar 不应被文档或 UI 描述为生产默认；只有当真实工具调用、真实检索、无 synthetic evidence、pytest、fallback 和诊断路径都稳定后，才能升级定位。
- Sidecar unavailable、crashed 或 disabled 时，用户应能看到 fallback 原因，并继续使用 Swift Loop 或得到明确降级说明。
- Remote MCP 已有实验性 HTTP/SSE JSON-RPC discovery、credential reference 解析、liveness、失败/backoff 和 crash/credential 诊断状态，但复杂 auth broker、跨 run 重连审计、RAG production evidence trace、evaluation harness 和 sidecar production 收敛仍属于后续工作，不是当前稳定承诺。

## 权限边界

- 只读工具可以自动执行，但必须记录证据来源。
- 写入工具必须经过权限确认或明确的安全 preset。
- Agent 输出到 wiki、paper notes、tasks 或 recommendation follow-up 前必须可审计。
- 任何包含用户正文或模型输出的持久化都必须说明路径和隐私影响。
- Prompt override、Skill toggle 和 MCP server 覆盖配置存放在 Research Root 的 `.sci-station/agent/profile.json`；Prompt 已进入执行链并记录 version/hash，Prompt patch review 会展示 rationale、impact 和 rollback，Skill Manager 已支持 catalog/search/import/toggle/trust 基础流，local command MCP 与实验性 remote HTTP/SSE MCP 已进入 runtime 状态层。run-level Skill snapshot、更深 MCP audit/harness 和 production RAG evidence trace 仍在后续阶段。

## Evidence 与写回

- 生产回答需要真实工具证据时，必须引用 paper、PDF、Markdown、Wiki、Graph artifact 或其它本地来源，不能把 synthetic/sample evidence 当作真实证据。
- Synthetic/sample evidence 只能保留在测试 fixture 或明确标注的实验路径中。
- 无法取得证据时，Agent 应说明读取、检索或索引失败原因，而不是编造来源。
- 写回 wiki、paper notes、tasks 或 artifacts 前应展示 draft、target path 和权限状态；拒绝审批时不得丢失 draft。

## Debug 与诊断

- App diagnostics 必须包含 app version、build、OS、语言和关键配置。
- 诊断包必须脱敏绝对路径、home 目录、secret-looking values。
- UI test bridge 可以强制 debug logging，但普通 Debug 使用不应持续高频写日志。

## Sidecar 协议

Sidecar 初始化数据应区分：

- `protocolVersion`：IPC 或行为不兼容时递增。
- `schemaVersion`：payload 结构演进时递增。
- `appVersion`：真实 App 版本，用于诊断和兼容判断。

## 变更要求

AI/Agent 相关改动必须在 Proposal 中写清：

- 工具是否读写用户数据。
- 权限确认路径。
- 失败和重试行为。
- debug event 名称和 payload 脱敏策略。
- 自动化测试和手动测试入口。
