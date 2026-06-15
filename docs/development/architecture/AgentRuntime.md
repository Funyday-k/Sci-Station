# AI Lab 与 Agent Runtime 架构

AI Lab 是可选能力。没有 LLM provider 或 API key 时，Sci-Station 的本地论文、Wiki、Tasks、Recommendation 等主路径仍应可用。

## 分层

```text
Swift App
├── Agent/      工具定义、权限、运行记录、debug events、UI 状态
├── LLM/        OpenAI-compatible provider 配置和调用抽象
└── UI/         AI Lab、timeline、approval、diagnostics

AgentRuntime/
├── sidecar runtime 原型
├── UI test runner
└── Python 测试夹具
```

## 权限边界

- 只读工具可以自动执行，但必须记录证据来源。
- 写入工具必须经过权限确认或明确的安全 preset。
- Agent 输出到 wiki、paper notes、tasks 或 recommendation follow-up 前必须可审计。
- 任何包含用户正文或模型输出的持久化都必须说明路径和隐私影响。

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
