# MT99：Release Regression 手动测试

更新时间：2026-05-05

## 目标

每个任务书结束前执行 30-45 分钟轻量回归，确认新功能没有破坏 Sci-Station 的核心主路径。

## 前置条件

- 已运行自动化基线，或报告中标记失败原因。
- 使用 Standard Workspace。
- 需要时补充 Empty Workspace 创建测试。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT99-01 | 创建新 workspace | 成功创建，不误写源码仓库 |
| MT99-02 | 打开旧 workspace | 成功打开，必要时安全迁移 |
| MT99-03 | 导入 PDF | Library 出现论文 |
| MT99-04 | 打开 PDF Reader | PDF 可阅读，基础控件可用 |
| MT99-05 | 保存 annotations.md | 文件落盘，重启后恢复 |
| MT99-06 | 新建 Wiki 页面并 Cmd+S | 文件落盘，Preview 可用 |
| MT99-07 | 新建 todo | Calendar/Tasks 可见，重启保留 |
| MT99-08 | 打开 Materials 并预览文件 | 不显示系统目录，预览正常 |
| MT99-09 | 打开 Projects | 项目列表/详情不崩溃 |
| MT99-10 | 打开 AI Lab | 基础 UI 可用 |
| MT99-11 | 打开 Settings | runtime/workspace 设置可见 |
| MT99-12 | 关闭并重启 App | 最近 workspace 恢复或安全回到欢迎页 |
| MT99-13 | 最近 workspace 自动恢复 | security-scoped bookmark 失效时不崩溃 |
| MT99-14 | 检查 Research Root 敏感文件 | 未出现 API key、`.env` 副本、Keychain 导出、debug secret |

## Partial Regression 规则

每个任务书至少执行：

```text
MT99-01 或 MT99-02
MT99-06
MT99-07
MT99-10
MT99-11
MT99-12
MT99-14
```

如果本轮修改涉及 Library/PDF/Materials/Calendar，则增加对应用例。

## P39.10-P39.12 AI Lab Release Gate

P39.10-P39.12 收口时，MT99 partial regression 额外检查：

```text
MT99-P39.12-01: AI Lab 打开后 runtime/source health/diagnostic buttons 可见且不崩溃。
MT99-P39.12-02: Library Inspector paper.md Health 面板在选择论文、切换论文、无论文状态下均不崩溃。
MT99-P39.12-03: provider failure 或 context budget stop 后，timeline 留下可见失败回复和可重试路径。
MT99-P39.12-04: Debug bundle 与 Copy Diagnostic 仅包含脱敏路径和 workspace-relative source，不包含 secret-looking values。
```

已知非本轮风险：`ChatMarkdownWebView` 的 WebKit actor-isolation warning 继续作为 release risk 记录；除非转为 runtime crash 或影响 AI Lab 主路径，否则不并入 P39.12 修复范围。

## P39.15 AI Lab Markdown / Wiki Writeback Gate

P39.15 收口时，MT99 partial regression 额外检查：

```text
MT99-P39.15-01: AI Lab assistant 气泡使用本地 ChatRenderer 渲染 KaTeX、GFM 表格和 fenced code；旧消息超过 20 条时可安全回退 legacy text。
MT99-P39.15-02: Wiki / Library Markdown Preview 断网可渲染 KaTeX 与表格，运行日志不出现 jsdelivr.net 出站请求。
MT99-P39.15-03: wiki 写回工具只允许 wiki/plans、wiki/papers、wiki/notes、wiki/projects；wiki/papers/<id>.md 必须匹配已有 paper id。
MT99-P39.15-04: 写回 wiki 的非 JSON 模型回复显示为“未确认的写回草稿”，不以 provider_error 结束。
MT99-P39.15-05: provider empty response 或 context/tool budget stop 产生可见 fallback final answer，并保留可重试上下文。
MT99-P39.15-06: Settings → AI Lab Tool Budget 默认显示 20 steps、1M context/accumulated tool text、384K per-tool output，可 reset。
```

P39.15 的阻塞判定：AI Lab Markdown 仍显示原始 `$$...$$`、wiki 写回无法审批到 `wiki/papers/<id>.md`、或 budget/empty response 仍直接变成 `provider_error`，均视为 S0 release blocker。

