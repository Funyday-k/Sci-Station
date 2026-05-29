# Sci-Station 长期规划与项目全局审视

更新时间：2026-05-26

> 本文件从今天起不再作为“下一个任务书列表”，而是作为 Sci-Station 的全局产品/工程状态地图。
> 旧的线性 P50 / P51 / P52 任务书已经不能代表当前项目状态：P50 的核心垂直切片已落地，P51/P52 的方向仍有价值但需要重新审视，不应继续以旧草案推动实施。

---

## 一、当前判断

Sci-Station 不是固定功能集合，而是一个 **可配置、可审计、本地优先的科研工作站**。

经过 P36–P50 与多轮 UI / 性能 / 测试修复后，项目已经从“持续铺新功能”进入“整体性打磨”阶段。下一阶段优先级不是继续增加大任务书，而是：

1. 梳理已经落地的能力边界。
2. 修复文档与代码状态不一致的问题。
3. 补齐中文、本地化、测试流程、性能与可用性债务。
4. 把 Recommendation / Queue / Reading Plan / Graph / AI Lab 这些已经存在的能力打磨成连续工作流。
5. 重新评估 Timeline、Milestone、Calendar Sync、Writing / Code / Theory 等未来方向，而不是沿用过期任务书。

---

## 二、已落地能力总览

| 能力域 | 当前状态 | 成熟度 | 主要缺口 |
|---|---|---:|---|
| Workspace / Module System | Workspace 模板、创建向导、模块声明、依赖 gating、project override、settings 写回已形成主干 | 高 | GUI spot check 与文档同步仍需补；模块说明与中文文案不完整 |
| Shell / ProjectSpace / Toolbar | 顶层 sidebar 收敛、ProjectSpace tab、ToolbarModel / CommandDispatcher、右栏 sticky policy 与响应式策略已落地 | 高 | 仍需做全局 UI 一致性与窄窗口/中文截断回归 |
| Home / Project Dashboard | Today / Active Projects / AI Review、Home widgets、Project Dashboard、widget drag/resize/persistence 已落地 | 高 | Widget 文案、空状态、性能与复杂交互仍需持续回归 |
| Library / PDF / Wiki / Materials / Tasks / Calendar | 基础科研工作区模块可用，支持本地文件、PDF 阅读、Wiki、待办与日历基础能力 | 中高 | 旧模块手测用例需要刷新；中文、错误态与跨模块入口需统一 |
| AI Lab / Agent Runtime | 多 provider、工具调用、论文读取、Markdown 渲染、Wiki 写回、Permission Dock、Draft Inbox、debug 事件链已建立 | 中高 | Provider 失败恢复、长上下文、中文交互、真实模型手测仍需系统化 |
| Evidence / Artifact / Permission | 写入前审批、本地 artifact、evidence refs、debug bundle、权限边界已成为核心安全模型 | 高 | 新功能必须继续接入，不允许绕过 Draft Inbox / Permission Dock |
| Research Graph / Graph Workflows | Graph 数据模型、citation graph、Graph UI、7 个 graph-backed agent tools 与 graph_insight workflow 已落地 | 中高 | MT17 手动回归需要补；大图性能、解释 UI 与 recommendation 联动可继续增强 |
| Research Queue | P48 已落地：Queue Store、YAML、ProjectSpace Queue tab、Library 菜单、Home / Project Dashboard 接入 | 高 | 中文细节、批量操作、Recommendation / Reading Plan 闭环继续打磨 |
| Recommendation | P49 Core 已落地，并已有 Recommendation UI、arXiv refresh、category selector、snapshot/history 与 AI evaluation 路径 | 中 | Settings / Scheduler / live retrieval 策略、空状态、失败态、API key 提示仍需产品化 |
| Reading Plan | P50 垂直切片已落地：ReadingPlanStore、YAML、deterministic generator、ProjectSpace 页面、Home / Project Dashboard active plan 接入 | 中 | Weekly Review 仍未完整产品化；计划编辑、复盘、中文与空状态需打磨 |
| Plugin / Contribution Catalog | Workspace contribution catalog、toolbar command catalog、plugin registry contribution 查询已接入 | 中高 | 文档需要解释新架构；第三方插件仍不是当前目标 |
| Testing / AI Usage Testing | Manual Test Protocol、MT00–MT99、SciStationCoreTestRunner、AgentRuntime pytest、P-AT scenario skeleton 与 live smoke 已有基础 | 中 | 手测执行记录不足；P-AT 仍受 AX 权限影响；视觉通道与 CI 脚本待补 |
| Performance / Launch / Windowing | Launch/window 多轮修复已完成；Library/Home/Shell/Agent streaming 已做 Phase 1/2 性能优化 | 中 | AppViewModel 仍过大；SwiftUI 广域 invalidation 是后续主要架构债 |
| Localization | P43.8 建立 L10n catalog 与局部中文修复，Queue/Home 部分已修 | 中低 | 很多页面仍有英文硬编码、截断、语序不自然或未接入本地化 key |

