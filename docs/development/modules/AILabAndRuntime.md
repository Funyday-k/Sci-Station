# AI Lab 与 Runtime

## 范围

负责 AI Lab conversation、agent tools、LLM provider、权限确认、运行日志、sidecar runtime 和 AI 相关 UI。

## 关键代码入口

- `Sci-Station/Agent/`
- `Sci-Station/LLM/`
- `Sci-Station/UI/AILabWorkspaceView.swift`
- `AgentRuntime/`
- `.sci-ai/`

## 不变量

- API key、token、client secret 只能进入 Keychain 或本机安全配置。
- 写入工具必须接权限确认或明确的安全 preset。
- 工具结果必须有证据引用，便于用户回看。
- provider failure、empty response、context budget stop 都必须有可见失败状态和重试路径。
- AI 运行记录不得泄漏 secret；debug bundle 必须脱敏。

## Proposal 要求

AI 相关 Proposal 必须写清：

- 工具名称、输入、输出和错误分类。
- 是否读写用户数据。
- 权限确认路径。
- 运行日志字段。
- UI pending/running/approval/failed/completed 状态。
- 自动化和手动测试入口。

## 发布前检查

- 无 API key 时 AI 入口不崩溃。
- provider 失败后用户知道如何重试或复制诊断。
- 写回 wiki/paper/queue/reading plan 的路径受限且可审计。
- AgentRuntime 测试在改动相关代码时通过。
