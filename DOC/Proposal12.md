# 任务书 12：全局研究空间、多项目管理与项目化任务/论文体系

更新时间：2026-04-29

## 2026-04-29 实现状态

任务书 12 的主体方向已经落地，但还不能关闭为“完全完成”。本轮已经完成了多项目 UI、项目化 Todo、项目级 Wiki/Materials 隔离、论文项目归属、全局 AI Lab 入口和设置增强；仍需继续收尾真正的物理论文库迁移、独立的项目-论文关系仓库，以及 Agent context 的 root/project 深适配。

### 已完成

- `ResearchRoot`、`ResearchProject`、`ProjectRegistryRepository` 已建立，root 会初始化 `library/`、`projects/`、`tasks/`、`settings/`、`.sci-station/`。
- 旧 workspace 可作为 legacy single-workspace root 兼容打开，并创建默认项目壳，不移动原有数据。
- Home 显示项目卡片，项目卡片单击只选中，双击进入项目主页，右键可编辑项目。
- Sidebar 改为项目堆叠结构，项目可折叠；AI Lab 已从项目内栏目移到全局 Projects 区域下方。
- root 名称移动到设置按钮右侧，Home 旁新增全局 Todo 图标入口。
- Todo 已增加 `project_ids`，支持全局 Todo 页面、项目 Todo 页面、完成/未完成切换、列表/卡片视图、多项目最多三列并排显示。
- Apple Reminders 默认同步移动到 Settings 并默认开启。
- Calendar 已区分项目事件与 Apple 导入事件，并提供两套独立分类过滤；Apple 事件继承系统日历颜色，节假日有单独分类。
- 论文 metadata 支持 `project_ids`、`core_project_ids`、`folder_path`，同一篇论文可归属多个项目并在项目内标记核心文章。
- Library 的 All Papers 支持折叠/展开子文件夹，论文右键支持 Add to Project / Add to Folder / Add to Core Paper。
- Wiki 与 Materials 已按当前项目隔离显示，不再把不同项目的材料和 wiki 页面混在一起。
- Tag 输入已支持基于已有 tag 的近似补全。
- LLM 默认配置切换为 DeepSeek OpenAI-compatible：`https://api.deepseek.com`，默认模型 `deepseek-v4-flash`，并提供 `deepseek-v4-pro` 预设。

### 尚未完成

- 论文文件的物理存储仍沿用当前 workspace `raw/papers` 兼容路径，尚未真正迁移到目标结构 `library/papers`。
- 项目-论文关系目前直接写在 `Paper.projectIDs` / `coreProjectIDs`，尚未拆成独立 `ProjectPaperLinkRepository`。
- Agent tool context 仍主要以 workspace/selected paper 为主，尚未完整携带 `ResearchRoot`、`currentProjectID`、项目关联论文和项目 Todo 上下文。
- 项目归档、排序、拖拽重排、项目删除/迁移策略仍未完善。
- Apple Reminders 的完整复刻还缺重复提醒、通知时间、列表选择、子任务、URL/location 等高级字段；当前先完成了项目化、完成视图、同步入口和基础提醒行为。

## 审阅意见

这次意见指出了一个比单个界面优化更底层的问题：Sci-Station 目前仍以“当前打开的单一 workspace”为中心，但真实科研工作更接近“一个长期研究根目录下有多个项目，共享同一个论文库、全局 Agent 设置和全局任务视图”。

因此，任务书 12 不应只做左侧 UI 微调，而应把产品数据模型从单 workspace 推进到：

```text
Research Root
  -> Global Paper Library
  -> Global Agent / LLM / Settings
  -> Projects
      -> Project Wiki
      -> Project Tasks
      -> Project Materials
      -> Project Outputs
```

任务书 11 已经落下 Agent 底座，但 Agent UI 不宜马上继续向前做，因为 Agent 的上下文边界必须先明确：它是服务于全局论文库、当前项目，还是所有项目。任务书 12 应先完成全局研究空间与多项目结构，再把 Agent Panel 接入这个新上下文。

## 当前问题

### 1. Home 只能管理当前 workspace

当前 Home / Dashboard 只能显示当前打开的 workspace。用户在两个或更多项目之间切换时，看不到所有项目的列表、状态和基本信息。

### 2. 左侧栏不是多项目结构

当前 Sidebar 是单个 workspace 下的 section 列表。用户希望左侧栏变成“项目堆叠 + 项目内栏目”的形式：

```text
Project A
  Home
  Library
  Wiki
  Tasks
  Materials
Project B
  Home
  Library
  Wiki
  Tasks
  Materials
```

