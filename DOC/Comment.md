以下是我对当前阶段的审阅和下一步修改意见。整体判断是：**底座已经成型，但产品价值闭环还没有真正跑通。下一步不建议继续扩很多外围功能，而应优先打通“论文导入 → Markdown 知识页 → LLM 总结 → wiki 再利用”这条主线。**

---

# 一、总体审阅结论

当前实现已经完成了一个比较扎实的 MVP 底座，包括：

- 工作区模型与目录初始化；
- 创建、打开、恢复最近工作区；
- SwiftUI 三栏主界面；
- Paper 数据模型；
- `meta.yaml` 读写；
- PDF 导入；
- `raw/papers/{paper-id}` 目录生成；
- `paper.pdf`、`meta.yaml`、`annotations.md` 生成；
- Library 列表展示；
- 元数据编辑；
- 系统默认方式打开 PDF；
- 基础测试验证 [1]。

这说明当前项目不是停留在概念层，而是已经有了可运行、可导入论文、可管理元数据的基础应用。

但是，从“科研工作站”的目标来看，现在仍然更像是一个：

> 本地 PDF + YAML 元数据管理器

还没有形成真正区别于普通 PDF 管理工具的核心能力，也就是：

```text
论文 PDF
  ↓
结构化 Markdown
  ↓
wiki 知识页
  ↓
LLM 总结和知识编译
  ↓
概念、反链、研究空白、再利用
```

文档中也明确指出，下一步优先级应该是 Markdown 知识库闭环、LLM 总结闭环、导入质量和测试补强、搜索与索引、PDF 阅读器深度联动、VSCode/VSCodium 联动 [1]。

---

# 二、当前做得好的地方

## 1. 架构方向正确

当前实现坚持了“文件系统优先”，没有把关键数据锁进私有数据库，这一点非常重要 [1]。

这意味着后续即使更换 App、LLM、编辑器、PDF 阅读器，用户的数据仍然是开放的：

```text
PDF
Markdown
YAML
BibTeX
普通目录结构
```

这是科研工作站最核心的长期价值。

---

## 2. MVP 主链路已经具备

现在已经可以做到：

```text
创建工作区
导入 PDF
生成论文目录
生成 meta.yaml
显示在 Library
编辑元数据
打开 PDF
```

这说明基础链路已经能支撑后续扩展，不需要推倒重来。

---

## 3. 模块边界相对清楚

目前 Workspace、Library、Importer、PDF、UI 的职责边界比较清楚 [1]。

这对后续加入 Markdown、LLM、Search、Graph 模块很有利。建议继续保持这种分层，不要把 LLM、PDF、Markdown、数据库逻辑混进 View 里面。

---

## 4. 验证意识较好

当前已经验证了：

- 工作区创建；
- citekey 生成；
- `meta.yaml` 编解码；
- Repository 保存和读取；
- Xcode App target 构建 [1]。

这说明项目已经有一定工程化基础。后续只需要把测试覆盖从“核心模型”扩展到“真实业务链路”。

---

# 三、当前主要问题

## 问题 1：还没有 Markdown 知识库闭环

这是当前最大的缺口。

文档中提到，当前每篇论文目录还没有生成 `paper.md`，也还没有实际创建 `wiki/papers` 页面 [1]。

这会导致论文导入后仍然停留在：

```text
PDF + meta.yaml
```

而不是进入：

```text
PDF + 原始文本 + wiki 知识页 + 反链 + LLM 可读上下文
```

因此，下一步最重要的不是先做搜索、图谱或 PDF 深度阅读，而是先补齐：

```text
paper.md
wiki/papers/{citekey}.md
Markdown 浏览
Markdown 编辑
YAML frontmatter
wikilink
backlink
```

---

## 问题 2：LLM 闭环尚未开始

当前文档中明确把 LLM 能力接入列为阶段 B，目标是形成：

```text
导入 PDF → 摘要生成 → 写入 wiki
```

的核心闭环 [1]。

目前如果没有 LLM，总体体验还只是“整理论文”。  
但你最初想要的是“AI 科研工作站”，因此 LLM 总结、分析、生成知识页是核心差异化能力。

---

## 问题 3：导入链路还比较浅

现在导入时只提取了：

```text
title
author
year
```

但缺少：

```text
doi
venue
arXiv
url
abstract
keywords
semantic_scholar_id
```

文档也指出目前缺少 DOI、venue、arXiv、URL 等信息补全机制 [1]。

这会影响后续：

