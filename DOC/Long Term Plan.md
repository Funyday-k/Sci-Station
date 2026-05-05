下面我建议把后续规划拆成 **8 个大方向**，并按照工作量大小分配不同数量的任务书。整体思路是：

1. **先把 P35/P36 的 Agent 与 Evidence 主链路打稳**；
2. **再引入自定义工作区与模块化架构**；
3. **然后做图谱、推荐、日历这些高价值研究工作流**；
4. **最后发展理论、代码、写作、实验等特化模块**。

目前 Sci-Station 已经是一个 macOS 本地优先科研工作站，核心数据落在用户选择的 Research Root 中，并已经包含论文库、项目 Wiki、材料、任务、日历、PDF 阅读和 AI Lab 等模块 [3]。P35 已经完成 citation/evidence critic、paper reading、related work、gap planning、run replay、runtime selector UI、evidence source jump 等 Production V1 能力 [1]。P36 原草案的核心目标是把这些 UI/contract 接入真实 live runtime，包括 runtime selector、sidecar supervisor、agent.start、embedding persistent store、evidence navigation 和 debug zip [2]。

---

# 一、任务书拆分原则

我建议后续任务书按以下粒度拆：

| 工作量 | 适合内容 | 建议任务书数量 |
|---|---|---|
| S 小型 | 单个 UI 增强、单个 schema、单个设置页 | 1 份 |
| M 中型 | 一个完整功能闭环：数据模型 + UI + 测试 | 1–2 份 |
| L 大型 | 跨 UI、Repository、Agent、索引、权限的系统能力 | 2–3 份 |
| XL 超大型 | 新产品方向，如图谱、推荐系统、特化研究模块 | 3–5 份 |

每份任务书最好都固定包含：

```text
1. 背景
2. 本轮目标
3. 实施任务
4. 非目标
5. 验收标准
6. Tests
7. 手动验证
8. 交付记录
9. 留给下一轮的边界
```

---

# 二、总体路线图：8 个大方向，建议拆成 18 份任务书

## 总览表

| 大方向 | 工作量 | 建议任务书 | 核心目标 |
|---|---:|---|---|
| A. Live Runtime 与 Agent 基础设施 | L | P36–P37 | 让 P35 的 workflow 真正进入 sidecar/live runtime |
| B. Artifact / Evidence / Approval 生命周期 | M | P38 | 统一 AI 产物、证据、审查、审批、写入 |
| C. 自定义工作区与模块系统 | L | P39–P41 | 支持创建工作区时选择模板和模块 |
| D. Project-centered 信息架构与 UI 重构 | M | P42–P43 | 从功能列表转向项目驾驶舱 |
| E. 论文图谱与引用关系谱 | XL | P44–P47 | Citation Graph、Semantic Graph、Research Graph |
| F. 每日推荐论文 / Research Queue | L | P48–P50 | 推荐论文、解释推荐原因、反馈闭环 |
| G. Calendar / Research Timeline | L | P51–P53 | 把任务、论文阅读、milestone、deadline 串起来 |
| H. 特化研究模块 | XL | P54–P57 | 理论研究、代码研究、写作、实验模块 |

---

# 三、建议任务书编号与命名

下面是我建议的任务书序列。

---

## A. Live Runtime 与 Agent 基础设施

这一部分承接 P35/P36，优先级最高。因为如果 runtime、sidecar、evidence、debug、approval 这些底座不稳，后面的图谱、推荐、模块化都会建立在不可靠基础上。

---

## P36：Live Sidecar Wiring 与 Workspace Template Foundation

> 这是对现有 P36 的重起草版本。保留原 P36 的 live runtime 目标，但加入自定义工作区的基础 schema。

### 目标

1. Runtime selector 真正影响新 AI Lab run；
2. app-level sidecar supervisor 接入真实状态；
3. paper reading / related work / gap planning 通过 sidecar `agent.start` 跑起来；
4. evidence navigation 从“打开源文件”升级为“定位 line range / PDF page”；
5. debug bundle 生成真实 zip；
6. 新增 WorkspaceTemplate / WorkspaceModule 的最小 schema。