---

## 三、已完成能力详述

### 1. Workspace 与模块系统

已完成：

- **Workspace 创建与模板**：Minimal / Literature Review 等模板通过创建向导生成确定性目录与 `workspace_modules.yaml`。
- **Module Registry**：模块声明包含 routes、project tabs、workflows、artifact kinds、write paths、依赖关系。
- **Settings → Modules**：支持启用/禁用、pin、dependency warning、directory repair、project-level override。
- **Contribution Catalog**：模块/插件贡献的 route、tab、workflow、artifact descriptor 已有集中 catalog，旧 registry API 作为兼容层继续存在。

当前问题：

- **文档漂移**：旧任务书仍以“待实现”口吻描述已完成能力。
- **用户解释不足**：模块启用、workflow 可见、AI credential 配置之间的关系还需要更清晰的 UI 文案。
- **手测不足**：P40/P41/P43 的 GUI spot check 需要补一轮，不只依赖自动化。

### 2. Shell、ProjectSpace 与 Home

已完成：

- **顶层导航收敛**：Home / Projects / Library / Calendar / AI Lab / Settings 成为稳定主入口。
- **ProjectSpace 容器**：项目内功能通过模块贡献 tab 呈现，包括 Overview / Papers / Queue / Reading Plan / Wiki / Tasks / Calendar / Graph / Recommendation 等。
- **ToolbarPolicy / ToolbarModel**：页面动作集中建模，ContentView 渲染 primary / overflow actions，通过 `AppToolbarCommandDispatcher` 分发。
- **Right Rail**：Inspector / AI rail 具备 sticky 语义，可被用户显式打开/关闭，不再被路由 suggestion 反复覆盖。
- **Home Widgets**：支持布局持久化、drag push-aside、1×1 / 1×2 / 2×2 等尺寸、响应式列数与模块过滤。

当前问题：

- **中文完整性不足**：Home、Settings、Recommendation、Reading Plan、Graph、AI Lab 中仍有英文硬编码或英文语序。
- **UI 一致性债务**：新旧页面的标题区、空状态、toolbar spacing、右栏行为仍有差异。
- **SwiftUI identity / animation 风险**：已修过 `ForEach(id: \.self)` duplicate ID 与 widget drag 回弹问题，后续必须继续用测试保护。

### 3. Library、PDF、Wiki、Materials、Tasks、Calendar

已完成：

- **Library**：论文导入、表格、搜索、排序、多选、metadata、项目链接、队列入口等主路径已建立。
- **PDF Reader**：PDF 阅读、annotation、paper context、Reader 与 Wiki/Library 之间的跳转能力存在。
- **Wiki / Materials**：项目 Wiki、文件预览、Markdown 渲染、Wiki 写回与 local-first 文件布局已成形。
- **Tasks / Calendar**：基础 todo、due date、calendar yaml 与 Dashboard 消费路径可用。

当前问题：

- **旧模块测试文档需要刷新**：MT01–MT06 多数仍描述基础主路径，没有反映 Queue、Reading Plan、Graph、Toolbar、Right Rail 等新连接。
- **Calendar 仍偏本地**：外部 Calendar / Reminders 同步不是当前主线，未来必须重新设计权限与冲突处理。
- **空/坏文件恢复需回归**：坏 YAML、缺 PDF、移动 workspace、bookmark 失效等场景要在 release hardening 中集中跑。

