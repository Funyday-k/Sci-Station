# MT17 Localization, Project Lifecycle, Toolbar Policy

更新时间：2026-05-11

## Preconditions

1. 打开一个包含至少两个项目、若干论文和 Wiki 页面 的 Sci-Station workspace。
2. Xcode build 与 `swift run SciStationCoreTestRunner` 已通过。
3. 在 Settings > Workspace 中可以切换 Interface Language。

## Test Cases

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT17-P43.8-01 | 切换中文 | Settings > Workspace > Interface Language 选择中文。 | 主 toolbar、顶层 sidebar、项目树、Projects 列表、Settings 主要分类显示中文。 |
| MT17-P43.8-02 | 切换英文 | Interface Language 选择 English。 | 同一入口恢复英文；布局不出现明显截断。 |
| MT17-P43.8-03 | Home toolbar | 打开 Home。 | 不显示 Import PDF / Add by Identifier；仍显示 Workspace / AI / Refresh 等全局动作。 |
| MT17-P43.8-04 | Library toolbar | 打开 Library。 | 显示 Import PDF / Add by Identifier 或中文等价；不显示 Wiki/PDF Reader 专用动作。 |
| MT17-P43.8-05 | PDF toolbar | 从论文打开 PDF Reader。 | 显示搜索、上一处、下一处、标注；不显示 Library column action。 |
| MT17-P43.8-06 | Wiki toolbar | 进入 ProjectSpace Wiki tab。 | 显示新建页面、保存、预览；不显示 PDF 标注动作。 |
| MT17-P43.8-07 | 项目树搜索 | 在侧栏项目树搜索项目名、描述或路径片段。 | 列表只显示匹配项目；清空后恢复。 |
| MT17-P43.8-08 | 归档项目 | 对活跃项目打开 context menu，选择归档并确认。 | 项目从 active list 隐藏；当前 route 回退到 Projects；状态栏提示归档完成。 |
| MT17-P43.8-09 | 显示并恢复归档 | 打开 Show Archived，选择归档项目 Restore。 | 项目回到 active list；可重新进入 ProjectSpace。 |
| MT17-P43.8-10 | 移入 workspace trash | 对项目选择 Move to Trash 并确认。 | 二次确认说明影响范围；项目目录移入 `.sci-station/trash/projects/`；route 安全回退。 |
| MT17-P43.8-11 | Settings 主路径 | 打开 Settings 的 Workspace / Modules / Projects / Library。 | 分类标题和主要入口文案随语言切换。 |
| MT17-P43.8-12 | 审计日志抽查 | 执行语言切换、toolbar route 切换、项目归档/恢复/移入 trash。 | debug log 包含 `l10n.language.change`、`toolbar.policy.resolve`、`project.archive.*`、`project.restore.confirmed`、`project.delete.*`。 |

## Known Deferred Checks

1. Library 深层 metadata inspector、PDF reader 内部 annotation editor、Wiki file manager、Markdown editor、AI Lab permission review 仍按 `docs/development/localization/P43.8_string_inventory.md` 登记为 deferred。
2. 中文长文案导致的紧凑布局问题统一进入 P43.9 UI bug bash。