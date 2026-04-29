# 任务书 12：全局研究空间、多项目管理与项目化任务/论文体系

更新时间：2026-04-29

## 1. 当前结论

任务书 12 的旧版本已经落后于代码状态。本轮基于当前代码重新审阅后，结论是：Sci-Station 已经从单一 workspace 原型推进到“全局研究根目录 + 多项目 + 全局任务 + 全局论文库”的过渡形态，任务书 12 的主体目标可以视为进入收尾阶段。

本轮新增实施后，任务书 12 的三项关键滞后点已经补上第一版：

- 新导入论文默认进入 `library/papers`，旧 `raw/papers` 继续兼容读取。
- 新增独立的 `ProjectPaperLinkRepository`，用 `library/project_paper_links.yaml` 保存项目-论文关系，并由 `PaperRepository` 与旧 metadata 字段桥接。
- Agent 快照、工具上下文和 run log 增加 root/current project 语义，`create_todo` 与 `update_paper_classification` 可默认使用当前项目。

因此，任务书 12 不再应继续描述“尚未建立全局论文库/项目关系/Agent root context”。这些已经有代码实现和核心验证覆盖。下一轮应转入任务书 13，处理迁移 UI、关系层 UI 完全解耦、Agent Panel 和项目生命周期策略。

## 2. 代码审阅结果

### 已完成并保留

- `ResearchRoot`、`ResearchProject`、`ProjectRegistryRepository` 已建立。
- root 初始化会创建 `library/`、`projects/`、`tasks/`、`settings/`、`.sci-station/`。
- 旧 workspace 可作为 legacy single-workspace root 打开，并创建默认项目壳，不移动原有数据。
- Home 显示项目卡片，项目卡片支持选择、双击进入项目主页和右键编辑。
- Sidebar 已是项目堆叠结构，并支持项目折叠与项目内栏目。
- Todo 已有 `project_ids`，支持全局 Todo、项目 Todo、完成/未完成切换和多项目显示。
- Calendar 已区分项目事件、Apple 导入事件和节假日分类过滤。
- Wiki 与 Materials 已按当前项目隔离显示。
- LLM 默认配置已切换到 DeepSeek OpenAI-compatible。

### 本轮补齐

- `Paper.directoryRelativePath(for:collectionPath:)` 将新论文目录落到 `library/papers`。
- `Paper.collectionPath(for:)` 同时支持 `library/papers` 与旧 `raw/papers`。
- `PaperRepository.loadPapers` 同时扫描全局库和旧库，重复 id 时优先全局库。
- `PaperRepository.save/delete` 同步维护项目-论文关系文件，并允许删除全局库或旧库内论文。
- `PDFImportService` 与 `LinkOnlyImportService` 的新导入路径已切到 `library/papers`。
- `CollectionRepository` 默认在 `library/papers` 创建 collection，并兼容扫描/操作旧 `raw/papers` collection。
- `MovePaperToCollectionService` 会在论文所在的 storage root 内移动：全局库论文留在 `library/papers`，旧论文留在 `raw/papers`。
- `ProjectPaperLinkRepository` 新增独立关系模型：`project_id`、`paper_id`、`is_core`、`folder_path`、`use_for`、时间戳。
- `AgentWorkspaceSnapshot` 新增 root、项目列表、当前项目、项目论文、项目 open todos 和全局库路径。
- `AgentToolContext` 新增 `researchRoot` 与 `currentProjectID`。
- `create_todo` 支持 `project_ids`，省略时默认写入当前项目。
- `update_paper_classification` 支持项目关联、核心项目标记和当前项目默认行为。
- `AgentRun` 记录 `current_project_id`。
- `AgentRunLogger` 与 `AgentCopilotBridgeExporter` 增加 root-level API。

## 3. 当前架构事实

```text
Research Root
├── library/
│   ├── papers/                    # 新论文默认物理存储
│   ├── refs/library.bib            # 全局 bibliography
│   ├── refs/tags.yaml
│   ├── paper_index.yaml
│   └── project_paper_links.yaml    # 项目-论文关系层
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
├── tasks/todos.yaml
├── settings/
│   ├── root_preferences.yaml
│   ├── llm.yaml
│   └── agent.yaml
└── .sci-station/
    ├── project_registry.yaml
    ├── agent/runs.jsonl
    └── agent/copilot-bridge/
```

兼容事实：旧 `raw/papers` 仍会被扫描、加载、删除和移动，但新导入不再写入该路径。

## 4. 任务书 12 验收状态

| 验收项 | 状态 |
| --- | --- |
| 创建全局研究根目录 | 已完成 |
| 在同一 root 下创建多个项目 | 已完成 |
| Home 项目卡片 | 已完成 |
| Sidebar 项目堆叠与折叠 | 已完成 |
| 项目编辑 | 已完成 |
| 当前项目 Tasks 过滤 | 已完成 |
| Home 跨项目 Todo | 已完成 |
| 新论文导入全局论文库 | 本轮完成 |
| 旧 `raw/papers` 兼容读取 | 本轮完成 |
| 同一论文关联多个项目 | 已完成，并新增关系仓库桥接 |
| 项目 Wiki / Overview / Core Papers 使用项目关联论文 | 已完成 |
| Agent root/project context | 本轮完成第一版 |
| Agent run log root-level | 本轮完成 |
| SwiftPM Core Test Runner | 已通过 |
| Xcode macOS build | 已通过 |

## 5. 留给任务书 13 的问题

任务书 12 不再继续扩大范围。以下内容转入任务书 13：

1. 提供可确认的旧库迁移 UI，将 `raw/papers` 复制或移动到 `library/papers`，并生成迁移报告。
2. 让 App UI 以 `ProjectPaperLinkRepository` 为第一数据源编辑项目-论文关系，逐步减少对 `Paper.projectIDs` / `coreProjectIDs` 的直接依赖。
3. 为项目-论文关系增加项目内备注、阅读目的、引用状态、pin/order 等字段。
4. 完成项目归档、排序、拖拽重排、删除/迁移策略。
5. 把 Agent Panel 接到新 snapshot，展示 root/project context、审批 tool call、运行历史和 Copilot Bridge 导出。
6. 继续增强 Apple Reminders：重复提醒、通知时间、列表选择、子任务、URL/location。

## 6. 风险与约束

- 旧 `raw/papers` 暂时不能自动移动，必须避免误删或破坏用户已有库。
- `ProjectPaperLinkRepository` 已存在，但 UI 仍有一部分编辑流程会通过 `Paper` metadata 字段进入；当前由 repository bridge 保持兼容。
- 全局论文 metadata 与项目关系层需要逐步拆清，不能一次性删除旧字段。
- Agent tool call 必须始终携带或默认出 current project id，否则多项目上下文会混淆。
- 后续迁移必须保留回滚路径，至少写出迁移前后路径映射。

## 7. 本轮验证

- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：通过。
