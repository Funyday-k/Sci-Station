# MT01：Workspace 手动测试

更新时间：2026-05-05

## 目标

验证 workspace 创建、打开、恢复、目录补齐、偏好保存和权限失效处理。

## 前置条件

- Empty Workspace、Standard Workspace、Broken Workspace 已准备。
- 已确认测试不会选择源码仓库根目录作为 Research Root。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT01-01 | 创建空 workspace | 目录结构和 seed/settings 正确生成 |
| MT01-02 | 打开已有 workspace | 不覆盖用户文件，状态正确加载 |
| MT01-03 | 最近 workspace 自动恢复 | 重启后恢复最近 workspace |
| MT01-04 | workspace 被移动或删除后的失效处理 | 不崩溃，清除失效 bookmark 或提示重新选择 |
| MT01-05 | 缺失目录自动补齐 | 只补缺失目录，不覆盖用户数据 |
| MT01-06 | settings/workspace_preferences.yaml 读写 | 修改后重启保持 |
| MT01-07 | Reveal in Finder | 打开真实 Research Root 或选中文件 |
| MT01-08 | 不允许直接选择源码仓库根目录时的提示 | 提示清楚，不误写源码仓库 |

## 验收重点

```text
不误删已有数据
不覆盖用户文件
目录结构符合预期
重启后能恢复
权限提示清楚
```

## 阻塞问题

```text
S0: 删除/覆盖用户文件；security bookmark 失效导致 crash
S1: 无法创建或打开 workspace；目录补齐破坏已有数据
```
