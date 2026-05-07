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

## 阻塞问题

```text
S0: 数据丢失、隐私泄漏、App crash
S1: workspace 无法打开；核心导航失效；Settings 或 AI Lab 无法打开
```
