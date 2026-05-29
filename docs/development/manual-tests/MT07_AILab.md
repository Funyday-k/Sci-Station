# MT07：AI Lab 基础手动测试

更新时间：2026-05-05

## 目标

验证 AI Lab 对话、project scope、thread、plan、Permission Dock、run history 和基础安全边界。

## 适用触发点

- AI Lab UI 骨架完成后执行 Skeleton Test。
- 新增 runtime、workflow、Permission Dock 或 run history 行为后执行 Happy Path / Edge Test。
- P36 必须执行 MT07 partial。

## 前置条件

- 已准备 Standard Workspace。
- 至少存在 1 个 project 和 1 篇 paper。
- 明确当前 runtime selector 状态。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT07-01 | 打开 AI Lab | 页面显示，不崩溃，空状态清楚 |
| MT07-02 | 切换 project scope | composer / context 与所选 project 对齐 |
| MT07-03 | New Chat 创建 pending thread | 未发送前不误写历史 |
| MT07-04 | 第一次成功 plan 后写入 threads.jsonl | 重启后可恢复 |
| MT07-05 | prompt draft 切换项目后恢复 | 不串项目草稿 |
| MT07-06 | 生成 plan | timeline / artifact draft 状态清楚 |
| MT07-07 | Permission Dock 展示 tool risk | 写操作风险可见 |
| MT07-08 | read-only tool auto-allow | 只读工具不阻塞主路径 |
| MT07-09 | write tool 默认 ask | 不自动写 workspace |
| MT07-10 | allow once | 只批准本次写入 |
| MT07-11 | deny | workflow 可解释失败或降级 |
| MT07-12 | 历史 run 重新打开 | replay 不受当前 selector 改变影响 |
| MT07-13 | 损坏 JSONL 行不阻止历史读取 | 损坏行被跳过或提示 |

## P36 Partial Scope

P36 至少执行：

```text
MT07-01
MT07-02
MT07-06
MT07-07
MT07-09
MT07-12
MT07-13
```

## P39.5 Stabilization Scope

P39.5 重点覆盖 AI Lab 的 thread/project affinity、消息持久化、错误恢复、中文输入、工具多选、审批策略和复制体验。

```text
MT07-P39.5-01: New Chat 未发送前不写历史，发送后 thread metadata 保存 context_scope/project_id
MT07-P39.5-02: 在已有 thread 中切换 project context 不串项目，不自动创建新对话
MT07-P39.5-03: project A 输入 draft，切到 project B 再切回 A，draft 和 context 不混淆
MT07-P39.5-04: 生成阅读计划失败时保留 user message、inline error、retry action
MT07-P39.5-05: Stop/Pause 后未发送文本回填 composer，已发送文本保留在历史
MT07-P39.5-06: 归档当前对话后自动跳转 New Chat 或最近 active thread
MT07-P39.5-07: 无 active thread 时点击 AI Lab 进入 New Chat 页面
MT07-P39.5-08: 中文输入法 composition 中 Enter 不发送，composition 结束后 Enter 才发送
MT07-P39.5-09: Tool picker checkbox 多选、Select All、Clear，单项点击不收起菜单
MT07-P39.5-10: 阅读论文 / 检索上下文 read-only 工具不触发审批
MT07-P39.5-11: 写 wiki workflow 先展示草稿，再对写入请求 Permission Dock 审批
MT07-P39.5-12: Permission Dock 点击 Run/Approve 后 run 继续或显示 inline failure reason
MT07-P39.5-13: Assistant message copy button 复制 Markdown/plain text
MT07-P39.5-14: 改变 tool selection 或 runtime selector 后打开旧 run，replay 仍按旧 metadata 展示
```

P39.5 手动报告路径：`docs/development/manual-tests/runs/2026-05-06_P39.5_AILabStabilization.md`。

## P39.10-P39.12 Release Gate Scope

P39.10-P39.12 覆盖 AI Lab 论文 QA、provider-native tool replay、retrieval/source health、`paper.md` 质量提示和诊断隐私。发布前至少执行：

```text
MT07-P39.12-01: 选中 library/papers 论文后，AI Lab Source Health 显示 selected source、chunks、paper.md health，并提供 Check/Rebuild/Open 操作。
MT07-P39.12-02: chunks=0 或 source 不可索引时，AI Lab 显示可理解 hint，不把用户导向 Settings-only 路径。
MT07-P39.12-03: Library Inspector paper.md Health 显示 summary、前三条 issue、Check/Open/Convert with MinerU。
MT07-P39.12-04: DeepSeek thinking-mode provider failure 不再空白提前终止；失败回复显示 Retry / Copy Diagnostic / Tool Evidence 操作。
MT07-P39.12-05: Copy Diagnostic 不包含 API key、token、完整用户主目录绝对路径或 provider credential。
MT07-P39.12-06: 图注类问题（例如 Figure 2 / 图 2）能通过 paper tool 读取图像引用、source path 和 line range，而不是 heading mismatch 报错。
```

