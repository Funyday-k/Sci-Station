# MT16: PDF Wiki Editing Manual Test Protocol

更新时间：2026-05-08
关联任务书：Proposal43.7

## Scope

验证 P43.7 的 PDF sidecar 标注、论文 `paper.md` 首次打开、Wiki 文件管理、Markdown 编辑器工具条，以及 PDF 选区进入全局 AI context。

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT16-P43.7-01 | PDF 选择文本高亮 | 打开一篇带本地 PDF 的论文，在 PDF Reader 中选择一段文字，点击高亮按钮或按 Cmd+Shift+H。 | PDF 上出现高亮，右栏 Notes -> PDF Marks 出现记录；重开同一 paper 后标注仍存在。 |
| MT16-P43.7-02 | PDF 下划线 | 选择 PDF 文本，点击下划线按钮或按 Cmd+Shift+U；缩放、翻页后返回该页。 | 下划线 overlay 位置保持正确，不写回原 PDF，只写 `pdf_annotations.json`。 |
| MT16-P43.7-03 | PDF note | 点击 note 按钮或按 Cmd+Shift+N，输入 note 后保存。 | PDF Marks 列表显示 note，可编辑 note 文本，点击跳转按钮回到对应页。 |
| MT16-P43.7-04 | 删除标注 | 在 PDF Marks 列表点击删除并确认。 | 标注从 PDF overlay 和列表消失，sidecar 中不再包含该记录。 |
| MT16-P43.7-05 | 打开 paper.md | 从 Library 或 Paper Inspector 点击打开论文 Markdown。 | 首次点击即显示 `paper.md` 内容，不需要 Reload Wiki。 |
| MT16-P43.7-06 | 新建 Wiki 页 | 在 Wiki 左栏点击 New Page，输入 `notes/test-page` 并应用。 | 文件创建为 `.md`，列表刷新并选中新页，editor 可编辑。 |
| MT16-P43.7-07 | 重命名当前 Wiki 页 | 选中新建页，点击 Rename，输入新文件名。 | 路径更新，内容不丢失，editor 继续显示新路径。 |
| MT16-P43.7-08 | 移动或归档当前 Wiki 页 | 使用 Move 输入目标文件夹，再使用 Archive 删除当前页。 | 移动后 selection 保持；归档后文件进入 `.sci-station/trash/wiki/`，列表选择安全回退。 |
| MT16-P43.7-09 | Markdown toolbar | 依次插入 heading、link、code block、task checkbox、table，并切到 Preview 或 Split。 | Draft 标记为 Unsaved；保存时状态显示 Saving -> Saved；Preview 与 source 内容同步。 |
| MT16-P43.7-10 | PDF 选区问 AI | 在 PDF 中选中文本，打开右侧 AI 面板，点击 Summarize 或 Todo Draft。 | AI action bar 显示 `Selected text from page N`，prompt 包含 page、selected text preview 和 `paper.md` path；写入类动作只生成 draft 意图。 |

## Notes

- PDF 标注默认 sidecar-only：`library/papers/<paper-id>/pdf_annotations.json`。
- Wiki 文件操作只允许 `wiki/` 与 `projects/<project-id>/wiki/` 下的 `.md`、`.markdown`、`.txt`。
- 删除/归档必须可恢复，不做 hard delete。