### 4. AI Lab、Artifact 与权限闭环

已完成：

- **Agent Runtime 主链路**：provider selection、sidecar/runtime health、tool loop、context budget、paper tools、graph tools、recommendation tool 等均已建立。
- **对话与线程**：thread/project affinity、归档、消息持久化、失败恢复、中文 IME、tool picker 等已多轮修复。
- **Markdown 渲染**：AI Lab 与 Wiki/Paper preview 支持本地 Markdown/KaTeX/GFM 渲染路径，避免在线 CDN 依赖。
- **Draft Inbox / Permission Dock**：AI 写入 workspace 前必须形成 draft 或 approval request；写入路径与 rollback hint 可审计。
- **Debug 事件**：`AppDebugEventName` 与 debug JSONL 已成为 UI 自动化和问题定位的共同通道。

当前问题：

- **真实 provider 回归不足**：自动化覆盖 contract，但真实模型下的失败模式、空响应、长工具链仍需手测。
- **中文科研对话体验**：提示语、工具结果摘要、错误解释与 approval 文案仍需中文产品化。
- **工具安全边界需保持**：任何新工具都必须声明 risk、permission key、target path 与 artifact kind。

### 5. Research Graph 与 Graph Workflows

已完成：

- **Research Graph**：统一 paper / project / concept / method / claim / evidence / artifact / run 等节点与关系。
- **Citation Graph**：本地 BibTeX、paper metadata、paper.md references 的 citation 解析与 unresolved placeholder 机制。
- **Graph UI**：Paper Neighborhood、Project Citation Graph、Theme Cluster、Evidence Support、Artifact Lineage 等视图。
- **Graph Agent Tools**：`find_missing_core_papers`、`generate_reading_path`、`detect_stale_citations`、`find_bridge_papers` 等 7 个 read-only 工具已接入。
- **Graph → AI Lab**：Graph UI action 可跳转 AI Lab，并以 `graph_insight` draft / artifact 进入审批与证据链。

当前问题：

- **Graph 大规模体验未充分验证**：节点多、引用不完整、布局截断、external placeholder 过多时的 UI 体验要回归。
- **MT17 待补执行记录**：文档有用例，但需要实际 run report。
- **与 Recommendation / Queue 的联动要打磨**：Graph insight 应该更自然地进入 Recommendation / Queue / Reading Plan，而不是散落在不同入口。

### 6. Research Queue

已完成：

- **Queue Store**：workspace / project scope、YAML 持久化、append / batch / reorder / status / remove / malformed yaml tolerance。
- **Queue UI**：ProjectSpace Queue tab、scope picker、status/source filter、Add-from-Library sheet、row actions、onboarding。
- **Library 集成**：单篇/批量论文加入 queue，状态切换可反向更新 queue。
- **Home / Project Dashboard**：Reading Queue card 已消费真实 queue entries。
- **自动化**：CoreTestRunner 覆盖 store、YAML、ingestor、home/project aggregation 与 debug scrub。

当前问题：

- **中文细节仍需查漏**：菜单、empty state、filter、status chip、错误提示需要完整中文审查。
- **跨功能闭环需增强**：Recommendation → Queue、Queue → Reading Plan、Reading Plan → Queue status 的路径已有基础，但用户心智仍需更清楚。

### 7. Recommendation

已完成：

- **Local-first scoring core**：配置、candidate gatherer、daily feed importer、text similarity、feature scoring、reason builder、snapshot/history。
- **Queue payload**：输出 `recommendation_note` / `queue_candidates`，可被 P48 Queue 通道消费。
- **arXiv 推荐路径**：已有 arXiv refresh client、分类选择、按日期抓取、历史去重、topK 扩展。
- **AI evaluation**：可调用已配置 provider 对标题/摘要进行评价；缺 API key 时只降级 AI evaluation，不阻塞基础推荐。
- **Recommendation UI**：ProjectSpace Recommendation 页面、field selector sheet、history/result pane、空状态与窗口布局已有多轮修复。

