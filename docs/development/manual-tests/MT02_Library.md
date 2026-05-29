# MT02：Library 手动测试

更新时间：2026-05-05

## 目标

验证论文导入、元数据、搜索、批量操作、collection、BibTeX 与重启恢复。

## 前置条件

- Standard Workspace 包含至少 1 个可导入 PDF。
- 网络相关用例可根据环境标记 skipped，但必须记录原因。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT02-01 | Import PDF | 生成 paper.pdf / paper.md / meta.yaml / annotations.md |
| MT02-02 | Drag PDF | 拖入后导入成功 |
| MT02-03 | Add by DOI | 元数据可获取；失败时可保存 link-only draft |
| MT02-04 | Add by arXiv | 元数据可获取；DNS/网络失败时降级可理解 |
| MT02-05 | Add by PDF URL | 下载或 link-only 降级路径清楚 |
| MT02-06 | 批量 Add by Link | 多链接结果可逐项确认 |
| MT02-07 | 编辑 meta.yaml 字段 | 保存后文件落盘，重启恢复 |
| MT02-08 | 搜索 title/author/tag/DOI/arXiv/abstract/BibTeX | 命中符合预期 |
| MT02-09 | 多选批量 tag | 多篇论文 metadata 更新正确 |
| MT02-10 | 多选批量 status/priority/rating | 批量字段更新正确 |
| MT02-11 | 删除论文确认路径 | 有确认，删除范围清楚 |
| MT02-12 | 重启后论文仍存在 | Library 索引恢复 |

## 验收重点

```text
导入不会污染源码仓库
metadata 可编辑可恢复
网络失败有 link-only fallback
删除路径明确且需确认
```

## 阻塞问题

```text
S0: 导入/删除造成数据丢失；敏感路径写入报告或 debug 文件
S1: PDF 主路径不可用；Library 重启后无法恢复索引
```