- BibTeX 质量；
- 引用管理；
- 搜索；
- LLM 总结 Prompt；
- 与 Semantic Scholar / arXiv 联动；
- 研究图谱构建。

不过这个问题我建议放在 Markdown 和 LLM 闭环之后处理，因为导入质量可以逐步增强，但知识流闭环必须先跑起来。

---

## 问题 4：PDF 阅读器仍然是最小实现

当前 Sioyek / Skim 只是协议预留，还没有真实命令调用或 URL scheme；也没有内置 PDF 预览、页码跳转、注释定位和阅读上下文联动 [1]。

这部分重要，但不是最高优先级。原因是：

> PDF 阅读器可以先依赖外部工具，但 Markdown 知识页和 LLM 总结必须由你的 App 组织起来。

所以 PDF 模块下一步只需要先补：

```text
配置默认 PDF 阅读器
Sioyek 打开命令
Skim 打开命令
打开失败提示
```

不要过早做复杂批注系统。

---

## 问题 5：占位 UI 较多，产品状态需要同步

文档指出，部分界面文案还停留在“下一步要做论文模型和导入”的旧描述，Sidebar 中除了 Library 之外很多 section 还是占位视图 [1]。

这会影响两个方面：

1. 用户不知道当前系统到底完成了什么；
2. AI 编程助手后续可能被旧文案误导。

所以建议尽快做一次“状态文案清理”。

---

# 四、我建议的下一步优先级

我建议采用以下顺序：

```text
第一优先级：Markdown 知识库闭环
第二优先级：LLM 总结闭环
第三优先级：导入结构补齐和测试补强
第四优先级：搜索与索引
第五优先级：PDF 阅读器真实联动
第六优先级：VSCode / VSCodium 联动
```

这个顺序与任务书中建议的优先级基本一致：先做 Markdown 知识库闭环，再做 LLM 总结闭环，然后补导入质量、搜索索引、PDF 阅读器和 VSCode/VSCodium 联动 [1]。

---

# 五、下一步具体修改意见

## 修改 1：补齐工作区目录结构

当前缺少：

```text
refs/csl/
researchflow.sqlite
```

建议在 Workspace 初始化时补齐：

```text
ResearchWorkspace/
├── refs/
│   ├── library.bib
│   └── csl/
└── researchflow.sqlite
```

不过注意：

```text
researchflow.sqlite
```

第一阶段可以先作为空文件或延迟创建，不一定马上实现索引层。

建议任务：

```text
WorkspaceInitializer
  - ensure refs/csl exists
  - ensure library.bib exists
  - optionally ensure researchflow.sqlite placeholder exists
```

验收标准：

```text
新建工作区后目录结构与 Proposal 完全一致。
打开旧工作区时可以自动补齐缺失目录。
```

---

## 修改 2：导入论文时创建 `paper.md` 和 `figures/`

当前每篇论文目录没有生成 `paper.md` 和 `figures/` [1]。

建议导入后目录变成：

```text
raw/papers/{paper-id}/
├── paper.pdf
├── paper.md
├── meta.yaml
├── annotations.md
└── figures/
```

第一版 `paper.md` 不需要真的完成高质量 PDF 转 Markdown，可以先生成占位模板：

```markdown
---
type: raw-paper
citekey: smith2024graph
source_pdf: paper.pdf
status: not_extracted
---

# Raw Text

PDF text has not been extracted yet.

## Extraction Notes

- Source: paper.pdf
- Method: pending
```

后续再接 PDFKit、Marker、MinerU 或 `pdftotext`。

验收标准：

```text
导入任意 PDF 后，paper.md 和 figures/ 必须存在。
```

---

## 修改 3：新增 wiki/papers 页面模板生成器

这是下一步最关键的修改。

导入论文后，应支持一键生成：

```text
wiki/papers/{citekey}.md
```

模板如下：

```markdown
---
type: paper
id: smith2024graph
citekey: smith2024graph
title: "Graph-based Retrieval Augmented Generation"
year: 2024
authors:
  - John Smith
tags: []
status: imported
source_pdf: ../../raw/papers/smith2024-graph-rag/paper.pdf
source_raw_md: ../../raw/papers/smith2024-graph-rag/paper.md
created: 2026-04-27
updated: 2026-04-27
---

# Graph-based Retrieval Augmented Generation

## TL;DR

待总结。

## 研究问题

待补充。

## 方法概述

待补充。

## 关键贡献

待补充。

## 实验与证据

待补充。

## 局限性

待补充。

## 与已有工作的关系

待补充。

## 可复现性检查

待补充。

## 对我研究的启发

待补充。

## 相关概念

- 

## 可能研究空白

- 

## 引用

[@smith2024graph]
```

