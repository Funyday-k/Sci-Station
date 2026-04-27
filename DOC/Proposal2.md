下面是基于你这 5 条新需求，对 Sci-Station 下一阶段的系统构思、实现 pipeline，以及可直接交给 AI 编程助手的任务书。

我先给出结论：**你现在提出的需求，意味着下一阶段不应该只做 LLM 总结闭环，而应该先把 Sci-Station 的界面和论文管理能力升级成“Zotero 风格的科研文库工作台”，然后在这个工作台里嵌入 PDF 阅读器、API 导入、云端 LLM、日历和 Todo。**

当前项目已经具备工作区、PDF 导入、`paper.md`、`wiki/papers/{citekey}.md`、Markdown 编辑、frontmatter、wikilink、backlinks 等最小知识闭环 [1][2]。但还没有 LLM 接入、导入元数据补全、全文检索、外部 PDF 阅读器深度集成、图谱可视化等能力 [2]。你的新需求正好对应下一轮架构升级。

---

# 一、总体实现方向

建议把下一阶段定位为：

```text
Sci-Station Phase 3:
Zotero-style Research Library Workbench
```

目标不是完全复制 Zotero，而是实现一个更适合你工作流的 macOS 原生科研工作台：

```text
左侧：文件夹分类 + 智能视图 + 彩色标签 + 订阅/API导入
中间：论文列表
右侧：PDF 内嵌阅读器 / 元数据 / LLM / Todo
顶部：按 DOI / arXiv / Inspire / URL 导入
首页：日历 + Todo + 最近论文 + 今日任务
```

核心主线应变成：

```text
文件夹 / API / Link 导入
        ↓
元数据补全
        ↓
PDF 下载或链接保存
        ↓
论文入库 raw/papers/
        ↓
分类文件夹 + 彩色标签
        ↓
内嵌 PDF 阅读
        ↓
云端 LLM 分析
        ↓
写回 wiki
        ↓
日历 / Todo 管理研究节奏
```

---

# 二、对 5 条需求的逐条审阅与实现构思

---

## 1. 内嵌 PDF 阅读器 + 默认本地预览调用

你的要求是：

> PDF 的预留口先写一个调用本地默认预览，同时希望能够将预览嵌在软件里，作为一个不错的 PDF 阅读器，风格参考 Zotero，分类栏目只需要自己的文件夹即可。

这个可以分两层实现。

---

## 1.1 第一层：保留外部默认预览

当前项目已经有 `PDFOpeningService` 协议，并且当前实现可以通过系统默认方式打开 PDF [2]。这一层应该保留，因为它简单、稳定，适合作为 fallback。

建议结构：

```swift
protocol PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws
}

final class SystemPDFOpeningService: PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws {
        await NSWorkspace.shared.open(url)
    }
}
```

---

## 1.2 第二层：新增内嵌 PDFKit 阅读器

macOS 原生最合适的是 `PDFKit`。

新增模块：

```text
PDF/
├── PDFOpeningService.swift
├── SystemPDFOpeningService.swift
├── EmbeddedPDFReaderView.swift
├── PDFReaderViewModel.swift
├── PDFDocumentService.swift
└── PDFReadingState.swift
```

核心能力第一版只做：

```text
打开 PDF
页码显示
上一页 / 下一页
缩放
搜索
跳页
保存阅读进度
右侧显示论文 metadata
```

第二版再做：

```text
高亮
注释
annotation 导出到 annotations.md
PDF 坐标回链
```

---

## 1.3 UI 风格参考 Zotero

建议主界面切换为：

```text
┌─────────────────────────────────────────────────────────────┐
│ Toolbar: Add by ID/Link | Import PDF | Search | LLM | Sync  │
├──────────────┬──────────────────────────────┬───────────────┤
│ Left Library │ Paper Table                  │ Right Panel   │
│              │                              │               │
│ My Library   │ Title | Tags | Authors | ... │ PDF Preview   │
│ Folders      │                              │ Metadata      │
│ Smart Views  │                              │ Notes         │
│ Tags         │                              │ LLM           │
│ Feeds/API    │                              │ Todo          │
└──────────────┴──────────────────────────────┴───────────────┘
```

对于你的截图，重点是实现：

```text
左侧：文件夹树 + 标签列表
中间：论文表格
右侧：PDF/元数据/笔记面板
```

---

## 2. 增强论文管理：子文件夹、彩色标签、Link、arXiv、INSPIRE

你的要求是：

> 加上子文件夹分类，自定义五颜六色的文字标签；不仅读取下载 PDF，也需要读取 link；调用 arxiv 和 inspire 接口爬取 PDF 和元数据。

这个建议拆成四个模块：

```text
Collections
Tags
Link Import
Metadata Providers
```

---

## 2.1 子文件夹分类功能

