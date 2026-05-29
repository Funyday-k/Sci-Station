# 任务书 6：Workspace 偏好、统一搜索前置与 Reader 工作流

## 审阅意见

任务书 6 原始范围覆盖 Workspace Preferences、Apple Reminders 双向同步、SQLite 搜索索引、metadata/BibTeX fixtures、PDF Reader 工作流面板和 README。方向正确，但一次性完成所有内容会把底座、外部系统同步、数据库索引和复杂 UI 读写混在同一轮里，风险偏高。

本轮审阅后将任务书 6 收束为可验证的第一阶段：先建立 workspace 级偏好文件、扩展 todo 外部映射字段、把 Library 搜索覆盖到 abstract/BibTeX/标识符、让 Reader 右侧栏具备 Notes/Tasks/Citations/Links 的真实操作入口，并更新 README 和测试。SQLite/FTS、完整 Reminders 双向冲突处理、provider fixtures 和 Reader Tasks 深水区移交给任务书 7。

## 背景

任务书 5 已经解决了启动恢复、Documents 默认目录、Library 操作区、列拖拽、Quick Link、collection rename、tag chip、todo/calendar、metadata 输入和 BibTeX 出口等高频问题。进入任务书 6 后，Sci-Station 需要把这些单点能力收束成更稳定的日常工作流：偏好随 workspace 走，搜索覆盖更多科研字段，Reader 面板不只是展示，而能写回笔记、创建任务和导出引用。

## 本轮已实施

1. Workspace 偏好底座
   - 新增 `WorkspacePreferences` 与 `WorkspacePreferencesRepository`。
   - 新增 `settings/workspace_preferences.yaml` 种子文件。
   - 工作区创建和打开时会补齐 `settings/` 与偏好文件。
   - Library visible columns 和 column order 从 workspace preferences 读取和保存。
   - Settings 页面显示 preferences 文件、schema version、当前 Library columns，并提供 Reset Library Columns 和 Clear Recent Workspace。

2. 最近 workspace 管理
   - `WorkspaceService` 新增清除最近 workspace bookmark 的入口。
   - 清除时会停止当前 security-scoped access scope，并清除 bookmark 数据。
   - 当前 session 中已经打开的 workspace 不会被强制关闭。

3. Todo 与 Apple Reminders 映射字段
   - `TodoItem` 新增 `externalSource`、`externalIdentifier`、`externalUpdatedAt`、`completedAt`、`dueTime`。
   - `TodoRepository` 编解码这些字段，保留旧 todo 文件兼容性。
   - 新增和已有 todo 都可以发布到 Apple Reminders，并保存 reminder 标识。
   - todo 完成/取消完成时维护 `completedAt`。

4. Library 搜索前置增强
   - 新增 `LibrarySearchService`。
   - 搜索覆盖 title、title translation、short title、citekey、authors、tags、DOI、arXiv、INSPIRE、URL、abstract、BibTeX、publication、venue、publisher、archive、categories、useFor。
   - App 仍保留内存过滤模型，后续可替换为 SQLite/FTS 索引服务。

5. PDF Reader 工作流面板
   - 新增 `PaperAnnotationsRepository`。
   - `Paper` 新增 `annotationsURL(in:)`。
   - Reader 右侧栏新增 Notes、Tasks、Citations 面板。
   - Notes 面板可编辑并保存当前论文的 `annotations.md`。
   - Tasks 面板可创建关联当前 paper id 的 todo，并显示当前论文相关任务。
   - Citations 面板显示 BibTeX，支持复制和导出。
   - Links 面板提供 DOI、arXiv、INSPIRE、URL、PDF URL 的打开按钮，并显示 wiki/backlink 摘要。

6. BibTeX 出口整理
   - BibTeX export sheet 移到 `ContentView` 全局挂载，Library 和 Reader 都能触发。
   - 新增 copy-only 方法供 Reader Citations 面板复用。

7. README 与核心验证
   - README 更新为当前功能、权限说明、手动检查清单和验证命令。
   - Core Test Runner 增加 workspace preferences round-trip、Library search 扩展字段、annotations round-trip、todo Reminders mapping 字段测试。

## 已验证

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
- `get_errors` 对 App/Core 相关文件未报告错误。

## 未完成并移交

1. SQLite/FTS 统一搜索索引尚未实现；本轮只完成了搜索字段覆盖和服务边界。
2. Apple Reminders 还没有真正的双向更新、完成状态回写、删除同步和冲突选择 UI。
3. DOI、arXiv、INSPIRE provider 固定 fixture 测试尚未系统化。
4. Reader Tasks 面板只支持创建和显示关联 todo，还没有完整编辑、完成、删除和筛选。
5. Workspace 最近列表、workspace 级共享视图配置 UI 和 schema migration UI 尚未完成。
6. Search Index 与 Reader/Tasks/Wiki 的统一查询入口仍需任务书 7 继续推进。

## 验收标准

1. 新建或打开旧 workspace 后存在 `settings/workspace_preferences.yaml`。
2. Library 列顺序和可见列保存到 workspace preferences，并能在重启后恢复。
3. Settings 可查看 workspace preferences，且可清除最近 workspace bookmark。
4. Todo YAML 能保留 Reminders 映射字段，已有 todo 可发布到 Apple Reminders。
5. Library 搜索可匹配 DOI、arXiv、abstract、BibTeX 等字段。
6. PDF Reader Notes 面板能写回 `annotations.md`。
7. PDF Reader Citations 面板能复制和导出 BibTeX。
8. README 与当前功能、权限和验证命令一致。
9. SwiftPM Core Test Runner 与 Xcode macOS build 通过。

## 移交到任务书 7

任务书 7 应聚焦“索引与同步的第二阶段”：SQLite/FTS 可重建索引、Reminders 双向同步和冲突策略、provider fixture 回归、Reader Tasks 完整编辑闭环、Workspace 最近列表和 schema migration UI。
