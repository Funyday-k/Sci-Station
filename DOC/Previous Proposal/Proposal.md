下面是一份可以直接交给 AI 编程 Agent 的 **macOS Swift 科研工作站程序编写报告 / 开发任务书**。  
它的目标是让 AI 根据这份说明，用 **Swift / SwiftUI** 编写一个本地优先、文件系统优先、Markdown 优先、LLM 可接入的科研工作站程序。

---

# macOS Swift 科研工作站程序编写报告

## 1. 项目名称

暂定名：

```text
Sci-Station
```


一句话定位：

> 一个基于 macOS、SwiftUI、Markdown、PDF、BibTeX、YAML 和 LLM 的本地优先科研工作站，用来替代 Obsidian + Zotero 的部分工作流，并与 VSCode / VSCodium 形成协作。

---

# 2. 产品目标

本程序的核心目标是构建一个面向科研人员的 macOS 原生应用，完成以下任务：

1. 管理论文 PDF、Markdown、BibTeX、标签、阅读状态和研究项目。
2. 使用开放文件结构存储所有数据，不把知识锁死在私有数据库中。
3. 支持外部开源 PDF 阅读器，例如 Sioyek、Skim，也可以提供内置 PDF 预览。
4. 支持 Markdown 知识库，包括双链、反链、标签、图谱。
5. 接入本地或云端 LLM，用于：
   - 阅读论文；
   - 总结论文；
   - 生成 Markdown 知识页；
   - 发现研究空白；
   - 编写文档；
   - 辅助代码开发；
   - 整理跨论文概念。
6. 与 VSCode / VSCodium 集成，用于代码、Markdown、Prompt、论文写作的高级编辑。
7. 尽量使用开源组件，保持数据可迁移、可版本控制、可长期保存。

---

# 3. 非目标

第一版不要实现过度复杂的功能。

第一版不需要：

1. 不需要实现完整 Zotero 级别的在线文献数据库。
2. 不需要实现完整 Obsidian 插件生态。
3. 不需要自己开发复杂 PDF 渲染引擎。
4. 不需要实现多人实时协作。
5. 不需要把所有 LLM API 都一次性接完。
6. 不需要一开始就实现 App Store 沙盒发布。

第一版重点是：

```text
本地工作区
论文入库
PDF 打开
标签管理
Markdown 知识库
LLM 总结
VSCode/VSCodium 联动
```

---

# 4. 技术栈要求

## 4.1 开发语言和框架

必须使用：

```text
Swift
SwiftUI
macOS 14+
Xcode 15+
Swift Concurrency
```

推荐使用：

```text
MVVM 架构
Service Layer
Repository Pattern
actor 管理并发任务
```

---

## 4.2 推荐依赖

可以通过 Swift Package Manager 引入以下库。

```text
MarkdownUI          Markdown 渲染
swift-markdown      Markdown 解析
Yams                YAML frontmatter 解析
GRDB.swift          SQLite 数据库和 FTS5 全文搜索
```

可选：

```text
Highlightr          代码高亮
Plot / Swift Charts 图表或统计
```

系统框架：

```text
PDFKit              内置 PDF 预览与注释读取
UniformTypeIdentifiers
FileProvider / FileManager
Combine
Security
AppKit
WebKit，可选
```

说明：

- 如果用户要求严格开源 PDF 阅读器，则主流程应优先调用外部 Sioyek / Skim。
- 内置 PDFKit 只作为快速预览器。
- PDF 相关代码必须通过协议抽象，方便未来替换为 MuPDF 或 PDFium。

---

# 5. 核心设计原则

## 5.1 文件系统优先

所有核心数据必须存储在用户可见的文件夹中，而不是只存在数据库里。

数据库只能作为缓存和索引，必须可以从文件重新生成。

工作区结构如下：

