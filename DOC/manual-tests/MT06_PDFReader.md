# MT06：PDF Reader 手动测试

更新时间：2026-05-05

## 目标

验证 PDF 打开、搜索、页码、缩放、Notes、Tasks、Citations、Links 和缺失 PDF 错误状态。

## 前置条件

- Standard Workspace 至少包含 1 篇带 PDF 的 paper。
- Broken Workspace 包含缺失 PDF 的 paper。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT06-01 | 打开 PDF | Reader 显示 PDF，不崩溃 |
| MT06-02 | 页码跳转 | 跳转到指定页 |
| MT06-03 | Cmd+F 搜索 | 搜索框打开并命中结果 |
| MT06-04 | Cmd+G 下一处 | 跳到下一个结果 |
| MT06-05 | Shift+Cmd+G 上一处 | 跳到上一个结果 |
| MT06-06 | 缩放 | 缩放稳定，布局不抖动 |
| MT06-07 | Notes 保存到 annotations.md | 文件落盘，重启恢复 |
| MT06-08 | Reader Tasks 创建 todo | todo 关联 paper/page 信息 |
| MT06-09 | Citations 复制 BibTeX | 剪贴内容正确 |
| MT06-10 | 导出 .bib | 文件生成路径清楚 |
| MT06-11 | Links 打开 DOI/arXiv/URL/PDF URL | 外部链接行为明确 |
| MT06-12 | 缺失 PDF 时显示错误不崩溃 | 提示可理解，可返回 Library |

## 验收重点

```text
PDFKit 控件稳定
annotations.md 是可见落盘文件
缺失 PDF 不影响 Library 其他功能
```

## 阻塞问题

```text
S0: Reader crash；annotations 保存导致数据丢失
S1: PDF 无法打开；搜索/页码基础能力不可用；缺失 PDF 导致模块崩溃
```
