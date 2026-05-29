# 任务书 39.5：AI Lab 稳定化、线程归属与审批体验修复

更新时间：2026-05-06

完成状态：Implementation complete；GUI 手动点击验证仍需在交互式 macOS App session 中补跑。

> 本任务书插入在 P39 与 P40 之间，专门处理 P39 手动测试中暴露的 AI Lab 阻塞问题。P39 已完成 Workspace Module Registry V1，但测试反馈显示 AI Lab 的 thread/project 归属、错误保存、中文输入、工具选择、审批策略和归档导航仍不稳定。P39.5 的目标是先把 AI Lab 的基础交互和运行可靠性修好，再进入 P40 Workspace Creation Wizard。

## 1. 背景

P39 手动测试记录暴露出以下 AI Lab 相关问题：

```text
AI-02: 切换 project scope 出现串项目或状态混淆。
问题6: 聊天模式仍有异常。
问题7: 工具管理交互不适合多工具选择，点击单项后菜单会收起。
问题9: 既有对话中切换项目会进入新对话；全局“当前项目”设计让 sidebar 与对话归属混淆。
问题10: 发送“请生成一个阅读本项目论文的计划”后出现错误，用户消息未保存；暂停后消息也没有可靠回填到输入框。
问题11: 归档当前对话后仍停留在该对话；无保存对话时进入 AI Lab 应该打开新对话页面。
问题12: 中文输入法 composition 中按回车被误判为发送。
问题13: 发送“总结第一篇文章，并写入wiki”后无回复并出现错误提示。
问题14: 阅读论文触发意义不明的审批；read-only 阅读工具不应要求审批，点击 run 后没有正常输出。
补充: AI 输出需要复制按钮。
```

这些问题会直接影响 P40 创建向导中 AI Lab 模块的可信度。P39.5 不扩大新功能，而是把 AI Lab 调整为可理解、可恢复、可测试的基础状态。

## 2. 本轮目标

1. 明确 AI Lab thread 与 project 的归属模型，取消或弱化全局“当前项目”对既有对话的误导。
2. 修复切换 project、切换 thread、New Chat、Archive 后的导航与状态一致性。
3. 保证用户消息、partial assistant message、错误状态和暂停状态都能保存或恢复。
4. 修复中文输入法 composition 期间 Enter 被误发送的问题。
5. 改善工具管理：多选框、全选、菜单不因单项选择自动关闭。
6. 修正 Permission Dock / tool approval 策略：read-only 检索、阅读、摘要上下文工具默认不要求审批；写入 wiki / tasks / artifact 等操作仍默认 ask。
7. 修复 plan 生成、总结并写入 wiki、阅读论文等基础 workflow 的无回复和 toast-only failure。
8. 增加 assistant 输出复制按钮，并确保复制内容为可读纯文本或 Markdown。
9. 建立覆盖 AI Lab 主路径的自动化和手动回归检查。

## 2.1 交互决策

P39.5 建议采用以下产品决策，避免继续扩大混乱状态：

```text
1. Thread 自身持有 project affinity，可为 nil / workspace / project_id。
2. 已保存 thread 的 project affinity 不随 sidebar 或外部 project selection 自动改变。
3. Composer 可在新对话开始前选择上下文范围，但该选择只影响新 run，不反向改写旧 thread。
4. Sidebar 不展示一个全局“当前项目”作为 AI Lab 的主状态；需要展示时只显示当前 thread 的 context badge。
5. 在已有 thread 中切换 project context 必须明确表现为“为下一次 run 选择上下文”，不能偷偷创建新对话。
6. 如果用户选择把当前 thread 迁移到另一个 project，必须是显式命令，P39.5 默认不做迁移功能。
```

本轮用户确认：以上五个关键决策均采用“是”。

## 3. 实施任务

- [x] [P39.5.1] AI Lab thread / project affinity model。
  - 为 thread/run metadata 明确保存 `context_scope`、`project_id`、`runtime_selector` 和 `created_from_route`。
  - 已保存 thread 打开后使用自身 metadata 渲染 context badge，不读取全局 project selection 作为事实来源。
  - New Chat 可选择 workspace / project context，但未发送前不写入历史。
  - 切换 sidebar project 不应让当前 thread 串项目或自动变成新对话。