```text
ResearchWorkspace/
├── inbox/
├── raw/
│   ├── papers/
│   │   └── smith2024-graph-rag/
│   │       ├── paper.pdf
│   │       ├── paper.md
│   │       ├── meta.yaml
│   │       ├── annotations.md
│   │       └── figures/
│   ├── web/
│   └── books/
├── wiki/
│   ├── papers/
│   ├── concepts/
│   ├── methods/
│   ├── datasets/
│   ├── authors/
│   ├── gaps/
│   └── projects/
├── refs/
│   ├── library.bib
│   └── csl/
├── prompts/
├── scripts/
├── code/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

其中：

```text
raw/     保存原始资料，只增不改
wiki/    保存 LLM 或用户整理后的知识库
refs/    保存 BibTeX 和引用样式
prompts/ 保存 LLM 提示词模板
code/    保存实验代码
outputs/ 保存论文、报告、导出文档
```

---

## 5.2 Markdown 优先

所有知识页必须使用 Markdown，并支持 YAML frontmatter。

论文知识页示例：

```markdown
---
type: paper
id: smith2024graph
citekey: smith2024graph
title: "Graph-based Retrieval Augmented Generation"
year: 2024
authors:
  - John Smith
  - Alice Wang
tags:
  - rag
  - graph-rag
  - llm
status: summarized
priority: high
source_pdf: ../../raw/papers/smith2024-graph-rag/paper.pdf
created: 2026-04-27
updated: 2026-04-27
---

# Graph-based Retrieval Augmented Generation

## TL;DR

……

## 研究问题

……

## 方法

……

## 关键贡献

……

## 局限性

……

## 与其他论文关系

- [[Retrieval Augmented Generation]]
- [[Knowledge Graph]]
- [[Vector RAG]]

## 可能研究空白

- [[gap-graph-rag-evaluation]]

## 引用

[@smith2024graph]
```

---

## 5.3 标签和元数据开放化

每篇论文必须有一个 `meta.yaml` 文件。

示例：

```yaml
id: smith2024-graph-rag
citekey: smith2024graph
title: "Graph-based Retrieval Augmented Generation"
authors:
  - "John Smith"
  - "Alice Wang"
year: 2024
venue: "arXiv"
doi:
arxiv: "2401.12345"
url: "https://arxiv.org/abs/2401.12345"
pdf: "paper.pdf"

tags:
  - rag
  - graph-rag
  - knowledge-graph
  - llm

status: unread
priority: high
rating: 4

use_for:
  - related-work
  - method-design

reading:
  added: 2026-04-27
  first_read:
  deep_read:

links:
  semantic_scholar:
  github:
  project_page:

notes:
  summary_file: "../../../wiki/papers/smith2024graph.md"
```

标签、阅读状态、优先级、评分都必须可以在程序 UI 中编辑，并写回 `meta.yaml`。

---

# 6. 应用模块划分

程序应分为以下模块。

```text
ResearchFlowApp
├── App
├── Core
├── Workspace
├── Library
├── PDF
├── Markdown
├── LLM
├── Graph
├── Search
├── Importer
├── Exporter
├── Integrations
├── Settings
└── Tests
```

---

## 6.1 App 模块

负责：

1. 程序入口。
2. 主窗口。
3. 菜单栏。
4. 全局状态。
5. 打开最近工作区。
6. 创建新工作区。

主界面布局：

```text
左侧 Sidebar
中间列表 / 图谱 / 编辑区
右侧 Inspector / LLM Panel
```

---

## 6.2 Workspace 模块

负责：

1. 创建工作区。
2. 打开工作区。
3. 验证目录结构。
4. 初始化必要文件夹。
5. 管理安全书签。
6. 监听文件变化。
7. 重建索引数据库。

核心对象：

```swift
struct Workspace {
    let rootURL: URL
    let rawURL: URL
    let wikiURL: URL
    let refsURL: URL
    let promptsURL: URL
    let codeURL: URL
    let outputsURL: URL
}
```

---

## 6.3 Library 模块

负责论文库管理。

功能：

1. 展示所有论文。
2. 按标签筛选。
3. 按状态筛选。
4. 按年份筛选。
5. 按项目筛选。
6. 支持全文搜索。
7. 支持导入 PDF。
8. 支持编辑元数据。
9. 支持生成 citekey。
10. 支持写入 `library.bib`。

核心数据结构：

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
    var url: String?
    var pdfRelativePath: String?
    var tags: [String]
    var status: ReadingStatus
    var priority: Priority
    var rating: Int?
    var useFor: [String]
    var createdAt: Date
    var updatedAt: Date
}
```

