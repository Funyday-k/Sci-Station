# Sci-Station 下一阶段任务书

更新时间：2026-04-29

## 1. 文档目的

这份任务书用于记录当前下一阶段的主方向。任务书 12 已经完成多项目 UI、项目化 Todo、项目级 Wiki/Materials 隔离、DeepSeek 默认 LLM 和日历分类过滤的大部分实现；下一阶段应继续收尾任务书 12，而不是立即开启全新任务书。

详细执行方案见 [DOC/Proposal12.md](Proposal12.md)。

## 2. 当前阶段结论

Sci-Station 目前已经具备论文导入、Wiki/Markdown、LLM 总结基础、Agent 底座和 Todo 等模块，并已经开始以一个全局研究根目录组织多个项目。

新的产品判断是：科研工作站应以一个全局研究根目录为基础，在其中管理多个项目、共享同一个论文库、共享 Agent/LLM 设置，并让每个项目拥有自己的 Wiki、任务、材料和输出。

因此，下一阶段的核心不是先继续扩 Agent UI，而是把任务书 12 的数据收尾做扎实：全局论文物理存储、项目-论文关系仓库、Agent root/project context。

## 3. 下一阶段主线

下一阶段主线为：

```text
Global Research Root
  -> Global Paper Library
  -> Global Agent / LLM Settings
  -> Multiple Projects
      -> Project Wiki
      -> Project Tasks
      -> Project Materials
      -> Project Outputs
```

## 4. 主要目标

### 4.1 全局研究根目录

- 新增全局 root 概念。
- 在 root 下创建 `library/`、`projects/`、`tasks/`、`settings/`、`.sci-station/`。
- 支持旧 workspace 检测和迁移/兼容打开策略。

### 4.2 多项目 Home 与 Sidebar

- Home 显示所有项目卡片。
- 合并现有 Workspace Management 和 Workspace Overview。
- 左侧栏改成可折叠的项目堆叠结构。
- 支持单击切换项目和右键编辑项目信息。

### 4.3 项目化 Todo

- Todo 增加项目归属。
- 当前项目 Tasks 只显示当前项目 Todo。
- Home 日历下方显示跨项目 Todo 总表。
- Todo 行显示来源项目。

### 4.4 全局论文库

- 论文库从项目内迁移为全局 library。
- 同一篇论文可关联多个项目。
- 项目 Wiki、Overview 和 Core Papers 基于项目关联论文构建。

### 4.5 全局 Agent 设置

- Agent/LLM/Copilot Bridge 设置放在 root-level settings。
- Agent run log 写入 root `.sci-station/agent/`。
- Agent context 同时包含 root、当前项目和项目关联论文。

## 5. 建议优先级

1. 将论文物理存储从兼容路径推进到 `library/papers`，并提供旧数据迁移/兼容策略。
2. 拆出 `ProjectPaperLinkRepository`，把项目内用途、核心状态和项目级备注从全局 paper metadata 中分离出来。
3. 完成 Agent context 的 root/project 适配，让 tool call 明确携带 current project id。
4. 补齐项目归档、排序、拖拽重排和删除/迁移策略。
5. 继续增强 Todo/Reminders：重复提醒、提醒时间、列表选择、子任务和完成归档。

## 6. 验收标准

1. 用户能创建全局研究根目录。
2. 用户能在同一根目录下创建至少两个项目。
3. Home 能同时显示所有项目卡片。
4. 左侧栏能折叠/展开多个项目并切换当前项目。
5. 当前项目 Tasks 只显示该项目 Todo。
6. Home 能显示跨项目 Todo 总览。
7. 论文导入进入全局论文库，同一论文可关联多个项目。
8. Agent 设置和运行日志在 root 层共享。
9. 旧 workspace 不会被破坏，至少可被识别并提示迁移或兼容打开。
10. SwiftPM Core Test Runner 和 Xcode macOS build 通过。

## 7. 下一轮建议直接做什么

建议继续做任务书 12 的收尾包：

- `GlobalPaperLibraryRepository` 或演进后的 `PaperRepository`，读写 `library/papers`。
- `ProjectPaperLinkRepository`，保存项目-论文关系、核心文章、项目内用途。
- 旧 `raw/papers` 到 `library/papers` 的兼容读取和可确认迁移。
- AgentWorkspaceSnapshot 增加 root/project/currentProjectID/project papers/project todos。
- Core Test Runner 覆盖迁移、项目论文关系和 agent context。

完成后再开启下一份任务书，进入 Agent Panel 和更完整的科研自动化流程。