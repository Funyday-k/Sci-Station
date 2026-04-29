# Sci-Station macOS 软件设计审阅意见

本文从 macOS 桌面软件设计视角审阅 Sci-Station 当前代码框架、信息架构与主要 UI 实现。审阅范围包括 `README.md`、`ContentView.swift`、`Sci_StationApp.swift`、`AppViewModel.swift`、`MainShellViews.swift`、`LibraryViews.swift`、`ProjectOverviewView.swift`、`MaterialsView.swift`、`WikiViews.swift`、`MarkdownEditorView.swift`、`SettingsViews.swift`、`EmbeddedPDFReaderView.swift` 以及 Workspace / Library / Repository 等核心层。

## 总体判断

Sci-Station 已经具备清晰的产品方向：它不是单一 PDF 管理器，而是一个本地优先的科研工作站，把论文库、项目、Wiki、材料、任务、PDF 阅读和 LLM 辅助放在同一个 macOS 应用里。当前架构采用 SwiftUI + MVVM + Service/Repository + actor 的组合，数据层坚持文件系统优先，Markdown / YAML / PDF 都落在用户可见目录中。这一方向非常适合科研用户，也符合 macOS 上“用户拥有文件、应用组织文件”的心智模型。

从产品形态看，项目已经完成了从“功能原型”到“可使用工作台”的关键骨架：三栏 `NavigationSplitView`、全局 Library、项目 Overview、Materials 浏览、Wiki 编辑、Dashboard、Settings、PDFKit Reader、Finder / VS Code / Apple Reminders 联动都已经出现。下一阶段最重要的不是继续堆功能，而是把它打磨成更像一个成熟 Mac 应用：更原生的导航与表格行为、更完整的菜单和快捷键、更可靠的窗口模型、更明确的信息层级，以及更细致的错误恢复。

## 已有设计优势

1. **本地优先的数据模型是产品核心优势。** Workspace 使用用户可见目录，论文、标注、Wiki、任务、偏好都用普通文件组织，这让用户可以备份、版本控制、外部编辑和迁移。这个方向应继续保持，不建议过早把核心数据隐藏进私有数据库。

2. **代码分层方向正确。** `WorkspaceService`、`PaperRepository`、`ProjectPaperLinkRepository`、`MarkdownRepository`、`TodoRepository` 等承担了明确的文件读写职责，SwiftPM target 又把核心逻辑从 UI 中排除出来，方便用 `SciStationCoreTestRunner` 做行为验证。

3. **macOS 原生能力已经被纳入设计。** 当前已经使用 security-scoped bookmark、Finder reveal、PDFKit、EventKit、Keychain、Settings scene、菜单命令和系统打开方式。这些能力是 Mac 应用体验的基础，后续应把它们从“能调用”提升到“符合 Mac 用户预期”。

4. **研究项目的工作流表达有潜力。** Projects Overview 把 proposal、core papers、data、code、figures、outputs、tasks 和 shared context 组织成研究流程，比传统文献管理器更贴近科研过程。

5. **PDF Reader 与论文元数据闭环已经成形。** 从 Library 双击进入内置 PDF Reader，Reader 侧栏提供 Metadata、Notes、Tasks、Citations、Links、Abstract、Files，这是很好的“阅读中工作台”方向。

## 高优先级改进建议

### 1. 让导航更符合 macOS Sidebar 语义

当前 Sidebar 是自定义 `VStack` / `ScrollView` / `onTapGesture` 组合，视觉上接近侧边栏，但缺少 `List(selection:)`、Outline、键盘选择、焦点环、VoiceOver 语义和系统选择行为。项目、Library folders、Tags 又都放在同一个手写侧栏里，随着项目和文件夹增长，用户会很快遇到层级拥挤和选择状态不清的问题。

建议：

