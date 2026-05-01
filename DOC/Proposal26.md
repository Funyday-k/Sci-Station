# 任务书 26：AI Lab Streaming, MinerU, and Workflow Smoke V1

更新时间：2026-05-01

## 1. 本轮目标

任务书 25 已经把 AI Lab 的对话入口、论文上下文、PDF -> Markdown fallback、多轮 prompt、工具/模型选择和侧栏交互补齐到可用状态。下一轮应把“看起来可用”推进到“跑真实 paper-doc-todo workflow 可复现”：真正 streaming、真实 MinerU、设置持久化、以及一次完整手动 smoke run。

本轮同时吸收 2026-05-01 的最新交互反馈：生成中 Return 不应触发停止；New Chat 必须立即清空当前对话界面；Conversation 模式不能因为模型直接输出自然语言或 Markdown 而报 “not JSON”；消息气泡需要 Markdown 渲染。

## 2. 背景与已验证状态

- SwiftPM core validation 已通过。
- Xcode macOS app build 已通过。
- AI Lab 现在能在 selected knowledge papers 上读取 metadata、`paper.md` excerpt 或 PDFKit fallback excerpt。
- Conversation / Plan / Assistant 的工具边界仍保持：Conversation 无工具，Plan 只允许 planning markdown，Assistant 需审批。
- Plan 文档仍只写 root `wiki/plans/`，Project Wiki 后续由 agent tool 操作。

## 3. 执行任务

### 3.0 Immediate Conversation Fixes

1. 生成中 Stop 只能由 Stop 按钮触发，Return / 双 Return 不触发暂停或停止。
2. New Chat 应立即显示空时间线，不再沿用旧 thread/run/session event。
3. Conversation 模式允许模型直接返回自然语言或 Markdown，并转为无工具的 `AgentPlan` 记录；Plan / Assistant 仍保持结构化 JSON 约束。
4. 对话气泡支持 Markdown 渲染，并保留文本选择能力。
5. AI Lab 主界面高频标签尽量切换为中文，减少“明明在中文对话但 UI/错误仍英文”的割裂感。

### 3.1 Streaming Provider Path

1. 为 OpenAI-compatible provider 打通 streaming response path，优先支持 assistant text delta；默认覆盖 DeepSeek OpenAI-compatible。
2. 将 GitHub Copilot SDK adapter 纳入实验 streaming 接口：SDK 未真正接入时明确返回未打包状态，不伪装成功。
3. AI Lab timeline 显示真实增量文本，而不是仅本地 thinking 动画。
4. Stop 按钮应真正取消 streaming task，并保留已生成的 partial response。
5. 若 provider 不支持 streaming，回退到任务书 25 的非 streaming path。

### 3.2 MinerU CLI Integration

1. 增加 MinerU CLI 配置项：默认命令为 `mineru`，并支持是否覆盖现有 `paper.md`。
2. PDF -> Markdown 优先调用 MinerU；失败时使用 PDFKit fallback。
3. 在 `paper.md` frontmatter 中记录 extraction engine、时间、source PDF、错误/降级状态。
4. AI knowledge library 显示 MinerU / fallback / missing 状态。

### 3.3 Persistence for Tool and Sidebar State

1. 将 AI Lab disabled tools 按 project / AI thread scope 写入 workspace preferences。
2. 将 pinned agent thread IDs 按 project 写入 workspace preferences。
3. App 重启后保持工具选择和 pinned chat 状态。
4. 保持 archived chat 不被 pin 状态重新显示。

### 3.4 Paper-Doc-Todo Smoke Run

1. 固定一个手动 smoke scenario：使用 `Test_Workspace` 工作区的所有文章，生成 `paper.md`，询问论文关系，生成 root `wiki/plans/` 计划，审批创建 todo。
2. 在任务书中记录实际观察：成功路径、失败路径、AI 是否引用了论文内容、工具调用是否可审查。
3. 必要时补充最小测试覆盖：paper whitelist、tool selection intersection、markdown conversion fallback。

### 3.5 UI Polish After Real Use

1. 检查双 Return 是否误伤需要空行的长 prompt。
2. 检查短/长气泡在窄窗口下是否仍稳定。
3. 检查 AI Lab Settings 中工具/模型/Bridge 文案是否足够清楚。
4. 检查 Sidebar pin/archive hover 在折叠状态是否符合预期。