你说“分类栏目只需要自己的文件夹即可”，这很好。建议不要做 Zotero 那种复杂 collection database，而是让左侧文件夹对应文件系统。

当前 `raw/papers/` 可以升级为：

```text
raw/papers/
├── Dark-Matter/
│   ├── 2024_wimp_capture/
│   └── 2023_solar_dm/
├── Astro/
├── Gamma-Ray/
└── Uncategorized/
```

但注意一个问题：如果真的把论文目录移动到不同子文件夹，路径会变。  
所以需要让 `Paper` 支持相对路径，而不是假设所有论文都在 `raw/papers/{paper-id}/` 这一层。

建议新增字段：

```yaml
collection_path: "Dark-Matter/2024_wimp_capture"
```

论文目录变为：

```text
raw/papers/Dark-Matter/2024_wimp_capture/{paper-id}/
├── paper.pdf
├── paper.md
├── meta.yaml
├── annotations.md
└── figures/
```

对应 `Paper` 增加：

```swift
var collectionPath: String?
var paperDirectoryRelativePath: String
```

左侧文件夹树扫描：

```text
raw/papers/
```

所有非论文目录都是 collection，包含 `meta.yaml` 的目录是 paper item。

---

## 2.2 彩色文字标签

当前项目已有 tags 字段和按标签搜索能力 [1][2]，但缺少标签颜色和标签管理中心。

建议新增全局文件：

```text
refs/tags.yaml
```

示例：

```yaml
tags:
  - name: Theory
    color: "#B57EDC"
    textColor: "#4A235A"
  - name: WIMPs
    color: "#D7BDE2"
    textColor: "#512E5F"
  - name: Experiment
    color: "#85C1E9"
    textColor: "#154360"
  - name: Simulation
    color: "#F7DC6F"
    textColor: "#7D6608"
```

`meta.yaml` 中仍然只保存标签名：

```yaml
tags:
  - Theory
  - WIMPs
```

这样好处是：

```text
标签定义在 refs/tags.yaml
论文只引用标签名
颜色修改一次，全局生效
```

新增模块：

```text
Tags/
├── TagDefinition.swift
├── TagRepository.swift
├── TagColor.swift
├── TagChipView.swift
└── TagManagerView.swift
```

UI 上实现类似你截图中的紫色标签：

```text
[Theory] [WIMPs]
```

---

## 2.3 读取 Link 的能力

你希望像图 2 一样输入：

```text
ISBN、DOI、PMID、arXiv ID、ADS 条码
```

你还特别提到 arXiv 和 INSPIRE。对你的方向，建议第一版支持：

```text
arXiv ID
DOI
INSPIRE literature URL / record ID
普通 URL
PDF URL
```

新增入口：

```text
Add by Identifier or Link
```

弹窗：

```text
输入 DOI、arXiv ID、INSPIRE URL、PDF URL 或普通网页链接
[输入框]
[识别类型] [导入]
```

识别规则：

```text
arXiv: 2401.12345 / arXiv:2401.12345 / https://arxiv.org/abs/2401.12345
DOI: 10.xxxx/xxxxx / https://doi.org/...
INSPIRE: https://inspirehep.net/literature/xxxx
PDF URL: 以 .pdf 结尾或 Content-Type application/pdf
普通 URL: 保存为 link item，后续再补 metadata
```

---

## 2.4 arXiv API 导入

arXiv API 可以返回：

```text
title
authors
abstract
published date
updated date
categories
doi
journal_ref
pdf link
abs link
```

pipeline：

```text
用户输入 arXiv ID
  ↓
ArxivIdentifierParser 识别 ID
  ↓
ArxivMetadataProvider 请求 arXiv API
  ↓
生成 PaperMetadataDraft
  ↓
下载 PDF
  ↓
创建 paper 目录
  ↓
写 meta.yaml
  ↓
写 paper.md 占位或初步文本
  ↓
写 wiki/papers 模板
  ↓
刷新 Library
```

建议 `meta.yaml` 增加：

```yaml
source_provider: arxiv
arxiv: "2401.12345"
abstract: "..."
categories:
  - hep-ph
  - astro-ph.CO
published: 2024-01-01
updated: 2024-02-01
pdf_url: "https://arxiv.org/pdf/2401.12345"
abs_url: "https://arxiv.org/abs/2401.12345"
```

---

## 2.5 INSPIRE API 导入

INSPIRE HEP API 适合高能物理、天体物理相关论文。

INSPIRE 常见 API：

```text
https://inspirehep.net/api/literature?q=...
https://inspirehep.net/api/literature/{record_id}
```

可以获取：

```text
title
authors
abstract
doi
arxiv_eprints
publication_info
collaborations
citation_count
urls
documents
```

pipeline：