并支持单击切换项目、折叠/展开项目、右键编辑项目信息。

### 3. Todo 缺少项目归属

多项目用户会有来自不同项目的任务。当前 Todo 主要存在当前 workspace 的 `tasks/todos.yaml`，没有稳定的 project scope。需要支持：

- 当前项目的 Tasks 页面只显示该项目相关 Todo。
- Home 页面显示所有项目的 Todo 总览。
- Todo 行上能看到来源项目。

### 4. 论文库应全局共享

论文不应被锁在某个项目目录里。不同项目都可能使用同一篇论文，只是论文对不同项目的用途、标签、阅读状态、Wiki 引用不同。

因此，应区分：

- 全局论文实体：论文 PDF、metadata、BibTeX、全局标签。
- 项目论文关系：这篇论文是否属于某项目、在该项目中的用途、项目内 notes / wiki 引用。

### 5. Agent 设置应全局可用

Agent、LLM Provider、Copilot Bridge、工具权限和运行日志不应散落在每个项目里。它们应在全局研究根目录下共享，同时每次运行携带当前项目上下文。

## 目标架构

### 目标目录结构

建议引入一个全局研究根目录，第一版可以命名为 `ResearchRoot` 或 `SciStationRoot`：

```text
SciStationRoot/
├── library/
│   ├── papers/
│   │   └── {paper-id}/
│   │       ├── paper.pdf
│   │       ├── paper.md
│   │       ├── meta.yaml
│   │       └── figures/
│   ├── refs/
│   │   ├── library.bib
│   │   └── tags.yaml
│   └── paper_index.yaml
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
├── tasks/
│   └── todos.yaml
├── settings/
│   ├── root_preferences.yaml
│   ├── llm.yaml
│   └── agent.yaml
└── .sci-station/
    ├── project_registry.yaml
    ├── agent/
    └── vscode/
```

第一版不必一次性迁移所有旧 workspace 文件，但新模型必须从一开始支持：全局根、多个项目、全局论文库、项目关系。

### 核心模型建议

新增或演进以下模型：

```text
ResearchRoot
ResearchProject
ProjectRegistry
ProjectPaperLink
GlobalPaperLibrary
ProjectScopedTodo
RootPreferences
```

其中：

- `ResearchRoot`：全局根目录，保存 library、projects、settings、agent。
- `ResearchProject`：单个项目，包含 project metadata 和项目内 wiki/materials/tasks。
- `ProjectRegistry`：记录所有项目的 id、名称、颜色、路径、排序、折叠状态。
- `ProjectPaperLink`：记录论文和项目的关系。
- `GlobalPaperLibrary`：负责全局论文加载、导入、搜索。
- `ProjectScopedTodo`：Todo 可归属一个或多个 project。

## 下一轮开发范围

### 目标 1：全局研究根目录 V1

- 新增全局研究根目录创建/打开流程。
- 根目录下自动创建 `library/`、`projects/`、`tasks/`、`settings/`、`.sci-station/`。
- 保留旧 `ResearchWorkspace` 的读取兼容策略。
- 新建项目时在 `projects/{project-id}/` 下生成项目目录。
- `project.yaml` 记录项目名称、描述、颜色、图标、创建时间、更新时间、默认标签。

### 目标 2：多项目 Home 与 Sidebar

- Home 显示所有项目卡片，而不是只显示当前 workspace。
- 每个项目卡片显示：名称、描述、论文数、Open Todos、最近更新时间、颜色/图标。
- 左侧栏改成项目堆叠结构。
- 支持折叠/展开项目。
- 支持单击切换当前项目。
- 支持右键编辑项目名称、描述、颜色、归档状态。
- 合并现有 Workspace Management 和 Workspace Overview，避免上下重复。

### 目标 3：项目化 Todo

- Todo 增加 `project_ids` 或等价项目归属字段。
- 当前项目 Tasks 页面只显示当前项目 Todo。
- Home 页面在日历下方显示跨项目 Todo 总表。
- Home 日历高度适当压缩，把空间让给跨项目任务。
- Todo 行显示项目 chip。
- 新增 Todo 时默认归属当前项目。
- 支持在 Todo 编辑器中切换项目归属。

### 目标 4：全局论文库与项目论文关系

- 将论文库设计为全局 library。
- Library 默认显示全局论文，可按当前项目筛选。
- 论文可关联到一个或多个项目。
- 项目 Overview / Wiki / Core Papers 只使用项目关联论文。
- 论文 metadata 保持全局唯一，项目内用途写入项目关系层。
- 避免把同一篇 PDF 复制到多个项目。

