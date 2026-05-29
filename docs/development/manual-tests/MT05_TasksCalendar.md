# MT05：Tasks / Calendar / Reminders 手动测试

更新时间：2026-05-05

## 目标

验证 todo、due date、priority、Apple Reminders 发布、Calendar 显示和权限拒绝降级。

## 前置条件

- Standard Workspace 包含 tasks 目录或已有 todos。
- Apple Reminders 权限相关用例需记录系统权限状态。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT05-01 | 新建 todo | todo 写入 workspace |
| MT05-02 | 编辑 todo | 字段更新并落盘 |
| MT05-03 | 删除 todo | 有确认或明确撤销路径 |
| MT05-04 | 设置 due date | Calendar 中显示 |
| MT05-05 | 设置 priority | 列表/详情一致 |
| MT05-06 | 添加 related paper id | 与论文关联可见 |
| MT05-07 | Calendar 显示 todo | 日期正确，不重复 |
| MT05-08 | 发布到 Apple Reminders | 系统提醒创建成功或显示权限提示 |
| MT05-09 | 拒绝系统权限后本地 todo 仍可用 | 本地功能不受阻断 |
| MT05-10 | 重启后 todo 保留 | 文件读取恢复 |

## 验收重点

```text
本地 todo 是主数据源
系统权限失败有 fallback
不会重复创建 Reminders
删除/完成状态清楚
```

## 阻塞问题

```text
S0: todo 数据丢失；未经确认批量删除；隐私数据泄漏到系统服务
S1: todo 创建/编辑不可用；Calendar 不显示本地 todo
```