阅读状态：

```swift
enum ReadingStatus: String, Codable, CaseIterable {
    case unread
    case skimmed
    case deepRead
    case summarized
    case used
    case rejected
}
```

优先级：

```swift
enum Priority: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case urgent
}
```

---

## 6.4 PDF 模块

PDF 模块必须支持两种模式。

### 模式一：外部 PDF 阅读器

优先支持：

```text
Sioyek
Skim
Preview
```

功能：

1. 从论文列表中打开 PDF。
2. 可以配置默认 PDF 阅读器。
3. 可以打开 PDF 所在目录。
4. 可以定位到某个页码，若外部工具支持。
5. 可以读取 PDF 文件路径并同步到 `meta.yaml`。

接口设计：

```swift
protocol PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws
}
```

实现：

```swift
final class SioyekPDFOpeningService: PDFOpeningService { }

final class SkimPDFOpeningService: PDFOpeningService { }

final class SystemPDFOpeningService: PDFOpeningService { }
```

### 模式二：内置 PDF 预览

使用 PDFKit。

功能：

1. 快速预览 PDF。
2. 显示页码。
3. 文本搜索。
4. 提取 PDF 文本。
5. 读取已有 PDF 注释。
6. 后续可增加高亮和批注。

注意：

> 第一版不要在 PDFKit 中实现复杂的 Zotero 式阅读器。重点是和文件系统、标签、LLM、Markdown 知识库打通。

---

## 6.5 Markdown 模块

负责：

1. 浏览 `wiki/`。
2. 渲染 Markdown。
3. 编辑 Markdown。
4. 解析 YAML frontmatter。
5. 支持 `[[双链]]`。
6. 显示反链。
7. 显示标签。
8. 创建新概念页。
9. 创建新论文页。
10. 从 LLM 输出生成 Markdown 文件。

核心对象：

```swift
struct WikiPage: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var type: WikiPageType
    var relativePath: String
    var tags: [String]
    var outgoingLinks: [String]
    var backlinks: [String]
    var createdAt: Date?
    var updatedAt: Date?
}
```

页面类型：

```swift
enum WikiPageType: String, Codable, CaseIterable {
    case paper
    case concept
    case method
    case dataset
    case author
    case gap
    case project
    case note
}
```

---

## 6.6 LLM 模块

LLM 是本程序的核心模块之一。

必须支持以下 Provider：

第一版至少支持：

```text
Ollama
OpenAI-compatible API
```

后续可支持：

```text
Anthropic
Gemini
Local LM Studio
```

Provider 抽象：

```swift
protocol LLMProvider {
    var id: String { get }
    var name: String { get }
    func streamChat(request: LLMChatRequest) async throws -> AsyncThrowingStream<LLMToken, Error>
    func complete(request: LLMChatRequest) async throws -> LLMChatResponse
}
```

请求结构：

```swift
struct LLMChatRequest: Codable {
    var model: String
    var systemPrompt: String
    var messages: [LLMMessage]
    var temperature: Double
    var maxTokens: Int?
}
```

消息结构：

```swift
struct LLMMessage: Codable {
    var role: LLMRole
    var content: String
}
```

LLM 任务类型：

```swift
enum LLMTaskType: String, Codable, CaseIterable {
    case summarizePaper
    case extractMetadata
    case generateWikiPage
    case findResearchGaps
    case comparePapers
    case generateRelatedWork
    case codeAssistant
    case polishWriting
}
```

---

# 7. LLM 功能要求

## 7.1 论文总结

用户选中一篇论文后，可以点击：

```text
Summarize with LLM
```

程序执行：

```text
读取 meta.yaml
读取 paper.md，如果没有则尝试从 PDF 提取文本
读取已有 annotations.md
读取相关 wiki 页面
拼接上下文
发送给 LLM
接收 Markdown 输出
写入 wiki/papers/{citekey}.md
更新 meta.yaml 的 status 为 summarized
```