P39.12 手动报告路径：`docs/development/manual-tests/runs/2026-05-07_P39.12_AILabReleaseGate.md`。

## P39.13 Archive / Paper Routing / Debug Scope

P39.13 覆盖用户反馈的 archived conversation、第三篇论文读取、heading 优先级和 Debug mode。发布前至少执行：

```text
MT07-P39.13-01: 归档当前对话后，主聊天区不再显示该 archived thread 的 messages、draft 或当前 run。
MT07-P39.13-02: 归档所有对话后，AI Lab 显示 New Chat/空状态，不通过 project fallback 显示已归档内容。
MT07-P39.13-03: 从 run history 打开只属于 archived thread 的 run，不会把 archived thread 重新设为 active thread。
MT07-P39.13-04: pinned thread 中包含 archived thread 时，刷新后 pinned 列表不显示 archived entry。
MT07-P39.13-05: 输入“第三篇文章的摘要是什么？”时，Tool Evidence 先 list_papers，再把 search/read 限制到第三篇 resolved paper id。
MT07-P39.13-06: 输入“第 3 篇论文的蒸发率公式是什么？”时，retrieval query 不包含“第 3 篇”序数噪声。
MT07-P39.13-07: read_paper_section 同时带 heading 和 start_line/end_line 时，返回 heading 对应章节而不是文档开头。
MT07-P39.13-08: 打开 Debug mode 后发送 prompt，`.sci-station/debug/app_events.jsonl` 记录 prompt、final response、tool results 和 thread 操作。
MT07-P39.13-09: Debug log 不包含 API key、token、secret 或完整用户主目录绝对路径。
MT07-P39.13-10: 关闭 Debug mode 后新增 AI Lab 操作不再追加普通 debug event，已有日志保留。
```

P39.13 手动报告路径：`docs/development/manual-tests/runs/2026-05-07_P39.13_DebugArchivePaperRouting.md`。

## P39.15 Markdown / Wiki Writeback / Budget Scope

P39.15 覆盖 AI Lab Markdown 渲染、Wiki 写回、工具预算和离线 Markdown Preview。发布前至少执行：

```text
MT07-P39.15-01: AI Lab 聊天气泡里 $$E_{\odot}=...$$ 渲染为公式，不再是字面量
MT07-P39.15-02: 表格 | 符号 | 含义 | 渲染为表格，不再是竖线纯文本
MT07-P39.15-03: ```python``` 代码块在气泡内有等宽字体 + 边框
MT07-P39.15-04: 输入“总结这篇文章并写入 wiki/papers/<id>.md”，Permission Dock 出现，批准后产生 wiki/papers/<id>.md
MT07-P39.15-05: provider 故意返回空回复时，AI Lab 出现“provider 返回空回复 + 保留上下文/草稿”而不是“运行失败”
MT07-P39.15-06: 论文 QA 连续 6+ 次 read_paper / read_paper_section 不被 budget 切断；超过 budget 时 fallback final answer 而非 provider_error
MT07-P39.15-07: 离线打开 Wiki 编辑器中含 $$...$$ 的 paper.md，公式仍能渲染
MT07-P39.15-08: 断网后 Markdown Preview 不访问 jsdelivr.net；本地 KaTeX/marked 仍工作
```

P39.15 手动报告路径：`docs/development/manual-tests/runs/2026-05-07_P39.15_AILabMarkdownWritebackBudget.md`。

## P47 Graph Workflows Scope

P47 覆盖 AI Lab graph 工具、deterministic preflight、graph_insight draft 与 Graph view action。发布前至少执行：

```text
MT07-P47-01: AI Lab tool picker 在 citation-graph 启用时显示 7 个 graph read-only 工具，禁用模块后隐藏。
MT07-P47-02: 输入“这个项目还有哪些核心论文没引？”时，timeline 自动出现 find_missing_core_papers tool result，并生成 graph_insight draft。
MT07-P47-03: 输入“读完这篇下一篇应该看什么？”时，timeline 自动出现 generate_reading_path tool result，不直接写 workspace。
MT07-P47-04: graph_insight draft 在 AI Drafts / Draft Inbox 中显示 kind、evidence refs 和 needs_review 状态。
MT07-P47-05: 从 graph_insight 后续保存到 wiki/todo 时必须出现 Permission Dock；拒绝时不写文件。
MT07-P47-06: Debug log 记录 agent.intent.graph_routed / agent.tool.graph_query，payload 不含论文正文、claim 全文或 secret。
```

P47 手动报告路径：`docs/development/manual-tests/runs/YYYY-MM-DD_P47_GraphPoweredWorkflows.md`。

## 阻塞问题

```text
S0: AI 未经审批直接写 workspace；secret 泄漏；App crash
S1: AI Lab 无法打开；New Chat/run 主路径不可用；history/replay 完全不可用
```
