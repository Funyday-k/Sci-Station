# 任务书 17：Library 原生表格体验 V1

更新时间：2026-04-29

## 1. 本轮结论

任务书 16 已完成 Mac 基础体验第一阶段：第一批菜单命令和快捷键、Library 搜索入口与过滤摘要、Wiki `Cmd+S` 与未保存提示、PDF Reader `Cmd+F` / Find Next/Previous、删除文案、关键 icon-only button 可访问性和空状态下一步操作均已落地。

下一阶段应进入 `docs/development/Comment.md` 中建议的第二阶段：Library 原生化。Library 是 Sci-Station 的核心生产力页面，目前仍是自定义 header + `ScrollView` + `LazyVStack`。这能显示列和支持拖拽列顺序，但对 macOS 用户期待的表格行为支持不足：排序、键盘选择、多选、复制字段、批量操作、右键菜单作用于多选等都难以继续扩展。

任务书 17 的目标是先完成 Library 原生表格体验 V1：优先评估并落地 SwiftUI `Table`，建立排序模型和选择模型，为后续批量操作、列宽持久化和更完整的表格行为打底。

## 2. 当前代码基线

- `LibraryListView` 已有搜索、filter chips、导入入口、删除确认、空状态。
- `LibraryPaperTableView` 名称上是 table，但内部仍是自定义 header + `ScrollView` + `LazyVStack`。
- Library visible columns 和 column order 已保存到 `workspace_preferences.yaml`。
- Paper row 支持单选、双击打开 Reader、右键菜单、项目关系菜单、删除。
- `AppViewModel.filteredPapers` 已统一处理 Project / Folder / Tag / Search 过滤。
- `ProjectPaperLinkRepository` 已是项目关系第一写入路径，Project Overview Core Papers 使用 pin/order 排序。

## 3. 本轮原则

1. **优先 SwiftUI `Table`。** 先用系统控件获得排序、选择、键盘和可访问性基础；只有遇到明确阻塞才记录为后续 `NSTableView` wrapper。
2. **保留现有数据源。** 表格仍从 `appModel.filteredPapers` 渲染，不改 PaperRepository 或关系仓库。
3. **先做单选稳定，再做多选。** V1 必须保持现有 selected paper / inspector 行为；多选批量操作若风险过大，可只建立 selection set，不落地批量写操作。
4. **不破坏现有列偏好。** 已有 visible columns/order 继续可用；列宽持久化可留到后续。
5. **右键菜单继续可用。** 单行右键菜单至少保留 Read in App、Open PDF、Export BibTeX、关系菜单和 Delete Paper。

## 4. 执行任务

### 4.1 评估与切换入口

1. 审阅 `LibraryPaperTableView`、`LibraryColumn`、`LibraryColumnValueView` 和 row context menu。
2. 确认 SwiftUI `Table` 在当前 macOS target 下支持所需列、selection、sort order 和 context menu。
3. 若 SwiftUI `Table` 可以满足 V1，则直接替换自定义列表；若不满足，保留自定义列表并记录阻塞原因到本任务书完成记录。

### 4.2 排序模型

1. 在 App/ViewModel 层增加 Library sort state：
   - 支持 title、authors、year、updated、rating、priority、status。
   - 初始排序保持与现有列表兼容，避免用户打开后顺序突变太大。
2. 将排序状态应用到 `filteredPapers` 后的显示列表。
3. 将排序状态写入 workspace preferences 或在本轮至少保存在 App session；建议本轮写入 workspace preferences。
4. UI 中显示当前排序方向，并允许用户点击列标题排序。

### 4.3 表格列与单选行为

1. 将可见列映射为 `TableColumn`：
   - Title、Authors、Year、Projects、Core In、Collection、Publication、Item Type、DOI、arXiv、Wiki、Tags、Status、Priority、Rating、Updated。
2. 表格 selection 与 `appModel.selectedPaperID` 保持同步。
3. 双击或默认打开行为保留：双击可进入内置 Reader，若无 PDF 则保持 disabled 或无动作。
4. Inspector 继续显示 selected paper draft。
5. 列显示仍受 `workspacePreferences.libraryVisibleColumns` 控制。

### 4.4 多选与批量操作准备

1. 建立 Library selection set，支持多选时不破坏单选 Inspector：
   - 单选时 Inspector 显示该 paper。
   - 多选时 Inspector 可先显示“Multiple papers selected”摘要。