```text
用户输入 INSPIRE URL / record id / query
  ↓
InspireIdentifierParser 识别
  ↓
InspireMetadataProvider 请求 API
  ↓
解析 JSON 为 PaperMetadataDraft
  ↓
如果有 arXiv ID，优先通过 arXiv 下载 PDF
  ↓
否则如果 documents 中有 PDF URL，下载 PDF
  ↓
否则创建 link-only paper
  ↓
写入 meta.yaml
```

---

## 3. 只需要 API 接口，不需要本地模型

你说：

> 我大概不会用本地的模型，因此只需要加上 API 接口的能力就好。

这意味着下一阶段 LLM 模块可以简化。

不需要：

```text
OllamaProvider
本地模型管理
本地 embedding
```

只做：

```text
OpenAICompatibleProvider
AnthropicProvider，可选
GeminiProvider，可选
```

最推荐第一版只做：

```text
OpenAI-compatible API
```

原因是它可以兼容很多服务：

```text
OpenAI
OpenRouter
SiliconFlow
DeepSeek-compatible endpoint
LM Studio server，如果以后要
vLLM server
```

新增配置：

```text
Provider Name
Base URL
API Key
Model
Temperature
Max Tokens
```

API Key 存 Keychain，普通设置文件只存：

```yaml
llm:
  provider: openai-compatible
  base_url: "https://api.openai.com/v1"
  model: "gpt-4o-mini"
  temperature: 0.2
```

不存：

```text
api_key
```

---

## 4. 工作台日历功能

你说：

> 既然是工作台，就需要一个日历功能，可以找一个优秀的开源组件，放到主界面。

这里我建议优先用 **SwiftUI 自己实现最小月历/周历**，不要一开始依赖复杂开源组件。原因：

1. macOS SwiftUI 开源日历组件质量参差不齐；
2. 很多是 iOS 优先；
3. 你的第一版需求只是工作台入口，不是完整日程系统；
4. 自己实现一个小日历并不复杂。

如果坚持开源组件，可让 AI 调研：

```text
HorizonCalendar
CalendarKit
KVKCalendar
ElegantCalendar
```

但它们很多偏 iOS/UIKit，不一定适合 macOS SwiftUI。

我建议第一版实现：

```text
DashboardCalendarView
```

功能：

```text
月视图
今天高亮
点击日期
显示当日 Todo
显示当日阅读计划
显示论文 deadline 或自定义事件
```

数据文件：

```text
workspace/tasks/calendar.yaml
```

或者更统一：

```text
workspace/tasks/tasks.yaml
```

---

## 5. Todo 功能

你的要求是：

> todo 功能，简单一点就好，放到主界面。

建议新增：

```text
tasks/todos.yaml
```

示例：

```yaml
todos:
  - id: "todo-20260427-001"
    title: "阅读 Dark Matter capture 综述"
    status: open
    due: 2026-04-28
    tags:
      - Dark-Matter
    related_papers:
      - garani2024dark
    created: 2026-04-27
    updated: 2026-04-27
```

Swift 数据结构：

```swift
struct TodoItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var status: TodoStatus
    var dueDate: Date?
    var tags: [String]
    var relatedPaperIDs: [String]
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

enum TodoStatus: String, Codable, CaseIterable {
    case open
    case inProgress
    case done
    case cancelled
}
```

主界面 Dashboard：

```text
Today
├── Calendar
├── Todo
├── Recently Added Papers
├── Recently Read Papers
└── Quick Add by DOI / arXiv / INSPIRE / URL
```

---

# 三、建议的新信息架构

你现在的应用可以从“Library/Wiki 为中心”升级为“Workbench 为中心”。

推荐侧边栏：

```text
Dashboard
Library
  All Papers
  Recent Added
  Recently Read
  Unfiled
  Trash
Collections
  Dark-Matter
    2024_Gamma
    Solar Capture
  Astro
  GR
Tags
  Theory
  WIMPs
  Experiment
  Simulation
Feeds / Import
  arXiv
  INSPIRE
Wiki
  Papers
  Concepts
  Gaps
Tasks
Settings
```

中间区域根据选择变化：

```text
Dashboard:
  Calendar + Todo + Recent Papers

Library/Collection/Tag:
  Paper Table

Paper selected:
  Paper Detail / PDF Reader / Metadata

Wiki:
  Markdown List + Markdown Editor
```

右侧 Inspector：

```text
Paper Metadata
Tags
Collections
PDF
Notes
LLM
Todo related to this paper
```

---

# 四、建议文件结构升级

当前工作区结构已经包含 `raw/`、`wiki/`、`refs/` 等 [2]。建议新增：