---

## 7.2 生成知识页

LLM 输出必须符合固定模板。

论文页模板：

```markdown
---
type: paper
id:
citekey:
title:
year:
authors:
tags:
status: summarized
---

# 标题

## TL;DR

## 研究问题

## 方法概述

## 关键贡献

## 实验与证据

## 主要结论

## 局限性

## 与已有工作的关系

## 可复现性检查

## 对我研究的启发

## 应该链接到的概念页

## 可能产生的新概念页

## 可能产生的研究空白

## 需要进一步验证的问题

## 引用
```

---

## 7.3 研究空白发现

用户可以对一个项目或多篇论文执行：

```text
Find Research Gaps
```

输入：

```text
多篇论文知识页
项目说明
已有概念页
用户当前假设
```

输出到：

```text
wiki/gaps/
```

每个 gap 文件格式：

```markdown
---
type: gap
id:
title:
tags:
related_papers:
confidence:
created:
---

# 研究空白标题

## 问题描述

## 为什么这是空白

## 已有证据

## 可能的研究路径

## 风险和反例

## 相关论文

## 下一步行动
```

---

## 7.4 多模型共享上下文

程序应维护一个文件：

```text
shared_research.md
```

用于给不同 LLM 工具共享上下文。

程序应支持：

1. 在 UI 中打开。
2. 一键复制。
3. 一键追加当前论文摘要。
4. 一键追加当前项目状态。
5. 一键发送给 LLM。

---

# 8. 搜索和索引模块

数据库只能作为缓存。

推荐使用 SQLite + FTS5。

索引内容：

```text
论文标题
作者
年份
标签
meta.yaml
paper.md
annotations.md
wiki 页面
BibTeX
```

搜索功能：

1. 全文搜索。
2. 标签过滤。
3. 状态过滤。
4. 类型过滤。
5. 年份过滤。
6. 搜索结果跳转文件。
7. 支持重建索引。

数据库表建议：

```sql
CREATE TABLE papers (
    id TEXT PRIMARY KEY,
    citekey TEXT NOT NULL,
    title TEXT NOT NULL,
    year INTEGER,
    venue TEXT,
    status TEXT,
    priority TEXT,
    rating INTEGER,
    relative_path TEXT NOT NULL,
    updated_at TEXT
);

CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE paper_tags (
    paper_id TEXT NOT NULL,
    tag_id INTEGER NOT NULL
);

CREATE TABLE wiki_pages (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    type TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    updated_at TEXT
);

CREATE VIRTUAL TABLE search_index USING fts5(
    object_id,
    object_type,
    title,
    body,
    tags
);
```

---

# 9. 图谱模块

第一版可以实现基础图谱。

图谱节点：

```text
论文
概念
方法
数据集
作者
研究空白
项目
```

图谱边：

```text
[[双链]]
引用关系
同标签关系
同项目关系
LLM 发现关系
```

第一版图谱功能：

1. 从 Markdown 中解析 `[[link]]`。
2. 建立节点和边。
3. 显示基础 force-directed graph 或列表式关系图。
4. 点击节点打开对应 Markdown。
5. 支持按类型过滤。
6. 支持按标签过滤。

如果图谱实现复杂，第一版可以先做“反链面板”和“关系列表”，第二版再做可视化图谱。

---

# 10. VSCode / VSCodium 集成

程序必须支持与 VSCode 或 VSCodium 联动。

功能：

1. 一键用 VSCode/VSCodium 打开当前工作区。
2. 一键打开当前 Markdown 文件。
3. 一键打开当前代码目录。
4. 自动生成 `.code-workspace` 文件。
5. 自动生成推荐插件清单。
6. 可选生成 `.vscode/tasks.json`。

生成的 workspace 文件示例：

```json
{
  "folders": [
    {
      "name": "ResearchWorkspace",
      "path": "."
    },
    {
      "name": "Code",
      "path": "code"
    },
    {
      "name": "Wiki",
      "path": "wiki"
    }
  ],
  "settings": {
    "markdown.preview.breaks": true,
    "files.associations": {
      "*.md": "markdown"
    }
  },
  "extensions": {
    "recommendations": [
      "foam.foam-vscode",
      "yzhang.markdown-all-in-one",
      "davidanson.vscode-markdownlint",
      "bierner.markdown-mermaid",
      "continue.continue"
    ]
  }
}
```