建议新增：

```text
WikiPageGenerator
PaperWikiTemplateRenderer
MarkdownFrontmatterWriter
```

验收标准：

```text
选中论文后点击 Generate Wiki Page。
生成 wiki/papers/{citekey}.md。
meta.yaml 中 notes.summary_file 指向该文件。
Library 中可以显示该论文是否已有 wiki page。
```

---

## 修改 4：新增 Markdown 模块

下一阶段应该正式新增 Markdown 模块。

最小功能包括：

```text
扫描 wiki/ 目录
显示 Markdown 页面列表
打开 Markdown
编辑 Markdown
保存 Markdown
解析 YAML frontmatter
解析 [[wikilink]]
统计 backlinks
```

第一版不一定要做复杂 Markdown 所见即所得，简单的：

```text
左侧页面列表
中间 Markdown 编辑器
右侧 frontmatter / backlinks
```

就足够。

建议模块：

```text
Markdown/
├── MarkdownDocument.swift
├── MarkdownRepository.swift
├── FrontmatterParser.swift
├── WikiLinkParser.swift
├── BacklinkIndex.swift
├── MarkdownEditorView.swift
└── MarkdownPreviewView.swift
```

验收标准：

```text
用户能在 App 内打开 wiki/papers/{citekey}.md。
用户能编辑并保存。
应用能识别页面中的 [[Concept]]。
应用能显示哪些页面链接到当前页面。
```

---

## 修改 5：先做 backlink，不急着做复杂 graph

图谱可视化容易消耗大量时间，但第一阶段真正有用的是：

```text
当前页面链接了谁？
谁链接了当前页面？
```

所以建议先实现：

```text
Outgoing Links
Backlinks
Related Pages
```

而不是马上做 force-directed graph。

例如右侧 Inspector 显示：

```text
Backlinks
- wiki/concepts/RAG.md
- wiki/gaps/graph-rag-evaluation.md

Outgoing Links
- [[Retrieval Augmented Generation]]
- [[Knowledge Graph]]
- [[Vector RAG]]
```

验收标准：

```text
修改 Markdown 后，backlink 可以重新计算。
点击 backlink 可以打开对应页面。
```

---

## 修改 6：接入 LLMProvider，但先只做两个 Provider

LLM 阶段建议不要一次性接太多供应商。

先做：

```text
OllamaProvider
OpenAICompatibleProvider
```

因为它们覆盖了：

```text
本地模型
云端兼容模型
LM Studio
vLLM
OpenRouter
其他 OpenAI-compatible API
```

建议接口：

```swift
protocol LLMProvider {
    var id: String { get }
    var name: String { get }

    func complete(request: LLMChatRequest) async throws -> LLMChatResponse

    func streamChat(request: LLMChatRequest) async throws -> AsyncThrowingStream<LLMToken, Error>
}
```

第一阶段如果流式实现复杂，可以先做非流式：

```swift
func complete(request: LLMChatRequest) async throws -> LLMChatResponse
```

然后再补流式。

验收标准：

```text
设置中可以选择 Ollama 或 OpenAI-compatible。
可以填写 Base URL、Model。
API Key 预留 Keychain 接口。
可以发送测试消息并得到回复。
```

---

## 修改 7：实现 Summarize with LLM

这是整个产品的价值拐点。

流程建议：

```text
用户选择一篇论文
点击 Summarize with LLM
应用读取 meta.yaml
应用读取 paper.md
如果 paper.md 为空，则尝试 PDFKit 提取文本
应用读取已有 wiki/papers/{citekey}.md
构造 Prompt
弹窗显示将发送的上下文摘要
用户确认
调用 LLM
生成 Markdown
保存到 wiki/papers/{citekey}.md
更新 meta.yaml status = summarized
```

注意：

LLM 输出不要直接静默覆盖用户已有内容。建议采用：

```text
如果 wiki page 不存在：直接创建
如果 wiki page 已存在：生成预览，用户确认后覆盖或追加
```

验收标准：

```text
用户能从 Library 选中一篇论文。
点击 Summarize with LLM。
看到 LLM 输出。
保存后 wiki/papers/{citekey}.md 更新。
meta.yaml 状态更新为 summarized。
```

---

## 修改 8：清理 UI 占位文案

