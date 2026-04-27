# Sci-Station 下一阶段任务书

更新时间：2026-04-27

## 1. 文档目的

这份任务书基于当前代码状态、原始 Proposal 和本轮审阅意见整理，目标是明确三件事：

1. 这一轮实际上已经完成了什么。
2. 当前还缺什么，阻碍下一阶段价值闭环。
3. 接下来最合理的开发顺序是什么。

## 2. 当前阶段结论

本轮已经把任务重点从“纯 PDF + YAML 管理”推进到了“最小 Markdown 知识闭环”。

现在系统已经具备以下主链路：

1. 创建或打开工作区。
2. 自动补齐工作区缺失结构。
3. 导入 PDF 并生成论文目录。
4. 为论文生成 paper.md 原始 Markdown 占位页。
5. 为论文生成 wiki/papers/{citekey}.md 知识页模板。
6. 在应用内浏览、编辑、保存 wiki Markdown。
7. 解析 frontmatter、wikilink 和 backlinks。

因此，Sci-Station 当前已经不再只是本地 PDF 管理器，而是完成了知识页落地的第一版底座。下一步不应再回头补同一层，而应进入 LLM 总结闭环和导入质量补强。

## 3. 本轮已完成内容

### 3.1 工作区结构补齐

- 已补齐 refs/csl 目录。
- 已补齐 researchflow.sqlite 占位文件。
- 已将 createWorkspace 和 openWorkspace 统一到 ensureWorkspaceStructure 逻辑。
- 已支持打开旧工作区时自动补齐缺失目录和种子文件，而不是直接报错。

### 3.2 论文导入输出结构补齐

- 已保留原有 paper.pdf、meta.yaml、annotations.md 生成能力。
- 已新增 paper.md 模板生成。
- 已新增 figures/ 空目录生成。
- 已保留导入后写入 summary_file 目标路径的逻辑。

导入后每篇论文目录现在为：

```text
raw/papers/{paper-id}/
├── paper.pdf
├── paper.md
├── meta.yaml
├── annotations.md
└── figures/
```

### 3.3 Wiki 页面生成器

- 已新增 WikiPageGenerator。
- 已支持为选中文章生成 wiki/papers/{citekey}.md。
- 已在生成后把 notes.summary_file 回写到 meta.yaml。
- 已在文件已存在时返回 alreadyExists，而不是静默覆盖。

### 3.4 Markdown 模块最小闭环

- 已新增 MarkdownDocument。
- 已新增 FrontmatterParser。
- 已新增 WikiLinkParser。
- 已新增 BacklinkIndex。
- 已新增 MarkdownRepository。
- 已支持扫描 wiki/ 下全部 Markdown 页面。
- 已支持打开、编辑、保存 Markdown 文件。
- 已支持解析 YAML frontmatter。
- 已支持解析 [[wikilink]]。
- 已支持统计当前页面的 backlinks。

### 3.5 UI 与状态文案更新

- Wiki section 已不再是占位页。
- 已新增 WikiWorkspaceView。
- 已新增 MarkdownPageListView。
- 已新增 MarkdownEditorView。
- 已新增 WikiInspectorView。
- Library 已新增 Wiki 状态列。
- Paper Inspector 已新增 Generate Wiki Page / Open Wiki Page 按钮。
- WorkspaceSectionOverview 的过期文案已更新为当前真实能力。

### 3.6 验证补强

- SwiftPM Core Test Runner 已新增工作区补齐检查。
- 已新增 PDFImportService 输出结构检查。
- 已新增 WikiPageGenerator 路径、模板和防覆盖检查。
- 已新增 FrontmatterParser 检查。
- 已新增 WikiLinkParser 检查。
- 已新增 BacklinkIndex 检查。
- 已新增 MarkdownRepository 读写检查。
- Xcode App target 构建已通过。

## 4. 当前还缺什么

虽然 Markdown 知识闭环已经落地，但产品价值闭环还没有完成，主要缺口集中在下面几项。

### 4.1 LLM 闭环仍未开始

当前已经有了 paper.md 和 wiki 页面，但还没有：

- LLMProvider 协议。
- OllamaProvider。
- OpenAI-compatible Provider。
- Prompt 构造。
- 论文总结动作入口。
- 结果预览、确认写回和状态更新。

这意味着系统已经具备“知识页容器”，但还没有“AI 总结引擎”。

### 4.2 导入质量仍然偏浅