- 将主侧边栏逐步迁移为 `List(selection:)` + `Section` + `DisclosureGroup` / `OutlineGroup`，保留当前视觉风格但交给系统处理选择、键盘、可访问性和高亮。
- 明确区分“当前项目”“当前页面”“Library filter”三种状态。现在 project 单击是 focus，双击才 open，这在 Mac 上不够直观，建议改为单击即进入项目 Overview，并在内容区顶部显示项目 breadcrumb。
- 侧栏底部的 Settings 可以保留，但全局 Settings 也应符合 macOS 菜单和 Settings scene 的入口预期，避免同一设置有两个不完全一致的入口。

### 2. Library 应改造成真正的 Mac 表格体验

Library 是应用的核心生产力页面，但当前表格是自定义 header + `ScrollView` + `LazyVStack`。这能快速实现列显示和拖拽排序，但距离 macOS 用户期待的表格还有差距：列宽调整、排序、多选、键盘上下移动、空格预览、复制字段、批量操作、拖拽到文件夹、右键菜单作用于多选项等都会变得困难。

建议：

- 优先评估 SwiftUI `Table` + `TableColumn`，如果受限再考虑轻量 `NSTableView` wrapper。Library 是最值得引入原生表格能力的地方。
- 增加排序模型：标题、作者、年份、更新时间、评分、优先级、阅读状态都应可排序，并把排序状态写入 workspace preferences。
- 支持多选和批量操作：移动文件夹、加标签、加入项目、标记 core、导出 BibTeX、删除。
- 搜索框建议接入 `.searchable` 或至少提供 `Cmd+F` 聚焦搜索；过滤条件应该以 token / chip 形式展示，让用户知道当前列表为什么变少。
- 删除提示文案仍提到 `raw/papers`，但 README 显示新导入已进入 `library/papers`。建议统一为“从 workspace 中删除该论文目录”，并显示实际相对路径。

### 3. 补齐菜单栏、快捷键和命令体系

当前 `Sci_StationApp.swift` 只有 Workspace 和 Paper 两个自定义菜单，且快捷键很少。Mac 用户会自然尝试 `Cmd+O` 打开、`Cmd+N` 新建、`Cmd+S` 保存、`Cmd+F` 搜索、`Space` 预览、`Cmd+,` 设置、`Cmd+I` Inspector、`Cmd+W` 关闭窗口等。

建议：

- 建立完整 Command 设计：Workspace、Project、Paper、View、Navigate、Window、Help。
- 关键命令建议先补：New Project、Create/Open Workspace、Import PDF、Add by Identifier、Save Metadata、Save Wiki Page、Search Library、Open in Reader、Open External PDF、Reveal in Finder、Toggle Inspector、Toggle Reader Sidebar。
- 将 Reader 搜索绑定到 `Cmd+F`，页码跳转和 zoom 也应支持快捷键。
- 对所有 destructive command 保持菜单 disabled 状态和确认流程一致。

### 4. 重新设计窗口与多任务模型

当前 App 使用单个 `WindowGroup` 和一个全局 `AppViewModel`。这对原型简单，但科研工作常常需要同时比较多个项目、多个 PDF、一个 Wiki 页面和一个 PDF。macOS 用户也会期待可以打开多个窗口或独立 Reader 窗口。

建议：

- 将全局服务和每个窗口的 UI state 分开。workspace 数据可以共享，但 selected section、selected paper、reader state、markdown draft 等应更接近 per-window state。
- 增加“Open Reader in New Window”或“Open Paper in Separate Window”，用于并排阅读论文。
- 支持恢复窗口状态：最近 workspace、当前项目、最近页面、Reader 页码、Wiki 编辑模式、Library 列宽和排序。
- 如果暂不支持多窗口，应在产品层明确这是单工作台模式，并确保 Reader 切换不会让用户丢失 Library 上下文。

### 5. Settings 页面需要从长表单变成 macOS 偏好面板

当前 Settings 把 Research Root、Projects、Library、Migration、Tasks/Reminders、LLM、Settings Files 放在一个长 ScrollView。功能可用，但长期会变成“管理后台”，不太像 Mac 设置面板。

建议：