```text
ResearchWorkspace/
├── raw/
│   └── papers/
│       ├── Dark-Matter/
│       │   └── garani2024dark/
│       │       ├── paper.pdf
│       │       ├── paper.md
│       │       ├── meta.yaml
│       │       ├── annotations.md
│       │       └── figures/
│       └── Uncategorized/
├── refs/
│   ├── library.bib
│   ├── tags.yaml
│   └── csl/
├── tasks/
│   ├── todos.yaml
│   └── calendar.yaml
├── imports/
│   ├── import_history.yaml
│   └── failed_imports.yaml
├── wiki/
└── settings.yaml
```

建议新增目录：

```text
tasks/
imports/
```

---

# 五、核心数据模型建议

## 5.1 Paper 增强

```swift
struct Paper: Identifiable, Codable, Hashable {
    var id: String
    var citekey: String
    var title: String
    var authors: [String]
    var year: Int?
    var venue: String?
    var doi: String?
    var arxiv: String?
    var inspireID: String?
    var url: String?
    var pdfURL: String?
    var abstract: String?
    var categories: [String]

    var collectionPath: String?
    var paperDirectoryRelativePath: String
    var pdfRelativePath: String?

    var tags: [String]
    var status: ReadingStatus
    var priority: Priority
    var rating: Int?
    var useFor: [String]

    var createdAt: Date
    var updatedAt: Date
    var lastReadAt: Date?
}
```

---

## 5.2 Collection

```swift
struct PaperCollection: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var relativePath: String
    var parentPath: String?
    var paperCount: Int
}
```

---

## 5.3 Tag

```swift
struct TagDefinition: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var colorHex: String
    var textColorHex: String?
}
```

---

## 5.4 Link Import Draft

```swift
struct PaperMetadataDraft: Codable, Hashable {
    var title: String
    var authors: [String]
    var year: Int?
    var venue: String?
    var doi: String?
    var arxiv: String?
    var inspireID: String?
    var url: String?
    var pdfURL: String?
    var abstract: String?
    var categories: [String]
    var sourceProvider: String
}
```

---

## 5.5 LLM Config

```swift
struct LLMConfiguration: Codable, Hashable {
    var provider: LLMProviderKind
    var baseURL: URL
    var model: String
    var temperature: Double
    var maxTokens: Int?
}

enum LLMProviderKind: String, Codable, CaseIterable {
    case openAICompatible
}
```

---

# 六、基本 Pipeline 设计

---

## Pipeline 1：本地 PDF 导入

```text
用户拖入 PDF 或点击 Import PDF
  ↓
选择目标 Collection，默认 Uncategorized
  ↓
PDFKit 读取基础 metadata
  ↓
生成 PaperMetadataDraft
  ↓
生成 citekey 和 paper-id
  ↓
创建 raw/papers/{collectionPath}/{paper-id}/
  ↓
复制 paper.pdf
  ↓
生成 paper.md、meta.yaml、annotations.md、figures/
  ↓
追加 refs/library.bib stub
  ↓
生成或预留 wiki/papers/{citekey}.md
  ↓
刷新 Library Table
```

---

## Pipeline 2：通过 arXiv ID 导入

```text
用户点击 Add by Identifier
  ↓
输入 arXiv:2401.12345 或 arxiv.org/abs/2401.12345
  ↓
IdentifierParser 识别为 arXiv
  ↓
ArxivMetadataProvider 请求 arXiv API
  ↓
解析 title/authors/abstract/categories/doi/journal_ref/pdf_url
  ↓
展示 Import Preview
  ↓
用户选择 Collection 和 Tags
  ↓
DownloadService 下载 PDF
  ↓
创建论文目录和 meta.yaml
  ↓
生成 wiki/papers 模板
  ↓
刷新 Library
```

---

## Pipeline 3：通过 INSPIRE 导入

```text
用户输入 INSPIRE URL / record id / query
  ↓
IdentifierParser 识别为 INSPIRE
  ↓
InspireMetadataProvider 请求 INSPIRE API
  ↓
解析 metadata
  ↓
如果有 arXiv ID：
      调用 arXiv PDF URL 下载
   否则如果有 document PDF：
      下载 document PDF
   否则：
      创建 link-only paper
  ↓
展示 Import Preview
  ↓
用户确认
  ↓
写入 raw/papers/{collection}/{paper-id}/
  ↓
写 meta.yaml
  ↓
刷新 Library
```

---

## Pipeline 4：通过普通 Link 导入

```text
用户输入 URL
  ↓
URLImportService 判断类型
  ↓
如果是 PDF URL：
      下载 PDF，走本地 PDF 导入流程
   如果是 arXiv URL：
      走 arXiv pipeline
   如果是 INSPIRE URL：
      走 INSPIRE pipeline
   如果是 DOI URL：
      走 DOI metadata pipeline
   否则：
      创建 link-only paper/item
  ↓
保存 url 到 meta.yaml
  ↓
如果无法下载 PDF，pdfRelativePath 为空
  ↓
Library 中显示 Link-only 标记
```