- [x] [P39.5.2] AI Lab navigation and archive behavior。
  - 点击 AI Lab 时，如果没有可见未归档 thread，进入 New Chat 页面。
  - 归档当前 thread 后立即跳转 New Chat 或最近一个未归档 thread。
  - 归档 thread 不应继续停留在当前消息区，也不应出现在默认 active list。
  - 历史列表应区分 active / archived，必要时提供 archived filter。

- [x] [P39.5.3] Message durability and error recovery。
  - 用户点击发送后，user message 必须先落盘或进入可恢复 pending record，再启动 run。
  - run 失败时保留 user message、partial assistant message、error summary、fallback reason 和 retry action。
  - toast 只能作为补充提示，不能是唯一错误载体；错误必须显示在 thread timeline 内。
  - 点击 Stop / Pause 后，未完成的用户意图或未发送文本应回填 composer，已发送文本必须留在历史。
  - 损坏 JSONL 行跳过或标记 warning，不阻断其它 thread 读取。

- [x] [P39.5.4] Composer keyboard and Chinese IME handling。
  - composition active 时 Enter 不发送消息，只交给输入法提交候选。
  - 非 composition 状态下 Enter 发送，Shift+Enter 换行。
  - Stop / retry / send button 状态不会覆盖用户正在 composition 的文本。
  - 增加针对 macOS `TextEditor` / `NSTextView` bridge 的手动测试说明。

- [x] [P39.5.5] Tool picker and tool management UX。
  - 工具管理使用 checkbox multi-select，支持 Select All / Clear。
  - 点击单个工具不关闭菜单，用户可连续选择多个工具。
  - tool list 显示 read-only / write / risky 分类和 module 来源。
  - 当前 thread/run 的 tool selection 应持久化到 run metadata，历史 replay 不受当前选择改变影响。

- [x] [P39.5.6] Permission Dock and tool approval policy。
  - read-only paper/library/search/context retrieval 工具默认 auto-allow，不出现写入审批。
  - 读取论文、生成阅读计划、总结论文等不写 workspace 的 workflow 不要求审批。
  - 写 wiki、写 tasks、保存 artifact、修改 workspace 文件等仍默认 ask。
  - Permission Dock 文案必须说明工具名、module scope、读/写性质、目标路径或数据范围。
  - 点击 Run / Approve 后必须继续 run 或给出 inline failure reason，不能静默无输出。

- [x] [P39.5.7] Workflow reliability for core prompts。
  - 修复“请生成一个阅读本项目论文的计划”主路径：必须产生 timeline、assistant response 或可解释 inline error。
  - 修复“总结第一篇文章，并写入wiki”主路径：先总结并展示草稿，再对 wiki 写入请求审批。
  - 修复“阅读论文”主路径：读取和摘要阶段不审批，只有保存/写入阶段审批。
  - sidecar unavailable / model unavailable / tool failure 时显示 fallback reason，并保留可重试状态。

- [x] [P39.5.8] Assistant output actions。
  - 每条 assistant message 增加 copy action。
  - 复制内容应为 Markdown/plain text，不包含 UI-only labels。
  - copying 失败时显示轻量 inline 状态，不打断 thread。

- [x] [P39.5.9] Chat mode layout and state cleanup。
  - 修复测试截图中 chat mode 异常显示。
  - 空状态、loading、streaming、paused、failed、archived 状态应互斥且可理解。
  - 避免 thread 切换时旧 run 的 loading/error 状态泄漏到新 thread。

- [x] [P39.5.10] Tests and delivery record。
  - Swift CoreTestRunner 覆盖 thread/project affinity、archive navigation、message persistence、tool approval classification。
  - 如涉及 Python sidecar payload，补充 AgentRuntime tests 覆盖 tool permission metadata 和 fallback error payload。
  - Xcode build 必须通过。
  - 新增或更新 MT07 AI Lab 手动测试记录，覆盖本轮 P0/P1 场景。