## P40 Workspace Creation Wizard Gate

P40 收口时，MT99 partial regression 额外检查：

```text
MT99-P40-01: Empty Workspace 的 Create Workspace 打开 Creation Wizard，取消后回到空状态。
MT99-P40-02: Settings → Workspace 的 Create Root 打开同一 Creation Wizard。
MT99-P40-03: 选择 Minimal / Literature Review 后，模块、目录、settings files、routes/project tabs/workflows 预览即时更新。
MT99-P40-04: 未确认 privacy / AI setup boundary 前不能完成创建；确认文案明确不写 API key/provider raw config/prompt/response plaintext。
MT99-P40-05: 非空未知目录被阻止；existing Research Root / legacy workspace 可打开且不覆盖用户文件。
MT99-P40-06: 创建后可进入 sidebar、Settings、Library、AI Lab New Chat entry；AI Lab 模块文案不暗示模型凭证已配置。
```

P40 的阻塞判定：wizard 无法从空状态或 Settings 打开、创建写入 `workspace_modules.yaml` 非确定性、或任一目标路径场景可能覆盖用户文件，均视为 S1/S0 blocker。

## P41 Module Settings Gate

P41 收口时，MT99 partial regression 额外检查：

```text
MT99-P41-01: Settings → Workspace 保留只读 Workspace Modules summary；Settings → Modules 可打开完整模块列表。
MT99-P41-02: 启用 / 关闭模块后 sidebar、ProjectSpace tab、workflow gating 立即刷新，无需重启。
MT99-P41-03: `recommendation` 依赖缺失时直接启用被阻止；Enable Dependencies 单次启用依赖链。
MT99-P41-04: Pin `tasks` 后 project sidebar 顺序刷新；重启后顺序保留。
MT99-P41-05: Repair required directory 需要确认；批准创建，取消不写入，wildcard 不创建外部目录。
MT99-P41-06: Project A override 不影响 Project B；删除 override 后 fallback 到 workspace config。
MT99-P41-07: `.sci-station/debug/app_events.jsonl` 有 module_settings.* 事件，payload 不含 secret、绝对路径或用户论文/wiki正文。
```

P41 的阻塞判定：Settings → Modules 无法打开、module toggle 写坏 `workspace_modules.yaml`、project override 串项目、repair 写出 workspace 外路径或删除用户文件，均视为 S1/S0 blocker。

## P42 Home / Project Dashboard Gate

P42 收口时，MT99 partial regression 额外检查：

```text
MT99-P42-01: Home 打开后 workspace name、module summary、workflow ready badge、Today / Active Projects / AI Review 可见。
MT99-P42-02: Empty Workspace 中 Home 三段面板显示 onboarding CTA，不 crash。
MT99-P42-03: Project Overview 顶部显示 Project Dashboard Panel，StageBadge 与 core papers/open gaps/recent artifacts/next deadline 占位正确。
MT99-P42-04: Settings → Modules 关闭 tasks 后，Home todo/deadline 卡片显示模块关闭引导，点击 Settings 可返回 Modules。
MT99-P42-05: `.sci-station/debug/app_events.jsonl` 有 home.aggregate / project_dashboard.render / home.panel.action，payload 不含 title 正文、paper/wiki 内容、绝对路径或 secret。
```

P42 的阻塞判定：Home 或 Project Overview 打开即 crash、三段面板缺失、debug payload 泄漏用户正文/secret、或模块禁用后导航 fallback 崩溃，均视为 S1/S0 blocker。

## P43 ProjectSpace Shell Gate

P43 收口时，MT99 partial regression 额外检查：