### 关键依据

P36 原草案已经明确要让 Swift Loop、LangGraph Sidecar、Auto fallback 都能影响新 run，并接入真实 sidecar health、restart、fallback 和 debug bundle 行为 [2]。P35 也明确 sidecar 不能直接写 workspace，所有写入仍必须通过 Swift Permission Dock [1]。

### 实施任务

```text
[P36.1] Runtime selector live wiring
[P36.2] App-level SidecarRuntimeCoordinator
[P36.3] Production workflows 接入 agent.start
[P36.4] Evidence navigation line target
[P36.5] Debug bundle 真实 zip
[P36.6] WorkspaceTemplate / WorkspaceModule schema V0
[P36.7] Workspace creation wizard skeleton
[P36.8] Tests and delivery record
```

### 非目标

```text
不做插件市场
不做完整模块启用/禁用 UI
不做 citation graph
不做 recommendation
不做 code execution sandbox
不让 sidecar 获得 workspace 写权限
```

### 验收标准

1. 切换 Swift Loop / LangGraph Sidecar / Auto fallback 后，新 run 的执行路径确实变化；
2. sidecar crash 后，UI 能显示 fallback reason 和 last checkpoint；
3. paper reading、related work、gap planning 都能通过 sidecar start path 输出 artifact draft；
4. evidence 点击后能定位 Markdown/Wiki/annotations 的 line range；
5. debug zip 默认不含 API key、`.env`、Keychain、private path inventory；
6. 新建 workspace 时能写入最小模板配置文件，例如：

```text
settings/workspace_template.yaml
settings/workspace_modules.yaml
```

---

## P37：Embedding Persistent Store 与 Retrieval Runtime

> 原 P36 中 embedding persistent store 任务较重，建议单独拆出一轮。

### 目标

把 P35 的 embedding V1 contract 变成真实可用的本地持久化检索能力。

P35 已经要求 embedding retrieval 可选启用，并且必须保留 FTS-only fallback [1]。P36 原草案也计划优先实现 sqlite-vec store，并在不可用时提供 deterministic fallback [2]。

### 实施任务

```text
[P37.1] EmbeddingStore protocol
[P37.2] sqlite-vec store implementation
[P37.3] deterministic fallback store
[P37.4] Swift embedding.embed / embedding.respond proxy
[P37.5] chunk schema version and migration
[P37.6] source_hash stale chunk detection
[P37.7] hybrid retrieval rerank / dedupe
[P37.8] indexing status UI
[P37.9] Tests
```

### 验收标准

1. 未开启 embedding 时，FTS-only path 正常；
2. 开启 embedding 时，FTS + embedding hybrid retrieval 正常；
3. source_hash 改变后，chunk 被标记 stale 或自动重建；
4. sidecar 不持有 embedding API key；
5. 检索结果仍返回可审计的 evidenceRefs。

---

# 四、B. Artifact / Evidence / Approval 生命周期

---

## P38：Artifact Lifecycle、Draft Inbox 与 Evidence Inspector

### 为什么要单独做？

现在 P35 已经有 paper note、related work、research plan、todo draft、critic report 等不同 artifact [1]。但产品层面需要统一它们的生命周期，否则以后推荐论文、图谱洞察、实验计划、写作建议都会各自为政。

### 目标

建立统一 AI 产物生命周期：

```text
Draft
-> Evidence Attached
-> Critic Checked
-> Needs Revision
-> Awaiting Approval
-> Approved
-> Written
-> Replayed
-> Stale
```

### 实施任务

```text
[P38.1] Artifact domain model
[P38.2] Artifact status machine
[P38.3] Draft Inbox UI
[P38.4] Evidence Inspector UI
[P38.5] Critic report unified rendering
[P38.6] Permission Dock V2 integration
[P38.7] Low-confidence save path
[P38.8] Artifact replay integration
[P38.9] Tests
```

### 关键数据结构建议

```text
Artifact
- id
- type
- project_id
- title
- target_path
- draft_markdown
- evidence_refs
- critic_report_id
- confidence
- status
- run_id
- created_at
- updated_at
- source_hashes
```

