# 任务书 31：AI Lab 按需读论文工具与 Tool Loop 前置

更新时间：2026-05-02

> 本任务书承接任务书 30。P1.1 已完成 Markdown + KaTeX 渲染，P1.6 已完成 Threads 全局化与 workspace 标签。本轮建议推进 P1.3「按需读论文工具」，先把 research-agent 最需要的只读工具契约稳定下来，再进入 P1.2 的真正 multi-step tool loop。

## 1. 已验证状态

1. `swift run SciStationCoreTestRunner` 通过。
2. `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
3. AI Lab 线程默认读取全局 store；workspace 作为标签与过滤器存在，旧 workspace-local thread 文件会迁移并归档。
4. 聊天渲染器已具备 GFM + KaTeX 展示能力，后续 tool loop 的最终回答可直接受益。

## 2. 本轮目标

让 AI Lab agent 不再把论文 markdown 全文无条件塞进 prompt，而是默认只给模型论文 metadata，并提供一组可被后续 tool loop 调用的只读 paper tools：

1. `list_papers`：按 project / tag / paper_id / query 列出候选论文，返回稳定 `paper_id`、标题、作者、年份、路径、是否已转换。
2. `read_paper`：读取指定 `paper.md`，支持分页或 range，返回页信息与截断提示。
3. `read_paper_section`：按 markdown heading 路径或 byte/line range 读取章节片段。
4. `search_papers`：在候选 `paper.md` 中做关键词搜索，返回 paper_id、heading、行号与上下文片段。

## 3. 实施任务

- [x] [P31.1] 梳理现有 `AgentBuiltInTools` / `AgentToolExecutor` / `AgentWorkspaceContextBuilder` 的工具注册、参数 schema、执行结果格式，确认最小改动路径。
- [x] [P31.2] 新增 paper tool 参数与结果模型，保持 `Codable`、`Sendable`，错误信息对模型可读，对 UI 可折叠展示。
- [x] [P31.3] 实装 `list_papers`、`read_paper`、`read_paper_section`、`search_papers`，只读工具默认 `risk == .readOnly`，permissionKey 使用 `paper.read`。
- [x] [P31.4] 调整 `AgentWorkspaceContextBuilder.snapshot`：默认只注入 metadata，不注入 `paper.md` 全文；新增 `AgentPaperContextPolicy.legacyExcerpts` 作为 legacy/调试 fallback。
- [x] [P31.5] 更新 `AgentPromptBuilder`：明确需要论文正文、公式、章节、证据时优先计划调用 `search_papers` / `read_paper_section` / `read_paper`，引用论文时带 `paper_id` 或相对路径。
- [x] [P31.6] 补充 CoreTestRunner：`agentPaperReadToolsReturnSectionsAndSearchMatches` 覆盖章节读取、行号搜索和默认 registry 暴露；新增 `agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault`、`agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext`、`agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext`。
- [x] [P31.7] 运行验证：`swift run SciStationCoreTestRunner` 与 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 均通过。
- [x] [P31.8] 更新 `docs/development/Proposal30.md` 完成记录与 `docs/development/chat.md` handoff，并写下一轮任务书 `docs/development/Proposal32.md`（P1.2 AgentLoopRunner）。

## 4. 验收标准

1. 在包含已转换论文的 workspace 中，`AgentWorkspaceContextBuilder.snapshot` 默认不再包含大段 markdown 正文，只包含论文 metadata 与可用工具提示。
2. `read_paper_section` 能根据 heading 路径返回目标章节，结果包含 paper_id、heading、来源路径和截断状态。
3. `search_papers` 能返回带行号/heading 的命中片段，且不会读取工作区外文件。
4. 只读 paper tools 的 schema 能被 `AgentPromptBuilder` 或现有 tool plan fallback 看见，为 P1.2 tool loop 做好接口准备。
5. CoreTestRunner 新增 case 全部通过，Xcode app build 通过。

## 5. 已知边界

- 本轮不实现真正 multi-step `model -> tool_result -> model` loop；P1.2 继续。
- 本轮不引入全文索引或向量数据库；`search_papers` 使用直接文本扫描。
- 本轮不把 agent run log / session event log 全局化；P1.6 的线程全局化边界继续存在。
- 本轮不做 MCP 接入；MCP 属于任务书 30 Phase 2。

## 6. Questions

1. `read_paper` 默认返回策略选哪个：A. 第一页 + page token；B. 全文但硬截断；C. 只返回目录/heading，强制模型再调 `read_paper_section`？推荐 A。
2. `search_papers` 的 query 是否需要支持多个关键词 AND/OR，还是先做单字符串 contains + 大小写不敏感？推荐先做单字符串。
3. `paper_id` 是否沿用现有库内 paper.id，还是额外接受文件相对路径作为别名？推荐两者都接受，结果统一回显 paper.id。
4. P1.2 tool loop 前，是否先让现有 plan fallback 可以手动执行这些 paper tools 作为过渡？推荐是，这样 P1.3 可以独立验收。

## 7. 2026-05-02 用户反馈修复记录

用户实测反馈三点：AI 对话框内鼠标悬停后无法滚动、多行代码块显示不完整、工具菜单只有 3 个且看不到论文 read/search 能力。

已修复：

1. `ChatMarkdownWebView` 改用滚轮透传的 `WKWebView` 子类，垂直滚动交还给外层 SwiftUI 时间线，解决鼠标在 AI 气泡上时无法上下滑动的问题。
2. `ChatRenderer.bundle/index.html` 的 `pre code` 样式改为保留换行并在气泡宽度内换行，避免多行/长行代码块被横向裁掉或撑坏布局。
3. 默认工具注册新增 `list_papers`、`read_paper`、`read_paper_section`、`search_papers` 四个只读论文工具；工具菜单会从 3 个扩展到包含论文检索/读取能力。
4. AI Lab runtime 事件行增加折叠详情；计划摘要、工具参数、工具执行事件可像 Copilot/OpenCode 一样展开查看。当前展示的是可审计的思考摘要（summary/steps/tool plan），不是模型隐藏 chain-of-thought。
5. CoreTestRunner 新增 `agentPaperReadToolsReturnSectionsAndSearchMatches`，验证章节读取、行号搜索和默认 registry 暴露；`swift run SciStationCoreTestRunner` 与 Xcode build 均通过。

待继续：

1. P1.2 尚未完成：当前还不是完整自动多步 `model -> tool_result -> model` loop；新增折叠事件和 paper tools 已经为后续 tool loop 展示打好 UI/工具基础。
2. P1.4 的 skill loader、P1.5 的确定性安全 hook 仍待后续任务书推进。

## 8. 2026-05-02 P31 完成记录

本轮已把 P1.3 的按需读论文工具纵向切通：

1. `AgentWorkspaceContextBuilder.snapshot` 默认 metadata-only：选中论文、AI Knowledge 论文、recent/project paper 列表都不再直接携带 `paper.md` / PDF 正文；如果已转换，仍通过 `raw_markdown_relative_path` 暴露 `paper.md` 路径，供工具按需读取。
2. 新增 `AgentPaperContextPolicy.legacyExcerpts`：保留旧版 excerpt 行为，用于调试或临时兼容；CoreTestRunner 验证深处 markdown marker 仍能在 legacy 策略下出现。
3. `AgentPromptBuilder` 现在明确说明 paper snapshots 是 metadata-first：当用户要公式、章节、方法、论据、引用或详细总结时，应先计划 `search_papers` / `read_paper_section` / `read_paper`，再基于工具结果合成回答。
4. CoreTestRunner 已新增 metadata-only、legacy excerpt、prompt 指令三条覆盖；`swift run SciStationCoreTestRunner` 与 Xcode app build 均通过。
5. 下一轮任务书：`docs/development/Proposal32.md`，目标是 P1.2 真正的 AgentLoopRunner。