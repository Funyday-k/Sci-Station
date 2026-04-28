# 任务书 8：项目层结构化与科研 artifact 工作流

## 审阅意见

任务书 7 已把 Sci-Station 的顶层定位从“论文管理库”重新校准为“科研 all-in-one 工作站”，并让 Projects 成为真实的项目总览入口。下一步不应立刻回到单点功能堆叠，而应把项目层的数据结构补上：项目介绍、核心论文、数据、代码、图片、输出和任务需要有可维护的元数据模型，而不是只依赖目录和 Markdown 约定。

任务书 8 的目标是把 Project Overview 从展示页推进为项目操作台，同时保持本地文件系统为源数据。

## 背景

当前 Projects 页面已经能打开 `wiki/projects/project_overview.md` 和 `wiki/projects/core_papers.md`，并根据标签、优先级和评分推导核心论文。这个方案足够启动项目层，但仍有几个明显限制：核心论文不能手动 pin，项目状态没有结构化字段，data/code/figures/outputs 只是目录入口，图片和数据还不能在 App 内预览。

## 目标

### 目标 1：Project Profile V1

- 新增 `project/profile.yaml` 或 `settings/project_profile.yaml`。
- 记录项目标题、短描述、研究问题、阶段、关键里程碑和默认 project overview 文档路径。
- Project Overview 顶部从 profile 读取项目标题和描述。
- profile 缺失时从 seeded defaults 自动创建。

### 目标 2：Pinned Core Papers

- 在 profile 中保存 pinned core paper ids 或 citekeys。
- Project Overview 优先展示 pinned papers。
- Library/Inspector 增加“Pin to Project Core”入口。
- 保留现有标签/优先级推导作为兜底。

### 目标 3：Artifact Browser V1

- 为 `data/`、`code/`、`figures/`、`outputs/` 增加轻量文件浏览视图。
- 支持 Reveal in Finder、Open with default app。
- 支持 Markdown/TXT/CSV/JSON 的只读预览。
- 支持图片预览：png、jpg、jpeg、webp、gif、tiff。
- 暂不执行代码。

### 目标 4：Project Milestones 与 Tasks 关联

- Project Overview 显示与项目相关的 open tasks。
- 支持用 project tag 或 profile id 关联 todo。
- 增加 milestone 概念，但第一版可以落在 YAML/Markdown 中。

### 目标 5：README 与验证更新

- 更新 README 中 Project Overview 和 artifact workflow 说明。
- Core Test Runner 覆盖 project profile 创建、读取和旧 workspace 回填。
- 手动检查清单加入图片预览、artifact 打开、core paper pinning。

## 执行任务

### 任务 A：ProjectProfile 模型与仓库

1. 定义 `ProjectProfile`。
2. 定义 `ProjectProfileRepository`。
3. 在 workspace 创建/打开时 seeded/backfill profile 文件。
4. AppViewModel 加载并保存 project profile。
5. Core Test Runner 覆盖缺失、读取、保存、回填。

### 任务 B：Core Paper Pinning

1. ProjectProfile 增加 pinned paper ids。
2. ProjectOverviewView 合并 pinned papers 和自动推导 papers。
3. Library row/context menu 或 Inspector 增加 pin/unpin 操作。
4. 保存后刷新 Project Overview。

### 任务 C：Artifact Browser

1. 新建 `ProjectArtifact` 模型。
2. 扫描 `data/`、`code/`、`figures/`、`outputs/`。
3. 新增 `ProjectArtifactBrowserView`。
4. 增加文本和图片预览。
5. 支持 default app 打开和 Finder 定位。

### 任务 D：Milestones 与项目任务

1. 约定项目 todo 的标记方式。
2. Project Overview 展示项目 open tasks 和近期 due tasks。
3. 提供新建项目 todo 的快捷入口。
4. 后续再接入 Apple Reminders 同步状态。

### 任务 E：文档与验收

1. 更新 README。
2. 更新手动检查清单。
3. 补 Core Test Runner。
4. 运行 SwiftPM 验证和 Xcode build。

## 验收标准

1. 新建和打开旧 workspace 都能获得 project profile。
2. Project Overview 显示 profile 标题、描述和阶段。
3. 用户可以 pin/unpin 核心论文，重启后仍保留。
4. Artifact Browser 能浏览 data/code/figures/outputs。
5. 图片文件可在 App 内预览。
6. 文本类文件可只读预览。
7. 项目相关 todo 能在 Project Overview 显示。
8. README 与实际功能一致。
9. `swift run SciStationCoreTestRunner` 和 Xcode macOS build 通过。

## 风险与约束

- profile 不能替代 Markdown proposal，二者应互补。
- Artifact Browser 不执行代码，避免权限、安全和环境复杂度扩散。
- 图片和文本预览先覆盖常见格式，不追求完整媒体管理。
- Pinned core papers 应使用稳定 paper id，并考虑 citekey 变更。

## 暂缓内容

- VS Code/VSCodium kernel 执行与 notebook 运行。
- 实验 run 管理和可重复计算环境。
- 数据版本管理和大型文件索引。
- SQLite/FTS 搜索索引。
- Reminders 双向同步冲突 UI。
