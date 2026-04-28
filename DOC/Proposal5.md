# 任务书 5：日程可编辑、引用导出与研究流程收束

## 背景

Sci-Station 已经具备本地工作区、论文导入、Library 管理、Wiki、PDF Reader、LLM 总结、Apple Calendar/Reminders 数据接入和扩展论文元数据。上一版任务书 5 的重点是“把已有功能收束成稳定研究流程”。本轮进一步暴露出几个更贴近日常使用的问题：月历只显示数量不显示事项内容，todo 创建和修改不够完整，Library 顶部操作优先级不清晰，元数据输入缺少键盘提交闭环，以及论文引用没有独立的 BibTeX 出口。

因此新版任务书 5 的目标不是新增孤立页面，而是把“日程、元数据、引用导出、检索基础”连成更可靠的研究工作流。

## 本轮已落地能力

1. Dashboard 月历从数字计数改为事项型月视图，直接显示 workspace todo、workspace event、Apple Calendar event 和 Apple Reminder 的标题。
2. Todo 创建时支持 due date、priority 和 notes；已有 todo 支持行内编辑 status、due date、priority、notes 和 title。
3. Library 顶部操作调整为 Import PDF 左移，Add by Link 作为最右侧蓝色主按钮。
4. Paper Inspector 文本字段支持回车保存元数据，并在点击空白区域时释放输入焦点。
5. 导入 DOI、arXiv、INSPIRE 元数据时会尽量抓取 provider 原生 BibTeX。
6. Paper 本地模型和 meta.yaml 支持保存 BibTeX。
7. 论文右键菜单新增 Export BibTeX，弹窗展示 BibTeX、自动复制到剪贴板，并提供导出 .bib 文件的入口。

## 当前缺口

1. Apple Reminders 仍然缺少本地 todo 与系统 reminder 的双向标识映射。
2. BibTeX 抓取已经接入 provider，但缺少 provider 样例回归测试和失败时的质量检查。
3. Todo 与 Calendar 仍是 day-level due date，没有 time、repeat、提醒提前量、external identifier 等字段。
4. Paper metadata 字段更多了，但还缺少面向 Zotero/CSL/BibTeX 的一致性校验。
5. Library 搜索仍是内存过滤，尚未覆盖 BibTeX、abstract、wiki 正文、annotations 和 LLM summary。
6. PDF Reader 右侧栏仍以只读展示为主，Notes/Tasks/Links 尚未形成完整读写闭环。
7. UI 行为主要靠手动验证，缺少针对 Calendar、Todo、BibTeX export、Inspector submit 的自动化检查。

## 新目标

### 目标 1：建立可信的任务同步模型

- 为 `TodoItem` 增加外部系统字段：external source、external identifier、external updated time。
- 支持将已有本地 todo 发布到 Apple Reminders。
- 支持从 Apple Reminders 刷新完成状态和 due date。
- 为冲突处理提供明确策略：本地优先、系统优先、手动选择。

### 目标 2：让引用数据可导入、可编辑、可导出

- 为 DOI、arXiv、INSPIRE provider 增加 BibTeX 样例测试。
- 增加 BibTeX normalization：统一 citekey、清理空字段、保留 provider 原始字段。
- 在 Paper Inspector 中提供 BibTeX 只读预览和重新生成动作。
- 支持批量导出选中论文或当前 collection 的 BibTeX。

### 目标 3：补强元数据可信度

- 为 `PaperMetadataCodec` 添加扩展字段与 BibTeX 的完整 round-trip 测试。
- 为 metadata refresh 增加差异预览，避免远端数据直接覆盖用户手改字段。
- 建立 Zotero-like 字段和 BibTeX/CSL 字段之间的映射表。

### 目标 4：启动统一搜索索引

- 明确 `researchflow.sqlite` 第一版 schema。
- 索引 paper metadata、BibTeX、abstract、wiki markdown、annotations、LLM summary。
- Library 和 Wiki 搜索逐步切换到统一搜索服务。
- 后续接入 PDF text extraction 缓存和 ranking。

### 目标 5：把 PDF Reader 接入研究动作

- 右侧栏扩展为 Metadata、Notes、Links、Tasks、Citations。
- Notes 面板直接编辑 `annotations.md`。
- Tasks 面板创建关联当前论文的 todo。
- Citations 面板显示 BibTeX 并支持复制/导出。
- Links 面板展示 wiki page、backlinks、DOI/arXiv/INSPIRE 外链。

## 执行任务

### 任务 A：Todo 与 Reminders 双向同步

- 扩展 `TodoItem` 外部同步字段。
- 更新 `TodoRepository` 编解码。
- 新增 Reminders 同步服务，处理新增、完成、due date 修改和冲突。
- Dashboard 增加发布、刷新和冲突提示。

### 任务 B：BibTeX 回归与批量导出

- 为 Crossref DOI BibTeX 添加固定样例。
- 为 arXiv BibTeX 添加固定样例。
- 为 INSPIRE BibTeX 添加固定样例。
- 增加单篇、选中多篇、collection 级导出。
- 增加剪贴板和 .bib 文件导出的手动测试清单。

### 任务 C：Metadata Refresh 与差异预览

- 对已有论文重新抓取 DOI/arXiv/INSPIRE 元数据。
- 展示本地字段和远端字段差异。
- 允许逐字段选择保留本地或采用远端。
- 刷新后保存到 `meta.yaml` 并更新 BibTeX。

### 任务 D：SQLite 搜索第一版

- 定义 papers、paper_metadata_index、wiki_pages、tasks、llm_runs 的最小 schema。
- 工作区加载后可重建索引。
- 先覆盖 title、authors、tags、DOI、arXiv、abstract、BibTeX、wiki 正文。
- 后续接 PDF 文本和 annotations。

### 任务 E：PDF Reader 工作流面板

- Notes 面板读写 `annotations.md`。
- Tasks 面板创建关联论文的 todo。
- Citations 面板复制/导出 BibTeX。
- Metadata 面板跳转 Library Inspector 编辑。

## 验收标准

1. 本地 todo 能创建、编辑、保存 priority、notes、due date，并能与 Apple Reminders 建立外部标识映射。
2. Calendar 月视图能直接显示事项标题，并在事项较多时保持布局不溢出。
3. 修改 Paper Inspector 文本字段后，回车保存成功，点击空白区域可结束输入状态。
4. DOI、arXiv、INSPIRE 导入能保存 BibTeX；失败时可用本地元数据生成 BibTeX。
5. 论文右键 Export BibTeX 会显示弹窗、复制剪贴板，并能导出 .bib 文件。
6. `meta.yaml` 往返不会丢失扩展元数据和 BibTeX。
7. SwiftPM Core Test Runner 与 Xcode macOS build 通过。

## 建议优先级

1. 先补 BibTeX 和 metadata codec 的回归测试，因为它们直接影响引用可靠性。
2. 再做 Reminders 双向同步，把 todo 变成真正可信的日程入口。
3. 然后推进 SQLite 搜索索引，让论文、Wiki、BibTeX、摘要和任务可统一检索。
4. 最后把 PDF Reader 右侧栏推进到 Notes/Tasks/Citations 的真实读写工作流。