### 目标 5：全局 Agent / LLM 设置

- Agent 设置从项目级移动到 root-level settings。
- Agent run log 默认写到 root `.sci-station/agent/runs.jsonl`。
- 每条 agent run 记录当前 project id。
- Agent context builder 同时读取 root context、当前 project context、项目关联论文。
- Copilot Bridge 导出到 root `.sci-station/agent/copilot-bridge/`。

## 执行任务

### 任务 A：定义全局根模型

- 新增 `ResearchRoot`。
- 新增 `ResearchProject`。
- 新增 `ProjectRegistryRepository`。
- 新增 root structure initializer。
- 新增旧 workspace 检测逻辑：识别旧 workspace 并提示迁移或作为单项目 root 打开。

### 任务 B：项目 registry 与项目创建

- 实现 `projects/{project-id}/project.yaml`。
- 支持创建项目、重命名项目、编辑描述、颜色、图标。
- 支持归档项目但不删除数据。
- Project registry 保存排序、折叠状态、最近打开项目。

### 任务 C：Home 与 Sidebar 改造

- Home 顶部显示全局研究根名称。
- Home 项目区域改成项目卡片 grid。
- Workspace Management 和 Workspace Overview 合并为一个区域。
- Sidebar 按项目显示可折叠 section。
- 当前项目切换后刷新 Library / Wiki / Tasks / Materials 的 project scope。

### 任务 D：Todo 项目化

- `TodoItem` 增加 `projectIDs`。
- `TodoRepository` 支持读写 `project_ids`，兼容旧 YAML 中没有该字段的 Todo。
- AppViewModel 增加：当前项目 Todo、全局 Todo、按项目过滤 Todo。
- Tasks 页面默认显示当前项目 Todo。
- Home 在日历下方显示全局 Todo 列表。

### 任务 E：论文库全局化

- 设计 `GlobalPaperLibraryRepository` 或演进 `PaperRepository` 使其可读取 root `library/papers/`。
- 新增 `ProjectPaperLinkRepository`。
- 导入论文默认进入全局 library。
- 当前项目下导入论文时自动建立 project-paper link。
- Library 提供 All Papers / Current Project Papers segmented control。

### 任务 F：Agent 上下文适配

- `AgentWorkspaceSnapshot` 演进为 root + project context。
- Tool context 增加 `root`、`currentProjectID`。
- `create_todo` 默认写入当前项目归属。
- `update_paper_classification` 支持项目关联论文。
- Agent run log 增加 project id 字段。

## 验收标准

1. 用户可以创建一个全局研究根目录。
2. 用户可以在该根目录下创建至少两个项目。
3. Home 能以项目卡片形式同时显示所有项目。
4. 左侧栏能显示多个项目，并支持折叠/展开和单击切换。
5. 项目右键菜单可编辑项目名称、描述、颜色或归档状态。
6. 当前项目 Tasks 只显示该项目 Todo。
7. Home 日历下方显示跨项目 Todo 总表，并在 Todo 行显示项目来源。
8. 论文导入后进入全局论文库，不重复复制到多个项目。
9. 同一篇论文可以关联到多个项目。
10. 当前项目 Wiki / Overview / Core Papers 只基于项目关联论文。
11. Agent 设置和 Copilot Bridge 位于全局 root，而不是单项目目录。
12. 旧 workspace 至少可以被识别，并提供迁移或兼容打开路径。
13. SwiftPM Core Test Runner 通过。
14. Xcode macOS build 通过。

## 风险与约束

- 这是数据模型级改造，不能只从 UI 层做假多项目。
- 迁移旧 workspace 时不能移动或删除用户数据，第一版应优先提供复制/导入式迁移。
- 全局论文库与项目 Wiki 要明确边界：PDF 和 metadata 全局，项目理解和产出留在项目目录。
- Todo 需要兼容旧 `tasks/todos.yaml`，不能让旧任务消失。
- Agent 不能在项目切换时混淆上下文，所有 tool call 必须携带 current project id。

## 建议实现顺序

1. 先做 root/project 数据模型和目录初始化。
2. 再做 Home 项目卡片和 Sidebar 项目切换。
3. 再做 Todo 项目化和全局 Todo 总表。
4. 再做全局论文库和项目论文关系。
5. 最后把 Agent context 和 Copilot Bridge 接到 root/project 模型上。

这个顺序可以避免先做 UI 再返工数据结构，也能让后续 Agent 真正理解“当前项目”和“全局论文库”的边界。