当前问题：

- **Settings / Scheduler 仍未产品化**：推荐频率、数据源、权重、topK、model 选择需要统一设置页。
- **外部请求策略需明示**：arXiv 是网络请求，必须有 opt-in、失败态、隐私说明和限频。
- **结果解释要继续打磨**：本地 score、AI evaluation、queue action、历史原因应统一展示，不让用户困惑“谁推荐的、为什么”。
- **推荐算法 V2 已单独立项**：见 `docs/development/RecommendationPaperRecommenderTaskbook.md`，聚焦 arXiv category 硬边界、关键词/种子论文软匹配、结构化 AI review、反馈闭环和 MMR 多样性重排。

### 8. Reading Plan

已完成：

- **ReadingPlan core**：`ReadingPlanStore`、`ReadingPlanYAMLCodec`、`ReadingPlanGenerator`、workspace/project scope。
- **生成与激活**：从 active queue entries 生成 deterministic weekly slots，支持 activate/archive/status/reorder。
- **Queue status sync**：slot 标记 reading / finished 时可同步回 ResearchQueueStore。
- **ProjectSpace UI**：Reading Plan 页面已可生成、激活、归档、更新 slot 状态。
- **Home / Project Dashboard**：Reading Plan widget 与 Current Reading Plan card 优先显示 active plan summary。

当前问题：

- **Weekly Review 未形成完整闭环**：复盘、carry-over、下周建议、AI weekly_review draft 还需要重新设计。
- **计划编辑体验偏基础**：日期、容量、手动插入/移除、与 todo/calendar 的联动仍是后续优化。
- **旧 `Proposal50.md` 已过期**：P50 不再作为未来任务书存在，状态以本文为准。

### 9. Testing 与 AI Usage Testing

已完成：

- **Manual Test Protocol**：定义 Skeleton / Happy Path / Edge / Acceptance Regression 流程。
- **MT 文档库**：MT00–MT20 与 MT99 已覆盖 Workspace、Library、Wiki、Tasks、AI Lab、Graph、Home、Queue、Recommendation 等模块。
- **Core 自动化**：`SciStationCoreTestRunner` 覆盖 module、toolbar、queue、reading plan、recommendation、graph、home widget 等核心逻辑。
- **AgentRuntime pytest**：Python runtime 与 UI test scenario loader / driver 基础测试存在。
- **P-AT 框架**：Scenario YAML、event/file assertions、AccessibilityDriver、drag support、debug test bridge、live smoke 部分通过。

当前问题：

- **手测报告不足**：很多 MT 有用例但没有最新 run report。
- **P-AT live smoke 仍不稳定**：3/5 live smoke 通过，2 条受 Accessibility trust 阻塞；这不是产品回归，但会影响自动化可用性。
- **视觉通道未完成**：SwiftUI warnings 已能抓取，但 screenshot baseline / visual diff / CI 脚本仍在后续。
- **测试文档需要重分层**：基础 MT、模块 MT、Release Gate、AI scenario 之间关系要简化。

### 10. Performance、Launch 与窗口

已完成：

- **Launch / window 修复**：主窗口尺寸、恢复、Splash、全屏行为、Recommendation 页面 titlebar/空状态布局已多轮修复。
- **Library 性能 Phase 1**：Library search/rows 改为局部 view model、debounced search、预计算 rows。
- **Home 性能 Phase 1**：Home reload watcher 合并、debounce、性能日志。
- **Shell 性能 Phase 2**：`AppShellRenderState` 集中派生 shell / toolbar / rail 状态，减少 body 中重复计算。
- **Agent streaming 性能 Phase 2**：streaming render cadence、live event polling、timeline rebuild 已降频。
- **周期性卡帧专项 Phase 2.5**：普通 Debug 使用不再默认启动 SwiftUI runtime warning 的 `OSLogStore` 轮询；Home / Project Dashboard 不再直接监听高频 Agent live events 或大型 `@Published` 数组，而是通过轻量 revision token 触发聚合刷新。
- **Reading 页面布局**：移除 nested ScrollView / infinite height，恢复自然纵向滚动。

当前问题：

