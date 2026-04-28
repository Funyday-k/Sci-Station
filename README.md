# Sci-Station

Sci-Station 是一个面向 macOS 的本地优先科研 all-in-one 工作站原型。它是把一个科研项目内部的 proposal、核心论文、数据、代码阅读、图片、输出、任务、日历和知识页组织在同一个可见的本地工作区中。

当前代码已经完成核心骨架：工作区创建与恢复、项目总览、论文导入、元数据读写、Library 管理、Wiki、Todo/Calendar、BibTeX 出口、内置 PDF Reader，以及可独立运行的核心验证工具。

## 当前状态

- 平台：macOS 14+
- UI：SwiftUI 三栏 NavigationSplitView
- 架构：MVVM + Service/Repository + actor 并发隔离
- 数据原则：文件系统优先，核心数据落在用户可见目录中
- 当前验证状态：Xcode App 可构建；SwiftPM 核心验证通过

## 工作区结构

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
│   ├── library.bib
│   └── tags.yaml
├── settings/
│   └── workspace_preferences.yaml
├── tasks/
│   ├── calendar.yaml
│   └── todos.yaml
├── imports/
│   ├── failed_imports.yaml
│   └── import_history.yaml
├── data/
├── prompts/
├── scripts/
├── code/
├── figures/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

## 已实现功能

### 1. 工作区管理

- 创建本地 ResearchWorkspace
- 打开已有工作区并自动补齐缺失目录和种子文件
- 使用 security-scoped bookmark 恢复最近一次打开的工作区
- 启动后保持 security-scoped 访问作用域，避免反复要求重新选择工作区
- Create/Open Workspace 和 Import PDF 系统面板默认打开 Documents
- 在 Finder 中定位当前工作区
- Settings 中可查看 workspace preferences 文件并清除最近工作区 bookmark

### 2. 科研项目总览

- Projects 入口显示 project-level overview，不再只是占位页
- 自动创建 `wiki/projects/project_overview.md` 作为项目介绍和 living proposal
- 自动创建 `wiki/projects/core_papers.md` 作为核心论文清单
- Project Overview 汇总论文数、核心论文数、项目文档数和未完成任务数
- 核心论文列表按 core/foundation/key/proposal 标签、优先级和评分推导，并显示简要内容
- Research Workflow 入口覆盖 proposal、core papers、data、code、figures、outputs、tasks 和 shared context

### 3. Workspace 偏好

- 保存 workspace 级偏好到 `settings/workspace_preferences.yaml`
- 记录 schema version，为后续迁移和索引准备底座
- Library visible columns 和 column order 从 workspace preferences 恢复
- 仍保留 App 内默认列作为偏好文件缺失时的兜底

### 4. 论文库与元数据

- Paper 模型包含标题、作者、年份、标签、阅读状态、优先级、评分、用途、出版信息、标识符、abstract、BibTeX 等字段
- 使用 `meta.yaml` 作为论文目录内的元数据文件
- 自动生成 citekey 和 paper id
- 支持从文件系统扫描 `raw/papers` 并加载本地论文库
- 支持在 Inspector 中编辑论文元数据并保存回 `meta.yaml`
- Collection 重命名后按真实目录推导 collection，避免 stale `collection_path` 导致论文消失
- Library 搜索覆盖标题、作者、标签、citekey、DOI、arXiv、INSPIRE、abstract、BibTeX 与出版信息

### 5. PDF 与链接导入

- 支持按钮选择 PDF 导入
- 支持把 PDF 拖入 Library 完成导入
- 使用 PDFKit 读取 PDF title / author 元数据，并从文件名中提取年份
- 导入时创建 `raw/papers/{collection}/{paper-id}/`
- 生成标准化文件：`paper.pdf`、`paper.md`、`meta.yaml`、`annotations.md`、`figures/`
- Quick Link 支持 DOI、arXiv、PDF URL 和普通网页链接，导入前可直接打开 URL 确认

### 6. Markdown 知识页闭环

- 支持为论文生成 `wiki/papers/{citekey}.md` 模板页
- 支持扫描 `wiki/` 下的 Markdown 页面
- 支持在应用内打开、编辑、保存 Markdown 文件
- 支持解析 YAML frontmatter 和 `[[wikilink]]`
- 支持在 Inspector 中查看 outgoing links 和 backlinks

### 7. Todo、Calendar 与 Apple Reminders

- Dashboard 月历显示本地 todo、workspace calendar event 和 Apple Calendar/Reminders 标题
- Todo 支持 due date、priority、notes、编辑和删除
- Todo YAML 记录 Apple Reminders 映射字段：`external_source`、`external_identifier`、`external_updated_at`、`completed_at`、`due_time`
- 可将新增或已有 todo 发布到 Apple Reminders，并在本地保存 reminder 标识

### 8. 应用界面

- 三栏主界面：侧边栏、内容区、检查器
- 顶部工具栏支持 Create Workspace、Open Workspace、Import PDF、Add by Identifier、Reveal in Finder
- Library 页面支持紧凑操作区、可配置列、列拖拽排序、tag chip 显示和右键菜单
- Paper Inspector 支持回车保存，点击空白区域结束元数据输入状态
- BibTeX 可从论文右键或 Reader Citations 面板复制、预览并导出 `.bib`
- Wiki 页面提供 Markdown 列表、编辑器和 Inspector
- Projects 页面提供项目介绍、核心论文、项目文档和科研 workflow 入口

### 9. PDF Reader

