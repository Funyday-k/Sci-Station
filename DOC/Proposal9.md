# 任务书 9：Markdown 工作台、AI 产物收束与项目级知识生产

## 审阅意见

任务书 8 规划了项目层结构化和 artifact workflow。本轮实际优先级发生变化：用户更明确地指出，Sci-Station 现在的一级导航过多，Papers、Concepts、Methods、Gaps 等很多内容实际上是 AI 帮助生产的知识产物，应收束到 Project/Wiki 的工作流里；同时 Wiki 和 Project 都需要真正可用的 Markdown 渲染与编辑体验。

因此本轮先完成导航收束、Project 前置、Markdown preview/split、公式渲染和 snippets 底座。任务书 9 应承接下一步：把 Markdown 工作台从“能用”推进到“高效写作和科研知识生产”。

## 本轮已实施

1. Library 默认列加入 Tags。
2. Sidebar 一级导航将 Projects 放到第一位。
3. Sidebar 收束 Papers、Concepts、Methods、Gaps、Graph 等分散入口，保留 Projects、Library、Inbox、Wiki、Tasks、AI Lab。
4. Project Overview 新增 AI Knowledge Workspace，集中进入 paper notes、concepts、methods、research gaps 和 AI Lab。
5. Project Brief 改为 Markdown preview 渲染，不再只显示源码摘录。
6. Wiki 编辑器新增 Source、Preview、Split 三种模式。
7. Wiki 编辑区右键可切换 Source Only、Preview Only、Split Source / Preview。
8. 新增轻量 WebKit Markdown preview，使用 marked + DOMPurify + KaTeX 渲染 GFM、表格、代码块、图片和公式。
9. 新增 `settings/markdown_snippets.yaml`，支持 workspace 自定义 snippets。
10. 新增默认 snippets：`;h2`、`;eq`、`;fig`、`;todo`、`;paper`。
11. 输入触发词位于文档末尾时会自动展开 snippet，也可通过 Snippets 菜单插入。
12. Core Test Runner 覆盖 snippets 文件创建、回填和自定义加载。

## 下一轮目标

### 目标 1：离线 Markdown 渲染资源

- 将 marked、DOMPurify、KaTeX 资源打包到 App 或 workspace cache。
- 网络不可用时 Preview 仍可渲染 Markdown 和公式。
- 保持 WebKit preview 的安全边界，继续使用 DOMPurify 或等价 sanitizer。

### 目标 2：Snippet Manager UI

- 在 Settings 或 Wiki 中提供 snippets 管理界面。
- 支持新增、删除、排序、编辑 trigger/title/body。
- 支持导入/导出 snippets 配置。
- 支持对 `${cursor}`、`${date}`、`${paper.citekey}` 等变量做替换。

### 目标 3：更完整的 Markdown 编辑能力

- 增加常用命令：加粗、斜体、行内代码、代码块、公式块、表格、任务列表、引用块。
- 增加快捷键和命令菜单。
- 支持选中文本包裹格式。
- 支持保存前 lint：未闭合代码块、未闭合公式块、坏链接提示。

### 目标 4：项目级 AI 产物工作流

- AI Lab 的输出默认写入 project-scoped 文档，而不是散落在一级栏目。
- Project Overview 显示 AI-generated paper notes、concepts、methods、gaps 的最近更新。
- 支持从 Project Overview 一键生成或刷新项目 brief/core paper synthesis。

### 目标 5：Project Profile 与 Pinned Core Papers

- 承接任务书 8 的 Project Profile V1。
- 支持 pin/unpin core papers。
- Project Overview 以 profile + pinned papers 为主，自动推导为兜底。

## 验收标准

1. 断网后 Wiki Preview 仍能渲染 Markdown 和公式。
2. Snippet Manager 可保存自定义 snippets，重启后保留。
3. Source/Preview/Split 模式在 Wiki 中稳定切换，不丢失未保存文本。
4. 常用 Markdown 命令能通过按钮、菜单或快捷键插入。
5. Project Overview 能显示 AI 产物最近更新。
6. AI Lab 输出能写入 Project/Wiki 约定位置。
7. Core Test Runner 覆盖 snippets 变量替换和配置往返。
8. Xcode macOS build 通过。

## 风险与约束

- WebKit preview 需要继续隔离和净化 HTML，不能直接信任用户 Markdown。
- 公式渲染要支持科研常用语法，但不应让渲染器成为重量级浏览器应用。
- snippets 的自动展开需要避免误触发，后续应加入开关和触发边界规则。
- AI 产物收束不能删除已有 wiki 目录，只调整入口和默认写入路径。