- **AppViewModel 仍是最大架构债**：单个 `@MainActor ObservableObject` 拥有大量 `@Published` 字段并被深层 view 读取，普通 body re-evaluation 仍会被全局对象放大。
- **Phase 3 方向**：拆分 ShellStore / LibraryStore / HomeStore / AgentStore / ProjectSpaceState；Home / Dashboard 继续下沉为独立 snapshot store，深层 row/card 改传 immutable props + closures。
- **性能测试缺口**：目前多为 build + 手感验证，缺少稳定 Instruments / ETTrace / before-after 报告模板。

### 11. Localization 与内容质量

已完成：

- **L10n Catalog**：已建立基础 key registry、英文/中文解析与 fallback audit。
- **部分中文修复**：Queue、Home widgets、Toolbar、Shell 等高频路径已有多轮补齐。

当前问题：

- **大量硬编码英文仍存在**：尤其 Settings、Recommendation、Reading Plan、Graph、AI Lab 错误态与空状态。
- **中文不是逐字翻译问题**：需要针对科研工作流重写自然中文文案。
- **截断/布局回归**：中文更长，必须在 compact / narrow / right rail / toolbar overflow 下单独测试。
- **文档语言不一致**：任务书、MT、README、UI 文案需要统一术语，如 Research Queue / Reading Plan / Draft Inbox / Permission Dock。

---

## 四、近期主线：整体性打磨，而不是继续开新大功能

下一阶段建议命名为：

```text
Release Hardening / Product Polish Round A
```

目标不是“完成 P51/P52”，而是把现有产品打磨到可持续迭代的状态。

### A. 文档与规划收敛

- **删除过时任务书**：`Proposal50.md`、`Proposal51.md`、`Proposal52.md` 不再作为当前 planning source。
- **保留历史脉络**：P40–P49 仍在 `docs/development/Previous Proposal/` 作为历史实现记录；P50 状态由本文记录，不再维护旧草案。
- **建立能力地图**：长期规划只描述能力域、状态、缺口和优先级，不写过细伪代码。
- **重整 MT 索引**：把 MT 文档分成 Core Smoke、Module Acceptance、Release Regression、AI Scenario 四类。

### B. 中文与本地化专项

- **建立硬编码清单**：用现有 localization audit 找出 SwiftUI `Text("...")`、按钮、tooltip、empty state、alert、菜单。
- **优先级**：
  1. Shell / Toolbar / Sidebar / Right Rail。
  2. Home / Queue / Reading Plan / Recommendation。
  3. AI Lab / Permission Dock / Draft Inbox。
  4. Settings / Graph / PDF / Wiki / Library edge states。
- **验收**：每个页面至少跑 English + 简体中文 + compact/narrow 一轮截图/手测。

### C. 性能与架构专项

- **短期**：继续清理 body 内排序/过滤/映射；避免深层 view 读取整个 `appModel`。
- **短期卡帧修复**：排查并关闭非必要周期任务；普通 Debug 不启动 UI 自动化专用 log polling；Home / Project Dashboard 使用 revision token 而不是直接监听高频 Agent 事件。
- **中期**：拆分 `AppViewModel` 的高频状态，优先从 Shell、Library、Home、Agent 四块下手。
- **中期拆分顺序**：先抽 `HomeSnapshotStore` / `ProjectDashboardStore`，再抽 `AgentSessionStore` 与 `LibraryListStore`，最后收敛 Shell / ProjectSpace route state。
- **约束**：不为局部卡顿引入全局缓存或复杂依赖；先用 profiler / os.Logger 证明热点。
- **验收**：保留 `swift run --quiet SciStationCoreTestRunner`、Xcode build、`git diff --check`，并为性能专项补充 Instruments/trace 记录。

### D. Testing / P-AT 专项

- **Manual Test**：补最新 run report，至少覆盖 MT00、MT07、MT18、MT19、MT20、MT99。
- **P-AT**：稳定 `sci_station_agent.uitest.cli` 使用方式，解决或文档化 AX trust，保持 3/5 live smoke 不回退。
- **Scenario 扩展**：Reading Plan、Recommendation refresh、Draft approval、Graph action 应逐步转成 YAML scenario。
- **视觉/Warning**：把 SwiftUI runtime warning log 纳入 Release Gate；视觉 diff 可后置，但接口要保留。

