# Library、PDF 与 Wiki

## 范围

负责论文导入、元数据、PDF 阅读、Markdown notes、Wiki 页面、双向链接和文档编辑体验。

## 关键代码入口

- `Sci-Station/Library/`
- `Sci-Station/Importer/`
- `Sci-Station/Import/`
- `Sci-Station/MetadataProviders/`
- `Sci-Station/PDF/`
- `Sci-Station/Markdown/`
- `Sci-Station/Wiki/`
- `Sci-Station/UI/LibraryViews.swift`
- `Sci-Station/UI/WikiViews.swift`

## 数据路径

- `library/papers/<paper-id>/meta.yaml`
- `library/papers/<paper-id>/paper.pdf`
- `library/papers/<paper-id>/paper.md`
- `library/papers/<paper-id>/annotations.md`
- `wiki/**/*.md`

## 不变量

- 导入失败应给可恢复状态，不应留下半写坏数据。
- Metadata provider 原始响应不应直接泄漏到 UI 或长期持久化。
- PDF、Markdown、Wiki 修改必须可保存、可重启恢复。
- AI 写回 wiki/paper notes 前必须有权限和路径校验。
- Markdown renderer 不应依赖不可控公网 CDN 作为核心路径。

## 发布前检查

- 导入 PDF 后 Library 可见。
- 打开 PDF Reader 可阅读。
- 修改 `annotations.md` 或 wiki 页面后重启仍保留。
- 旧 workspace 中 paper metadata 缺字段时不崩溃。