### Artifact 类型

```text
paper_note
related_work
research_plan
todo_draft
recommendation_note
graph_insight
experiment_plan
writing_revision
```

### 验收标准

1. 所有 AI workflow 产物都进入 Draft Inbox；
2. 用户可以查看 target path、diff、evidence coverage、critic status；
3. unsupported claim 会阻止直接 approval；
4. 用户可选择保存为 low confidence draft，但 UI 必须警告；
5. 保存后 artifact metadata 能保留 evidenceRefs 和 run_id。

---

# 五、C. 自定义工作区与模块系统

这是你自己提出的重点，我认为应该成为产品架构主线。不同研究者工作对象不同，Sci-Station 不能假设所有人都需要同一套 Library / Wiki / Code / Calendar / AI Lab。

---

## P39：Workspace Module Registry V1

### 目标

让系统知道“一个工作区启用了哪些模块”。

### 实施任务

```text
[P39.1] WorkspaceModule model
[P39.2] Built-in module registry
[P39.3] Module dependency declaration
[P39.4] Module-provided routes
[P39.5] Module-provided directories
[P39.6] Module-provided workflows
[P39.7] Module permission scope
[P39.8] Module settings persistence
[P39.9] Tests
```

### 内置模块建议

```text
paper-library
wiki
projects
materials
tasks
calendar
pdf-reader
ai-lab
code
datasets
experiments
citation-graph
recommendation
writing
theory-notes
```

### 示例 schema

```yaml
id: code-research
title: Code Research
version: 1
enabled: true

directories:
  - code/
  - data/
  - outputs/
  - projects/*/code/
  - projects/*/data/

routes:
  - /code
  - /experiments
  - /datasets

workflows:
  - experiment_planning
  - run_log_summary
  - paper_to_code_checklist

permissions:
  write_paths:
    - projects/*/wiki/
    - projects/*/tasks/
    - projects/*/outputs/
```

### 验收标准

1. workspace 可读取 `settings/workspace_modules.yaml`；
2. 未启用模块不显示对应 UI 入口；
3. 模块可声明目录、路由、workflow、权限范围；
4. 旧 workspace 打开后自动迁移到默认模块配置；
5. 不做第三方插件，只做内置 registry。

---

## P40：Workspace Creation Wizard V1

### 目标

把当前“选择一个空文件夹作为 Research Root”的流程升级为“创建研究空间”。

当前 README 中的快速试用流程是首次启动后点击 Create Workspace，选择空文件夹作为 Research Root [3]。这对开发者可用，但对真实用户不够产品化。

### 创建流程建议

```text
Step 1: 选择研究类型
Step 2: 选择启用模块
Step 3: 预览目录结构
Step 4: AI / 隐私 / Keychain 设置
Step 5: 创建示例项目或空工作区
```

### 预设模板

```text
Minimal Workspace
Literature Review
Theory Research
Code Research
Writing Project
Experimental Research
Custom
```

### 实施任务

```text
[P40.1] Create Workspace wizard UI
[P40.2] WorkspaceTemplate registry
[P40.3] Template -> directories generation
[P40.4] Template -> module config generation
[P40.5] Optional seed content
[P40.6] Privacy and AI setup page
[P40.7] Migration for legacy workspace
[P40.8] Tests
```

### 验收标准

1. 用户能选择模板创建 workspace；
2. 创建前能预览目录结构；
3. 创建后生成对应 module config；
4. Minimal / Literature Review / Theory / Code / Writing 至少 5 个模板可用；
5. AI 默认关闭，Keychain/API 边界说明清楚。

---

## P41：Module Customization Settings V1

### 目标

允许用户在 Settings 中启用、禁用、排序、pin 模块。

### 实施任务

```text
[P41.1] Module settings page
[P41.2] Enable / disable module
[P41.3] Pin to sidebar
[P41.4] Project-level module visibility
[P41.5] Missing directory repair
[P41.6] Dependency warning
[P41.7] Tests
```

### 验收标准

