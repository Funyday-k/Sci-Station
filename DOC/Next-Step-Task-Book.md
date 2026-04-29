# Sci-Station 下一阶段任务书

更新时间：2026-04-29

## 1. 当前阶段结论

任务书 12 已按当前代码重新审阅并更新，并完成关键收尾：新论文默认进入 `library/papers`、旧 `raw/papers` 兼容读取、独立项目-论文关系仓库、Agent root/current project context 和核心验证覆盖。

任务书 13 已完成第一步：legacy `raw/papers` 检测与 dry-run 迁移计划。Settings 的 Library 区域现在能显示 legacy paper 数量、ready/conflict 计数和目标路径预览，但尚未执行真实迁移。

详细执行方案见 [DOC/Proposal13.md](Proposal13.md)。

## 2. 当前代码基线

- 全局研究根目录和多项目 registry 已存在。
- Home 与 Sidebar 已支持多项目。
- Todo 已支持项目归属和全局视图。
- 新导入论文默认进入 `library/papers`。
- 旧 `raw/papers` 继续兼容读取，避免破坏旧 workspace。
- `library/project_paper_links.yaml` 已保存项目-论文关系。
- `PaperRepository` 会桥接关系仓库与旧 paper metadata 字段。
- Agent snapshot 和工具上下文已包含 root/current project。
- `LegacyPaperMigrationService` 已能生成 `raw/papers` 到 `library/papers` 的 dry-run 计划。

## 3. 下一阶段主线

```text
Global Research Root
  -> Safe Legacy Paper Migration
  -> Project-Paper Link UI
  -> Agent Panel V1
  -> Project Lifecycle Controls
```

## 4. 主要目标

### 4.1 旧论文库迁移

- 检测 `raw/papers` legacy paper。
- 提供 dry-run 迁移计划。
- 展示冲突、目标路径和迁移报告。
- 用户确认后迁移到 `library/papers`。
- 保证迁移后同一 paper id 不重复显示。

### 4.2 项目-论文关系 UI

- UI 编辑项目归属和核心文章时优先写入 `ProjectPaperLinkRepository`。
- 保留 `Paper.projectIDs` / `coreProjectIDs` 作为兼容镜像。
- 增加项目内用途、文件夹、pin/order 等关系层字段。

### 4.3 Agent Panel V1

- 在全局 AI Lab 下显示 Agent Panel。
- 展示 root、current project、project papers、project todos 和可用工具。
- 支持 plan-only、工具审批、执行结果和 run history。
- 支持 Copilot Bridge 导出。

### 4.4 项目生命周期

- 项目归档/取消归档。
- 项目排序和拖拽重排。
- 保守删除策略：第一版优先归档，不做物理删除。

## 5. 建议优先级

1. 实现迁移执行与迁移报告，默认采用复制策略，并继续保留旧 `raw/papers`。
2. 执行后刷新 Library，确认同一 paper id 优先显示 `library/papers` 版本。
3. 将项目-论文关系 UI 写入切换到关系仓库。
4. 建 Agent Panel plan-only UI。
5. 加入 tool call 审批与 run history。
6. 最后完善项目排序、归档和删除策略。

## 6. 验收标准

1. 用户能看到当前 root 是否还有 legacy `raw/papers` 论文。
2. 用户能确认并执行一次迁移到 `library/papers`。
3. 迁移报告写入 root 可见位置。
4. Library 不重复显示同一 paper id。
5. UI 修改项目-论文关系会更新 `library/project_paper_links.yaml`。
6. Agent Panel 能基于当前项目生成计划。
7. Agent Panel 能逐项批准写入工具。
8. Agent run log 含 current project id。
9. SwiftPM Core Test Runner 通过。
10. Xcode macOS build 通过。