- 使用 Settings scene 内的分组导航或 toolbar tabs：General、Library、Projects、Integrations、AI、Advanced。
- 将 Legacy migration 放入 Advanced 或独立 sheet，显示 dry-run 结果、冲突处理和报告入口。
- 对 Clear Recent Workspace、Delete Folder、Copy Ready legacy papers 等操作加更明确的风险说明和二次确认。
- LLM API Key 存 Keychain 是正确方向，UI 上应明确“不会写入 workspace 明文文件”。

### 6. 强化错误恢复与长任务反馈

当前错误主要通过全局 alert 呈现，长任务以 `ProgressView` 和状态文字为主。随着远程导入、PDF 下载、LLM 调用、Reminders 同步、Legacy migration 增多，单一 alert 会让用户难以判断哪个对象失败、是否可重试、失败后数据是否安全。

建议：

- 为导入、迁移、LLM、Reminders、文件保存建立局部错误状态，并提供 Retry、Reveal Log、Copy Error、Open Target Folder 等 recovery action。
- 对批量导入提供可展开的结果清单：成功、跳过、失败、失败原因、可重试项。
- 对文件写入和删除提供更清晰的 atomic / backup 策略。删除论文目录前可考虑移入 workspace 内 Trash 或 `.sci-station/trash`，再提供清空操作。

## 中优先级设计建议

### 1. Onboarding 应少展示目录树，多解释用户收益

空 workspace 页面现在展示大量目录和 seeded files，这对开发者有帮助，但对普通用户偏技术。建议把第一屏改成“创建研究根目录 / 打开已有根目录 / 从 Zotero 或 PDF 文件夹开始 / 查看示例项目”，目录结构放到 Advanced 或 Help 中。

### 2. Project Overview 需要更强的“下一步”导向

当前 Overview 有指标卡、Project Brief、Core Papers、Project Documents、Workflow tiles。建议增加一个明确的 Next Actions 区域，例如“补充 proposal、导入核心论文、添加第一个任务、打开 data/code 文件夹”。科研工作站的首页应帮用户继续推进研究，而不仅是展示入口。

### 3. Wiki 编辑器需要文档级编辑体验

当前 Markdown editor 已支持 Source / Preview / Split 和 snippets，这是好基础。建议补充：

- `Cmd+S` 保存、dirty indicator、关闭/切换页面前的未保存确认。
- 编辑器 line wrap、字体大小、字数/行数、插入 wikilink、快速打开页面。
- Preview 滚动同步和本地资源安全策略。
- snippets 图形化管理，减少用户直接编辑 YAML 的频率。

### 4. Materials 更适合接入 Quick Look 与文件监听

Materials 页面已经能预览 Markdown、Python、文本、图片和 PDF，并能打开 VS Code / Finder。建议继续 Mac 化：

- 使用 Quick Look 或 QuickLookThumbnailing 提供更接近 Finder 的文件预览。
- 接入 FSEvents 或目录监听，减少手动 Reload。
- 支持拖拽文件到 Materials、从 Materials 拖到 Finder / 邮件 / 其他 App。
- Python 运行结果目前更像桥接入口，后续可显示最近运行状态、日志位置和失败原因。

### 5. PDF Reader 可向“研究阅读器”深化

当前 PDFKit reader 已有页码、搜索、缩放、历史前进后退和右侧面板。建议下一阶段优先做：

- `Cmd+F` 搜索、Find Next/Previous、搜索结果计数。
- 页缩略图或 Outline 面板，用于长论文导航。
- Reader Notes 自动保存或显式 dirty 状态，避免用户以为输入已保存。
- 从 PDF 选中文本创建 note / task / citation snippet。
- 支持独立窗口和最近阅读队列。

## 架构层建议

### 1. 拆分过大的 AppViewModel

`AppViewModel` 当前承担 workspace、project、library、import、wiki、tasks、calendar、LLM、PDF reader、settings、migration 等大量状态和操作。对于早期原型这是有效的，但继续增长会降低测试性和 UI 变更速度。

建议逐步拆成：