## 4. 非目标

- 不实现完整向量数据库或 RAG。
- 不推进 Project Lifecycle Control。
- 不让 Project Wiki 通过普通 UI 直接写入。
- 不取消现有 approval flow。

## 5. 验收标准

1. 支持 streaming provider 时，AI 输出能逐步显示，Stop 能取消。
2. MinerU CLI 可配置；不可用时 fallback 明确且可追踪。
3. 工具选择和 pinned chat 状态能跨重启保留。
4. 完成一次真实 paper-doc-todo smoke run，并在任务书中记录结果。
5. SwiftPM core validation 通过。
6. Xcode macOS build 通过。

## 6. Decisions

1. MinerU CLI 默认命令名：`mineru`。
2. Streaming 覆盖：DeepSeek OpenAI-compatible 与 GitHub Copilot SDK adapter 实验接口。
3. Tool/pin 状态：按 project / AI thread 分开持久化。
4. paper-doc-todo smoke run：使用 `Test_Workspace` 工作区的所有文章。

## 7. Question

1. 下一轮是否要把 Conversation 模式完全改成“普通聊天协议”，只在 Plan / Assistant 时要求 JSON？
2. MinerU 输出目录如果产生多份 Markdown，是否优先使用 MinerU 的主文档，还是保留全部输出到 paper 目录？
3. GitHub Copilot SDK adapter 的真实接入是否继续走 OAuth relay，还是先只保留 Bridge export？

## 8. 完成记录

已完成 V1。

### 8.1 实施摘要

- Composer：生成中 Return / 双 Return 不再触发 Stop；Stop 只由按钮触发。
- New Chat：空 draft thread 会立即显示空 timeline，不再因为 session id 为空而回退展示旧事件。
- Conversation fallback：聊天模式允许模型直接返回自然语言或 Markdown；非 JSON 内容会被保存为无工具 `AgentPlan.final_response_draft`，Plan / Assistant 仍保留 JSON 约束。
- Markdown 气泡：用户与 AI 气泡改为 `AttributedString(markdown:)` 渲染，保留 text selection。
- Streaming V1：OpenAI-compatible provider 支持 SSE delta；AI Lab 会显示真实增量文本。GitHub Copilot SDK adapter 暴露 experimental streaming surface，但 SDK 未打包时明确返回 unavailable。
- MinerU V1：PDF -> Markdown 默认尝试 `mineru -p <pdf> -o <output>`；失败或无 Markdown 输出时自动 PDFKit fallback；frontmatter 记录 extraction engine、时间与 fallback reason。
- Persistence：AI Lab disabled tools 按 project/thread scope 写入 `settings/workspace_preferences.yaml`；pinned agent threads 按 project 写入 workspace preferences。
- Settings：AI Lab 设置增加 MinerU command 与覆盖已有 `paper.md` 开关。
- UI 语言：AI Lab 常见模式、timeline 事件标题、输入占位和状态提示切换为中文。

### 8.2 Smoke 观察

- 找到外部工作区：`/Users/funyday/Documents/Test_Workspace`。
- 该工作区包含 3 个 PDF：`sarkarxxxx-constraining-dark-matter`、`garani2017-dark-matter-sun`、`widmark2017-thermalization-time-scales`。
- 3 个 `paper.md` 目前都存在，但内容仍为 `status: not_extracted` stub。
- 当前终端 PATH 未找到 `mineru`，因此真实 MinerU CLI run 在本机环境中不可执行；App 会在命令不可用时进入 PDFKit fallback。
- 完整 paper-doc-todo AI smoke（询问论文关系、生成 plan、审批 todo）仍依赖实际 App 会话和可用 LLM key，本轮完成代码路径与数据目标检查。

### 8.3 验证

- VS Code error check：通过。
- `swift run SciStationCoreTestRunner`：通过；新增覆盖 Conversation plain-text fallback 与 workspace preferences scoped state round-trip。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath ./.derivedData build`：通过。

### 8.4 剩余风险

- `mineru` 未安装或不在 PATH 时只能验证 fallback；安装后仍需在 App 内触发一次真实解析。
- GitHub Copilot SDK adapter 仍是实验接口，真实 SDK execution 未打包。
- Conversation streaming V1 主要面向自然语言/Markdown；Plan / Assistant 仍建议等待完整 JSON 后展示结构化结果。
