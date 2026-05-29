# MT04：Materials / VS Code 手动测试

更新时间：2026-05-05

## 目标

验证材料浏览、预览、隐藏系统目录、Reveal in Finder、VS Code 打开和 Python run bridge。

## 前置条件

- Standard Workspace 包含 inbox、data、code、figures、outputs、scripts、prompts 等用户材料目录。
- 如测试 VS Code bridge，确认本机可打开 VS Code。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT04-01 | Materials 显示用户材料 | 用户文件可见 |
| MT04-02 | settings/ 不显示 | 系统目录默认隐藏 |
| MT04-03 | .sci-station/ 不显示 | 内部目录默认隐藏 |
| MT04-04 | Markdown 预览 | Markdown 可读 |
| MT04-05 | Python 预览 | 代码显示清楚 |
| MT04-06 | 图片预览 | 图片渲染正确 |
| MT04-07 | PDF 预览 | PDF 可打开或提示转 PDF Reader |
| MT04-08 | Reveal in Finder | 定位真实文件 |
| MT04-09 | Open workspace in VS Code | VS Code 打开 Research Root |
| MT04-10 | Open selected file in VS Code | VS Code 打开选中文件 |
| MT04-11 | 创建 workspace .venv | 需要用户确认，不误写系统 Python |
| MT04-12 | Run in VS Code 写入 tasks.json | 写入路径清楚，可审计 |
| MT04-13 | Terminal run 生成 .command | 需要确认，命令内容可检查 |

## 验收重点

```text
默认隐藏系统目录
外部工具行为可审计
不会自动执行代码
不会把 secret 写入 workspace
```

## 阻塞问题

```text
S0: 未经批准执行命令；泄漏 secret；误改系统目录
S1: Materials 主页面无法打开；Reveal/Open in VS Code 主路径不可用
```