1. 用户能在 Settings 中启用/禁用模块；
2. 禁用模块不删除用户数据，只隐藏 UI 和 workflow；
3. 模块依赖缺失时显示 warning；
4. 模块目录缺失时可一键 repair；
5. Project 可以覆盖 workspace 默认模块显示。

---

# 六、D. Project-centered 信息架构与 UI 重构

---

## P42：Workspace Home 与 Project Dashboard

### 目标

打开 App 后，用户首先看到“今天该做什么”，而不是一堆功能入口。

### Workspace Home 建议内容

```text
Today
- Due tasks
- Reading queue
- Upcoming deadlines
- Pending AI drafts

Active Projects
- Current milestone
- Recent papers
- Recently edited wiki pages
- Open gaps

AI Review
- Needs approval
- Unsupported claims
- Stale evidence warnings
```

### Project Dashboard 建议内容

```text
Project Overview
- Stage
- Core papers
- Open tasks
- Open research gaps
- Recent artifacts
- Next deadline
- Current reading plan
```

### 实施任务

```text
[P42.1] Workspace Home data aggregator
[P42.2] Today panel
[P42.3] Active projects panel
[P42.4] Pending AI drafts panel
[P42.5] Stale evidence panel
[P42.6] Project dashboard V1
[P42.7] Tests
```

---

## P43：Project Space Tabs 与 Sidebar 收敛

### 目标

避免左侧栏无限膨胀。

### 建议信息架构

```text
Sidebar:
- Home
- Projects
- Library
- Calendar
- AI Lab
- Settings

Project Space:
- Overview
- Papers
- Wiki
- Tasks
- Calendar
- Graph
- Code
- Data
- Outputs
- AI Workflows
```

### 实施任务

```text
[P43.1] ProjectSpace container
[P43.2] Module-contributed project tabs
[P43.3] Sidebar pin system
[P43.4] Route persistence
[P43.5] Empty states
[P43.6] Tests
```

---

# 七、E. 论文图谱与引用关系谱

这是一个 XL 方向，建议至少拆 4 份任务书。不要一开始追求炫酷可视化，要先做数据模型、引用边、局部图、可操作 insight。

---

## P44：Research Graph Data Model V1

### 目标

建立统一 research graph 底座。

### 节点

```text
paper
project
concept
method
dataset
claim
evidence
task
artifact
calendar_event
```

### 边

```text
cites
mentions
supports
contradicts
extends
uses
belongs_to
related_to
generated_by
scheduled_for
```

### 实施任务

```text
[P44.1] Graph schema in researchflow.sqlite
[P44.2] Paper node indexer
[P44.3] Project node indexer
[P44.4] Wiki concept/method extractor
[P44.5] Evidence node bridge
[P44.6] Incremental update
[P44.7] Tests
```

---

## P45：Citation Graph V1

### 目标

先做本地论文库内部 citation graph。

### 数据来源

```text
library/papers/*/meta.yaml
library/refs/library.bib
wiki citation blocks
paper.md references section
DOI / arXiv metadata if available
```

### 实施任务

```text
[P45.1] Citation metadata parser
[P45.2] Paper reference resolver
[P45.3] citation_edges table
[P45.4] cited_by / cites view
[P45.5] Paper neighborhood UI
[P45.6] Missing reference warning
[P45.7] Tests
```

### 验收标准

1. 单篇论文页能看到 cites / cited by；
2. Project 能看到核心论文之间的引用关系；
3. 找不到本地论文时显示 external placeholder；
4. 不因 DOI 缺失而崩溃。

---

## P46：Graph UI V1

### 目标

做可操作的图谱，而不是装饰性图谱。

### 图谱视图

```text
Paper Neighborhood
Project Citation Graph
Theme Cluster Graph
Evidence Support Graph
```

### 节点操作

```text
Open paper
Open note
Add to project
Mark as core paper
Create todo
Generate reading order
Explain connection
Find bridge papers
```

### 实施任务

```text
[P46.1] Graph layout V1
[P46.2] Node detail inspector
[P46.3] Edge explanation
[P46.4] Graph filter and lens
[P46.5] Node actions
[P46.6] Tests
```