## 4. 非目标

```text
不做完整 AI Lab 信息架构重设计或全新视觉系统
不做多 agent 编排或新 provider 能力
不做 P40 Workspace Creation Wizard
不做 P41 Module Settings enable/disable UX
不改变 P38/P39 的写入审批根边界：写 workspace 仍必须经 Permission Dock
不让 sidecar 或 read-only tool 获得直接写 workspace 权限
不把 prompt/response 明文写入 debug bundle 或 workspace module config
```

## 5. 验收标准

1. 在 project A/B 间切换后，已有 thread 不串项目，不自动创建新对话，context badge 与 thread metadata 一致。
2. 无保存对话时点击 AI Lab 打开 New Chat；归档当前对话后不再停留在归档对话。
3. run 失败、sidecar fallback、tool failure 都会在 thread 内保留 user message 和 inline error，可 retry。
4. Stop / Pause 后 composer 状态可恢复，不丢失用户正在输入或刚发送的内容。
5. 中文输入法 composition 中按 Enter 不发送消息。
6. 工具管理支持 checkbox 多选、全选，点击工具项不关闭菜单。
7. read-only 阅读/检索/总结上下文工具不触发审批；写 wiki/tasks/artifact 仍触发审批。
8. “生成阅读计划”“总结第一篇文章并写入 wiki”“阅读论文”三条手动主路径有可见输出或可解释 inline failure。
9. assistant message 可复制，复制内容可读。
10. SwiftPM CoreTestRunner、AgentRuntime pytest、Xcode build 通过，或交付记录明确环境阻塞。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充：

```text
get_errors for edited SwiftUI/App files
manual AI Lab run with Swift Loop runtime
manual AI Lab run with LangGraph Sidecar or Auto fallback when available
manual inspection of thread/run JSONL after failed run and archived thread
privacy keyword scan for debug bundle and AI Lab diagnostics
```

## 7. 手动测试计划

本任务书完成后必须执行 MT07 AI Lab partial，并新增 P39.5 重点用例：

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

Regression mini-pass：

```text
Workspace open
Sidebar -> AI Lab
New Chat / active thread / archived thread
Settings -> AI / runtime selector
Library paper context -> AI Lab reading workflow
Artifact preview after AI generated draft
```

阻塞验收的问题等级：

```text
S0: App crash；未经审批写 workspace；secret/debug bundle 泄漏；用户消息或用户文件丢失
S1: AI Lab 无法打开；发送后无任何可见输出或 inline error；thread/project 串线；归档状态错误；中文输入法误发送
S2: copy/tool picker/文案类可用性问题，不阻断核心 run
```

## 8. 交付记录

完成实现后补充：

```text
完成日期：2026-05-06
Git commit：未提交
自动化测试结果：
- `swift run SciStationCoreTestRunner`：PASS
- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests`：PASS，28 passed
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：PASS
手动测试报告：docs/development/manual-tests/runs/2026-05-06_P39.5_AILabStabilization.md
已知问题：GUI-only 用例仍需交互式 App session 补跑，尤其是中文 IME composition、工具 popover 连续多选、assistant copy button 和真实 sidecar/model workflow。
推迟到 P40 的事项：Workspace Creation Wizard、template -> module config generation、directory preview、privacy/AI setup page
推迟到 P41 的事项：Module settings page、enable/disable UX、pin to sidebar、directory repair UI
```

## 9. Questions

1. AI Lab 是否采用 thread 自持 project affinity，并取消全局“当前项目”作为 AI Lab 主状态？已确认：是。
2. 既有 thread 中切换 project 是否只影响下一次 run context，而不自动迁移 thread？已确认：是。
3. read-only 阅读/检索/总结上下文工具是否默认 auto-allow，仅写入类工具进入 Permission Dock？已确认：是。
4. run 失败时是否必须把错误写入 thread timeline，而不是只显示右上角 toast？已确认：是。
5. P40 是否等待 P39.5 的 AI Lab P0/S1 问题修复并通过 MT07-P39.5 后再进入完整创建向导？已确认：是。