# Sci-Station

Sci-Station 是一个面向 macOS 的本地优先科研工作站原型，目标是用 Swift 和 SwiftUI 搭建一套可替代部分 Obsidian + Zotero 工作流的原生工具链。

当前代码已经完成 MVP 前两阶段的核心骨架：工作区创建与恢复、论文导入、元数据读写、基础论文库界面，以及可独立运行的核心验证工具。

## 当前状态

- 平台：macOS 14+
- UI：SwiftUI 三栏 NavigationSplitView
- 架构：MVVM + Service/Repository + actor 并发隔离
- 数据原则：文件系统优先，核心数据落在用户可见目录中
- 当前验证状态：Xcode App 可构建；SwiftPM 核心验证通过

## 已实现功能

### 1. 工作区管理

- 创建本地 ResearchWorkspace
- 打开已有工作区
- 校验必需目录和种子文件是否存在
- 使用 security-scoped bookmark 恢复最近一次打开的工作区
- 在 Finder 中定位当前工作区

当前创建出的工作区结构如下：

```text
ResearchWorkspace/
├── inbox/
├── raw/
│   ├── papers/
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
│   ├── csl/
│   └── library.bib
├── prompts/
├── scripts/
├── code/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

### 2. 论文库与元数据

- 定义了 Paper 模型，包含标题、作者、年份、标签、阅读状态、优先级、评分、用途等字段
- 使用 meta.yaml 作为论文目录内的元数据文件
- 自动生成 citekey 和 paper id
- 支持从文件系统扫描 raw/papers 并加载本地论文库
- 支持在界面侧栏中编辑论文元数据并保存回 meta.yaml
- 自动维护 refs/library.bib 中的 BibTeX stub

### 3. PDF 导入流程

- 支持通过按钮选择 PDF 导入
- 支持把 PDF 拖入 Library 界面完成导入
- 使用 PDFKit 读取 PDF title / author 元数据，并从文件名中提取年份
- 导入时会创建 raw/papers/{paper-id}/ 目录
- 生成标准化文件：paper.pdf、paper.md、meta.yaml、annotations.md、figures/
- 生成 notesSummaryRelativePath 指向 wiki/papers/{citekey}.md 的预留路径

### 4. Markdown 知识页闭环

- 支持为论文生成 wiki/papers/{citekey}.md 模板页
- 支持扫描 wiki/ 下的 Markdown 页面
- 支持在应用内打开、编辑、保存 Markdown 文件
- 支持解析 YAML frontmatter 和 [[wikilink]]
- 支持在 Inspector 中查看 outgoing links 和 backlinks

### 5. 应用界面

- 三栏主界面：侧边栏、内容区、检查器
- 顶部工具栏支持 Create Workspace、Open Workspace、Import PDF、Open PDF、Reveal in Finder
- Library 页面支持搜索标题、作者、标签和 citekey
- Paper Inspector 支持编辑核心元数据字段并回写
- Library Inspector 支持 Generate Wiki Page / Open Wiki Page
- Wiki 页面不再是占位页，而是最小可用的 Markdown 列表 + 编辑器 + Inspector

### 6. PDF 打开抽象

- 定义了 PDFOpeningService 协议
- 当前实现可通过系统默认方式打开 PDF
- 已预留 Sioyek / Skim 集成入口，但尚未接入实际打开逻辑

### 7. 核心验证

仓库中包含独立的 SwiftPM 可执行验证器，用于验证核心文件系统与元数据逻辑。

当前覆盖的检查包括：

- 工作区创建后结构完整
- 旧工作区打开时自动补齐缺失目录和占位文件
- citekey 生成规则正确
- meta.yaml 编解码可往返
- PaperRepository 保存和读取可往返
- PDF 导入后生成 paper.md 和 figures/
- WikiPageGenerator 生成模板页并拒绝静默覆盖
- FrontmatterParser、WikiLinkParser、BacklinkIndex、MarkdownRepository 基础检查通过

## 尚未完成的部分

以下能力仍处于待开发状态：

- LLM 接入与论文总结工作流
- 导入元数据补全（doi、venue、arXiv、url、abstract 等）
- VSCode / VSCodium 联动
- 全文检索与索引数据库
- 外部 PDF 阅读器深度集成
- 图谱可视化
- 更完整的行为测试和 UI 测试

## 目录说明

```text
Sci-Station/
├── App/                AppViewModel 等应用状态管理
├── Importer/           PDF 导入逻辑
├── Library/            Paper 模型、YAML 编解码、Repository
├── PDF/                PDF 打开协议与实现
├── UI/                 侧边栏、Library、Inspector 等 SwiftUI 视图
├── Workspace/          工作区模型、校验、bookmark 持久化
├── ContentView.swift   主界面入口
├── Sci_StationApp.swift
Tools/
└── SciStationCoreTestRunner/
DOC/
└── Proposal.md
```

## 运行方式

### 在 Xcode 中运行

```bash
open Sci-Station.xcodeproj
```

然后在 Xcode 中：

- 选择 Scheme 为 Sci-Station
- 选择运行目标为 My Mac
- 按 Command + R

### 命令行构建

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
	-project Sci-Station.xcodeproj \
	-scheme Sci-Station \
	-destination 'platform=macOS' \
	build
```

## 验证方式

运行核心验证器：

```bash
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift run SciStationCoreTestRunner
```

预期输出：

```text
All SciStation core checks passed.
```

## 开发说明

- 当前工程对 Swift 6 并发检查较严格，部分纯值类型与纯工具方法已经显式标注 nonisolated
- Workspace 和 Library 模块中的核心类型已开放给 SwiftPM 交叉 target 使用
- 目前没有引入外部 SwiftPM 依赖，YAML 编解码采用了轻量手写实现

## 相关文档

- 项目原始任务书：DOC/Proposal.md
- 下一阶段任务书：DOC/Next-Step-Task-Book.md

## 下一步建议

如果要继续推进，优先级最高的三个方向通常是：

1. 先接入最小 LLM 闭环，把“选择论文 -> 读取 paper.md/wiki page -> 生成总结 -> 写回 wiki”做成可确认、可保存的工作流。
2. 再补导入质量和测试，把 doi、venue、arXiv、url 等元数据补全能力和对应验证补起来。
3. 然后做搜索与索引，最后再补真实 PDF 阅读器联动和 VSCode 集成。