### E. Recommendation / Queue / Reading Plan 工作流打磨

- **目标体验**：
  1. 用户从 Recommendation 找到值得读的 paper。
  2. 加入 Queue。
  3. 从 Queue 生成本周 Reading Plan。
  4. 读完后同步状态、生成复盘、回到 Project Dashboard。
- **当前优先**：
  - Recommendation 空状态、API key 缺失、arXiv 网络失败、AI evaluation 降级说明。
  - Recommendation V2 专项任务书：先做 category hard boundary、keyword/seed scoring、score breakdown，再推进 feedback / MMR / structured AI review。
  - Queue / Reading Plan 的 scope picker 与 project 切换一致性。
  - Reading Plan 的 Weekly Review 重新设计为小闭环，而不是旧 P50 草案的大系统。

### F. UI 一致性与可访问性

- **统一页面骨架**：ProjectSpace 页面标题区、toolbar、空状态、列表 panel、detail rail 应复用一致结构。
- **检查 macOS 行为**：窗口尺寸、titlebar avoidance、full-screen、右栏 resize、toolbar overflow、keyboard focus。
- **Accessibility IDs**：继续为主路径补 `UITestAccessibilityID`，不要等到 P-AT 场景写完才补。

### G. 隐私、安全与本地优先审计

- **继续坚持**：
  - 不把 API key 写入 workspace。
  - 不把 prompt、paper abstract、wiki 正文、用户绝对路径写入 debug payload。
  - AI 写 workspace 必须通过 Draft Inbox / Permission Dock。
  - 网络请求必须可解释、可关闭、可失败降级。
- **重点审计**：
  - arXiv 推荐请求。
  - AI evaluation payload。
  - debug bundle / app_events.jsonl。
  - UI test bridge debug-only 行为。

---

## 五、未来方向：重新立项，不沿用旧 P51/P52

以下方向仍有价值，但都需要在整体打磨后重新写轻量 RFC，而不是复活旧任务书。

### 1. Research Timeline

保留方向：

- 聚合 paper / todo / calendar / agent run / artifact / queue / reading plan 的时间线。
- 支持 project scope、source ref、open source、annotation、snapshot。

需要重新审视：

- 是否真的需要独立持久化 timeline events，还是 derived-first 即可。
- 与 Home / Project Dashboard 的关系。
- 与 Graph 的关系。
- 大量事件下的性能和过滤体验。

### 2. Milestone / Planning

保留方向：

- 项目 milestone、验收标准、linked todos、linked reading plan、AI plan draft approval。

需要重新审视：

- Milestone 与 Todo / Reading Plan / Calendar 的边界。
- 是否先做纯手动 milestone，再做 AI plan approval。
- 是否值得引入跨文件 journal / batch apply，还是先用更小的 patch preview。

### 3. Calendar / Reminders Sync

保留方向：

- 本地 calendar yaml 与系统 Calendar / Reminders 的 opt-in 同步。

需要重新审视：

- Sandbox 权限、冲突解决、重复事件、撤销、用户隐私提示。
- 不应在 Reading Plan / Milestone 尚未打磨前贸然接外部同步。

### 4. 专门研究模块

候选方向：

- Theory Research Module。
- Code / Experiment Research Module。
- Writing / Manuscript Module。
- Dataset / Lab Module。

约束：

- 暂不引入自动执行 shell / Python / notebook 的能力。
- 先做记录、组织、计划、证据链接、审批写入。
- 每个模块必须回答：module id、artifact kinds、write paths、MT 用例、debug events、本地化范围。

### 5. 分发与产品化

方向：

- Signing / Notarization。
- Release build privacy audit。
- First-run onboarding。
- Sample workspace。
- Crash / debug report 脱敏导出。

约束：

- 先完成打磨与测试治理，再做正式分发准备。

---

## 六、近期优先级建议

### S1：必须优先做