---

## P47：Graph-powered Research Workflows

### 目标

让图谱反过来增强 related work、gap planning、推荐论文。

### Workflow

```text
Find missing core papers
Generate reading path
Detect stale citations
Build evidence matrix from graph
Explain paper cluster
Find method lineage
```

### 实施任务

```text
[P47.1] Missing core paper detector
[P47.2] Reading path generator
[P47.3] Stale citation detector
[P47.4] Graph-backed related work workflow
[P47.5] Graph-backed gap planning workflow
[P47.6] Tests
```

---

# 八、F. 每日推荐论文 / Research Queue

建议不要叫普通“每日推荐”，而是叫：

```text
Research Queue
Daily Reading Queue
```

核心不是刷信息流，而是帮助用户推进当前项目。

---

## P48：Research Queue V1

### 目标

建立推荐论文的 inbox。

### 推荐来源

```text
Project core papers
Recently read papers
Open research gaps
Stale evidence warnings
User-added keywords
Manual watchlist
```

### 实施任务

```text
[P48.1] ResearchQueue model
[P48.2] Queue item status
[P48.3] Add paper to queue
[P48.4] Add recommendation reason
[P48.5] Queue UI
[P48.6] Add to Library / Add to Project actions
[P48.7] Tests
```

### Queue item 状态

```text
new
skim
deep_read
added_to_library
added_to_project
dismissed
not_relevant
already_known
```

---

## P49：Recommendation Engine V1

### 目标

做第一版可解释推荐。

### 推荐理由

```text
Because it cites one of your core papers
Because it is cited by a core paper
Because it matches current project keywords
Because it fills an identified research gap
Because it updates stale evidence
Because it is semantically similar to recently read papers
```

### 实施任务

```text
[P49.1] Candidate source adapter
[P49.2] Local scoring model
[P49.3] Explanation generator
[P49.4] Duplicate detector
[P49.5] User feedback model
[P49.6] Privacy boundary
[P49.7] Tests
```

### 非目标

```text
不做无限信息流
不默认上传用户论文全文
不做社交推荐
不自动导入论文
```

---

## P50：Reading Plan 与 Weekly Review

### 目标

把推荐论文转化为阅读计划。

### 实施任务

```text
[P50.1] Daily queue
[P50.2] Weekly reading plan
[P50.3] Reading load setting
[P50.4] Skim/deep-read workflow integration
[P50.5] Weekly review artifact
[P50.6] Calendar integration preview
[P50.7] Tests
```

---

# 九、G. Calendar / Research Timeline

当前项目已经有 Todo、Calendar 与 Apple Reminders 能力 [3]，但下一步应该从普通日历升级为 Research Timeline。

---

## P51：Research Timeline V1

### 目标

把任务、论文阅读、AI workflow、project milestone 组织成时间线。

### Timeline event 类型

```text
todo
deadline
reading_block
writing_block
experiment_run
advisor_meeting
submission_deadline
artifact_due
weekly_review
```

### 实施任务

```text
[P51.1] TimelineEvent model
[P51.2] Project milestone model
[P51.3] Timeline UI
[P51.4] Link event to paper/project/task/artifact
[P51.5] Drag to reschedule
[P51.6] Tests
```

---

## P52：Milestone Planning 与 AI Plan Approval

### 目标

把 P35 的 gap planning todo drafts 接入 timeline，但继续保持审批机制。

P35 已经要求 gap planning 生成 milestones 和 todo drafts，但不能自动创建 todo，必须经过 Swift approval [1]。

### 实施任务

```text
[P52.1] Research milestone artifact
[P52.2] AI-generated timeline draft
[P52.3] Permission Dock approval
[P52.4] Duplicate task detection
[P52.5] Calendar preview before write
[P52.6] Tests
```

---

## P53：Calendar / Reminders 双向增强

### 目标

加强 Apple Calendar / Reminders 同步、冲突处理、完成状态回写。

### 实施任务