- `WorkspaceCoordinator`：打开、恢复、权限、root compatibility。
- `LibraryViewModel`：列表、筛选、排序、选择、批量操作、导入状态。
- `ProjectViewModel`：当前项目、项目 registry、overview 数据。
- `WikiViewModel`：页面列表、草稿、保存、backlinks、snippets。
- `ReaderViewModel`：PDF 页面、搜索、侧栏、阅读状态。
- `SettingsViewModel`：偏好、迁移、集成状态。

不需要一次性重构。可以从 Library 和 Wiki 这两个 UI 状态最重的区域开始。

### 2. 保持文件优先，但建立版本化迁移策略

当前 YAML / Markdown 文件可见是优势，但也意味着格式升级需要严肃处理。建议为每类持久文件建立 schema version、迁移器和验证器，并在 Settings / Advanced 中提供“Validate Workspace”入口。

重点对象：

- `settings/workspace_preferences.yaml`
- `library/paper_index.yaml`
- `library/project_paper_links.yaml`
- `paper/meta.yaml`
- `tasks/todos.yaml`
- `settings/markdown_snippets.yaml`

### 3. 核心验证器可继续扩大到 UI 前的行为契约

`SciStationCoreTestRunner` 已经覆盖许多文件系统与元数据逻辑。建议继续补以下合同测试：

- Project link 与 paper metadata mirror 的冲突处理。
- Collection rename / move 后的引用一致性。
- Markdown backlinks 和 snippets 的边界情况。
- Remote import provider 的固定 fixture。
- Workspace migration 的 dry-run 与 report 格式。

## 视觉与交互细节建议

1. **统一标题层级。** 有些页面使用 `.largeTitle`，Settings 使用 42pt rounded bold，Empty Workspace 也使用 42pt。建议建立统一页面标题样式，避免设置页显得比核心工作页更重。

2. **减少纯图标按钮。** 侧栏顶部和 Reader 工具栏大量使用 icon-only button。虽然有 `.help`，但仍建议补充 accessibility label，并在关键位置使用 `Label` 或可配置的文本显示。

3. **谨慎使用项目颜色作为大面积背景。** Project cards 和 Sidebar project group 使用项目色 opacity。建议检查深色模式、高对比度和不同 accent color 下的可读性。

4. **统一 primary action。** Library 的 Add by Link、Wiki 的 Save、Settings 的 Rename/Save、Materials 的 VS Code 都使用 prominent，但语义不完全一致。每个页面最好只有一个最主要的 prominent action。

5. **提供空状态的下一步操作。** Library、Wiki、Materials、Projects 的空状态应直接提供 Import / Create / Open Folder 等下一步，而不仅是说明文字。

## 建议的实施顺序

1. **第一阶段：Mac 基础体验补齐。** 完成菜单命令、快捷键、`.searchable`、Reader `Cmd+F`、Wiki `Cmd+S`、删除文案修正、关键 icon button accessibility label。

2. **第二阶段：Library 原生化。** 将论文列表迁移到 `Table` 或 `NSTableView` wrapper，加入排序、多选、批量操作和列宽持久化。

3. **第三阶段：导航和窗口模型。** 侧栏迁移到 selection-based List / Outline，明确 current project 和 current page，增加独立 Reader window。

4. **第四阶段：Settings 和错误恢复。** Settings 分区，迁移/导入/LLM/Reminders 提供局部错误、结果报告和重试。

5. **第五阶段：科研工作流深化。** Project Overview 加 Next Actions，Wiki 加更完整编辑体验，Materials 加 Quick Look / FSEvents，PDF Reader 加选中文本到 note/task。

## 结论

Sci-Station 当前最有价值的部分不是某一个单点功能，而是“本地文件系统 + 科研项目工作流 + Mac 原生能力”的组合。代码框架已经足够支撑继续迭代，但 UI 需要尽快从自定义原型控件转向 macOS 用户熟悉的系统行为，尤其是 Sidebar、Table、Menu Commands、Window 和 Settings。只要下一阶段优先打磨这些 Mac 基础体验，Sci-Station 会更像一个可信赖的日常科研工具，而不是功能很多但操作仍偏原型的实验应用。
