# MT03：Wiki / Markdown 手动测试

更新时间：2026-05-05

## 目标

验证 Markdown 编辑、保存、预览、frontmatter、wikilink、backlink、snippet 和重启恢复。

## 前置条件

- Standard Workspace 包含 wiki 目录。
- 至少有一个用于图片相对路径测试的图片文件。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT03-01 | 新建 Wiki 页面 | 文件在 wiki/ 下创建 |
| MT03-02 | 编辑并 Cmd+S 保存 | Unsaved 标记消失，文件落盘 |
| MT03-03 | 未保存切换页面提示 | 不静默丢失修改 |
| MT03-04 | Source/Preview/Split 切换 | 内容一致，不崩溃 |
| MT03-05 | 表格渲染 | GFM 表格显示正确 |
| MT03-06 | 代码块渲染 | 代码块格式正确 |
| MT03-07 | KaTeX 公式渲染 | 公式显示或降级提示清楚 |
| MT03-08 | 图片相对路径渲染 | 图片从 workspace 相对路径加载 |
| MT03-09 | YAML frontmatter 解析 | frontmatter 不污染正文预览 |
| MT03-10 | [[wikilink]] outgoing links | outgoing links 可识别/跳转 |
| MT03-11 | backlinks | backlink 列表准确 |
| MT03-12 | snippets 触发 | snippet 插入内容正确 |

## 验收重点

```text
保存路径正确
切换页面不丢内容
预览不执行不安全内容
相对资源路径符合 Research Root
```

## 阻塞问题

```text
S0: 编辑保存导致数据丢失；未保存内容静默丢失
S1: Wiki 页面无法创建/保存；重启后内容无法恢复
```