---

# 11. 导入流程

用户拖入 PDF 后，程序执行：

```text
1. 复制 PDF 到 inbox/
2. 尝试读取 PDF 标题
3. 尝试从文件名、PDF metadata、arXiv ID 提取元数据
4. 生成 citekey
5. 创建 raw/papers/{paper-id}/
6. 移动 PDF 为 paper.pdf
7. 创建 meta.yaml
8. 创建 annotations.md
9. 尝试写入 refs/library.bib
10. 更新数据库索引
11. 在 UI 中显示该论文
```

citekey 规则：

```text
firstAuthorYearKeyword
```

示例：

```text
smith2024graph
wang2023retrieval
lee2022knowledge
```

如果冲突，则追加后缀：

```text
smith2024graphA
smith2024graphB
```

---

# 12. PDF 转 Markdown

第一版不需要内置复杂 PDF 转 Markdown 引擎。

应支持外部工具调用。

用户可以在设置中配置：

```text
Marker 命令路径
MinerU 命令路径
pdftotext 命令路径
Tesseract 命令路径
```

程序执行转换时：

```text
paper.pdf
转为
paper.md
```

转换服务接口：

```swift
protocol PDFTextExtractionService {
    func extractText(from pdfURL: URL, outputURL: URL) async throws
}
```

实现：

```swift
final class PDFKitTextExtractionService: PDFTextExtractionService { }

final class ExternalCommandTextExtractionService: PDFTextExtractionService { }
```

第一版优先顺序：

```text
如果存在 paper.md，则直接使用
否则使用 PDFKit 提取文本
如果用户配置了外部命令，则使用外部命令
```

---

# 13. 设置模块

设置页面需要包括：

## 13.1 工作区设置

```text
当前工作区路径
重新扫描
重建索引
打开文件夹
打开 VSCode/VSCodium
```

## 13.2 PDF 设置

```text
默认 PDF 阅读器
Sioyek 路径
Skim 路径
是否使用内置 PDF 预览
```

## 13.3 LLM 设置

```text
Provider 类型
Base URL
API Key
默认模型
温度
最大输出长度
是否允许上传 PDF 原文
是否优先使用本地模型
```

API Key 必须存入 macOS Keychain，不允许明文写入配置文件。

## 13.4 外部工具设置

```text
Marker 路径
MinerU 路径
pdftotext 路径
Pandoc 路径
Quarto 路径
```

---

# 14. 安全和隐私要求

必须满足：

1. 默认本地优先。
2. 不经用户确认，不把 PDF 原文发送给云端 LLM。
3. API Key 存储在 Keychain。
4. 工作区路径使用 security-scoped bookmark 保存。
5. LLM 请求前显示将发送的上下文摘要。
6. 用户可以选择：
   - 只发送摘要；
   - 发送 paper.md；
   - 发送选中文本；
   - 发送完整上下文。
7. 所有 LLM 输出必须标记为 AI 生成，用户可以编辑确认。

---

# 15. 主界面设计

主界面建议如下：

```text
┌──────────────────────────────────────────────────────────────┐
│ Toolbar: Import PDF | Summarize | Search | Open in VSCode    │
├───────────────┬───────────────────────────────┬──────────────┤
│ Sidebar       │ Main Content                  │ Inspector    │
│               │                               │              │
│ Library       │ Paper List / Markdown / PDF   │ Metadata     │
│ Wiki          │                               │ Tags         │
│ Graph         │                               │ LLM Panel    │
│ Projects      │                               │ Backlinks    │
│ Gaps          │                               │ Actions      │
│ Settings      │                               │              │
└───────────────┴───────────────────────────────┴──────────────┘
```

Sidebar 项：

```text
Library
Inbox
Wiki
Papers
Concepts
Methods
Gaps
Projects
Graph
LLM Lab
Settings
```

论文列表字段：