```text
MT99-P43-01: 顶层 sidebar 固定为 Home / Projects / Library / Calendar / AI Lab / Settings；不显示 Materials / Wiki / Tasks 顶层入口。
MT99-P43-02: Projects 打开项目列表；进入项目后显示 ProjectSpace tab strip，Overview leftmost。
MT99-P43-03: 切换 Papers / Wiki / Tasks / Calendar / AI Workflows tab 均不 crash，route.persist 与 project_space.tab_change 写入 debug log。
MT99-P43-04: 启用 citation-graph 后 Graph tab 出现并显示 P44-P46 placeholder；禁用后 fallback 到 Overview。
MT99-P43-05: 拖拽重排 top sidebar / ProjectSpace tabs 后重启仍保留顺序；Settings 与 Overview 不丢失。
MT99-P43-06: 关闭并重启 App 后恢复上次 sidebar item / project / tab；project missing 或 module disabled 时安全降级。
```

P43 的阻塞判定：sidebar 顶层项不收敛、ProjectSpace 无法进入、模块禁用导致 crash、`workspace_preferences.yaml` route/pin 字段损坏、或 debug payload 泄漏用户正文/secret，均视为 S1/S0 blocker。

## P43.9 Home Widgets / Responsive UI Gate

P43.9 收口时，MT99 partial regression 额外检查：

```text
MT99-P43.9-01: Home 默认显示 8 个 widget 入口；Edit Layout 可进入/退出，不打断 HomeSnapshot reload。
MT99-P43.9-02: 上移/下移、拖拽、尺寸切换、隐藏/恢复、Reset Default 均会更新 Home，并写入 `settings/workspace_preferences.yaml` 的 `home_widget_layout`。
MT99-P43.9-03: 窗口宽度约 1400 / 1200 / 900 / 720 pt 时 Home widgets 分别为 4 / 3 / 2 / 1 columns；compact/narrow 右栏隐藏，项目树默认折叠。
MT99-P43.9-04: Library / ProjectSpace / AI Lab / PDF / Wiki / Settings 主路径 toolbar 只显示当前页面动作；narrow 下 page actions 进入 overflow。
MT99-P43.9-05: 简体中文和 English 下 Home widget 标题、gallery、empty state、toolbar overflow 无明显残留或截断。
MT99-P43.9-06: `.sci-station/debug/app_events.jsonl` 有 home.widget.* 与 shell.responsive_policy.apply 事件，payload 不含用户正文、论文/wiki 内容、绝对路径或 secret。
```

P43.9 的阻塞判定：Home 打开即 crash、widget layout 写坏 preferences、模块禁用导致 Home/ProjectSpace crash、窄窗口无法触达页面主动作、或 debug payload 泄漏用户正文/secret，均视为 S1/S0 blocker。

## P47 Graph Workflows Gate

P47 收口时，MT99 partial regression 额外检查：

```text
MT99-P47-01: citation-graph 默认启用时 ProjectSpace Graph tab 与 AI Lab graph tools 可见；关闭模块后 route/tool/workflow 同步隐藏并 fallback。
MT99-P47-02: AI Lab graph read-only 工具调用不触发 Permission Dock；graph_insight 后续写入仍必须审批。
MT99-P47-03: Graph view 的 Generate Reading Order / Explain Connection / Find Bridge Papers action 跳到 AI Lab 并创建 run timeline。
MT99-P47-04: Draft Inbox / AI Drafts 能显示 nested graph_insight_draft，并列出 graph evidence refs。
MT99-P47-05: Debug events `agent.tool.graph_query` / `agent.tool.graph_result_size` / `agent.intent.graph_routed` 不含正文、绝对路径或 secret。
```

P47 的阻塞判定：Graph action 无法进入 AI Lab、graph 工具绕过审批写 workspace、Draft Inbox 不识别 graph_insight、或 debug payload 泄漏用户正文/secret，均视为 S1/S0 blocker。

## P48 Research Queue V1 Gate

P48 收口时，MT99 partial regression 额外检查（详细步骤见 `MT19_ResearchQueue.md`）：