---

## Pipeline 5：内嵌 PDF 阅读

```text
用户选中 Paper
  ↓
如果存在 paper.pdf：
      EmbeddedPDFReaderView 加载 PDFDocument
   否则如果存在 pdfURL：
      显示 Download PDF 按钮
   否则：
      显示 No PDF available
  ↓
用户阅读、搜索、跳页
  ↓
记录 lastReadAt 和 lastPage
  ↓
写回 meta.yaml reading.last_page / reading.last_read_at
```

---

## Pipeline 6：云端 API LLM 总结

```text
用户选中 Paper
  ↓
点击 Summarize with LLM
  ↓
读取 meta.yaml、paper.md、annotations.md、已有 wiki page
  ↓
如果 paper.md 内容不足：
      尝试从 PDFKit 抽取文本
      或提示用户确认继续
  ↓
构造 Prompt
  ↓
调用 OpenAI-compatible API
  ↓
显示生成结果预览
  ↓
用户选择 Replace / Append / Save Draft
  ↓
写回 wiki/papers/{citekey}.md
  ↓
更新 meta.yaml status = summarized
```

---

## Pipeline 7：Todo 与日历

```text
用户在 Dashboard 添加 Todo
  ↓
选择 due date、tags、related paper
  ↓
写入 tasks/todos.yaml
  ↓
CalendarView 根据 due date 聚合任务
  ↓
点击日期显示当日任务
  ↓
完成任务后更新 status = done
```

---

# 七、系统性任务书

下面是可以直接交给 AI 编程助手的任务书。

---

# Sci-Station 下一阶段任务书：Zotero 风格科研工作台升级

## 1. 阶段目标

请继续开发 Sci-Station。本阶段目标是将当前的最小 Markdown 知识库原型，升级为一个更接近 Zotero 风格的 macOS 科研工作台。

当前项目已经完成：

1. 工作区创建、打开和最近工作区恢复。
2. 工作区结构补齐，包括 `refs/csl` 和 `researchflow.sqlite` 占位。
3. PDF 导入后生成 `paper.pdf`、`paper.md`、`meta.yaml`、`annotations.md`、`figures/`。
4. `WikiPageGenerator`，可生成 `wiki/papers/{citekey}.md`。
5. Markdown 页面扫描、打开、编辑、保存。
6. YAML frontmatter、`[[wikilink]]` 和 backlinks 解析。
7. Library 表格、Paper Inspector、Wiki 页面最小可用 UI。
8. 系统默认 PDF 打开能力。

本阶段新增目标：

1. 实现内嵌 PDF 阅读器。
2. 实现 Zotero 风格左侧文件夹分类。
3. 实现自定义彩色文字标签。
4. 实现通过 arXiv / INSPIRE / URL 导入论文和元数据。
5. 实现云端 API LLM 接口，不需要本地模型。
6. 实现 Dashboard 日历和简单 Todo。
7. 保持文件系统优先，不把核心数据锁进数据库。

---

## 2. 总体 UI 目标

请将主界面逐步调整为三栏科研工作台：

```text
左侧 Sidebar:
- Dashboard
- Library
  - All Papers
  - Recent Added
  - Recently Read
  - Unfiled
- Collections
  - 用户自定义文件夹树
- Tags
  - 彩色标签列表
- Import
  - Add by Identifier / Link
- Wiki
- Tasks
- Settings

中间 Content:
- Dashboard 时显示 Calendar + Todo + Recent Papers
- Library/Collection/Tag 时显示 Paper Table
- Wiki 时显示 Markdown 列表和编辑器

右侧 Inspector:
- Paper Metadata
- Embedded PDF Reader
- Tags
- Collection
- LLM Actions
- Related Todo
```

风格参考 Zotero：左侧分类，中间论文列表，右侧 PDF / 元数据 / 笔记，不需要完全复制 Zotero。

---

## 3. 工作区结构升级

请在 Workspace 初始化和旧工作区补齐逻辑中新增：

```text
tasks/
├── todos.yaml
└── calendar.yaml

imports/
├── import_history.yaml
└── failed_imports.yaml

refs/
├── tags.yaml
```

完整结构应支持：

