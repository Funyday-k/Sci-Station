# 任务书 25：AI Lab Usable Conversation and Paper Workflow V2

更新时间：2026-05-01

## 1. 本轮目标

任务书 24 已完成 AI Lab 的可用性基础，但真实 `ai-paper-doc-todo` 工作流暴露了几个硬阻塞：发送不像 chat、页面不会跟随最新消息、短消息气泡过宽、AI 只看到很少论文内容、模型/工具控制太隐蔽、prompt 仍像单轮英文任务。

本轮第一要务是让 AI Lab 能真正服务论文-文档-todo 工作流。Project Lifecycle 继续后置；只有当 AI 能稳定多轮对话、读取论文元信息/正文摘录、并让用户清楚选择模型和工具时，才进入下一步功能。

## 2. 用户反馈必须覆盖

1. Chat 发送改为连续两次 Return；AI 思考时 Return 变成暂停/停止输出；发送后输入框立即清空。
2. 对话气泡按文字长短动态调整，不再短句占满宽度。
3. 发送新消息后自动滚动到底部，让用户立刻看到自己刚发的内容和思考状态。
4. AI 不能只看到论文标题；需要 PDF 转 Markdown 能力，并以 MinerU-compatible 的方式生成/读取 `paper.md`。
5. API cache 命中太低，疑似没有真正多轮；需要重读并优化项目内 Agent prompt，让 AI 按用户语言回答。
6. AI Lab 的设置按钮默认进入 Settings 的 AI Lab 分栏。
7. Copilot Export 含义不明；需要解释为外部桥接导出，或从主输入区移除。
8. 左侧栏标题本身可折叠；子项目缩进；标题语言跟随当前 UI；长名显示前部；hover 子项目显示 pin/archive；pin 后折叠时仍显示该子项目；archive 点击前询问。
9. 工具选择要参考 opencode 风格：可见、可选、和权限边界清楚。
10. DeepSeek provider 下要提供不同 model 选择。

## 3. 执行任务

### 3.1 Composer and Timeline

1. 实现连续两次 Return 发送。
2. 捕获 prompt 后立即清空 composer draft。
3. 生成中将发送按钮切换为停止/暂停输出，并让 Return 触发同一动作。
4. pending prompt、thinking、timeline event、run 改变时自动滚动到底部。
5. 用户和 AI 气泡在最小/最大宽度内按内容长度估算宽度。
6. Thinking 状态显示动态文案/轻量动画；真正 streaming 之前先做本地生成体验。

### 3.2 Paper Context and PDF Markdown

1. 扩展 `AgentPaperSnapshot`：venue/publication、DOI、arXiv、URL、language、folder、PDF/Markdown 相对路径、metadata summary。
2. 有 `paper.md` 时读取受限长度 excerpt 进入 Agent context。
3. 增加 PDF -> Markdown service：优先保留 MinerU-compatible 输出路径，当前若无 MinerU CLI，也要用 PDFKit fallback 写出可读 `paper.md`。
4. 在 AI Lab 增加“为已选知识论文生成 Markdown”的动作。

### 3.3 Prompt, Multi-Turn, and Cache Shape

1. 当 provider 支持 chat messages 时，将稳定 system/context 与当前用户 turn 分离。
2. 将当前 thread 最近对话历史传给 planner。
3. prompt 明确：除非用户指定其他语言，否则使用用户当前语言回答。
4. Conversation 模式保持 tool_calls 为空；Plan/Assistant 继续受安全边界约束。

### 3.4 Settings, Tools, Models, and Copilot Bridge

1. Settings category 状态移入 `AppViewModel`，AI Lab 齿轮直接打开 AI Lab 分栏。
2. 增加 DeepSeek model preset picker/menu。
3. 增加 AI Lab 工具 toggle；最终可用工具 = 用户勾选工具 ∩ 当前模式允许工具。
4. Copilot Bridge 从“神秘 Export”改为有说明的外部 prompt/manifest 导出。

### 3.5 Sidebar Chat Ergonomics