文档指出，部分界面文案还是旧状态，Sidebar 里多个 section 仍然是占位视图 [1]。

建议立即处理：

```text
Library：显示真实论文库
Wiki：显示 wiki 页面列表或“尚未建立知识页”
Graph：显示“backlink 已支持，图谱开发中”
LLM Lab：显示 Provider 设置和测试入口
Settings：显示工作区、PDF、LLM、外部工具设置
```

不要出现“下一步要做论文模型和导入”这类过期提示。

验收标准：

```text
所有占位文案都反映当前真实能力。
用户不会误以为 PDF 导入还没实现。
```

---

## 修改 9：补强导入测试

当前测试覆盖偏窄，PDFImportService 缺少独立验证，UI 层和 AppViewModel 层也缺少行为验证 [1]。

建议至少补这些测试：

```text
PDFImportServiceTests
  - 导入 PDF 后目录是否存在
  - paper.pdf 是否存在
  - meta.yaml 是否存在
  - annotations.md 是否存在
  - paper.md 是否存在
  - figures/ 是否存在
  - 重复导入是否生成不同 paper-id

WikiPageGeneratorTests
  - 能否根据 Paper 生成 wiki/papers/{citekey}.md
  - frontmatter 是否正确
  - source_pdf 路径是否正确
  - 已存在文件时是否避免静默覆盖

MarkdownParserTests
  - frontmatter 解析
  - wikilink 解析
  - backlink 统计

LLMRequestBuilderTests
  - Prompt 是否包含 metadata
  - Prompt 是否包含 paper content
  - 空 paper.md 时是否给出合理错误
```

验收标准：

```text
核心链路：导入 PDF → 生成 paper.md → 生成 wiki page → LLM request 构造，均有测试覆盖。
```

---

# 六、我建议下一轮开发采用的任务包

我建议下一轮不要同时做太多模块，而是采用：

```text
方案 1：知识库优先
```

也就是文档里提到的：

- 新增 Markdown 模块；
- 导入后自动生成 `paper.md` 和 `wiki/papers` 页面模板；
- 做 wikilink 和 backlink 最小闭环 [1]。

原因是：

> 只有论文进入 Markdown 知识库，后续 LLM、搜索、图谱、VSCode 联动才有共同的数据底座。

如果直接先做 LLM，LLM 结果也需要有地方保存。  
如果直接先做搜索，搜索也需要有 wiki 页面可索引。  
如果直接先做图谱，图谱也依赖 wikilink 和 backlink。

所以最合理顺序是：

```text
先 Markdown
再 LLM
再 Search
再 Graph
```

---

# 七、建议下一步开发顺序

## 第一步：修正工作区结构

完成：

```text
refs/csl/
researchflow.sqlite placeholder
```

同时打开旧工作区时自动补齐。

---

## 第二步：修改 PDF 导入输出结构

导入后生成：

```text
paper.pdf
paper.md
meta.yaml
annotations.md
figures/
```

---

## 第三步：新增 wiki 页面生成器

选中论文后生成：

```text
wiki/papers/{citekey}.md
```

并在 `meta.yaml` 中更新：

```yaml
notes:
  summary_file: "../../../wiki/papers/smith2024graph.md"
```

---

## 第四步：实现 Markdown 页面列表

扫描：

```text
wiki/papers/
wiki/concepts/
wiki/methods/
wiki/datasets/
wiki/authors/
wiki/gaps/
wiki/projects/
```

并展示页面列表。

---

## 第五步：实现 Markdown 编辑和保存

先用普通 TextEditor 即可。

不必第一版追求高级 Markdown 渲染。

---

## 第六步：实现 frontmatter 和 wikilink 解析

支持：

```markdown
---
type: paper
tags:
  - rag
---

[[Retrieval Augmented Generation]]
[[Knowledge Graph]]
```

---

## 第七步：实现 backlink 面板

根据所有 wiki 页面构建：

```text
page A → page B
page C → page B
```

当打开 page B 时，显示：

```text
Backlinks:
- page A
- page C
```

---

## 第八步：补测试

覆盖：

```text
Workspace 补齐
PDFImportService
WikiPageGenerator
FrontmatterParser
WikiLinkParser
BacklinkIndex
```

---

# 八、可以直接发给 AI 编程助手的下一步指令

下面这段可以直接复制给 AI 编程助手：