```text
ResearchWorkspace/
├── inbox/
├── raw/
│   ├── papers/
│   ├── web/
│   └── books/
├── wiki/
├── refs/
│   ├── csl/
│   ├── library.bib
│   └── tags.yaml
├── tasks/
│   ├── todos.yaml
│   └── calendar.yaml
├── imports/
│   ├── import_history.yaml
│   └── failed_imports.yaml
├── prompts/
├── scripts/
├── code/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

---

## 4. 子文件夹分类 Collections

### 4.1 目标

实现左侧 Collections 文件夹树。分类直接对应 `raw/papers/` 下的子文件夹。

例如：

```text
raw/papers/
├── Dark-Matter/
│   ├── Solar-Capture/
│   │   └── garani2024dark/
│   └── WIMPs/
├── Astro/
└── Uncategorized/
```

### 4.2 要求

1. 支持创建 Collection 文件夹。
2. 支持重命名 Collection。
3. 支持删除空 Collection。
4. 支持将 Paper 移动到 Collection。
5. 支持按 Collection 筛选论文列表。
6. 支持导入 PDF 或 API 论文时选择 Collection。
7. 移动论文后必须更新 `meta.yaml` 中的路径字段。

### 4.3 数据模型

新增：

```swift
struct PaperCollection: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var relativePath: String
    var parentPath: String?
    var paperCount: Int
}
```

更新 `Paper`：

```swift
var collectionPath: String?
var paperDirectoryRelativePath: String
```

### 4.4 模块建议

```text
Collections/
├── PaperCollection.swift
├── CollectionRepository.swift
├── CollectionTreeBuilder.swift
├── CollectionSidebarView.swift
└── MovePaperToCollectionService.swift
```

---

## 5. 彩色标签 Tags

### 5.1 目标

实现类似 Zotero 的彩色标签。论文列表中以彩色 chip 显示标签，左侧标签区可筛选。

### 5.2 文件格式

新增：

```text
refs/tags.yaml
```

示例：

```yaml
tags:
  - name: Theory
    color: "#B57EDC"
    textColor: "#4A235A"
  - name: WIMPs
    color: "#D7BDE2"
    textColor: "#512E5F"
  - name: Experiment
    color: "#85C1E9"
    textColor: "#154360"
```

论文 `meta.yaml` 中仍然只保存标签名：

```yaml
tags:
  - Theory
  - WIMPs
```

### 5.3 要求

1. 支持创建标签。
2. 支持编辑标签颜色。
3. 支持删除标签定义。
4. 支持给 Paper 添加/删除标签。
5. 支持按标签筛选论文。
6. 支持 Paper Table 中彩色显示标签。

### 5.4 模块建议

```text
Tags/
├── TagDefinition.swift
├── TagRepository.swift
├── TagManagerView.swift
├── TagChipView.swift
└── TagFilterView.swift
```

---

## 6. 内嵌 PDF 阅读器

### 6.1 目标

在应用中内嵌一个基本 PDF 阅读器，同时保留系统默认打开 PDF 的能力。

### 6.2 要求

1. 使用 `PDFKit` 实现内嵌 PDF 阅读。
2. 支持加载选中论文的 `paper.pdf`。
3. 支持页码显示。
4. 支持上一页、下一页。
5. 支持跳转页码。
6. 支持缩放。
7. 支持文本搜索。
8. 支持记录阅读进度。
9. 支持按钮“Open in Default Viewer”。

### 6.3 阅读状态

在 `meta.yaml` 中新增：

```yaml
reading:
  last_page: 12
  last_read_at: 2026-04-27
```

### 6.4 模块建议

```text
PDF/
├── PDFOpeningService.swift
├── SystemPDFOpeningService.swift
├── EmbeddedPDFReaderView.swift
├── PDFReaderViewModel.swift
├── PDFDocumentService.swift
└── PDFReadingStateService.swift
```

---

## 7. Identifier / Link 导入

### 7.1 目标

实现类似 Zotero 的“通过标识符添加论文”功能。

用户可以输入：

```text
arXiv ID
arXiv URL
DOI
INSPIRE URL
INSPIRE record id
PDF URL
普通 URL
```

### 7.2 UI

新增弹窗：

```text
Add by Identifier or Link

输入 DOI、arXiv ID、INSPIRE URL、PDF URL 或普通网页链接:
[                                               ]

Collection: [选择文件夹]
Tags:       [可选标签]

[Preview Metadata] [Import]
```

### 7.3 识别类型

新增：

```swift
enum ImportIdentifierKind: String, Codable {
    case arxiv
    case doi
    case inspire
    case pdfURL
    case url
    case unknown
}
```

### 7.4 模块建议

```text
Import/
├── IdentifierParser.swift
├── IdentifierImportView.swift
├── ImportPreviewView.swift
├── PaperMetadataDraft.swift
├── RemoteImportService.swift
├── DownloadService.swift
└── LinkOnlyImportService.swift
```

---

## 8. arXiv 导入

### 8.1 目标

通过 arXiv ID 或 URL 获取元数据和 PDF。

### 8.2 Pipeline

```text
用户输入 arXiv ID / URL
  ↓
IdentifierParser 识别 arXiv ID
  ↓
ArxivMetadataProvider 请求 arXiv API
  ↓
