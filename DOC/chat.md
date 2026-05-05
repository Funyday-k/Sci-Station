P1.6 完成。本轮交付总结：

**Threads 全局化 + workspace 标签**（已实施）：
- 模型：`AgentThread` 增加 `workspaceID` / `workspaceName`，用于把工作区变成标签而不是存储分区。
- 存储：`AgentThreadRepository` 迁到 macOS Application Support 全局 store：`~/Library/Application Support/Sci-Station/agent/threads.jsonl`。旧的 `{workspace}/.sci-station/agent/threads.jsonl` 会在读取/写入线程时一次性迁入全局 store，并保留为 `{workspace}/.sci-station/agent/threads.legacy.jsonl`。
- UI/状态：AI Lab 默认显示全部 workspace 的线程；顶部 thread strip 增加 `Current workspace` 开关；thread strip 和左侧 AI Lab 侧边栏都显示 workspace 标签副标题。Settings 的 Agent Threads 路径也改为全局 store。
- 测试：`SciStationCoreTestRunner` 新增 `agentThreadRepositoryGlobalStoreFiltersByWorkspaceID`、`agentThreadRepositoryMigratesPerWorkspaceLegacy`，并更新 legacy archive 测试为注入临时 store，避免写入真实 Application Support。

**验证**：
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。

**重要余留**：线程列表现在是全局的，但 agent run log / session event log 仍然是 workspace-local。打开另一个 workspace 的历史线程时，标题和标签可见；若当前 workspace 没有对应 `runs.jsonl`，timeline 内容可能为空。这是 P1.6 的已知边界，后续可在 session/event 全局化或 thread preview 摘要中处理。

用户随后基于 App 截图反馈三点：AI 气泡悬停后无法滚动、多行代码块显示不完整、工具菜单只有 3 个且看不到论文 read/search 能力。

**反馈修复已完成**：
- `ChatMarkdownWebView` 改用滚轮透传 WKWebView 子类；垂直滚动交给外层时间线，解决鼠标在 AI 对话框上时无法上下滑动。
- `ChatRenderer.bundle/index.html` 的 `pre code` 改为保留换行并按气泡宽度换行，改善多行/长行代码块显示。
- 默认 agent registry 新增 `list_papers`、`read_paper`、`read_paper_section`、`search_papers` 四个只读论文工具，permissionKey = `paper.read`，工具菜单不再只有 3 个。
- AI Lab runtime 事件行增加折叠详情；`reasoning_summary` 显示为“思考摘要”，工具参数/结果可展开查看。注意这里展示的是可审计摘要，不是隐藏 chain-of-thought。
- 新增 CoreTestRunner case：`agentPaperReadToolsReturnSectionsAndSearchMatches`，覆盖章节读取、行号搜索、默认 registry 暴露。

**验证**：
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。

继续完成 P31.4/P31.5/P31.6/P31.8：

- `AgentWorkspaceContextBuilder.snapshot` 默认改为 metadata-only；选中论文、AI Knowledge 论文、recent/project paper 列表都不再携带 `paper.md` / PDF 正文。已转换论文仍通过 `raw_markdown_relative_path` 暴露路径，供 paper tools 按需读取。
- 新增 `AgentPaperContextPolicy.legacyExcerpts`，用于调试/兼容旧的 excerpt 注入行为；CoreTestRunner 验证 legacy 策略仍可保留深处 markdown 内容。
- `AgentPromptBuilder` 现在明确要求：当用户需要论文公式、章节、方法、论据、引用或详细总结时，应先计划调用 `search_papers` / `read_paper_section` / `read_paper`，并在回答中回显 `paper_id` 或相对路径。
- 新增 CoreTestRunner case：`agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault`、`agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext`、`agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext`。

**验证**：
- `get_errors` 对本轮编辑 Swift 文件无报错。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。

**下一项建议进入 `DOC/Proposal32.md`**：实现 P1.2 AgentLoopRunner，让模型能真正 `model -> tool_call -> tool_result -> model` 多步运行。当前 paper tools、metadata-only prompt、折叠 runtime UI 已经为这一步打底。

继续根据用户两张截图调研 OpenCode agent 交互逻辑，并重新规划权限/交互：

- 新增 `DOC/OpenCode-Agent-Interaction-Report.md`，记录 OpenCode session loop、tool part、permission ask/reply、auto-allow 和 UI dock 逻辑。
- 确认本地三个根因：Chat 模式禁用所有工具；Permission Dock 显示了 auto-allowed read-only 工具；手动执行工具后没有继续第二轮模型回答。
- `DOC/Proposal32.md` 已调整：Chat/Assistant 都应走 loop；Chat 只允许只读工具自动执行；Permission Dock 只保留 pending ask。
