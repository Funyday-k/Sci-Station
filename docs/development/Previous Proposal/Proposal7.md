# 任务书 7：科研项目总览与 all-in-one 顶层设计

## 审阅意见

任务书 6 完成了 workspace preferences、Reader 右侧工作流面板、扩展搜索和 README 校准，但产品重心仍容易被理解成“论文管理库”。这与 Sci-Station 的真正目标不一致：它不应只是 Zotero 的替代品，而应该是一个围绕科研项目展开的本地优先 all-in-one 工作站。

因此，任务书 7 的优先级从 Search Index/Reminders 第二阶段调整为“项目层”。索引、同步和 Reader 任务闭环仍重要，但需要先让应用的一级入口表达清楚：一个项目内部应同时容纳 proposal、核心论文、数据、代码阅读、图片、输出、任务、日历和知识页。

## 顶层定位

Sci-Station 的一级对象是 Research Project，而不是单篇 paper 或单个 collection。论文库是项目的一部分；Wiki、Todo、Calendar、PDF Reader、BibTeX、data/code/figures/outputs 都服务于项目推进。

项目层应提供以下核心能力：

- 项目介绍和 living proposal。
- 核心论文列表及每篇论文的简要贡献说明。
- 论文、任务、数据、代码、图片、输出的统一入口。
- 后续可接入 VS Code/VSCodium kernel、实验记录、图像阅读和数据索引。

## 本轮目标

### 目标 1：Projects 入口从占位页升级为项目总览

- 在侧边栏 Projects 打开真实的 `ProjectOverviewView`。
- 总览页展示论文数、核心论文数、项目文档数和未完成任务数。
- 展示项目介绍文档摘要。
- 展示核心论文列表，并为每篇论文提供标题、作者、简要内容、标签和 Library/Reader 入口。

### 目标 2：工作区结构补齐项目级目录

- 保留已有 `code/`、`outputs/`。
- 新增 `data/` 用于数据和数据说明。
- 新增 `figures/` 用于项目级图片、图表和阅读材料。
- 打开旧 workspace 时自动补齐这些目录。

### 目标 3：项目种子文档

- 自动创建 `wiki/projects/project_overview.md`。
- 自动创建 `wiki/projects/core_papers.md`。
- Project Overview 页能直接打开这两个文档。

### 目标 4：README 与任务书同步

- README 将产品定位改为“本地优先科研 all-in-one 工作站”。
- 明确 Sci-Station 不是 Zotero 替代品，而是科研项目容器。
- 写出任务书 8，承接下一阶段项目层增强。

## 已实施范围

- `ResearchWorkspace` 新增 `data/`、`figures/` required directories。
- `ResearchWorkspace` 新增 `wiki/projects/project_overview.md` 与 `wiki/projects/core_papers.md` seeded files。
- `ProjectOverviewView` 实现项目总览、项目文档、核心论文和 research workflow 入口。
- `WorkspaceContentView` 将 `.projects` 路由到项目总览页。
- `WorkspaceSection.projects` 摘要改为项目级 all-in-one 语义。
- Core Test Runner 增加新目录和项目种子文档创建/回填检查。
- README 更新工作区结构、功能说明、尚未完成清单和相关文档索引。

## 验收标准

1. 新建 workspace 后存在 `data/`、`figures/`、`wiki/projects/project_overview.md` 和 `wiki/projects/core_papers.md`。
2. 打开旧 workspace 会自动补齐上述目录和文件。
3. 点击侧边栏 Projects 显示项目总览，而不是通用 section placeholder。
4. 项目总览能打开项目介绍和核心论文 Markdown 文档。
5. 项目总览能显示核心论文候选及简要内容。
6. README 不再把 Sci-Station 表述为 Zotero 替代品。
7. `swift run SciStationCoreTestRunner` 和 Xcode macOS build 通过。

## 暂缓内容

- 项目级配置模型和 pin core papers UI。
- 图像阅读器和数据预览器。
- VS Code/VSCodium kernel 适配。
- 实验 run、artifact、dataset 的结构化 schema。
- SQLite/FTS 搜索索引和 Reminders 双向同步。