解析 title/authors/abstract/categories/doi/journal_ref/pdf_url
  ↓
显示 Import Preview
  ↓
用户确认 Collection 和 Tags
  ↓
DownloadService 下载 PDF
  ↓
创建论文目录
  ↓
写 meta.yaml
  ↓
生成 paper.md / annotations.md / figures/
  ↓
生成 wiki/papers 模板或预留路径
  ↓
刷新 Library
```

### 8.3 模块建议

```text
MetadataProviders/
├── ArxivMetadataProvider.swift
├── ArxivEntryParser.swift
└── ArxivAPIModels.swift
```

### 8.4 meta.yaml 增加字段

```yaml
source_provider: arxiv
arxiv: "2401.12345"
abstract: "..."
categories:
  - hep-ph
published: 2024-01-01
updated: 2024-02-01
pdf_url: "https://arxiv.org/pdf/2401.12345"
abs_url: "https://arxiv.org/abs/2401.12345"
```

---

## 9. INSPIRE 导入

### 9.1 目标

通过 INSPIRE HEP API 获取高能物理/天文相关论文元数据。

### 9.2 Pipeline

```text
用户输入 INSPIRE URL / record id
  ↓
IdentifierParser 识别 INSPIRE
  ↓
InspireMetadataProvider 请求 INSPIRE API
  ↓
解析 title/authors/abstract/doi/arxiv_eprints/publication_info/citation_count/documents
  ↓
如果有 arXiv ID:
      通过 arXiv PDF 下载
   否则如果 documents 中有 PDF:
      下载 PDF
   否则:
      创建 link-only item
  ↓
显示 Import Preview
  ↓
用户确认
  ↓
写入 paper 目录和 meta.yaml
  ↓
刷新 Library
```

### 9.3 模块建议

```text
MetadataProviders/
├── InspireMetadataProvider.swift
├── InspireAPIModels.swift
└── InspireMetadataMapper.swift
```

### 9.4 meta.yaml 增加字段

```yaml
source_provider: inspire
inspire_id: "..."
citation_count: 123
collaborations:
  - "..."
```

---

## 10. 云端 API LLM

### 10.1 目标

只实现 API 型 LLM，不实现本地 Ollama。

### 10.2 Provider

第一版只做：

```text
OpenAI-compatible API
```

### 10.3 配置

新增设置页：

```text
LLM Settings
Provider: OpenAI-compatible
Base URL
Model
API Key
Temperature
Max Tokens
Test Connection
```

API Key 必须通过 Keychain 保存，不能写入普通文件。

### 10.4 模块建议

```text
LLM/
├── LLMProvider.swift
├── LLMModels.swift
├── LLMError.swift
├── LLMConfiguration.swift
├── OpenAICompatibleProvider.swift
├── APIKeyStore.swift
├── KeychainAPIKeyStore.swift
├── PaperSummaryPromptBuilder.swift
├── PaperSummaryService.swift
└── LLMWritebackService.swift
```

### 10.5 Summarize Pipeline

```text
用户选中 Paper
  ↓
点击 Summarize with LLM
  ↓
读取 meta.yaml、paper.md、annotations.md、已有 wiki page
  ↓
如果 paper.md 内容不足，尝试 PDFKit 文本抽取或提示用户
  ↓
构造 Prompt
  ↓
调用 OpenAI-compatible API
  ↓
显示生成结果预览
  ↓
用户选择 Replace / Append / Save Draft
  ↓
写回 wiki/papers/{citekey}.md
  ↓
更新 meta.yaml status = summarized
```

---

## 11. Dashboard、日历与 Todo

### 11.1 目标

新增 Dashboard 主界面，放置日历、Todo、最近论文和快速导入。

### 11.2 Dashboard 布局

```text
Dashboard
├── 顶部 Quick Import
│   └── DOI / arXiv / INSPIRE / URL 输入框
├── 左侧 Calendar
├── 右侧 Today Todo
├── 下方 Recently Added Papers
└── 下方 Recently Read Papers
```

### 11.3 Todo 文件

新增：

```text
tasks/todos.yaml
```

示例：

```yaml
todos:
  - id: "todo-20260427-001"
    title: "阅读 Dark Matter capture 综述"
    status: open
    due: 2026-04-28
    tags:
      - Dark-Matter
    related_papers:
      - garani2024dark
    created: 2026-04-27
    updated: 2026-04-27
