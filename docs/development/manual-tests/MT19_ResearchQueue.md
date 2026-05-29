# MT19：Research Queue V1 手动测试

更新时间：2026-05-17
任务书：P48
状态：Ready / Automated baseline passed

## 0. 自动化基线

已执行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

结果：PASS（21 条 P48 自动化用例 + 整体 build）。

## 1. 测试范围

覆盖 P48 Research Queue V1 新增能力：

1. `ResearchQueueStore` / `ResearchQueueIngestor` 落盘与重入一致。
2. ProjectSpace `Queue` tab：scope 切换、status / source 过滤、Add from Library、状态变更、移动、移除、onboarding。
3. `Library` 页右键菜单与批量编辑：`Reading Queue` 子菜单 / `Add to Queue` 子菜单。
4. Home Today 卡：`readingQueueEntries` 优先渲染，queue 为空时回退启发式列。
5. Project Dashboard：新增独立 `Reading Queue` 卡，与 `Current Reading Plan` 卡并存；空状态走 `Open Queue Tab` CTA。
6. `Paper.status` 切换驱动 queue entry 状态自动迁移（unread → reading → finished / dismissed）。
7. AI 推荐链路（`recommendation_note` payload `queue_candidates`）的 Permission Dock 入队（待 P49 producer 落地后才有真实数据，本轮空跑）。
8. paper-library 模块禁用时 Queue tab、Add to Queue 菜单、HomePanel readingQueueEntries 都自动隐藏。

## 2. 用例

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT19-P48-01 | 空 workspace onboarding | 新建空 workspace（标准 template）→ 打开 ProjectSpace → 切到 `Queue` tab | 显示 onboarding CTA `Add a paper from Library / Graph to start your queue.`；点击 `Add from Library…` 打开 sheet |
| MT19-P48-02 | Library 单文献入队（项目 scope） | Library 列表选 1 篇 → 右键 → `Reading Queue` → `Add to <Project Name> Queue` → 切到 Queue tab，scope 选 Project | 列表显示该论文一行，状态 `Queued`，source pill `Manual`；右键再次菜单标记为 ✓ `Remove from <Project Name> Queue` |
| MT19-P48-03 | Library 批量入队（workspace scope） | Library 列表多选 3 篇 → 右键 → `Add to Queue` → `Workspace Queue` → 切到 Queue tab，scope 选 Workspace | 三行依次出现，order 1/2/3；任一行右键 `Reading Queue` 菜单显示 ✓ |
| MT19-P48-04 | 状态自动迁移 unread→reading | 打开任一 queue 行对应 paper detail，把 `Status` 切到 `Skimmed` | Queue tab 中该行 status badge 变为 `Reading`，副行新增 `paper status sync` 来源；`startedAt` 写入 yaml |
| MT19-P48-05 | 状态自动迁移 reading→finished | 把同一 paper 的 `Status` 切到 `Summarized` | Queue tab 中该行 status badge 变为 `Finished`，`Active` 过滤下消失；切到 `Finished` 过滤可看到；`finishedAt` 写入 yaml |
| MT19-P48-06 | 行内动作 ↑↓ / 状态切换 / 删除 | Queue tab 用 ↑↓ 重排两行；行右侧 ⋮ 菜单 `Mark queued / reading / finished / deferred / dismissed` 各点一遍；最后 `Remove from queue` | 顺序持久化；状态切换写 `lastTouchedAt` 与对应时间戳；Remove 后该行从所有过滤里消失 |
| MT19-P48-07 | Add from Library 搜索 | 打开 `Add from Library…` sheet，键入标题片段 / 作者片段 | 列表实时筛选；已在该 scope 中的 paper 显示绿色 ✓ `Added`；点击 `Add` 不重复添加 |
| MT19-P48-08 | Home Today 卡接入 | 给 workspace 添加 ≥ 1 个 active queue entry → 进入 Home Today | `Reading Queue` 卡渲染 queue 行（图标着色 + 副行 chip），count 与 entries 一致；queue 全空时回退到原启发式列 + onboarding CTA |
| MT19-P48-09 | ProjectDashboard 卡 | 进入项目 ProjectSpace 的 Overview 标签 | `Reading Queue` 卡（icon `tray.full`）显示前 3 条 active；空时显示 `Add a paper from Library / Graph to start your queue.` + `Open Queue Tab`；行点击跳到 Queue tab |
| MT19-P48-10 | Current Reading Plan 卡保持 | 同一 ProjectSpace Overview | 既有 `Current Reading Plan` 卡保留（占位文案 `Reading Plan data arrives in P50.`），未被 P48 卡替换 |
| MT19-P48-11 | YAML 落盘与重启重入 | 在 workspace 中加 4 条 entry（混合 scope/状态）→ 退出应用 → 用 `tail -n +1 library/queue.yaml projects/*/queue.yaml` 检查文件 → 重启应用 | yaml 字段齐整（schema_version / scope / order / status / source）；重启后所有行顺序与状态保持一致 |
| MT19-P48-12 | malformed yaml 容错 | 手工把 `library/queue.yaml` 改成缺失 `id:` 的部分块 → 重启应用 | 应用不崩溃；`Reading Queue` 仅读出可解析行；调试日志写 `queue.load.error` 警告；下次写入不覆盖已有非空文件 |
| MT19-P48-13 | paper-library 模块禁用 | Settings → Modules 关闭 Paper Library → 回 ProjectSpace | Queue tab 在 ProjectSpace 不可见；Library 行右键不再显示 `Reading Queue`；Home Today 卡走 `Library 模块已关闭` 提示 |
| MT19-P48-14 | Permission Dock 入队（推荐 producer） | 当 P49 落地后：触发 `recommendation_note` artifact，approve → ingestor 应自动 append entries | source pill 显示 `Recommendation`，`source_refs` 字段携带 run_id / tool_call_id；本轮 P49 未落地时该项 N/A |
| MT19-P48-15 | 中英文界面 | 切换简体中文 / English | Queue tab toolbar、菜单文案、空状态文案、Home / ProjectDashboard 卡的副行 chip 在两种语言下都不截断、无残留 |
| MT19-P48-16 | 深浅色模式 | 切换系统外观 | status badge tint、source pill、按钮在 light / dark 都可读 |