1. AI Lab、Collection、Project 标题点击即可折叠/展开。
2. 子项目缩进更明显，长名使用 tail truncation 保留前部。
3. Chat 子项 hover 时显示 pin/archive 图标。
4. Pin 的 chat 在 AI Lab 折叠后仍保留可见。
5. Archive 前弹出确认。

### 3.6 Knowledge Library Filters

1. 在搜索基础上整合分类 filter：All、Project、Core、Tagged、Has PDF、Has Markdown、Missing Markdown。
2. 保留 All/Clear/Done 和选择数量显示。
3. 过滤只影响列表呈现，不偷偷修改已有选择。

## 4. 非目标

- 不推进旧 Project Lifecycle Control。
- 不引入无限 Auto Run Loop。
- 不允许未审批 workspace 写入。
- Plan 文档只写 root `wiki/plans/`；Project Wiki 后续必须由 agent tool 操作。
- 不引入 OpenCode runtime/front-end 依赖，只学习其交互结构。

## 5. 验收标准

1. 双 Return 发送、发送后清空、生成中 Return/按钮可停止。
2. 新消息自动滚动到底部，thinking 气泡立即可见。
3. 短消息短气泡，长消息在上限宽度内换行。
4. 选中论文的元信息和 `paper.md`/PDF excerpt 能进入 Agent context。
5. 应用能从选中 PDF 生成可读 `paper.md`。
6. Provider request 包含多轮历史，prompt 按用户语言回答。
7. AI Lab 设置齿轮直接打开 Settings > AI Lab。
8. 工具选择、DeepSeek model 选择可见并影响 agent run。
9. Copilot Bridge 的目的和输出路径清晰。
10. Sidebar 折叠、缩进、pin、archive confirmation、长名显示符合反馈。

## 6. 验证计划

1. 运行 VS Code error check。
2. 运行 `swift run SciStationCoreTestRunner`。
3. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath ./.derivedData build`。
4. 最终检查 git changed files/status。

## 7. 完成记录

已完成。

### 7.1 已实施

- AI Lab composer 支持双 Return 发送，发送后立即清空输入；生成中按钮和 Return 可停止当前输出任务。
- Timeline 使用 `ScrollViewReader` 自动滚动到底部；thinking bubble 改为动态状态文案。
- 对话气泡按内容估算宽度，短句不再占满固定宽度。
- AI knowledge library 增加 All / Project / Core / Tagged / Has PDF / Has Markdown / Missing Markdown 过滤，并提供选中论文 PDF -> `paper.md` 的转换动作。
- 新增 MinerU-compatible PDF-to-Markdown bridge：当前通过 PDFKit fallback 写出可读 `paper.md`，保留后续接入 MinerU richer output 的前置格式。
- `AgentPaperSnapshot` 扩展 venue、publication、DOI、arXiv、URL、language、PDF/Markdown 路径、metadata summary、Markdown/PDF excerpt。
- Agent prompt 支持 chat provider 多轮消息：system/context、历史对话、当前 user_goal 分离；明确按用户语言回答。
- AI Lab 设置齿轮直接打开 Settings > AI Lab；Settings 中增加 AI Lab Tools、DeepSeek model picker、Copilot Bridge 解释与导出入口。
- 工具选择会与当前 Conversation / Plan / Assistant 模式边界取交集。
- 左侧 AI Lab chat 支持 pin、hover archive、archive confirmation；折叠时 pinned chat 保持可见。Collection / Project 标题点击可折叠。

### 7.2 验证

- VS Code error check：触达 Swift 文件无错误。
- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath ./.derivedData build`：通过。

### 7.3 剩余风险

- PDF-to-Markdown 当前是 PDFKit fallback，不是完整 MinerU layout/公式/表格解析；下一轮应接入可配置 MinerU CLI 并保留 fallback。
- 工具开关和 pinned chat 当前为运行时状态，尚未写入 workspace preferences。
- Thinking/生成动画仍是非 streaming 的本地状态动画；真正逐 token streaming 需要 provider streaming path。
