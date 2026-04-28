# 任务书 5：Library 可用性、启动恢复与引用出口收束

## 审阅意见

上一版任务书 5 的方向是正确的：Sci-Station 已经不缺单点功能，下一步重点应放在“研究流程是否可靠”。但原文仍然把过多长期目标放在同一轮里，例如 Reminders 双向同步、SQLite 全文索引、PDF Reader 工作流面板和 metadata refresh 差异预览。这些任务相互依赖，若继续堆在同一个任务书里，会让验收边界变得模糊。

本次修订将任务书 5 收束为已经落地的可用性和可靠性修复：启动后自动恢复工作区、Library 操作区可读、列表列可拖动排序、collection 重命名不丢论文、tag 视觉更清晰、Quick Link 可直接打开外链，以及 BibTeX 导入导出闭环。更大的同步、检索、PDF 工作流任务移交到任务书 6。

## 背景

Sci-Station 当前已经具备本地工作区、论文导入、Library 管理、Wiki、PDF Reader、LLM 总结、Apple Calendar/Reminders 数据接入、扩展论文元数据和 BibTeX 导出。最近几轮使用中暴露的问题主要来自日常操作摩擦：每次启动需要重新选择工作区、Library 顶部按钮排布过散、列表列顺序无法按用户习惯调整、Quick Link 粘贴 URL 后不能直接跳转确认、collection 子文件夹改名后论文在筛选视图中消失、tag chip 太小且颜色识别度不足。

任务书 5 的目标因此调整为：先把这些高频操作打磨稳定，再进入任务书 6 的同步和索引阶段。

## 本轮已实施

1. 启动恢复：恢复 security-scoped bookmark 后保持访问作用域，避免下次启动因无文件权限而清除最近工作区。
2. 默认目录：Create/Open Workspace 和 Import PDF 的系统面板默认定位到用户 Documents 文件夹。
3. Library 操作区：Manage Collections、Manage Tags、Import PDF、Add by Link 正常紧凑排布，不再把主按钮拉到屏幕最右端。
4. 列顺序：论文列表表头支持拖动排序，排序结果继续通过 `library.visibleColumns` 保存。
5. Quick Link：输入框右侧增加外链跳转按钮，支持 `http/https` 链接，也支持 `arxiv.org/...` 这类省略 scheme 的输入。
6. Collection 改名：加载论文时按真实目录推导 collection；重命名 collection 后同步写回该目录内论文的 `collection_path`，避免论文从新文件夹视图中消失。
7. Tag chip：tag 显示改为更大的淡色胶囊，颜色比上一版更深，未定义 tag 会自动获得稳定浅色。
8. Todo 和 Calendar：Dashboard 月历显示事项标题，todo 创建和编辑支持 due date、priority 和 notes。
9. Metadata 输入：Paper Inspector 文本字段支持回车保存，点击空白区域可结束输入状态。
10. BibTeX：DOI、arXiv、INSPIRE 导入尽量保存原生 BibTeX；论文右键可 Export BibTeX，弹窗预览、复制剪贴板并支持导出 `.bib` 文件。

## 已验证

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。
- Core Test Runner 增加了 collection stale `collection_path` 回归覆盖，确保目录已移动但 metadata 仍是旧 collection 时，加载结果仍以真实目录为准。
- Core Test Runner 覆盖了 BibTeX 多行字段 round-trip，以及 todo priority/notes 持久化。

## 仍然存在的缺口

1. Workspace bookmark 现在会保持访问作用域，但还缺少 UI 层的“最近工作区列表”和手动清除入口。
2. Library 列配置仍是本机偏好，还不是 workspace 级共享视图配置。
3. Tag 颜色可见性已经提升，但缺少一套预设 palette 和批量重着色工具。
4. Apple Reminders 仍然没有本地 todo 与系统 reminder 的双向标识映射。
5. BibTeX 已能导入导出，但缺少 DOI/arXiv/INSPIRE provider 固定样例测试和批量导出。
6. Library 搜索仍是内存过滤，没有覆盖 BibTeX、abstract、wiki、annotations 和 LLM summary。
7. PDF Reader 右侧栏仍以只读展示为主，Notes/Tasks/Citations 尚未形成完整读写闭环。

## 验收标准

1. 关闭并重新打开 App 后，最近一次打开的 workspace 能自动恢复。
2. 如果需要重新选择 workspace，系统面板默认打开 Documents 文件夹。
3. Library 顶部按钮保持正常间距，不出现大面积空白分隔。
4. 用户可拖动论文列表表头改变列顺序，重启后顺序仍保留。
5. Quick Link 可直接打开 URL，方便导入前确认网页。
6. 重命名包含论文的 collection 后，论文仍显示在新 collection 视图中。
7. Tags 列显示更大的淡色彩色 tag chip。
8. SwiftPM Core Test Runner 与 Xcode macOS build 通过。

## 移交到任务书 6

任务书 6 应聚焦长期底座：最近工作区管理、workspace 级视图偏好、Reminders 双向同步、统一搜索索引、BibTeX/metadata 回归样例、PDF Reader Notes/Tasks/Citations 读写闭环，以及 README/手动测试清单更新。