```text
Title
Authors
Year
Tags
Status
Priority
Rating
Updated
```

右侧 Inspector：

```text
Metadata
Tags
Reading Status
Related Wiki Page
PDF Path
BibTeX Entry
LLM Actions
Backlinks
```

---

# 16. 核心用户流程

## 16.1 新建工作区

```text
用户点击 Create Workspace
选择文件夹
程序创建标准目录结构
初始化 shared_research.md
初始化 refs/library.bib
初始化 prompts/
初始化 SQLite 索引
显示主界面
```

---

## 16.2 导入论文

```text
用户拖入 PDF
程序创建论文目录
生成 meta.yaml
更新 library.bib
显示在 Library
用户添加标签
用户选择 Open PDF
程序调用 Sioyek 或内置 PDF 预览
```

---

## 16.3 LLM 总结论文

```text
用户选择论文
点击 Summarize with LLM
程序读取 PDF 文本或 paper.md
程序读取 meta.yaml
程序构造 Prompt
用户确认发送内容
LLM 流式返回
程序显示预览
用户点击 Save
程序写入 wiki/papers/{citekey}.md
程序更新 meta.yaml
程序重建索引
```

---

## 16.4 生成研究空白

```text
用户选择多篇论文
点击 Find Gaps
程序读取对应 wiki 页面
程序读取 shared_research.md
LLM 生成 gap 文档
保存到 wiki/gaps/
图谱和反链更新
```

---

# 17. Prompt 模板

程序内置以下 Prompt。

## 17.1 论文总结 Prompt

```markdown
你是我的科研助理。请阅读下面的论文内容，并生成结构化 Markdown 知识页。

要求：

1. 不要只做摘要，要提取可进入知识库的结构化知识。
2. 保留论文的核心论点、方法、假设、实验、局限。
3. 主动识别与已有概念的连接。
4. 发现潜在研究空白。
5. 输出 Markdown，包含 YAML frontmatter。
6. 不确定内容必须标记为「待验证」。
7. 不要编造引用。
8. 如果论文内容不足，请明确说明缺失信息。

输出结构：

---
type: paper
id:
citekey:
title:
year:
authors:
tags:
status: summarized
---

# 标题

## TL;DR

## 研究问题

## 方法概述

## 关键贡献

## 实验与证据

## 主要结论

## 局限性

## 与已有工作的关系

## 可复现性检查

## 对我研究的启发

## 应该链接到的概念页

## 可能产生的新概念页

## 可能产生的研究空白

## 需要进一步验证的问题

## 引用

论文元数据：

{{metadata}}

论文内容：

{{paper_content}}
```

---

## 17.2 研究空白 Prompt

```markdown
你是一个严谨的科研顾问。请根据以下多篇论文知识页和我的研究目标，发现潜在研究空白。

要求：

1. 不要泛泛而谈。
2. 每个研究空白都必须说明证据来源。
3. 区分真正空白、工程实现空白、评估空白、数据空白。
4. 给出可能的研究路线。
5. 给出风险和反例。
6. 不要声称某方向没人做过，除非上下文中有明确证据。
7. 所有不确定内容标记为「待验证」。

我的研究目标：

{{research_goal}}

已有上下文：

{{shared_research}}

论文知识页：

{{paper_pages}}

请输出多个 Markdown gap 文档，每个文档包含：

---
type: gap
title:
tags:
related_papers:
confidence:
---

# 研究空白标题

## 问题描述

## 为什么这是空白

## 证据来源

## 可能研究路径

## 实验设计建议

## 风险和反例

## 下一步行动
```

---

# 18. 开发阶段规划

## 第一阶段：MVP

目标：

```text
可以创建工作区
可以导入 PDF
可以编辑 meta.yaml
可以打开外部 PDF 阅读器
可以显示论文列表
可以显示和编辑 Markdown
可以接入 Ollama 或 OpenAI-compatible API
可以生成论文总结
```

必须完成：

