# 任务书 13：论文库迁移、项目关系 UI 与 Agent Panel

更新时间：2026-04-29

## 1. 背景

任务书 12 已完成全局研究根目录、多项目 UI、项目化 Todo、全局论文库默认路径、项目-论文关系仓库和 Agent root/project context 的第一版。

当前系统进入新的阶段：底层数据结构已经具备多项目研究站的形状，但用户还缺少可控迁移、关系层可视化编辑和真正可用的 Agent Panel。因此任务书 13 不再继续扩大 root/project 基础模型，而是把这些能力做成用户可以理解、确认和回滚的工作流。

## 2. 当前代码基线

- 新导入论文默认进入 `library/papers`。
- 旧 `raw/papers` 仍兼容读取、删除和移动。
- `library/project_paper_links.yaml` 已保存项目-论文关系。
- `PaperRepository` 会在读取时叠加项目关系，并在保存/删除时同步关系文件。
- Agent snapshot 已包含 root、current project、project papers、project open todos 和全局库路径。
- Agent tools 已支持 current project 默认写入。

### 2.1 2026-04-29 本轮进展

- 新增 `LegacyPaperMigrationService`，可扫描 `raw/papers` 中的 legacy metadata 并生成 dry-run 迁移计划。
- 迁移计划会给出 source path、target `library/papers` path、paper id、标题、ready/conflict 状态。
- 迁移计划会检测目标目录已存在、全局库重复 paper id、legacy 库内部重复 paper id。
- Settings 的 Library 区域已展示 legacy `raw/papers` 摘要、ready/conflict 计数和前 5 条 dry-run 条目。
- App 加载 workspace 时会刷新 dry-run plan，用户也可以在 Settings 中手动刷新扫描。
- Core Test Runner 已覆盖 ready-to-copy 与 global duplicate conflict 两类迁移计划。
- 本轮没有执行真实复制/移动，也没有写迁移报告；这些留给下一轮。

## 3. 目标

### 目标 A：旧论文库迁移工作流

- 检测 `raw/papers` 中仍存在的 legacy paper。
- 在 Settings 或 Library 中提供迁移入口。
- 迁移前展示影响范围：论文数量、目标路径、潜在冲突、预计移动/复制列表。
- 默认使用复制或安全移动策略，不直接破坏旧库。
- 生成迁移报告，记录 old path、new path、paper id、状态和错误。
- 迁移后刷新 Library，确保旧路径和新路径重复 id 时优先显示新路径。

### 目标 B：项目-论文关系 UI 改用关系仓库

- Library Inspector 中项目归属、核心文章、项目文件夹等编辑操作，以 `ProjectPaperLinkRepository` 为第一写入目标。
- `Paper.projectIDs` / `coreProjectIDs` 暂时保留为兼容镜像，但不作为 UI 的长期主数据源。
- 支持每个项目内独立设置：核心状态、项目内用途、项目文件夹、pin/order。
- Project Overview 的 Core Papers 和项目论文统计从关系层读取。
- Core Test Runner 增加关系层编辑与旧 metadata 桥接回归。

### 目标 C：Agent Panel V1

- 在全局 AI Lab 下提供 Agent Panel。
- 展示当前 root、current project、project papers、project todos 和可用工具。
- 支持 plan-only 运行，展示计划 JSON 的摘要和 tool calls。
- 对 requires_confirmation 的工具调用提供逐项批准。
- 执行后写入 root `.sci-station/agent/runs.jsonl`。
- 支持导出 Copilot Bridge prompt 到 root `.sci-station/agent/copilot-bridge/`。

### 目标 D：项目生命周期

- 支持项目归档/取消归档。
- 支持项目排序和拖拽重排。
- 明确项目删除策略：只删除 registry entry、归档项目，或迁移/保留项目目录。
- 删除前展示受影响论文关系、Todo、Wiki 和 Materials 数量。

## 4. 执行顺序

1. 先做 legacy `raw/papers` 检测和迁移计划，不立即执行真实迁移。已完成第一版 dry-run。
2. 加入迁移执行与迁移报告，并用核心验证覆盖路径冲突。下一轮优先。
3. 将项目-论文关系 UI 的写入路径切到 `ProjectPaperLinkRepository`。
4. 建立 Agent Panel 的 plan-only UI。
5. 增加工具调用审批和 run history。
6. 最后处理项目排序、归档和删除策略。

## 5. 验收标准

1. 用户能看到是否还有 legacy `raw/papers` 论文。
2. 用户能执行一次可确认、可审计的迁移，将论文迁移到 `library/papers`。
3. 迁移后 Library 不重复显示同一 paper id，并优先显示全局库版本。
4. 用户在 UI 中修改项目-论文关系时，会更新 `library/project_paper_links.yaml`。
5. 旧 metadata 中的 `project_ids` 仍可被读取并桥接，不造成项目论文丢失。
6. Agent Panel 能基于当前项目生成计划。
7. Agent Panel 能展示并批准 `create_todo` / `update_paper_classification` tool call。
8. Agent run log 写入 root-level JSONL，并包含 current project id。
9. SwiftPM Core Test Runner 通过。
10. Xcode macOS build 通过。

## 6. 风险

- 迁移涉及真实用户文件，必须优先做 dry-run 和报告。
- 关系层和旧 metadata 的双写期可能出现冲突，需要定义优先级：关系仓库优先，metadata 作为兼容镜像。
- Agent Panel 不能默认执行写入工具，必须保留确认门槛。
- 项目删除策略必须保守，第一版可只做归档，不做物理删除。
