# Sci-Station 长期规划（P40 起 active roadmap）

更新时间：2026-05-07

> 本文件只保留尚未实施 / 还要做的内容。已完成基线只列状态行，不再展开实施任务。
> 详细任务书请打开 `DOC/ProposalNN.md`，子任务沿用 P39 时建立的 `Proposal39.5.md..Proposal39.15.md` 命名习惯。

---

## 一、已完成基线（只读，不再展开）

| 段位 | 范围 | 关键落地物 | 任务书 |
|---|---|---|---|
| P36 | Live Sidecar Wiring + Workspace Template Foundation | runtime selector live wiring、`SidecarRuntimeCoordinator`、`agent.start`-driven workflows、evidence line range navigation、debug bundle zip、`WorkspaceTemplate`/`WorkspaceModule` schema V0 | （历史） |
| P37 | Embedding Persistent Store + Hybrid Retrieval | `AgentEmbeddingStore`、deterministic fallback、Swift `embedding.embed/respond` proxy、`source_hash` stale detection、retrieval trace v2、index status UI | （历史） |
| P38 | Artifact Lifecycle / Draft Inbox / Evidence Inspector / Permission Dock V2 | `ArtifactDraft / ArtifactRecord / ArtifactApproval` schema、status machine、Draft Inbox UI、Evidence Health、partial failure recovery、saved artifact lineage、low-confidence save path | （历史） |
| P39 | Workspace Module Registry V1 与内置模块声明系统 | `WorkspaceModuleSchema`、`WorkspaceModuleRegistry.builtInModules`（含 disabled `code/datasets/experiments/citation-graph/recommendation/writing/theory-notes`）、`WorkspaceTemplateRegistry`、`workflowRequirements` gating、artifact kind descriptor、Permission Dock module scope 解释、legacy workspace 自动迁移 | （历史） |
| P39.5 – P39.15 | AI Lab 稳定化子任务 | thread/project affinity、消息持久化、IME、tool picker、approval、archived thread、第三篇论文路由、Debug mode、provider JSON parse fallback、Markdown 渲染（chat web view + 离线 doc preview）、context budget tuning、wiki writeback 路径扩展 | `Proposal39.5.md..Proposal39.15.md` |

> 已完成基线如有回归请通过 hotfix proposal 处理（命名沿用 `Proposal{N}.{minor}.md`），不写入本路线图主线。

---

## 二、当前活跃

| 段位 | 状态 | 简要范围 |
|---|---|---|
| P40 Workspace Creation Wizard V1 | 已草拟 `DOC/Proposal40.md`，未实施 | Empty Workspace / Settings 入口的可视化创建流程；模板选择、目录预览、隐私 / AI 边界确认；写出 deterministic `settings/workspace_modules.yaml` |

P40 实施并验收通过后，依序进入 P41–P47。下面 7 份任务书已经成稿：

```
DOC/Proposal41.md  Module Customization Settings V1
DOC/Proposal42.md  Workspace Home + Project Dashboard V2
DOC/Proposal43.md  Project Space Container + Sidebar 收敛
DOC/Proposal44.md  Research Graph Data Model V1
DOC/Proposal45.md  Citation Graph V1
DOC/Proposal46.md  Graph UI V1
DOC/Proposal47.md  Graph-Powered Research Workflows
```

---

## 三、P40–P47 总体路线（重排后）

```text
阶段 1：自定义工作区 + 项目中心 UI
  P40 Workspace Creation Wizard V1            — 已草拟
  P41 Module Customization Settings V1        — 启用/禁用、pin、目录 repair、project-level override
  P42 Workspace Home + Project Dashboard V2   — Today / Active Projects / AI Review 三段聚合
  P43 ProjectSpace 容器 + Sidebar 收敛         — 模块贡献的 project tab、route persistence

阶段 2：研究图谱
  P44 Research Graph Data Model V1            — graph.sqlite + 增量索引
  P45 Citation Graph V1                       — 本地 BibTeX/meta.yaml/references 解析
  P46 Graph UI V1                             — 5 个可操作视图，自实现 force-directed
  P47 Graph-Powered Research Workflows        — graph 反向接入 agent 工具，仍走 Draft Inbox + Permission Dock
```

