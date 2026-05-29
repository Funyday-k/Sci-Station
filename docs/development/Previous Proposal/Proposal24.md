# 任务书 24：AI Lab Usable Workflow V1

更新时间：2026-05-01

## 1. 本轮结论

原任务书 24 已移为 [docs/development/Proposal-1.md](Proposal-1.md)，作为后续 Project Lifecycle Control 候选。本轮新的任务书 24 不推进生命周期新功能，优先把 AI Lab 优化到可用状态，确保 `ai-paper-doc-todo` 工作流能跑通：AI 能按用户选择读取论文知识库，围绕论文、Markdown 文档和 todo 进行对话、计划和受控操作。

opencode-dev 的优秀点不在装饰，而在交互结构：清晰的 session timeline、底部 composer、可见的 pending interaction、精简的 top context、可切换 agent/mode、侧栏管理历史、设置集中管理 runtime 细节。本轮借鉴这些模式，但继续保持 Swift-native，不引入 OpenCode runtime 依赖。

## 2. 当前问题

1. 全局右栏信息不明且不可折叠，AI Lab 的 runtime rail 也挤占主对话空间。
2. AI 可读取哪些 papers 不透明；用户无法选择哪些论文进入 AI 知识库。
3. AI Lab 顶栏和底栏信息重复，底栏意义不够明确。
4. 运行时设置散落在中间栏折叠区，Settings 本身也缺少清晰分类。
5. Hook 结果在主界面可见度过高，干扰对话主线。
6. 所有对话都像 plan 模式，缺少 conversation / plan / assistant 的意图边界。
7. 发送 prompt 后缺少即时用户气泡和 thinking 占位，反馈不够像真正对话。
8. 对话历史在右侧 runtime 中，不适合日常查找；历史需要放到左侧 AI Lab 下，并支持右键管理。

## 3. 执行任务

### 3.1 AI Knowledge Library

1. 在 AI Lab 顶栏显示 AI knowledge papers：选中数量 / 全库数量。
2. 点击该信息时弹出论文选择界面。
3. 论文列表支持勾选 / 取消勾选，并支持 All / Clear。
4. Agent snapshot、plan、Copilot Bridge export 只包含选中的论文；未选中的论文不进入 AI workspace context。
5. 默认状态为了兼容旧行为，首次进入时选中全部论文。

### 3.2 Collapsible Global Inspector

1. 全局右栏增加折叠入口。
2. 折叠后保留窄按钮，可恢复 Inspector。
3. AI Lab 内部 runtime rail 不再展示 Hook results；runtime 详情转移到 Settings 的 AI Lab 分类。

### 3.3 Settings Categories

1. Settings 改为左侧分类 + 右侧内容的分栏结构。
2. 至少包含 Workspace、Projects、Library、Tasks、AI Lab、Developer 分类。
3. AI Lab 分类聚合 LLM provider、GitHub Copilot、Agent Platform、Preset、Hook/MCP runtime details。
4. Hook 结果只在 AI Lab settings 的细节区域保留，不进入主对话流。

### 3.4 AI Lab Mode Selector

1. 增加三种模式：Conversation、Plan、Assistant。
2. Conversation：只读取信息、处理信息，不执行工具，不显示 Run Approved Tools。
3. Plan：允许生成计划，并允许 Markdown planning 工具；不允许修改软件其他信息。
4. Assistant：允许进入现有 tool approval + execute flow。
5. UI 文案要让用户知道当前模式能做什么。

### 3.5 Composer and Thinking Feedback

1. 发送后立即在 timeline 里显示用户输入。
2. AI 正在生成时显示 assistant thinking 状态气泡。
3. 返回结果后用真实 session events / run card 替换 thinking 占位。
4. Composer 底栏只保留固定功能按钮，不重复 project/model/provider 信息。

### 3.6 Sidebar Chat History

1. AI Lab 在左侧 sidebar 中可展开，显示当前项目的最近对话。
2. 对话支持右键 Open、Rename、Archive、Duplicate Prompt。
3. 第一轮 AI 对话完成后，线程标题用 plan title / prompt 自动生成。
4. 主 AI Lab 中不再把 Conversation History 放在右侧 runtime rail。