```text
MT99-P48-01: Library 行右键 `Reading Queue → Add to Workspace/Project Queue` 后，ProjectSpace 的 Queue tab 立即显示新行；再次右键显示 ✓ Remove。
MT99-P48-02: Queue tab 上 ↑↓ 重排 / 状态切换 / Remove 后切换到其他 tab 并返回，顺序与状态保持。
MT99-P48-03: 把 paper Status 从 unread 切到 skimmed，对应 queue 行自动迁移到 Reading；切到 summarized 后自动迁移到 Finished，写入 startedAt / finishedAt。
MT99-P48-04: 重启 App 后 `library/queue.yaml` 与 `projects/*/queue.yaml` 数据完整恢复；手工破坏一个 entry 块的 yaml 不导致崩溃，仅写 `queue.load.error` 警告。
MT99-P48-05: Settings → Modules 关闭 Paper Library 后 Queue tab、Library 行 `Reading Queue` 菜单、HomePanel readingQueueEntries 全部隐藏；重新启用后立即恢复。
MT99-P48-06: Home Today `Reading Queue` 卡 / Project Dashboard 新 `Reading Queue` 卡 渲染 active entries；queue 为空时分别回退启发式列与 onboarding CTA，`Current Reading Plan` 卡保持 P50 占位。
```

P48 的阻塞判定：Queue 写入丢失（重启后行消失或顺序乱）、`Paper.status` → queue 自动迁移失败、paper-library 禁用后 Queue tab 仍可见、Permission Dock 之外的路径直接消费 graph 工具结果写 queue，均视为 S1/S0 blocker。

## P49 Recommendation Engine Core Gate

P49 Core Layer 收口时，MT99 partial regression 额外检查（详细步骤见 `MT20_Recommendation.md`）：

```text
MT99-P49C-01: `swift run --quiet SciStationCoreTestRunner` 通过，覆盖 config YAML、daily feed import、candidate dedup、local-interest ranking、snapshot/history/P48 payload。
MT99-P49C-02: `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过；新增 Recommendation Core 不破坏 App target。
MT99-P49C-03: `docs/development/Proposal49.md` 标记 Core 已落地，并明确 UI / Scheduler / live external retrieval 为 Layer B/C 待补；`Long Term Plan.md` 第六节同步状态。
MT99-P49C-04: `recommendation_note` payload 仍包含 P48 ingestor 所需 `kind/artifact_kind/queue_scope/queue_candidates`；candidate 只持久化 id、external_key、display_title、rank、total、reason，不写 raw abstract/full text。
```

P49 Core 的阻塞判定：Core 自动化失败、App target 编译失败、daily feed 导入无法 canonicalize arXiv id、snapshot 写入 raw full text/abstract、或 payload 不再能被 P48 ingestor 消费，均视为 S1 release blocker。

## 2026-05-17 UI Bug Bash Gate

本轮针对 P42 Home / P48 Queue / Shell Right Rail 的用户反馈修复，partial regression 额外检查：

```text
MT99-BB0517-01: Home → Edit Layout 后，每个 widget 卡片右上出现拖拽把手；鼠标悬停 widget 显示 openHand 光标，可在任意 1x1 / 2x2 等尺寸间拖动重排；Edit Layout 退出后卡片内按钮恢复可点。
MT99-BB0517-02: Edit Layout 期间 Today / Quick Actions / Active Projects 卡片内的导航按钮不再吃掉拖动手势；点击 Done 退出 Edit Layout 后这些按钮仍可正常导航。
MT99-BB0517-03: ProjectSpace → Queue tab 在简体中文界面下所有可见文案为中文，包括 header / toolbar / 空态 / picker / row 控件 / 添加 sheet / 状态与来源 chip；切换到 English 仍显示英文。
MT99-BB0517-04: 首次进入 Queue tab 不再出现一段时间的白屏；从其他 tab 切回 Queue tab 立即显示 header 与 toolbar。
MT99-BB0517-05: 工具栏 Inspector 按钮与 AI 按钮均可同一图标点击切换显示/隐藏右栏；当前模式下 tooltip 显示「收起检查器 / 收起 AI」并切换为 sidebar.trailing 图标。
MT99-BB0517-06: 论文库 / Wiki / Home / PDF Reader 等场景的右栏 header 不再额外显示 AI sparkles 与折叠按钮；右栏隐藏后只剩 CollapsedShellRailRestoreButton 的两个还原按钮，且 tooltip 已本地化。
MT99-BB0517-07: 在项目 A 的 Queue tab 选中 Project 范围后，切换到项目 B，Queue tab 的 scope picker 自动切到项目 B 的 project 范围而不是 workspace。
```

2026-05-17 UI Bug Bash 的阻塞判定：Home widget 在 Edit Layout 下仍无法拖动、Queue tab 中文 / 白屏问题复现、Inspector 按钮无法关闭右栏、或 Workspace / Project 范围在切换项目后丢失，均视为 S1 release blocker。

## 2026-05-17 UI Bug Bash Round 2 Gate

P49 收口前，针对 Round 1 修复后用户复测仍未通过的 Home / Queue / Right Rail 三组问题，partial regression 额外检查：

```text
MT99-BB0517R2-01: Home → Edit Layout 后，按住任一 widget 拖动到另一 widget 上方/左侧，其它 widgets 立即向后让位（push-aside），dragged widget 跟随光标，有阴影 + 1.03 放大；松手后新顺序写入 `settings/workspace_preferences.yaml` 的 `home_widget_layout`，重启后保留。**关键回归**（Round 3）：松手后 widget 必须**真的**保留在新位置，不能短暂停留后又回弹到原始位置。两条根因均已修复：
    - `HomeWidgetLayout.repack` 不再以 `(row, column)` 重新排序 items，否则 `moveWidget` 写入的新数组顺序会被旧位置 sort 覆盖回去（在 `~/Documents/ResearchWorkspace/.sci-station/debug/app_events.jsonl` 2026-05-17T09:13:18Z 复现）；
    - 拖拽落点改用 `moveWidget(_:onto:)` 语义（"放到 target 当前格子上"），前向 / 后向拖动都会把 source 真正交换到 target 的位置，而不是只挪一格。
    - 自动化覆盖：`SciStationCoreTestRunner` 新增 `homeWidgetDragOntoCommitsInBothDirections` 同时验证这两个不变量。
MT99-BB0517R2-02: 在 4 / 3 / 2 / 1 columns 下都能拖动并重排；narrow 单列下拖动仍能成功（同列上下移动）。
MT99-BB0517R2-03: Edit Layout 期间右键菜单 / 尺寸 picker 出现 "竖向 (1×2)" / "Tall (1×2)" 选项的 widgets 为：Today、Active Projects、AI Review、Recent Papers、Reading Plan、Quick Actions；Calendar 与 Project Health 不出现 Tall 选项。
MT99-BB0517R2-04: 把上述任一 widget 切到 Tall (1×2)，渲染高度比 1×1 显著加高，并显示 3-4 条 list rows + 顶部计数 header；切回 1×1 后 small widget 显示 26pt 大数字 + caption + 首项预览（不再只是数字）。
MT99-BB0517R2-05: ProjectSpace → Queue tab 首次打开时不再卡顿；滚动 / 切换 status / source / scope picker 立即响应；entry list 行内 ↑↓ 与 ellipsis 菜单全部本地化为中文。
MT99-BB0517R2-06: 在 Library / Queue / Home / Calendar / AI Lab 任一路由下，点击工具栏 Inspector 按钮：
    - 当前 rail 隐藏 → rail 打开，且即使切换 tab 也保留打开状态；
    - 当前 rail 显示 → rail 收回，且即使切换到 Library/Wiki/PDF 等"建议显示"的路由也保留隐藏状态。
MT99-BB0517R2-07: 在 expanded 宽度下，rail 显示时左侧有 6pt resize handle，鼠标变为左右调整光标，可拖动调整 rail 宽度，width 写入 `@AppStorage("sciStation.shellRightRailWidth")` 并跨 App 重启保留。
MT99-BB0517R2-08: Settings → Workspace → Modules 关闭 paper-library 后 Home Reading Plan widget 隐藏；重新启用后立即恢复，并保留之前选择的 Tall 尺寸。
```

Round 2 的阻塞判定：widget 拖动仍不触发 push-aside 重排 / Tall 选项缺失 / 工具栏 Inspector 在任一路由下仍无法 toggle 显示与隐藏 / queue tab 复现冻结 / 右栏 width 不再可拖动，均视为 S1 release blocker。

## 阻塞问题

```text
S0: 数据丢失、隐私泄漏、App crash
S1: workspace 无法打开；核心导航失效；Settings 或 AI Lab 无法打开
```
