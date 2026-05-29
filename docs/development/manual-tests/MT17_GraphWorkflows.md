# MT17：Graph Workflows 手动测试

更新时间：2026-05-12

## 目标

验证 P47 Graph-Powered Research Workflows：AI Lab 能看到 7 个 graph 工具，graph intent 能路由到只读工具，Graph view action 能跳转 AI Lab，`graph_insight` 草稿能进入 Draft Inbox/AI Drafts，模块关闭时工具和 workflow 被隐藏。

## 前置条件

- 已准备 Standard Workspace。
- Workspace 中至少有 1 个 project、3 篇 paper，其中至少 1 篇被标记为当前 project core paper。
- 已运行一次 Graph index/rebuild，Graph tab 能打开并显示节点。
- AI Lab runtime 可用；如果 provider 不可用，至少能观察到 deterministic preflight/tool evidence 与 inline failure。
- `citation-graph` 与 `ai-lab` 模块启用。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT17-P47-01 | Graph 工具可见 | AI Lab tool picker 出现 `find_missing_core_papers`、`generate_reading_path`、`detect_stale_citations`、`find_unsupported_artifact_claims`、`find_stale_saved_artifacts`、`find_method_lineage`、`find_bridge_papers`；均为 read-only / `graph.read` |
| MT17-P47-02 | 模块 gating | 关闭 `citation-graph` 后 graph tools 从 tool picker 消失；`graph_insight` workflow 不可用；重新启用后恢复 |
| MT17-P47-03 | 缺漏核心论文 intent | 在 project scope 输入“这个项目还有哪些核心论文没引？”；timeline 出现 `find_missing_core_papers` tool result；结果包含 candidates / graph node id |
| MT17-P47-04 | graph_insight Draft | MT17-P47-03 后 AI Drafts / Draft Inbox 出现 `graph_insight` needs_review 条目，evidence refs sourceType 为 `graph` |
| MT17-P47-05 | 阅读路径 intent | 选中 paper 后输入“读完这篇下一篇应该看什么？”；timeline 出现 `generate_reading_path`；返回 ordered reading path，不直接写 workspace |
| MT17-P47-06 | 过时引用 intent | 输入“检查这个项目有没有过时引用”；timeline 出现 `detect_stale_citations`；若存在 newer `extends` 边，结果展示 suggested newer paper |
| MT17-P47-07 | unsupported claims | 输入“哪些 artifact claim 缺乏证据？”；timeline 出现 `find_unsupported_artifact_claims`；warning/error severity 可读 |
| MT17-P47-08 | stale saved artifacts | 输入“有哪些 saved artifact 证据过期？”；timeline 出现 `find_stale_saved_artifacts`；结果列出 stale reason |
| MT17-P47-09 | method lineage | 输入包含 `method:<id>` 的“方法谱系/lineage”问题；timeline 出现 `find_method_lineage`；结果按 depth 展示 extends/uses chain |
| MT17-P47-10 | bridge papers | 输入包含两个 `paper:<id>` 的 connection/bridge 问题；timeline 出现 `find_bridge_papers`；返回 path_found 与 path_edges |
| MT17-P47-11 | Graph action: Generate Reading Order | 在 Graph view 触发 Generate Reading Order；App 跳到 AI Lab，新建对话并自动提交 graph_insight prompt |
| MT17-P47-12 | Graph action: Explain Connection / Find Bridge Papers | 在 Graph view 触发 connection/bridge action；App 跳到 AI Lab，prompt 包含 from/to id，并触发 bridge workflow |
| MT17-P47-13 | Permission Dock follow-up | 从 graph_insight 草稿触发保存/写 wiki 的后续动作时必须进入 Permission Dock；未批准前不写 workspace |
| MT17-P47-14 | Debug log | `.sci-station/debug/app_events.jsonl` 记录 `agent.tool.graph_query`、`agent.tool.graph_result_size`、必要时 `agent.tool.graph_error` / `agent.intent.graph_routed`；payload 不含论文正文、claim 全文或 secret |

## P47 Partial Regression Scope

P47 收口至少执行：

```text
MT17-P47-01
MT17-P47-02
MT17-P47-03
MT17-P47-04
MT17-P47-05
MT17-P47-11
MT17-P47-13
MT17-P47-14
```

## 阻塞问题

```text
S0: graph read-only 工具未经审批写 workspace；debug payload 泄漏正文/secret；App crash
S1: AI Lab 无法看到 graph 工具；Graph action 无法进入 AI Lab；Draft Inbox 无法识别 graph_insight
```