```

### 11.4 Todo 模块

```text
Tasks/
├── TodoItem.swift
├── TodoRepository.swift
├── TodoListView.swift
├── TodoEditorView.swift
└── TodoDashboardWidget.swift
```

### 11.5 Calendar 模块

第一版请优先用 SwiftUI 自实现简单月历，不要强依赖复杂第三方库。若确需第三方库，请先给出可用性评估。

```text
Calendar/
├── CalendarEvent.swift
├── CalendarRepository.swift
├── DashboardCalendarView.swift
└── CalendarDayCellView.swift
```

日历第一版只需要：

1. 显示月视图。
2. 高亮今天。
3. 点击某天。
4. 显示当天 Todo。
5. 显示任务数量标记。

---

## 12. 开发顺序

请按以下顺序开发，避免一次性改太多导致不可控。

### Step 1：工作区结构升级

- 新增 `tasks/`
- 新增 `imports/`
- 新增 `refs/tags.yaml`
- 更新 Workspace 初始化和旧工作区补齐逻辑
- 增加测试

### Step 2：Collections 子文件夹分类

- 扫描 `raw/papers/` 下的文件夹树
- 识别 Collection 和 Paper item
- 左侧显示 Collection 树
- 导入 PDF 时选择 Collection
- 支持移动 Paper 到 Collection

### Step 3：彩色标签

- 新增 `refs/tags.yaml`
- 新增 TagRepository
- 新增 TagChipView
- Paper Table 显示彩色标签
- 支持按标签筛选

### Step 4：内嵌 PDF 阅读器

- 使用 PDFKit 实现 EmbeddedPDFReaderView
- 选中 Paper 时加载 PDF
- 支持页码、跳页、缩放、搜索
- 保留 Open in Default Viewer

### Step 5：Identifier / Link 导入

- 新增 IdentifierParser
- 新增 Add by Identifier 弹窗
- 实现 arXiv 导入
- 实现 INSPIRE 导入
- 实现 PDF URL / 普通 URL 导入
- 显示 Import Preview

### Step 6：云端 API LLM

- 实现 OpenAICompatibleProvider
- 实现 Keychain API Key 存储
- 实现 PaperSummaryPromptBuilder
- 实现 Summarize with LLM
- 预览确认后写回 wiki

### Step 7：Dashboard、日历、Todo

- 新增 Dashboard
- 新增 TodoRepository
- 新增简单 Calendar View
- Dashboard 显示 Todo、日历、最近论文、快速导入

---

## 13. 验收标准

本阶段完成后，应能做到：

1. 左侧可以看到 Zotero 风格的分类文件夹。
2. 可以创建、重命名、删除 Collection。
3. 可以把论文移动到 Collection。
4. 可以创建彩色标签并给论文打标签。
5. Paper Table 可以显示彩色标签 chip。
6. 可以输入 arXiv ID 导入论文、元数据和 PDF。
7. 可以输入 INSPIRE URL 或 ID 导入元数据。
8. 可以输入 PDF URL 下载并入库。
9. 可以输入普通 URL 创建 link-only paper。
10. 选中论文后能在 App 内嵌阅读 PDF。
11. 可以用系统默认预览打开 PDF。
12. 可以配置 OpenAI-compatible API。
13. 可以对论文执行 Summarize with LLM。
14. LLM 结果必须预览确认后写回 wiki。
15. Dashboard 显示日历和 Todo。
16. Todo 可以新增、完成、删除。
17. 所有核心数据仍可在文件系统中直接查看和编辑。

---

## 14. 测试要求

至少补以下测试：

```text
WorkspaceStructureTests
- tasks/ 是否创建
- imports/ 是否创建
- refs/tags.yaml 是否创建

CollectionRepositoryTests
- 扫描 Collection 树
- 创建 Collection
- 移动 Paper 后路径和 meta.yaml 是否更新

TagRepositoryTests
- tags.yaml 读写
- 标签颜色解析
- Paper 标签保存回 meta.yaml

IdentifierParserTests
- arXiv ID
- arXiv URL
- DOI
- INSPIRE URL
- PDF URL
- 普通 URL

ArxivMetadataProviderTests
- 使用 mock response 测试解析

InspireMetadataProviderTests
- 使用 mock response 测试解析

EmbeddedPDFReaderTests
- PDF 文件存在时能加载
- PDF 缺失时显示错误状态

LLMProviderTests
- OpenAI-compatible request 构造正确
- API Key 不写入普通配置

TodoRepositoryTests
- todos.yaml 读写
- 创建、完成、删除 Todo
```

---

# 八、最终建议

我建议你把下一阶段的优先级稍微调整为：

```text
1. Zotero 风格 Library 工作台
2. Collections + 彩色 Tags
3. 内嵌 PDF 阅读器
4. arXiv / INSPIRE / URL 导入
5. OpenAI-compatible LLM
6. Dashboard + Calendar + Todo
```

原因是：你现在真正想要的不是单纯的 LLM 工具，而是一个**日常可用的科研文库工作台**。LLM 是其中一个强功能，但它应该建立在稳定的论文管理、分类、标签、导入和阅读体验之上。