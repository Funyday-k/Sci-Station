# Sci-Station

Sci-Station 是一个面向 macOS 的本地优先科研 all-in-one 工作站原型。它以一个全局研究根目录组织多个科研项目，共享全局论文库、任务、Agent/LLM 设置，并让每个项目拥有自己的 Wiki、材料、任务和输出。

当前代码已经完成核心骨架：工作区创建与恢复、项目总览、论文导入、元数据读写、Library 管理、Wiki、Todo/Calendar、BibTeX 出口、内置 PDF Reader、Codex-style AI Lab V1 + thread 化准备，以及可独立运行的核心验证工具。

## 当前状态

- 平台：macOS 14+
- UI：SwiftUI 三栏 NavigationSplitView
- 架构：MVVM + Service/Repository + actor 并发隔离
- 数据原则：文件系统优先，核心数据落在用户可见目录中
- 当前验证状态：Xcode App 可构建；SwiftPM 核心验证通过

## 工作区结构

```text
ResearchRoot/
├── .sci-station/
│   ├── project_registry.yaml
│   └── agent/
├── library/
│   ├── papers/
│   │   └── {paper-id}/
│   │       ├── paper.pdf
│   │       ├── paper.md
│   │       ├── meta.yaml
│   │       ├── annotations.md
│   │       └── figures/
│   ├── refs/
│   │   ├── library.bib
│   │   └── tags.yaml
│   ├── paper_index.yaml
│   └── project_paper_links.yaml
├── projects/
│   └── {project-id}/
│       ├── project.yaml
│       ├── shared_research.md
│       ├── wiki/
│       ├── tasks/
│       ├── data/
│       ├── code/
│       ├── figures/
│       └── outputs/
├── inbox/
├── raw/
│   ├── papers/        # legacy compatibility; new imports use library/papers
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
│   ├── markdown_snippets.yaml
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

## AI 配置分层

仓库根目录的 `.sci-ai/` 用于区分产品化 AI preset 与本机工作区 AI bridge 配置：

- `.sci-ai/sci-station/`：Sci-Station 产品内置 AI preset，允许进 GitHub；只保存非敏感配置、schema、skills、hooks、commands、MCP 模板和 secret references。
- `.sci-ai/workspace.local/`：当前 checkout 的本机 AI 配置，不进 GitHub；可放 Claude Code bridge、MCP 实际路径和机器相关设置。
- `.claude/` 与 `.mcp.json`：为需要固定路径的外部 agent 工具保留的本机 bridge 文件，不进 GitHub。

任何 API key、OAuth token、refresh token、client secret、private key 或机器私有凭据都不得写入 `.sci-ai/sci-station/`。

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
- Projects 是一级导航第一入口，Papers/Concepts/Methods/Gaps 等 AI 产物入口收束到 Project/Wiki 工作流中
- 自动创建 `wiki/projects/project_overview.md` 作为项目介绍和 living proposal
- 自动创建 `wiki/projects/core_papers.md` 作为核心论文清单
- Project Overview 汇总论文数、核心论文数、项目文档数和未完成任务数
- 核心论文列表按 core/foundation/key/proposal 标签、优先级和评分推导，并显示简要内容
- Research Workflow 入口覆盖 proposal、core papers、data、code、figures、outputs、tasks 和 shared context
- AI Knowledge Workspace 集中进入 paper notes、concepts、methods、research gaps 和 AI Lab

### 3. Workspace 偏好

- 保存 workspace 级偏好到 `settings/workspace_preferences.yaml`
- 记录 schema version，为后续迁移和索引准备底座
- Library visible columns 和 column order 从 workspace preferences 恢复
- 仍保留 App 内默认列作为偏好文件缺失时的兜底

### 4. Materials 与 VS Code 联动

- 左侧栏新增 Materials，用于阅读 workspace 内用户材料文件
- Materials 默认扫描 `inbox/`、`data/`、`code/`、`figures/`、`outputs/`、`scripts/`、`prompts/` 和 `shared_research.md`
- Materials 不显示 `settings/`、`refs/`、`tasks/`、`imports/`、`.sci-station/` 等系统目录
- 点号开头的目录或文件视为内部/隐藏内容，不进入 Materials 列表
- 支持 Markdown、Python、文本、图片和 PDF 预览，其他数据文件可用默认 App 或 VS Code 打开
- Materials 可直接打开整个 workspace 或选中文件到 VS Code / VSCodium
- Python 文件提供运行面板，可选择 System Python、workspace `.venv` 或手选 venv
- 可从 Materials 发起创建 workspace `.venv`，配置写入 `.sci-station/python_environment.txt`
- Run in VS Code 会写入 `.vscode/tasks.json` 与 `.sci-station/vscode/last_python_run.json`，再打开 workspace 和代码文件
- Terminal 运行会生成 `.sci-station/runs/*.command` 并交给 macOS Terminal 执行

### 5. 论文库与元数据

- Paper 模型包含标题、作者、年份、标签、阅读状态、优先级、评分、用途、出版信息、标识符、abstract、BibTeX 等字段
- 使用 `meta.yaml` 作为论文目录内的元数据文件
- 自动生成 citekey 和 paper id
- 新导入论文写入 `library/papers`，并继续兼容扫描旧 `raw/papers`
- `library/project_paper_links.yaml` 保存项目-论文关系，`PaperRepository` 会桥接旧 metadata 中的 `project_ids` / `core_project_ids`
- 支持在 Inspector 中编辑论文元数据并保存回 `meta.yaml`
- Collection 重命名后按真实目录推导 collection，避免 stale `collection_path` 导致论文消失
- Library 搜索覆盖标题、作者、标签、citekey、DOI、arXiv、INSPIRE、abstract、BibTeX 与出版信息
- Library Table V2 支持按 workspace 偏好顺序渲染列，并可在 Columns 菜单中 Move Earlier / Move Later
- 多选论文可批量设置阅读状态、优先级、评分、移动 folder，并批量 add/remove tags；批量操作会保留 selection set

### 6. PDF 与链接导入

- 支持按钮选择 PDF 导入
- 支持把 PDF 拖入 Library 完成导入
- 使用 PDFKit 读取 PDF title / author 元数据，并从文件名中提取年份
- 导入时创建 `library/papers/{collection}/{paper-id}/`
- 生成标准化文件：`paper.pdf`、`paper.md`、`meta.yaml`、`annotations.md`、`figures/`
- Quick Link 支持 DOI、arXiv、PDF URL 和普通网页链接，导入前可直接打开 URL 确认
- Add by Link 支持批量粘贴多个链接/标识符，按换行、逗号、分号和空白分割，顺序导入并保留失败项

### 7. Markdown 知识页闭环

- 支持为论文生成 `wiki/papers/{citekey}.md` 模板页
- 支持扫描 `wiki/` 下的 Markdown 页面
- 支持在应用内打开、编辑、保存 Markdown 文件
- Wiki 编辑器支持 `Cmd+S` 保存、Unsaved 标记，并在切换页面前提示未保存 draft
- Wiki 编辑器支持 Source、Preview、Split 三种模式，右键可切换 split source/preview
- Preview 使用轻量 WebKit Markdown 渲染，支持 GFM、表格、代码块、图片和 KaTeX 公式
- 支持 workspace 自定义 Markdown snippets，默认提供 `;eq`、`;fig`、`;todo`、`;paper` 等触发词
- 支持解析 YAML frontmatter 和 `[[wikilink]]`
- 支持在 Inspector 中查看 outgoing links 和 backlinks

### 8. Todo、Calendar 与 Apple Reminders

- Dashboard 月历显示本地 todo、workspace calendar event 和 Apple Calendar/Reminders 标题
- Todo 支持 due date、priority、notes、编辑和删除
- Todo YAML 记录 Apple Reminders 映射字段：`external_source`、`external_identifier`、`external_updated_at`、`completed_at`、`due_time`
- 可将新增或已有 todo 发布到 Apple Reminders，并在本地保存 reminder 标识

### 9. 应用界面

- 三栏主界面：侧边栏、内容区、检查器
- 顶部工具栏支持 Create Workspace、Open Workspace、Import PDF、Add by Identifier、Reveal in Finder
- 菜单栏提供第一批 Workspace、Paper、View、Wiki 命令；`Cmd+N` 新建项目，`Cmd+O` 打开 workspace，`Cmd+F` 聚焦当前搜索，`Cmd+S` 保存 Wiki 页面
- Materials 页面提供 workspace 用户材料浏览、预览、Finder 定位和 VS Code 打开
- Library 页面使用 SwiftUI `Table` 呈现论文列表，支持系统多选、键盘 selection、可配置可见列、列顺序菜单、标题/作者/年份/更新时间/评分/优先级/状态排序、过滤 chip 摘要、tag chip 显示、Space/Preview PDF fallback 和右键菜单
- Paper Inspector 支持回车保存，点击空白区域结束元数据输入状态
- 删除论文确认会显示实际论文目录相对路径
- BibTeX 可从论文右键或 Reader Citations 面板复制、预览并导出 `.bib`
- Wiki 页面提供 Markdown 列表、编辑器和 Inspector
- Library、Wiki、Materials、Projects 空状态提供直接下一步操作
- Projects 页面提供项目介绍、核心论文、项目文档和科研 workflow 入口

### 10. PDF Reader

- 内置 PDF Reader 支持页码、`Cmd+F` 搜索、`Cmd+G` / `Shift+Cmd+G` 查找下一处/上一处、缩放、PDFKit 历史前进/后退
- Reader 右侧栏支持 Metadata、Notes、Tasks、Citations、Links、Abstract、Files
- Notes 面板可读写当前论文的 `annotations.md`
- Tasks 面板可创建与当前 paper id 关联的 todo
- Citations 面板展示 BibTeX，支持复制和导出
- Links 面板展示 DOI、arXiv、INSPIRE、URL、PDF URL 并可直接打开

### 11. Codex-style AI Lab V1

- AI Lab 提供对话优先的 Agent Panel，conversation scope 跟随 Sidebar 当前项目
- 每个项目 conversation 使用对应 project context 生成 plan 与执行 approved tools
- 首屏以 thread strip、prompt composer 和 session event timeline 为主，Context、Current Plan、Permission Dock、Hook Activity、MCP Servers、Preset Manager、Conversation History 等管理内容收进折叠区
- New Chat 先创建 session-only pending thread，第一次成功 plan 后写入 `.sci-station/agent/threads.jsonl`
- prompt draft 先按 project/thread 保存在 App session 内，避免切换项目或 thread 后立即丢失
- 预留 disabled Auto Run Loop 入口，提示未来连续 agent loop 只自动执行 read-only tools，workspace 写入仍逐项审批；停止条件包括最大轮数、最大工具调用数、连续失败、等待写入审批和用户手动 stop
- Plan UI 展示 title、summary、risk、steps、tool calls 和 final response draft，可从历史 run 重新打开查看
- Permission Dock 展示 tool risk、permission key、matched/default policy、path preview、allow once、deny、correction feedback 和 session-scoped approval 草案入口；写入工具默认 ask，read-only 工具显示 auto-allow 且保留审计
- 执行结果显示 success/error、message 和 modified paths，并与 permission/session events 交叉显示
- 每次 plan-only 或 approved execution 写入 `.sci-station/agent/runs.jsonl`，并把 user message、assistant summary、permission requested/resolved、hook result、tool completed/failed 写入 `.sci-station/agent/session_events.jsonl`
- AI Lab 读取更长 run history，并按 Sidebar project conversation / current thread 过滤显示；损坏 JSONL 行不会阻止历史读取
- Thread 支持重命名、归档隐藏、空 draft 丢弃；历史 unthreaded project runs 可手动整理为新 thread 或加入当前 thread
- Prompt draft 按 project/thread 持久化到 `.sci-station/agent/drafts.json`，切换项目或 thread 后可恢复
- 历史 run 可将 prompt 复制到 New Chat 复用，但不会自动执行工具
- Agent Platform V1 core 已加入 Swift-native 底座模型：agent profile、subagent profile、allow/ask/deny permission rule、hook definition/result、plugin manifest、command template、skill manifest、MCP server configuration、append-only session event，以及 Provider V2 request/response skeleton；OpenAI-compatible Provider V2 wrapper 已可生成 chat/tool payload，主 plan path 仍保留稳定 `LLMProvider.complete`
- AI Lab 可展示和临时禁用 `SessionStart`、`PreToolUse`、`PostToolUse`、`Stop` hooks，hook result 进入 session event timeline
- MCP UI 先展示 product preset template 与 local workspace config 的边界、enabled 状态、local command/remote URL、allowed tools、timeout 和 credential reference count；本阶段不启动 MCP server，写入或外部 side-effect MCP tools 仍必须进入 permission layer
- 当前 `.claude` hooks、skills 和 `.mcp.json` 作为工作区级 prototype；产品化路径是迁移到 Sci-Station 内置 preset registry、permission layer、hook engine 和 MCP 配置 UI
- `.sci-ai/sci-station/presets/research-core/` 已提供可进 GitHub 的 research-core preset；`.sci-ai/workspace.local/`、`.claude/` 和 `.mcp.json` 被视为本机配置并由 gitignore 排除
- Agent thread log、run log、workspace preferences、LLM settings 等路径信息集中在 Settings

### 12. 核心验证

仓库中包含独立的 SwiftPM 可执行验证器，用于验证核心文件系统与元数据逻辑。

当前覆盖的检查包括：

- 工作区创建后结构完整
- 旧工作区打开时自动补齐缺失目录和占位文件
- Project Overview 所需 `data/`、`figures/` 和 `wiki/projects/` 种子文档会自动创建或补齐
- Markdown snippets 配置文件会自动创建或补齐，并支持自定义触发词加载
- Materials 扫描只包含用户材料路径，会隐藏 settings 和点号开头的内部文件，并识别 Python 文件
- 批量链接输入解析会分割常见粘贴格式并去重
- VS Code bridge 会为 Python material 写入可运行 task 与 bridge 状态文件
- 最近 workspace bookmark 失效时自动清理
- WorkspacePreferencesRepository 保存和读取可往返
- citekey 生成规则正确
- meta.yaml 编解码可往返
- PaperRepository 保存、读取、删除和 nested collection 加载可往返，并兼容 `library/papers` / `raw/papers`
- ProjectPaperLinkRepository 可保存项目-论文关系，并在加载论文时叠加到 Paper metadata
- PaperAnnotationsRepository 可读写 `annotations.md`
- TodoRepository 保留 priority、notes、related paper ids 和 Reminders 映射字段
- Agent plan parser、tool approval、Agent run log/history、project conversation filtering、thread archiving、prompt draft persistence、approved execution、Agent Platform core model、permission matcher、hook engine、plugin/skill/MCP schema、session event log 和 Provider V2 request model
- LibrarySearchService 覆盖 DOI、abstract、BibTeX 等扩展字段
- PDF 导入后在 `library/papers` 生成 `paper.md` 和 `figures/`
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
- 打开 Materials，确认 code/figures/data/outputs 可浏览，settings 和点号开头文件不会显示。
- 在 Materials 里选择代码或图片文件，确认可预览、Reveal in Finder，并可用 VS Code 打开。
- 在 Materials 里选择 Python 文件，确认可切换运行来源、创建 `.venv`、准备 VS Code task，并可用 Terminal 运行。
- 在 Library 的 Add by Link 中粘贴多条 DOI/arXiv/URL，确认显示解析数量，Import All 后成功项进入 Library，失败项留在输入框。
- 在 Projects 中确认项目介绍以 Markdown preview 显示，AI Knowledge Workspace 收束 paper notes/concepts/methods/gaps。
- 在 Wiki 中切换 Source、Preview、Split，确认公式如 `$$E=mc^2$$` 可渲染，右键菜单可切换 Split。
- 在 Wiki 中修改页面后确认出现 Unsaved，按 `Cmd+S` 可保存，切换页面前会提示未保存 draft。
- 在 Wiki 源码模式输入 `;eq`，确认会展开为公式块；打开 `settings/markdown_snippets.yaml` 可自定义 snippets。
- 在 Library 按 `Cmd+F`，确认搜索框聚焦并显示过滤 chip；删除论文确认显示实际相对路径。
- 在 Library 中使用 Columns 菜单调整可见列，点击排序列标题按钮或 Columns 菜单中的 Sort 项，确认排序写入 `workspace_preferences.yaml`。
- 在 Reader 按 `Cmd+F`、`Cmd+G`、`Shift+Cmd+G`，确认搜索栏和下一处/上一处查找可用。
- 重命名 collection 后确认该 collection 下论文仍可显示。
- 在 Reader 的 Notes 面板保存文字，确认对应论文目录的 `annotations.md` 更新。
- 在 Reader 的 Citations 面板复制/导出 BibTeX，确认剪贴板和 `.bib` 文件内容正确。
- 新建 todo 并发布到 Apple Reminders，确认 `tasks/todos.yaml` 写入 `external_source` 和 `external_identifier`。

## 尚未完成的部分

- 旧 `raw/papers` 迁移已支持 copy-only dry-run、确认执行和 JSON 报告；仍需更完整的冲突解决与历史报告浏览 UI
- Project Overview 的项目配置模型、阶段状态和核心论文拖拽排序
- 项目-论文关系 UI 已切到 `ProjectPaperLinkRepository` 第一写入路径；仍需更完整的关系历史和批量编辑
- Library 原生表格体验 V1 已完成：SwiftUI `Table`、排序模型、selection 同步、多选、Copy Citation、Copy BibTeX 和低风险批量 BibTeX 导出；列拖拽/任意列顺序在 SwiftUI `Table` 版本中暂停，后续可评估 `NSTableView` wrapper
- AI Lab 后续增强：将 Agent Platform V1 core 接入 UI 的 preset/provider 状态、permission dock、hook activity、MCP server 状态、更多工具、计划导入和有限轮次 Agent loop
- Markdown renderer 的离线资源打包、snippet 图形化管理和更完整编辑器快捷键
- SQLite/FTS 统一搜索索引和增量更新
- Apple Reminders 双向同步、完成状态回写和冲突选择 UI
- DOI、arXiv、INSPIRE provider 的固定 fixture 回归套件
- Reader Tasks 面板的完整编辑、完成和筛选能力
- Workspace 最近列表和 workspace 级共享视图配置 UI
- VS Code / VSCodium 的深度联动：自动触发 task、kernel、diagnostics、terminal 输出和文件状态同步
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
├── LLM/                LLM 配置、Provider V1/V2 抽象、提示词和写回服务
├── Markdown/           Markdown、frontmatter、wikilink、backlink 支持
├── MetadataProviders/  DOI、arXiv、INSPIRE provider 与 mapper
├── PDF/                PDFKit Reader 和 PDF 打开协议
├── Tags/               Tag 定义与仓库
├── Tasks/              Todo 模型与仓库
├── UI/                 侧边栏、Projects、Library、Dashboard、Inspector 等 SwiftUI 视图
├── Wiki/               Wiki page 生成服务
├── Workspace/          工作区模型、偏好、bookmark 持久化
├── Agent/              Agent run/thread、tool、permission、hook、plugin/MCP、session event 模型
├── ContentView.swift   主界面入口
└── Sci_StationApp.swift
Tools/
└── SciStationCoreTestRunner/
DOC/
├── Proposal.md
├── Proposal5.md
├── Proposal6.md
├── Proposal7.md
├── Proposal8.md
├── Proposal9.md
├── Proposal10.md
└── Proposal11.md
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
- 任务书 8：[DOC/Proposal8.md](DOC/Proposal8.md)
- 任务书 9：[DOC/Proposal9.md](DOC/Proposal9.md)
- 任务书 10：[DOC/Proposal10.md](DOC/Proposal10.md)
- 任务书 11：[DOC/Proposal11.md](DOC/Proposal11.md)
- 任务书 17：[DOC/Proposal17.md](DOC/Proposal17.md)
- 任务书 18：[DOC/Proposal18.md](DOC/Proposal18.md)
- 任务书 19：[DOC/Proposal19.md](DOC/Proposal19.md)