---

## 四、P40 状态摘要（详细见 `DOC/Proposal40.md`）

- 入口：Empty Workspace 与 Settings → Workspace。
- 模板：Minimal、Literature Review；Code/Theory/Writing/Experimental 模板预留 disabled。
- 写出：`settings/workspace_template.yaml`、`settings/workspace_modules.yaml`（schema_version 1）。
- 边界：不写 API key / Keychain / provider raw config / prompt-response 明文；AI Lab 模块启用不等于模型凭证已配置。
- 前置：`Proposal39.5.md` GUI-only spot check（中文 IME、tool picker、approval）需要在对外发布前完成。

---

## 五、P41–P47 状态摘要

下面是各任务书的 1–2 段范围摘要。完整流程图、伪代码、测试、Debug 字段请打开对应 `Proposal{N}.md`。

### P41 Module Customization Settings V1（详见 `DOC/Proposal41.md`）

- 在 `Sci-Station/UI/SettingsViews.swift` 的 `Workspace` 类目下新增 "Modules" 子页：可启用/禁用模块、pin 到 sidebar、project-level override、目录 repair、依赖 warning、模块说明展开。
- 写入 `settings/workspace_modules.yaml`（schema_version 1）；`AppViewModel.workspaceModuleConfiguration` 是单一真相来源；UI 只展示 / 改写它。
- 不引入第三方插件，不允许新增不在 `WorkspaceModuleRegistry.builtInModules` 之外的模块 id。
- Debug：`module_settings.toggle / repair / override_apply / dependency_warning_shown`。

### P42 Workspace Home + Project Dashboard V2（详见 `DOC/Proposal42.md`）

- 把现有 `Sci-Station/UI/DashboardViews.swift` 的 `DashboardView` 改造为 Today / Active Projects / AI Review 三段聚合：今日待办 + reading queue + 等待审批 draft + stale evidence。
- Project Dashboard 加 stage、core papers、open gaps、recent artifacts、next deadline、current reading plan 字段。
- 新增轻量 `HomeAggregator`（一个 viewmodel-side 的 read-only data builder），按 `lastBuilt` 缓存，避免每次重渲染都全表扫描。
- Debug：`home.aggregate / project_dashboard.render / panel.snapshot`。

### P43 ProjectSpace 容器 + Sidebar 收敛（详见 `DOC/Proposal43.md`）

- 顶层 sidebar 收敛为 `Home / Projects / Library / Calendar / AI Lab / Settings`，project 内部走 tab（Overview / Papers / Wiki / Tasks / Calendar / Graph / AI Workflows）。
- 模块禁用时 tab 自动隐藏；pin 偏好与 last route 写入 `WorkspacePreferences`。
- 关键点：sidebar 项与 ProjectSpace tab 都从 `WorkspaceModuleRegistry.availableProjectTabs(in:)` 派生，不再硬编码。
- Debug：`sidebar.render / project_space.tab_change / route.persist`。

### P44 Research Graph Data Model V1（详见 `DOC/Proposal44.md`）

- 在 `.sci-station/graph/graph.sqlite` 建表 `graph_nodes / graph_edges / graph_node_evidence`；schema 版本化。
- 节点：`paper / project / concept / method / dataset / claim / evidence / task / artifact / calendar_event / run / approval`。
- 边：`cites / mentions / supports / contradicts / extends / uses / belongs_to / related_to / generated_by / approved_by / scheduled_for`。
- 增量重建（基于 `source_hash` 与 `updated_at` 时间戳），失败时回退到全量重建（带 progress event）。
- Debug：`graph.indexer.rebuild_started/finished/incremental_skip / graph.repository.write/error`。

### P45 Citation Graph V1（详见 `DOC/Proposal45.md`）

- 数据来源限定本地：`library/papers/*/meta.yaml`、`library/refs/library.bib`、`paper.md` references section。
- 不引入 Crossref / Semantic Scholar 在线 API；外部论文显示为 external placeholder node。
- `ReferenceResolver` 优先 DOI / arXiv，fallback 到 normalized title + first-author 模糊匹配；resolver 不抛错，而是输出 `unresolved warning`。
- Debug：`citation.parse / citation.resolve_unmatched / citation.edge_upsert`。

