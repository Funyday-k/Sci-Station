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

## 阻塞问题

```text
S0: AI 未经审批直接写 workspace；secret 泄漏；App crash
S1: AI Lab 无法打开；New Chat/run 主路径不可用；history/replay 完全不可用
```
