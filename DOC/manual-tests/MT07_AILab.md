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

P39.5 手动报告路径：`DOC/manual-tests/runs/2026-05-06_P39.5_AILabStabilization.md`。

## 阻塞问题

```text
S0: AI 未经审批直接写 workspace；secret 泄漏；App crash
S1: AI Lab 无法打开；New Chat/run 主路径不可用；history/replay 完全不可用
```