```markdown
请继续开发 Sci-Station / ResearchFlow Mac 的下一阶段功能。本阶段目标是完成 Markdown 知识库闭环。

当前项目已经完成：
1. 工作区创建和打开。
2. 工作区目录初始化。
3. Paper 数据模型。
4. ReadingStatus 和 Priority。
5. citekey 和 paper id 生成。
6. meta.yaml 读写。
7. PaperRepository 保存与加载。
8. PDF 选择和拖拽导入。
9. raw/papers/{paper-id}/paper.pdf、meta.yaml、annotations.md 生成。
10. Library Table 展示。
11. Paper Inspector 元数据编辑。
12. 系统默认方式打开 PDF。
13. 基础 Core Test Runner。

下一阶段请按以下顺序实现。

第一步：补齐工作区目录结构
- Workspace 初始化时创建 refs/csl/。
- Workspace 初始化时创建或预留 researchflow.sqlite。
- 打开旧工作区时自动补齐缺失目录。
- 更新相关测试。

第二步：补齐论文导入目录结构
导入 PDF 后，每篇论文目录必须包含：

raw/papers/{paper-id}/
├── paper.pdf
├── paper.md
├── meta.yaml
├── annotations.md
└── figures/

其中 paper.md 第一版可以是模板文件，不需要真正完成 PDF 转 Markdown。
figures/ 为空目录即可。

第三步：新增 WikiPageGenerator
- 根据 Paper 和 meta.yaml 生成 wiki/papers/{citekey}.md。
- 生成 Markdown frontmatter。
- 写入论文标题、作者、年份、citekey、source_pdf、source_raw_md。
- 正文包含 TL;DR、研究问题、方法概述、关键贡献、实验与证据、局限性、相关概念、可能研究空白、引用等章节。
- 如果文件已存在，不允许静默覆盖，必须返回 alreadyExists 错误或要求用户确认。
- 生成后更新 meta.yaml 中 notes.summary_file。

第四步：新增 Markdown 模块
请创建 Markdown 模块，至少包括：

MarkdownDocument.swift
MarkdownRepository.swift
FrontmatterParser.swift
WikiLinkParser.swift
BacklinkIndex.swift
MarkdownEditorView.swift
MarkdownPageListView.swift

功能要求：
- 扫描 wiki/ 下所有 .md 文件。
- 读取 Markdown 正文。
- 解析 YAML frontmatter。
- 解析 [[wikilink]]。
- 统计 backlinks。
- 支持打开、编辑、保存 Markdown 文件。

第五步：更新 UI
- Sidebar 中 Wiki section 不再是占位页。
- 点击 Wiki 后显示 Markdown 页面列表。
- 点击页面后打开 Markdown 编辑器。
- 右侧 Inspector 显示 frontmatter、outgoing links、backlinks。
- Library 中选中论文后提供 Generate Wiki Page 按钮。
- 如果该论文已有 wiki page，按钮显示 Open Wiki Page。

第六步：补测试
请新增或扩充以下测试：
- Workspace 初始化能创建 refs/csl/。
- PDF 导入后生成 paper.md 和 figures/。
- WikiPageGenerator 能生成正确路径和 frontmatter。
- 已存在 wiki page 时不会静默覆盖。
- FrontmatterParser 能解析 YAML frontmatter。
- WikiLinkParser 能解析 [[link]]。
- BacklinkIndex 能正确统计反链。

代码质量要求：
1. 使用 Swift / SwiftUI。
2. 保持 MVVM + Service Layer。
3. 文件系统仍然是真实数据源。
4. 所有文件写入必须有错误处理。
5. UI 不得阻塞主线程。
6. 所有长任务使用 async/await。
7. 不要引入私有数据库作为唯一数据源。
8. 新增模块必须职责清晰。
9. 每完成一个步骤，请说明新增文件、修改文件、测试方法。
```

---

# 九、最终建议

我的建议很明确：

> 下一步不要先做复杂图谱，也不要先做完整 PDF 阅读器，更不要先堆很多 LLM Provider。  
> 应该先完成 Markdown 知识库闭环。

最小闭环应该是：

```text
导入 PDF
  ↓
生成 paper.md
  ↓
生成 wiki/papers/{citekey}.md
  ↓
应用内打开和编辑 Markdown
  ↓
解析 [[wikilink]]
  ↓
显示 backlinks
```

完成这个之后，再进入：

```text
Summarize with LLM
  ↓
LLM 写入 wiki/papers/{citekey}.md
  ↓
生成概念页 / gaps
  ↓
搜索和图谱
```

这样项目就会从“PDF 管理器”真正变成“科研知识工作站”。