```text
[P53.1] Apple Reminders completion sync
[P53.2] Conflict detection
[P53.3] Due time and reminder alert
[P53.4] Calendar event import
[P53.5] Project calendar filter
[P53.6] Tests
```

---

# 十、H. 特化研究模块

这是远期最大工作量。建议不要一口气全做，而是先做用户差异最明显的两个：

1. Theory Research；
2. Code / Experiment Research。

---

## P54：Theory Research Module

### 适合用户

```text
数学
理论 CS
理论物理
哲学
形式化证明方向
```

### 核心对象

```text
Definition
Assumption
Lemma
Theorem
Proof
Counterexample
Open Problem
```

### 目录建议

```text
wiki/definitions/
wiki/theorems/
wiki/proofs/
wiki/open_problems/
projects/{project-id}/theory/
```

### Workflow

```text
Extract definitions from paper
Compare assumptions
Build theorem dependency map
Generate proof sketch
Find missing lemma
Convert paper note to formal theory note
```

### 实施任务

```text
[P54.1] Theory module schema
[P54.2] Definition/Theorem/Proof note templates
[P54.3] Theory wiki index
[P54.4] Theorem dependency graph V1
[P54.5] Theory-specific AI workflow
[P54.6] Tests
```

---

## P55：Code / Experiment Research Module

### 适合用户

```text
机器学习
系统
算法工程
软件工程
计算科学
```

### 核心对象

```text
Repository
Dataset
Experiment
Run
Metric
Baseline
Ablation
Figure
Result
```

### 目录建议

```text
projects/{project-id}/code/
projects/{project-id}/data/
projects/{project-id}/experiments/
projects/{project-id}/runs/
projects/{project-id}/outputs/
```

### Workflow

```text
Paper-to-code checklist
Reproduction plan
Experiment plan
Run log summary
Baseline comparison
Ablation table generation
Result-to-claim evidence check
```

### 实施任务

```text
[P55.1] Code research module schema
[P55.2] Experiment model
[P55.3] Run log model
[P55.4] Dataset registry
[P55.5] Experiment report artifact
[P55.6] VS Code bridge enhancement
[P55.7] Tests
```

### 注意

这里仍然不建议马上做完整 code execution sandbox。P35/P36 都明确不做 shell/python/code execution sandbox，也不让 sidecar 获得 workspace 写权限 [1][2]。可以先做“记录、组织、计划、总结、证据链接”，而不是让 AI 自动运行代码。

---

## P56：Writing / Manuscript Module

### 适合用户

```text
论文写作
proposal 写作
综述写作
基金申请
书籍章节
```

### 核心对象

```text
Manuscript
Section
Claim
Citation
Figure
Table
Reviewer Comment
Revision Task
```

### Workflow

```text
Outline to manuscript
Claim citation coverage check
Unsupported claim detector
Reviewer response draft
Figure/table checklist
Related work rewrite
Submission checklist
```

### 实施任务

```text
[P56.1] Manuscript project type
[P56.2] Section-level artifact model
[P56.3] Citation coverage inspector
[P56.4] Reviewer response workflow
[P56.5] Writing deadline integration
[P56.6] Tests
```

---

## P57：Experimental / Lab Module

### 适合用户

```text
湿实验
材料
仪器
生物医学
化学
实验物理
工程实验
```

### 核心对象

```text
Protocol
Sample
Instrument
Batch
Measurement
Observation
Lab Note
Result
```

### Workflow

```text
Protocol planning
Experiment checklist
Sample tracking
Measurement log summary
Result report
Safety note
```

### 实施任务

```text
[P57.1] Lab module schema
[P57.2] Protocol template
[P57.3] Sample registry
[P57.4] Measurement log
[P57.5] Lab timeline integration
[P57.6] Tests
```

---

# 十一、按优先级重新排序

如果从现在开始推进，我建议顺序是：

