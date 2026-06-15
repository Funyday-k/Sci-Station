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

## AI 对话升级方向

目标是从原始聊天框升级为研究协作面板：

- 左侧：会话/thread 列表、项目过滤、最近上下文和固定会话。
- 中央：消息流、工具调用卡、审批卡、失败/重试状态、可折叠 reasoning。
- 右侧：证据、引用、相关论文、项目任务、生成产物和可写回目标。
- 输入区：附件、引用当前选择、模式选择、工具预算、发送前权限摘要。
- 输出动作：保存到 Project Brief、写入 Wiki、生成任务、创建阅读 Todo、创建材料记录。

实现约束：

- 对话 UI 不直接持有 provider 细节；provider 和 runtime 仍由 `Agent/`、`LLM/`、`AgentRuntime/` 处理。
- 工具调用必须有结构化状态：pending、running、approval、failed、completed。
- 写入动作必须可撤销或可审计，至少记录目标路径、摘要、权限来源和 run id。
- 证据引用应能回到论文、PDF 选区、Wiki 文档或材料文件。
- 后续接入 Apple Intelligence 时，优先预留 App Intents、Spotlight semantic index、Foundation Models / Language Model protocol 的抽象边界，而不是把系统 AI 直接耦合到聊天视图。

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
- 写回 wiki、paper notes、tasks 或 recommendation follow-up 的路径受限且可审计。
- AgentRuntime 测试在改动相关代码时通过。
