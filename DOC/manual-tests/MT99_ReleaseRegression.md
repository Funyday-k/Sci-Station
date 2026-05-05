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

## 阻塞问题

```text
S0: 数据丢失、隐私泄漏、App crash
S1: workspace 无法打开；核心导航失效；Settings 或 AI Lab 无法打开
```