- **文档状态归一**：长期规划、MT、Proposal 历史归档与当前代码状态对齐。
- **中文本地化专项**：高频页面不再出现明显英文残留、截断或语义不自然。
- **Performance Phase 3 设计**：围绕 `AppViewModel` 拆分制定小步方案，先 Shell / Library / Home / Agent。
- **P-AT 稳定化**：把 3/5 live smoke 保持为固定回归；AX trust 阻塞路径文档化。
- **Recommendation / Reading Plan 可用性**：修空状态、失败态、scope 切换、API key 提示、网络请求说明。

### S2：随后做

- **Weekly Review 小闭环**：基于现有 Reading Plan 做最小复盘，而不是大 milestone 系统。
- **Graph / Recommendation / Queue 联动**：让 graph insight 更自然地进入 queue/recommendation。
- **Manual Test run reports**：补最新手测记录，并清理过时 gate。
- **Settings 信息架构**：模块、AI、Recommendation、Debug、Localization 设置分区更清楚。

### S3：暂缓

- **Research Timeline 大系统**。
- **Milestone Planning + AI Plan Approval 大系统**。
- **外部 Calendar / Reminders Sync**。
- **Code / Experiment 自动执行能力**。
- **第三方插件市场或动态代码加载**。

---

## 七、新功能进入主线前的检查清单

任何新功能不论大小，都必须回答：

1. **属于哪个 module？**
   是否可被 `WorkspaceModuleConfiguration` 启用/禁用？

2. **贡献哪些 routes / project tabs / workflows / toolbar commands？**
   是否通过 contribution catalog / toolbar catalog，而不是硬编码散落？

3. **产生什么 artifact kind？**
   是否进入 Draft Inbox / Permission Dock？

4. **写哪些 workspace paths？**
   是否在 module permission write paths 中声明？

5. **是否 local-first？**
   如果需要网络，是否 opt-in、可失败降级、可解释？

6. **是否本地化？**
   英文和简体中文是否都有自然文案？是否检查 compact/narrow？

7. **是否有 debug event？**
   event name 是否登记到 `AppDebugEventName`，payload 是否脱敏？

8. **是否有测试？**
   Core test、AgentRuntime pytest、MT 用例、必要时 P-AT scenario 是否齐全？

9. **是否考虑性能？**
   是否避免 body 内大规模排序/过滤/映射？是否避免深层 view 读取整个 `appModel`？

10. **是否有回滚/恢复策略？**
    坏 YAML、缺文件、权限拒绝、网络失败、provider 失败时是否可理解？

---

## 八、验证基线

常规代码改动至少运行：

```bash
swift run --quiet SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
git diff --check
```

涉及 AgentRuntime / P-AT 时增加：

```bash
.venv/bin/python -m pytest AgentRuntime/tests/ -q
.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q
```

涉及真实 UI smoke 时使用当前 P-AT CLI，并注意：

```text
1. 先确保 Debug app 是最新构建。
2. 确认没有旧 Sci-Station.app 实例复用。
3. Accessibility-dependent scenario 需要 SciStationUIProbe 获得 AX trust。
4. 事件断言依赖 .sci-station/debug/app_events.jsonl。
```

---

## 九、文档索引

- **手动测试协议**：`docs/development/ManualTestProtocol.md`
- **手动测试计划说明**：`docs/development/MT Plan.md`
- **手动测试用例目录**：`docs/development/manual-tests/`
- **Release Regression**：`docs/development/manual-tests/MT99_ReleaseRegression.md`
- **AI Usage Testing**：`docs/development/Proposal-AT.md`
- **历史任务书**：`docs/development/Previous Proposal/`
- **本文件**：当前全局状态、近期优先级与未来方向判断

---

## 十、本次规划重置结论

本次重置后：

```text
1. 不再把 P50 当作未来主线；Reading Plan 垂直切片已经落地。
2. 不再沿用旧 P51 / P52 草案；Timeline / Milestone 进入重新审视 backlog。
3. 下一阶段主线是整体打磨：中文、性能、测试、文档、Recommendation/Queue/Reading Plan 工作流。
4. 任何新大功能必须先通过全局能力地图和检查清单，而不是直接追加任务书。
```