### P46 Graph UI V1（详见 `DOC/Proposal46.md`）

- 5 个视图：Paper Neighborhood、Project Citation Graph、Theme Cluster Graph、Evidence Support Graph、Artifact Lineage Graph。
- 自实现 force-directed layout（不引入第三方依赖），SwiftUI Canvas + 固定种子，保证测试可重现。
- 节点动作：Open Paper / Add to Project / Mark Core / Create Todo / Generate Reading Order / Explain Connection / Find Bridge Papers。
- Debug：`graph.ui.subgraph_query / graph.ui.layout_tick / graph.ui.action`。

### P47 Graph-Powered Research Workflows（详见 `DOC/Proposal47.md`）

- 新增 7 个 graph-backed agent 工具：`find_missing_core_papers / generate_reading_path / detect_stale_citations / find_unsupported_artifact_claims / find_stale_saved_artifacts / find_method_lineage / find_bridge_papers`。
- 扩展 `related_work / gap_planning / paper_reading` workflow 的默认工具集合；所有产物仍走 Draft Inbox + Permission Dock，不直接写 workspace。
- 把 `AgentPaperIntentRouter` 升级为 paper / graph 双 intent 识别。
- Debug：`agent.tool.graph_query / agent.tool.graph_result_size / agent.tool.graph_error`。

---

## 六、P48 起远期路线（保留路线图条目，不展开实施任务）

下列段位仅供方向参考，正式进入前必须重新审阅当时的实施现状再起草任务书。

```text
阶段 3：推荐与阅读计划
  P48 Research Queue V1
  P49 Recommendation Engine V1（local-first，可解释）
  P50 Reading Plan + Weekly Review

阶段 4：日历与研究时间线
  P51 Research Timeline V1
  P52 Milestone Planning + AI Plan Approval
  P53 Calendar / Reminders Sync V2

阶段 5：特化研究模块
  P54 Theory Research Module
  P55 Code / Experiment Research Module
  P56 Writing / Manuscript Module
  P57 Experimental / Lab Module

阶段 6：产品化与分发准备
  P58 Local-first Release Hardening
  P59 Distribution / Notarization Preparation
  P60 Privacy-preserving Feedback Loop
```

P48–P50 的核心约束：所有推荐结果都是 `recommendation_note` artifact，必须经 Draft Inbox + Permission Dock 才能写入 todo / wiki / project。不做无限信息流；不上传论文全文；不做社交推荐。

P51–P53 的核心约束：AI 生成的 timeline draft 也走 Draft Inbox。

P54–P57 不引入 sandbox 化的 shell / python / code execution；只做"记录、组织、计划、总结、证据链接"，复用 P38 Permission Dock 写入闭环。

---

## 七、产品判断（保持不变）

```text
Sci-Station 不是固定功能集合，
而是一个可配置、可审计的本地科研工作站。
```

任何 P41 之后的功能都必须答出三个问题：

1. **它在 `WorkspaceModuleRegistry` 的哪个模块下？** 否则无法被启用 / 禁用。
2. **它产生的 artifact 是哪一种 kind？** 必须能进 Draft Inbox。
3. **它写入 workspace 的路径在哪个模块的 `permissions.writePaths`？** 否则 Permission Dock 无法解释。

---

## 八、文件交叉索引

- 任务书结构模板：`DOC/Proposal40.md`（9 段结构）。
- 手动测试索引：`DOC/manual-tests/MT07_AILab.md`（AI Lab 主线）、`DOC/manual-tests/MT99_ReleaseRegression.md`（每轮回归）。
- 模块 / 模板代码：`Sci-Station/Workspace/WorkspaceTemplates.swift`。
- 偏好持久化：`Sci-Station/Workspace/WorkspacePreferences.swift`、`Sci-Station/Workspace/WorkspacePreferencesRepository.swift`。
- Debug 事件总线：`Sci-Station/Agent/AgentRunLogger.swift`（`AppDebugEvent` + `AppDebugEventLogger`）。
- 自动化测试入口：`Tools/SciStationCoreTestRunner/main.swift`。