## 3. 验收记录模板

```text
测试日期：
测试人：
Git commit：
macOS / Xcode：
Workspace：Empty / Standard / Broken / Custom
自动化基线：PASS / FAIL

MT19-P48-01：PASS / FAIL / N/A
MT19-P48-02：PASS / FAIL / N/A
MT19-P48-03：PASS / FAIL / N/A
MT19-P48-04：PASS / FAIL / N/A
MT19-P48-05：PASS / FAIL / N/A
MT19-P48-06：PASS / FAIL / N/A
MT19-P48-07：PASS / FAIL / N/A
MT19-P48-08：PASS / FAIL / N/A
MT19-P48-09：PASS / FAIL / N/A
MT19-P48-10：PASS / FAIL / N/A
MT19-P48-11：PASS / FAIL / N/A
MT19-P48-12：PASS / FAIL / N/A
MT19-P48-13：PASS / FAIL / N/A
MT19-P48-14：PASS / FAIL / N/A（P49 未落地前默认 N/A）
MT19-P48-15：PASS / FAIL / N/A
MT19-P48-16：PASS / FAIL / N/A

结论：PASS / CONDITIONAL PASS / BLOCKED / INCOMPLETE
阻塞问题：
后续问题：
```

## 4. P48 当前执行摘要

本轮已完成 P48.1–P48.10 的代码与自动化基线（21 条 SciStationCore 测试覆盖 store / yaml / ingestor / module-registry / home aggregator / project dashboard preview）。本文件用于 release/manual pass 的执行模板与验收清单。
