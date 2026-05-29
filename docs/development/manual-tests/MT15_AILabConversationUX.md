# MT15：AI Lab 对话体验 / Reasoning / 权限审核 / P43.6 手动测试

更新时间：2026-05-08
适用任务书：`docs/development/Proposal43.6.md`

## 前置条件

- 已运行 `swift run SciStationCoreTestRunner`。
- 已运行 `python -m pytest AgentRuntime/tests`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 使用包含至少 1 个 active project、2 篇可搜索 paper、1 个 wiki page 的 workspace。
- Settings -> AI Lab 已配置可用模型；建议启用 debug logging 便于检查审计事件。

## 测试用例

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT15-P43.6-01 | Plan 模式问答 | 打开 AI Lab，确认顶部模式为 Plan，提问一段普通论文阅读问题 | UI 只显示 Plan / Agent 两段式模式；Plan badge 显示 read-only + draft 语义；AI 回复完整显示，不因结构化响应或流式中断变成空白 |
| MT15-P43.6-02 | Agent 模式权限提示 | 切到 Agent，要求写入 Wiki 草稿或执行写入类工具 | 顶部提示 Agent 可请求工作区更改；所有写动作进入权限审核，不直接落盘 |
| MT15-P43.6-03 | 展开思考过程 | 运行一次会产生 reasoning summary 的请求，点击 timeline 中的“思考过程” | 默认折叠；展开后只显示可公开摘要、步骤/工具数量和 payload 摘要，不显示大段原始不可公开思维链 |
| MT15-P43.6-04 | 工具调用行 | 触发 `search_papers` 或 `read_paper_section` | 工具默认显示为低噪声单行；展开后才显示 JSON/输出摘要；失败时显示错误摘要和可重试提示 |
| MT15-P43.6-05 | Inline permission Allow | 对一个待审批写工具点击 Allow，再点击运行已允许工具 | 默认主操作只有 Allow / Deny；Allow 后状态进入 allow once；执行后 timeline 出现工具完成或 draft review 路径 |
| MT15-P43.6-06 | Inline permission Deny | 对一个待审批写工具点击 Deny 并继续 | 记录 denial；后续恢复/执行不会写入被拒绝的工具；debug event 记录脱敏 decision |
| MT15-P43.6-07 | Draft Review | 对 `write_markdown_plan` / `write_wiki_markdown` 展开 Details | 显示 target path、参数、diff preview、run 来源语义；可保存草稿副本、请求 AI rewrite；生成内容可从 UI 追踪到 draft 或 run artifact |
| MT15-P43.6-08 | 长会话回看 | 构造超过 160 条 timeline event 的 thread，点击“加载更早事件” | 初始显示最近事件；点击后加载更早事件，顺序保持从旧到新；当前 thread 可完整回看 |
| MT15-P43.6-09 | 工具集为空保护 | 在工具菜单清空可用工具后尝试发送 | 发送被阻止；composer 下方显示明确原因；不会出现静默“哑火” |
| MT15-P43.6-10 | 输出完整性回归 | 使用容易返回 JSON envelope 的模型请求长回答，或手动停止一段正在流式的结构化输出 | 已生成的用户可见字段仍显示为部分回复；失败/停止 run 保存 partial assistant response |

## Debug 检查

打开 `.sci-station/debug/app_events.jsonl`，确认以下事件按操作出现，且不包含 prompt 全文、Markdown 全文、工具输出全文或 secret：

```text
ai.mode.change
ai.timeline.project
ai.permission.inline_decision
ai.draft_review.rewrite_requested
ai.toolset.unavailable
```

## 阻塞判定

```text
S0: AI 回复再次变空/丢失、Allow/Deny 绕过审批直接写入、debug payload 泄漏正文或 secret
S1: Plan/Agent 模式语义错误、工具集为空仍可启动、长会话无法加载早期事件、draft 路径不可追踪
S2: 单个 row 展开样式或文案轻微不一致，但不影响审核与回看
```