- 内置 PDF Reader 支持页码、搜索、缩放、PDFKit 历史前进/后退
- Reader 右侧栏支持 Metadata、Notes、Tasks、Citations、Links、Abstract、Files
- Notes 面板可读写当前论文的 `annotations.md`
- Tasks 面板可创建与当前 paper id 关联的 todo
- Citations 面板展示 BibTeX，支持复制和导出
- Links 面板展示 DOI、arXiv、INSPIRE、URL、PDF URL 并可直接打开

### 10. 核心验证

仓库中包含独立的 SwiftPM 可执行验证器，用于验证核心文件系统与元数据逻辑。

当前覆盖的检查包括：

- 工作区创建后结构完整
- 旧工作区打开时自动补齐缺失目录和占位文件
- Project Overview 所需 `data/`、`figures/` 和 `wiki/projects/` 种子文档会自动创建或补齐
- 最近 workspace bookmark 失效时自动清理
- WorkspacePreferencesRepository 保存和读取可往返
- citekey 生成规则正确
- meta.yaml 编解码可往返
- PaperRepository 保存、读取、删除和 nested collection 加载可往返
- PaperAnnotationsRepository 可读写 `annotations.md`
- TodoRepository 保留 priority、notes、related paper ids 和 Reminders 映射字段
- LibrarySearchService 覆盖 DOI、abstract、BibTeX 等扩展字段
- PDF 导入后生成 `paper.md` 和 `figures/`
- WikiPageGenerator 生成模板页并拒绝静默覆盖
- FrontmatterParser、WikiLinkParser、BacklinkIndex、MarkdownRepository 基础检查通过

## 权限说明

- 工作区路径通过 macOS security-scoped bookmark 保存；如果工作区被移动或删除，App 会清除失效 bookmark 并回到打开工作区状态。
- Calendar/Reminders 功能使用 EventKit。首次请求后需要在系统权限面板允许访问；拒绝权限时本地 todo 仍可使用，只是不会发布到 Apple Reminders。
- LLM API Key 存入 macOS Keychain，不写入 workspace 明文配置文件。

## 手动检查清单

- 关闭并重新打开 App，确认最近 workspace 自动恢复。
- 打开 Create/Open Workspace 或 Import PDF，确认系统面板默认定位到 Documents。
- 打开 Projects，确认 Project Overview 显示项目介绍、核心论文、项目文档和 data/code/figures/outputs 入口。
- 在 Library 中拖动列标题并重启，确认列顺序从 `workspace_preferences.yaml` 恢复。
- 重命名 collection 后确认该 collection 下论文仍可显示。
- 在 Reader 的 Notes 面板保存文字，确认对应论文目录的 `annotations.md` 更新。
- 在 Reader 的 Citations 面板复制/导出 BibTeX，确认剪贴板和 `.bib` 文件内容正确。
- 新建 todo 并发布到 Apple Reminders，确认 `tasks/todos.yaml` 写入 `external_source` 和 `external_identifier`。

## 尚未完成的部分

- Project Overview 的项目配置模型、阶段状态和自定义核心论文 pinning
- SQLite/FTS 统一搜索索引和增量更新
- Apple Reminders 双向同步、完成状态回写和冲突选择 UI
- DOI、arXiv、INSPIRE provider 的固定 fixture 回归套件
- Reader Tasks 面板的完整编辑、完成和筛选能力
- Workspace 最近列表和 workspace 级共享视图配置 UI
- VSCode / VSCodium 联动
- 外部 PDF 阅读器深度集成
- 图谱可视化
- 更完整的行为测试和 UI 测试

## 目录说明

```text
Sci-Station/
├── App/                AppViewModel 等应用状态管理
├── Calendar/           本地 calendar event 模型与仓库
├── Collections/        Collection 管理与移动论文服务
├── Import/             DOI/arXiv/INSPIRE/URL 导入服务
├── Importer/           PDF 导入逻辑
├── Library/            Paper 模型、YAML 编解码、Repository、搜索、annotations
├── LLM/                LLM 配置、提示词和写回服务
├── Markdown/           Markdown、frontmatter、wikilink、backlink 支持
├── MetadataProviders/  DOI、arXiv、INSPIRE provider 与 mapper
├── PDF/                PDFKit Reader 和 PDF 打开协议
├── Tags/               Tag 定义与仓库
├── Tasks/              Todo 模型与仓库
├── UI/                 侧边栏、Projects、Library、Dashboard、Inspector 等 SwiftUI 视图
├── Wiki/               Wiki page 生成服务
├── Workspace/          工作区模型、偏好、bookmark 持久化
├── ContentView.swift   主界面入口
└── Sci_StationApp.swift
Tools/
└── SciStationCoreTestRunner/
DOC/
├── Proposal.md
├── Proposal5.md
├── Proposal6.md
├── Proposal7.md
└── Proposal8.md
```

## 运行方式

### 在 Xcode 中运行

```bash
open Sci-Station.xcodeproj
```

然后在 Xcode 中选择 Scheme 为 Sci-Station，运行目标为 My Mac，按 Command + R。

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
swift run SciStationCoreTestRunner
```

预期输出：

```text
All SciStation core checks passed.
```

标准完成检查：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

## 开发说明

- 当前工程对 Swift 6 并发检查较严格，纯值类型与纯工具方法需要按需标注 `nonisolated`。
- Workspace、Library、Tasks、Markdown 等核心类型已开放给 SwiftPM 交叉 target 使用。
- 目前没有引入外部 SwiftPM 依赖，YAML 编解码采用轻量手写实现。

## 相关文档

- 项目原始任务书：[DOC/Proposal.md](DOC/Proposal.md)
- 任务书 5：[DOC/Proposal5.md](DOC/Proposal5.md)
- 任务书 6：[DOC/Proposal6.md](DOC/Proposal6.md)
- 任务书 7：[DOC/Proposal7.md](DOC/Proposal7.md)