```text
第一阶段：把 P35/P36 主链路打稳
P36 Live Sidecar Wiring + Template Foundation
P37 Embedding Persistent Store
P38 Artifact Lifecycle / Draft Inbox

第二阶段：建立可自定义科研工作区
P39 Workspace Module Registry
P40 Workspace Creation Wizard
P41 Module Customization Settings

第三阶段：重构主 UI 和项目中心体验
P42 Workspace Home / Project Dashboard
P43 Project Space Tabs / Sidebar 收敛

第四阶段：图谱能力
P44 Research Graph Data Model
P45 Citation Graph V1
P46 Graph UI V1
P47 Graph-powered Workflows

第五阶段：推荐与阅读计划
P48 Research Queue V1
P49 Recommendation Engine V1
P50 Reading Plan / Weekly Review

第六阶段：日历与研究时间线
P51 Research Timeline V1
P52 Milestone Planning / AI Plan Approval
P53 Calendar / Reminders Sync V2

第七阶段：特化模块
P54 Theory Research Module
P55 Code / Experiment Research Module
P56 Writing Module
P57 Experimental / Lab Module
```

---

# 十二、近期 4 份任务书建议细化到可执行版本

我建议你接下来先只正式起草 P36–P39。后面的 P40–P57 可以暂时作为 roadmap，不需要马上写得太死。

---

## P36 推荐正式标题

```text
任务书 36：
Live Sidecar Wiring、Evidence Navigation 深化与 Workspace Template Foundation
```

### P36 核心交付

```text
1. Runtime selector 真实影响新 run
2. Sidecar coordinator 真实接入 UI
3. Production workflows 通过 agent.start 跑
4. Evidence line range / PDF page navigation
5. Debug bundle zip
6. WorkspaceTemplate / WorkspaceModule schema V0
```

---

## P37 推荐正式标题

```text
任务书 37：
Embedding Persistent Store、Hybrid Retrieval Runtime 与 Index Health UI
```

### P37 核心交付

```text
1. sqlite-vec 或 fallback embedding store
2. Swift embedding proxy
3. hybrid retrieval
4. source_hash stale chunk
5. indexing status UI
6. FTS-only fallback 保持可用
```

---

## P38 推荐正式标题

```text
任务书 38：
Artifact Lifecycle、Draft Inbox、Evidence Inspector 与 Permission Dock V2
```

### P38 核心交付

```text
1. 统一 Artifact model
2. Draft Inbox
3. Evidence Inspector
4. Critic report rendering
5. low-confidence draft path
6. artifact replay
7. approval writeback 闭环
```

---

## P39 推荐正式标题

```text
任务书 39：
Workspace Module Registry V1 与内置模块声明系统
```

### P39 核心交付

```text
1. WorkspaceModule schema
2. Built-in module registry
3. Module routes
4. Module directories
5. Module workflows
6. Module permission scopes
7. Legacy workspace migration
```

---

# 十三、最重要的产品判断

我建议你把后续任务的中心思想定成：

```text
Sci-Station 不是一个固定功能集合，
而是一个可配置的本地科研工作站。
```

所以后续开发不要按照：

```text
加一个图谱
加一个推荐
加一个日历
加一个代码模块
```

而应该按照：

```text
统一 Artifact 生命周期
统一 Module 系统
统一 Project Space
统一 Research Graph
统一 Evidence / Approval / Replay
```

这样未来做 Theory Research、Code Research、Writing、Experimental Research 时，不会变成四套互相割裂的功能。

---

# 十四、最终建议

我建议下一步不要直接开做图谱或推荐，而是先完成这 4 个任务书：

```text
P36 Live Sidecar Wiring + Workspace Template Foundation
P37 Embedding Persistent Store + Retrieval Runtime
P38 Artifact Lifecycle + Draft Inbox
P39 Workspace Module Registry V1
```

这 4 个完成后，Sci-Station 的底层形态会从：

```text
本地论文/项目管理 App + AI Lab
```

升级为：

```text
本地优先、可定制、可审计的科研工作站平台
```

然后再进入：

```text
P40–P43 自定义工作区和 Project-centered UI
P44–P47 论文图谱和引用图谱
P48–P50 每日推荐论文 / Research Queue
P51–P53 Research Timeline
P54–P57 特化研究模块
```

这样路线会比较稳，不会因为过早做上层炫酷功能而导致底层抽象反复返工。