1. Xcode 项目。
2. SwiftUI 主界面。
3. Workspace 创建和打开。
4. 文件夹结构初始化。
5. PDF 导入。
6. `meta.yaml` 读写。
7. 论文列表。
8. 标签编辑。
9. 外部 PDF 打开。
10. Markdown 渲染和编辑。
11. LLM Provider 抽象。
12. Ollama 接入。
13. 论文总结并保存到 `wiki/papers/`。

---

## 第二阶段：索引和搜索

目标：

```text
建立 SQLite/FTS5 索引
支持全文搜索
支持标签和状态筛选
```

必须完成：

1. SQLite 数据库。
2. 从文件重建索引。
3. 搜索界面。
4. wiki 页面索引。
5. PDF 提取文本索引。
6. 标签筛选。

---

## 第三阶段：图谱和反链

目标：

```text
实现双链、反链、基础图谱
```

必须完成：

1. 解析 `[[双链]]`。
2. 建立 wiki 页面关系。
3. 显示反链面板。
4. 显示关系列表。
5. 可选实现图谱可视化。

---

## 第四阶段：VSCode / VSCodium 集成

目标：

```text
让程序和代码工作流打通
```

必须完成：

1. 一键打开工作区。
2. 生成 `.code-workspace`。
3. 生成推荐插件列表。
4. 打开当前 Markdown 文件。
5. 打开 `code/` 目录。

---

## 第五阶段：高级 LLM 工作流

目标：

```text
从单篇论文总结升级为知识编译系统
```

必须完成：

1. 多论文对比。
2. 研究空白发现。
3. 概念页自动生成。
4. shared_research.md 管理。
5. LLM 输出审查。
6. LLM 任务历史。

---

# 19. 测试要求

必须写单元测试，至少覆盖：

```text
Workspace 初始化
meta.yaml 解析和写入
citekey 生成
Markdown frontmatter 解析
双链解析
标签筛选
LLM 请求构造
LLM 响应解析
PDF 导入路径生成
数据库重建索引
```

测试示例：

```swift
func testCitekeyGeneration() throws {
    let paper = Paper(
        id: "test",
        citekey: "",
        title: "Graph-based Retrieval Augmented Generation",
        authors: ["John Smith"],
        year: 2024,
        venue: nil,
        doi: nil,
        arxiv: nil,
        url: nil,
        pdfRelativePath: nil,
        tags: [],
        status: .unread,
        priority: .medium,
        rating: nil,
        useFor: [],
        createdAt: Date(),
        updatedAt: Date()
    )

    let citekey = CitekeyGenerator.generate(for: paper)
    XCTAssertEqual(citekey, "smith2024graph")
}
```

---

# 20. 交给 AI 编程 Agent 的总指令

下面这段可以直接复制给 AI 编程助手。