2. 右键菜单若 selection count > 1，第一版至少提供：
   - Export BibTeX for Selection。
   - Clear Selection。
3. 批量移动 folder、批量加 tag、批量加入 project 可作为后续任务，不强行塞入 V1。

### 4.5 键盘与复制

1. 上下方向键应跟随系统 Table selection。
2. Space 预览可先不做 Quick Look，但要记录为任务书 18/后续候选。
3. 增加 Copy Citation / Copy BibTeX 命令或右键项，至少对当前 selected paper 生效。
4. 删除键仍走现有确认，不直接删除。

### 4.6 回归验证与文档

1. 增加必要的核心测试或 ViewModel 纯逻辑测试，至少覆盖 sort state 与排序结果。
2. 更新 README 的 Library 功能说明。
3. 在 `docs/development/Next-Step-Task-Book.md` 标记任务书 17 入口。
4. 运行 `swift run SciStationCoreTestRunner`。
5. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。

## 5. 验收标准

1. Library 论文列表使用系统 `Table` 或任务书记录了明确阻塞和替代实现。
2. 用户能按 title、authors、year、updated、rating、priority、status 排序。
3. 表格 selection 与 Inspector selected paper 同步。
4. 右键菜单保留现有单篇论文操作。
5. 可见列偏好仍生效，不会丢失用户保存的列顺序。
6. 删除仍需要确认，并继续显示实际论文目录相对路径。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 6. 非目标

- 不在本轮实现完整 `NSTableView` wrapper，除非 SwiftUI `Table` 明确无法满足 V1。
- 不在本轮实现列宽持久化。
- 不在本轮实现完整批量编辑写操作。
- 不在本轮实现 Quick Look / Space 预览。
- 不在本轮重构 Sidebar 或窗口模型。

## 7. 风险与约束

- SwiftUI `Table` 在复杂 cell、context menu、多选和双击上的行为可能与自定义列表不同，需要优先保证选中和 Inspector 不回退。
- `LibraryColumnValueView` 当前是通用 cell view，迁移到 `TableColumn` 时要避免过度复制逻辑。
- 多选 selection set 与现有 `selectedPaperID` 需要明确优先级，避免 Inspector 显示错对象。
- 排序写入 workspace preferences 时要保持旧 preferences 可读取。

## 8. 建议拆分顺序

1. 先抽出排序模型和 sorted papers 纯逻辑。
2. 再用 SwiftUI `Table` 替换显示层，保持单选和右键菜单。
3. 再接入可见列偏好。
4. 再处理多选摘要和 selected BibTeX 导出。
5. 最后补文档、测试和验证。

## 9. Question

1. Library V1 是否接受先使用 SwiftUI `Table`，若遇到限制再后续改 `NSTableView` wrapper？建议接受。
2. 多选批量操作本轮是否只做 selection 和 BibTeX export，批量编辑留后续？建议本轮只做低风险批量导出。
3. 排序偏好是否写入 workspace preferences？建议写入，保持 workspace 级行为一致。
4. 如果 Table 迁移影响现有列拖拽排序，是否允许本轮暂停列拖拽、保留 Settings 中的列配置？建议允许，优先系统表格行为。

## 10. 完成记录

完成时间：2026-04-29

本轮按用户确认后的方向完成 Library 原生表格体验 V1：

- Library 论文列表切换为 SwiftUI `Table`，保留 `appModel.filteredPapers` 作为数据源。
- 增加 workspace 级 Library sort state，支持 title、authors、year、updated、rating、priority、status，并写入 `settings/workspace_preferences.yaml`。
- 表格 selection 切换为 selection set；单选继续同步 `selectedPaperID` 和 Inspector，多选时 Inspector 显示 Multiple Papers Selected 摘要与批量动作。
- 右键菜单保留单篇 Read in App、Open PDF、Export BibTeX、项目关系菜单和 Delete Paper，并新增 Copy Citation / Copy BibTeX。
- 多选右键和 Inspector 支持 Export BibTeX for Selection、Copy BibTeX for Selection、Copy Citation for Selection、Clear Selection。
- 删除仍走现有确认流程并显示实际论文目录相对路径。
- SwiftUI `TableColumnBuilder` 当前不适合按任意 workspace 列顺序动态生成完整列集合，因此本轮暂停列拖拽和任意列顺序恢复；可见列设置继续生效，后续 V2 可评估 `NSTableView` wrapper 或更细的 Table column 方案。

验证：

- `swift build` 通过。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