### 3.7 Top Bar Compression

1. AI Lab 顶栏只保留 mode、knowledge papers、AI settings 等高价值信息。
2. 移除重复信息；provider/runtime 细节进入 Settings / AI Lab 分类。
3. 顶栏保持紧凑，避免挤压对话内容。

## 4. 非目标

- 不启用无限 Auto Run Loop。
- 不引入 OpenCode runtime 或前端依赖。
- 不推进 [docs/development/Proposal-1.md](Proposal-1.md) 的 Project Lifecycle Control。
- 不绕过现有 permission layer。
- 不在本轮完成所有 paper-doc-todo 真实业务 prompt 优化；下一轮专门跑通真实工作流。

## 5. 验收标准

1. AI Lab 顶栏能显示 selected / total AI knowledge papers。
2. 用户能弹出论文列表并勾选 AI 可读取的论文。
3. Agent context 中 recent/project papers 只包含选中的论文。
4. 全局 Inspector 可折叠和恢复。
5. Settings 有清晰分类，AI Lab settings 聚合 provider、Copilot、runtime details。
6. Hook results 不再显示在 AI Lab 主对话界面。
7. AI Lab 支持 Conversation / Plan / Assistant 三种模式。
8. Conversation 模式不展示执行工具入口；Assistant 模式保留审批执行。
9. Plan 模式只允许 Markdown planning 工具进入审批执行。
10. 发送 prompt 后立即显示用户气泡和 thinking 气泡。
11. AI Lab 底栏只保留固定功能按钮。
12. AI Lab 对话历史出现在左侧 AI Lab 折叠区，并支持右键管理。
13. 第一轮 AI 完成后线程标题不再停留在 New Chat。
14. `swift run SciStationCoreTestRunner` 通过。
15. Xcode macOS build 通过。

## 6. 完成记录

已完成。

- AI knowledge library 已接入顶栏，支持论文勾选、All、Clear，并持久化到 workspace preferences。
- Agent snapshot、plan、Copilot Bridge export 已按选中论文过滤；工具执行上下文也加入论文白名单保护。
- 新增 Conversation / Plan / Assistant 模式：Conversation 不暴露工具，Plan 只允许 `write_markdown_plan`，Assistant 保留现有受控执行。
- 新增 `write_markdown_plan` 工具，写入 `wiki/plans/*.md` 并继续走 approval flow。
- AI Lab 主界面去掉 runtime rail，Hook results 从主 timeline 过滤，只保留在 Settings / AI Lab。
- Settings 已改为 Workspace / Projects / Library / Tasks / AI Lab / Developer 分类。
- 全局右侧 Inspector 已支持折叠与恢复。
- AI Lab 对话历史已移入左侧 AI Lab 折叠区，支持 Open、Rename、Archive、Duplicate Prompt。
- Composer 已实现即时用户气泡和 AI thinking 气泡，底栏只保留固定功能按钮。

验证记录：

- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath ./.derivedData build`：通过。

## 7. 复盘

本轮把 AI Lab 从“能展示 agent runtime”推进到“用户能控制 AI 可读上下文并按模式使用”的状态。剩余风险主要在真实 `ai-paper-doc-todo` 业务链路：虽然 UI 与权限边界已经到位，但还需要用实际论文集合、Markdown planning 文档和 todo 创建/更新任务反复跑通，检查 prompt、context granularity、response rendering 和 tool call 质量。

## 8. Question

1. 下一轮是否以真实 `ai-paper-doc-todo` 场景作为唯一主线，先不推进 Project Lifecycle？建议是。
2. AI knowledge library 是否还需要加入“按项目/标签/文件夹批量选择”？建议下一轮加入。
3. Plan 模式写入的 Markdown plan 是否固定到 `wiki/plans/`，还是需要按项目写到 project wiki？建议下一轮决定并实现 project-local path。
4. Conversation 模式是否需要优化为直接显示最终回答，而不是仍经过 plan JSON 的内部结构？建议下一轮处理。