```markdown
你是一名资深 macOS Swift 开发者。请为我开发一个名为 ResearchFlow Mac 的 macOS 原生科研工作站应用。

技术要求：

1. 使用 Swift、SwiftUI、macOS 14+。
2. 使用 MVVM + Service Layer 架构。
3. 所有核心数据必须存储在用户可见的文件系统中。
4. SQLite 只能作为缓存和搜索索引，必须可以从文件重建。
5. 支持 Markdown、YAML frontmatter、BibTeX、PDF、LLM。
6. 优先本地优先和隐私保护。
7. 不要把数据锁在私有数据库中。

第一阶段 MVP 功能：

1. 创建和打开 ResearchWorkspace 工作区。
2. 初始化以下目录：

ResearchWorkspace/
├── inbox/
├── raw/papers/
├── raw/web/
├── raw/books/
├── wiki/papers/
├── wiki/concepts/
├── wiki/methods/
├── wiki/datasets/
├── wiki/authors/
├── wiki/gaps/
├── wiki/projects/
├── refs/
├── prompts/
├── scripts/
├── code/
├── outputs/
└── shared_research.md

3. 支持拖入 PDF。
4. 导入 PDF 时创建：

raw/papers/{paper-id}/
├── paper.pdf
├── meta.yaml
└── annotations.md

5. 支持读取和写入 meta.yaml。
6. 支持论文列表显示，包括标题、作者、年份、标签、状态、优先级、评分。
7. 支持编辑标签、状态、优先级、评分，并写回 meta.yaml。
8. 支持用外部 PDF 阅读器打开 PDF，至少支持系统默认打开，预留 Sioyek 和 Skim。
9. 支持内置 Markdown 渲染和编辑。
10. 支持读取和显示 wiki/ 下的 Markdown 文件。
11. 支持 Ollama 和 OpenAI-compatible API 的 LLM Provider 抽象。
12. 支持选择一篇论文并调用 LLM 生成 Markdown 论文总结。
13. LLM 生成结果保存到 wiki/papers/{citekey}.md。
14. 保存后更新 meta.yaml 的 status 为 summarized。

请先生成完整 Xcode 项目结构和关键文件，不要一次性堆砌所有代码。请按以下顺序实现：

第一步：
- 创建 SwiftUI App 主框架。
- 实现 Workspace 创建和打开。
- 实现标准目录初始化。

第二步：
- 实现 Paper 数据模型。
- 实现 meta.yaml 读写。
- 实现 PDF 导入。

第三步：
- 实现论文列表 UI。
- 实现右侧 Inspector。
- 实现标签、状态、优先级编辑。

第四步：
- 实现 PDFOpeningService。
- 支持系统默认 PDF 打开。
- 预留 SioyekPDFOpeningService 和 SkimPDFOpeningService。

第五步：
- 实现 Markdown 文件浏览、渲染和编辑。
- 支持 YAML frontmatter 解析。
- 支持保存 Markdown。

第六步：
- 实现 LLMProvider 协议。
- 实现 OllamaProvider。
- 实现 OpenAICompatibleProvider。
- 支持流式输出。

第七步：
- 实现 Summarize Paper 功能。
- 读取 meta.yaml、paper.md 或 PDF 文本。
- 构造 Prompt。
- 调用 LLM。
- 保存 wiki/papers/{citekey}.md。

第八步：
- 添加单元测试。
- 测试 Workspace 初始化、meta.yaml 解析、citekey 生成、Markdown frontmatter 解析、LLM 请求构造。

代码质量要求：

1. 每个模块职责清晰。
2. 所有文件操作必须有错误处理。
3. 所有异步任务使用 async/await。
4. UI 不得阻塞主线程。
5. API Key 必须预留 Keychain 存储接口。
6. LLM 请求前必须允许用户确认将发送的内容。
7. 生成的 Markdown 必须可被其他编辑器直接打开。
8. 代码必须可编译。
9. 每完成一个阶段，请说明新增文件、核心类、如何测试。

请先输出项目目录结构，然后开始实现第一阶段第一步。
```

---

# 21. 第一版验收标准

MVP 完成后，应该能够做到：

```text
1. 启动 App。
2. 创建一个 ResearchWorkspace。
3. 拖入一篇 PDF。
4. 程序自动创建 raw/papers/{paper-id}/。
5. 程序生成 meta.yaml。
6. 论文出现在 Library 列表。
7. 用户可以添加标签。
8. 用户可以修改阅读状态。
9. 用户可以用外部 PDF 阅读器打开论文。
10. 用户可以调用本地 Ollama 总结论文。
11. 程序生成 wiki/papers/{citekey}.md。
12. 用户可以在 App 中阅读 Markdown 总结。
13. 用户可以一键用 VSCode/VSCodium 打开整个工作区。
```

---

# 22. 推荐最终架构总结

最终程序应该是：

```text
ResearchFlow Mac
├── 文件系统：真实数据源
├── SQLite：索引缓存
├── SwiftUI：macOS 原生界面
├── PDF：外部阅读器优先，内置预览辅助
├── Markdown：知识库核心格式
├── YAML：元数据和标签
├── BibTeX：引用管理
├── LLM：论文分析和知识编译
├── VSCode/VSCodium：代码和高级 Markdown 编辑
└── Graph：知识关系可视化
```

核心思想是：

> 不做一个封闭的 Zotero 或 Obsidian 克隆，而是做一个 macOS 原生的开放式科研中枢。  
> PDF、Markdown、BibTeX、YAML、代码、Prompt 都保存在普通文件中。  
> App 负责组织、索引、可视化、调用 LLM 和连接外部工具。