当前导入仍主要依赖 PDFKit 和文件名，只能稳定得到：

- title
- authors
- year

仍缺：

- doi
- venue
- arXiv
- url
- abstract
- keywords
- semantic scholar / crossref 补全接口

这会直接影响后续 BibTeX 质量、搜索质量和 LLM Prompt 质量。

### 4.3 Markdown 仍是最小编辑器

当前版本已经足够用于验证链路，但还缺少：

- 预览模式或双栏模式。
- 未保存状态提示。
- 基于链接目标的直接跳转建议。
- 对不存在链接页面的创建入口。
- 更细的编辑体验优化。

这些不是当前最高优先级，但属于下一阶段的自然补强项。

### 4.4 PDF 联动仍然停留在最小实现

目前仍只有系统默认方式打开 PDF。

还没有：

- Sioyek / Skim 的真实调用。
- 跳页。
- 注释回链。
- 内置 PDF 预览。

### 4.5 搜索与索引仍未开始

researchflow.sqlite 目前只是占位文件，尚未承担真实索引职责。

因此当前仍缺：

- 面向 meta.yaml 的统一索引。
- 面向 wiki/*.md 的全文索引。
- 跨论文与知识页的统一搜索。

## 5. 下一步建议优先级

当前优先级应从“Markdown 知识库优先”正式切换到下面这组顺序：

1. LLM 总结闭环。
2. 导入质量和测试补强。
3. 搜索与索引。
4. PDF 阅读器真实联动。
5. VSCode / VSCodium 联动。
6. 图谱可视化。

原因很直接：Markdown 承载层已经到位，下一步最有价值的不是继续堆 Markdown 基础设施，而是让 LLM 真正把论文内容写回知识页。

## 6. 下一轮建议开发范围

### 阶段 B：LLM 能力接入

目标：形成“导入 PDF -> 读取 paper.md / wiki page -> 生成总结 -> 写回 wiki”的核心闭环。

本阶段建议交付：

- 定义 LLMProvider 协议。
- 先接 OllamaProvider。
- 再接 OpenAICompatibleProvider。
- 定义聊天请求、响应和错误模型。
- 定义论文总结 Prompt Builder。
- 支持从 Library 触发 Summarize with LLM。
- 在写回 wiki 前提供预览与确认。
- 生成完成后更新 paper status 或 summary 状态。

验收标准：

- 用户能从选中的论文触发一次总结。
- 系统会读取 meta.yaml、paper.md 和已有 wiki 页面。
- 用户能看到生成结果预览。
- 用户确认后结果写回 wiki/papers/{citekey}.md。

### 阶段 C：导入质量与元数据补全

目标：让导入信息不再只停留在 title / author / year。

本阶段建议交付：

- 增加 DOI、venue、arXiv、url 字段补全入口。
- 优先考虑 Crossref、arXiv 或 Semantic Scholar 补全策略。
- 增加 paper.md 内容为空时的合理降级处理。
- 针对重复导入、弱元数据 PDF、损坏 PDF 补错误路径验证。

验收标准：

- 至少一种补全路径可稳定写回 meta.yaml。
- 失败场景有清晰错误提示。
- LLM Prompt 能使用更完整的 metadata。

### 阶段 D：搜索与索引

目标：把已有论文库和 wiki 页面变成真正可检索的知识库。

本阶段建议交付：

- 为 meta.yaml 和 wiki/*.md 建立统一索引。
- 先支持标题、作者、标签、摘要检索。
- 再支持全文搜索。
- 明确 researchflow.sqlite 的真实职责。

### 阶段 E：PDF 阅读器联动

目标：把阅读动作接回研究流程，而不是只做系统打开。

本阶段建议交付：

- 接入 Sioyek 或 Skim 的真实打开命令。
- 增加阅读器配置入口。
- 支持最小跳页能力。
- 对打开失败给出可理解提示。

## 7. 我建议下一轮直接做什么

如果只选一个任务包，我建议下一轮直接做下面这组：

### 方案 1：LLM 闭环优先

建议任务：

- 定义 LLMProvider 协议。
- 实现 OllamaProvider。
- 实现 OpenAICompatibleProvider。
- 新增 Summarize with LLM 动作。
- 新增 Prompt Builder。
- 新增生成结果预览与确认写回。

这是当前最应该做的一步，因为 Markdown 落点已经存在，再不接 LLM，知识页就仍然主要是人工模板。

### 方案 2：导入质量优先

建议任务：

- 补 doi / venue / arXiv / url。
- 优化 paper.md 原文提取策略。
- 增加更真实的导入失败测试。

适合在 LLM 之前做，前提是你更关注输入质量而不是先看到 AI 闭环。

### 方案 3：搜索优先

建议任务：

- 建索引。
- 做统一搜索入口。
- 支持从搜索结果跳回论文或 wiki 页面。

适合在 LLM 接入之后做，因为届时知识页内容会更丰富，搜索收益更高。

## 8. 推荐的实际开发顺序

推荐顺序如下：

1. 先做 LLMProvider 和 Summarize with LLM。
2. 再做 metadata 补全和导入质量提升。
3. 然后做搜索与索引。
4. 再补 PDF 阅读器真实联动。
5. 最后再做 VSCode / VSCodium 联动和图谱可视化。

## 9. 可直接给 AI 编程助手的下一步指令

下面这段可以直接用于下一轮开发：

```markdown
请继续开发 Sci-Station 的下一阶段功能。本阶段目标是完成 LLM 总结闭环，并建立可确认写回的总结流程。

当前项目已经完成：
1. 工作区创建、打开和最近工作区恢复。
2. 工作区缺失目录自动补齐，包括 refs/csl 和 researchflow.sqlite 占位。
3. Paper 模型、citekey / paper id 生成、meta.yaml 编解码、PaperRepository 保存与加载。
4. PDF 导入，并生成 raw/papers/{paper-id}/paper.pdf、paper.md、meta.yaml、annotations.md、figures/。
5. WikiPageGenerator，可生成 wiki/papers/{citekey}.md，并更新 meta.yaml 中 notes.summary_file。
6. Markdown 模块，包括 MarkdownDocument、MarkdownRepository、FrontmatterParser、WikiLinkParser、BacklinkIndex。
7. 应用内 Wiki 页面列表、Markdown 编辑器、frontmatter / outgoing links / backlinks Inspector。
8. Library 中的 Generate Wiki Page / Open Wiki Page 按钮。
9. Core Test Runner 对工作区补齐、PDFImportService、WikiPageGenerator、FrontmatterParser、WikiLinkParser、BacklinkIndex、MarkdownRepository 的验证。

下一阶段请按以下顺序实现。

第一步：定义 LLMProvider 抽象
- 新增 LLMProvider 协议。
- 新增请求、响应、错误和模型配置结构。
- 第一阶段只支持非流式 complete 接口即可。

第二步：接入两个 Provider
- 实现 OllamaProvider。
- 实现 OpenAICompatibleProvider。
- 支持 Base URL、Model、API Key 配置。

第三步：实现论文总结任务
- 从选中的 Paper 读取 meta.yaml。
- 读取 raw/papers/{paper-id}/paper.md。
- 读取已有 wiki/papers/{citekey}.md。
- 构造论文总结 Prompt。
- 返回结构化 Markdown 结果。

第四步：实现写回前预览
- 用户点击 Summarize with LLM 后，不要直接覆盖 wiki 页面。
- 先显示生成结果预览。
- 用户确认后才写回 wiki/papers/{citekey}.md。
- 写回后更新 paper 的相关状态。

第五步：更新 UI
- Library Inspector 中增加 Summarize with LLM 按钮。
- Settings 或 LLM Lab 中增加 Provider 配置入口。
- 显示当前 Provider、Model 和错误信息。

第六步：补测试
- LLM Prompt Builder 是否包含 metadata、paper.md 和已有 wiki 内容。
- 空 paper.md 或缺失 wiki 页面时是否走合理降级逻辑。
- 生成结果写回前是否必须显式确认。

代码质量要求：
1. 保持文件系统为真实数据源。
2. UI 不阻塞主线程。
3. 长任务全部使用 async/await。
4. 不允许无提示静默覆盖用户已有 wiki 内容。
5. Provider、Prompt、写回流程要职责清晰。
```

## 10. 最终建议

当前阶段已经完成了文档审阅中要求的第一优先级，也就是 Markdown 知识库闭环。接下来不建议再围绕 Markdown 基础设施继续横向扩展，而应直接进入“Summarize with LLM -> 预览确认 -> 写回 wiki”这条主线。

只有这条链路打通，Sci-Station 才会从“可整理论文”变成“可编译知识”的科研工作站。