# 任务书 14：项目-论文关系 UI 主数据源切换

更新时间：2026-04-29

## 1. 本轮结论

任务书 13 已完成旧 `raw/papers` 到 `library/papers` 的安全迁移第一版：Settings 可展示 dry-run 计划，用户确认后 copy ready 条目，冲突跳过，报告写入 `.sci-station/migrations/`，Library 读取时同一 paper id 优先显示 `library/papers` 版本。

当前最需要收敛的是项目-论文关系 UI。底层 `ProjectPaperLinkRepository` 已存在，但用户在 Library Inspector 或 paper context menu 中修改项目归属、核心文章和使用目的时，仍主要通过 `Paper.projectIDs`、`coreProjectIDs`、`useFor` 等 metadata 镜像进入，再由 `PaperRepository.save` 间接重建 `library/project_paper_links.yaml`。这能保持兼容，但还不是关系仓库作为第一数据源的产品形态。

任务书 14 的目标是把“项目中的这篇论文是什么关系”变成一等 UI 与一等写入路径，为后续 Agent Panel 和项目生命周期控制打底。

## 2. 当前代码审阅

### 已具备

- `ProjectPaperLinkRepository` 保存 `project_id`、`paper_id`、`is_core`、`folder_path`、`use_for`、`created_at`、`updated_at`。
- `PaperRepository.loadPapers` 会读取关系文件，并把关系叠加到 `Paper.projectIDs`、`coreProjectIDs`、`folderPath`、`useFor`。
- `PaperRepository.save` 会根据 `Paper` 镜像字段调用 `replaceLinks`，保证旧 UI 写入后关系文件不丢。
- `ProjectOverviewView` 的论文数量和核心论文列表已经通过加载后的 `Paper` 镜像显示项目论文。
- Core Test Runner 已覆盖关系仓库 round-trip 与旧 metadata overlay。

### 仍未完成

- Library 的 `PaperClassificationMenuItems` 仍调用 `togglePaperProject` / `togglePaperCoreProject`，实际修改的是 `Paper.projectIDs` 与 `coreProjectIDs`。
- Inspector 中 `Use For` 是论文级 metadata 字段，不是每个项目内独立的 `ProjectPaperLink.useFor`。
- `folderPath` 目前既被用作 Library collection，又被关系层复用；项目内文件夹语义还没有在 UI 上明确。
- 关系模型尚未包含 pin/order 字段；Project Overview 的 Core Papers 只能按现有 Paper priority/status/updatedAt 排序。
- 还没有专门的 ViewModel API 让 UI 直接 upsert/remove 某个 `ProjectPaperLink`。

## 3. 目标

### 目标 A：关系仓库成为 UI 第一写入路径

- 新增 App/ViewModel 层的关系编辑 API：添加/移除项目关系、切换核心状态、更新项目内用途、更新项目内文件夹。
- 这些 API 直接调用 `ProjectPaperLinkRepository`，保存后刷新 papers，并让 `Paper` 镜像只作为兼容显示层。
- 保留 `PaperRepository.save` 的旧 metadata 桥接，避免破坏旧导入、Agent tool 和现有 metadata 编辑流程。

### 目标 B：Library Inspector 显示关系层编辑面板

- 在 Paper Inspector 的 Organization 区域展示每个 active project 的关系行。
- 每行支持 membership、core、project useFor、project folderPath 的编辑。
- 已关联项目靠前显示，未关联项目可快速添加。
- 保存后 `library/project_paper_links.yaml` 立即反映变化。

### 目标 C：项目内 pin/order 设计并落地第一版

- 为 `ProjectPaperLink` 增加保守的排序字段，例如 `is_pinned` 与 `sort_order`。
- YAML 解析需要兼容旧文件：缺失字段时默认未 pin、无排序值。
- Project Overview 的 Core Papers 优先按 pinned、sort_order、priority/status/updatedAt 排序。
- UI 第一版可先提供 pin toggle，拖拽重排可留到下一轮。

### 目标 D：核心验证覆盖

- Core Test Runner 增加关系层编辑 API 回归：UI-facing 方法能直接写入 `project_paper_links.yaml`。
- 验证旧 metadata 中的 `project_ids` / `core_project_ids` 仍会被读取或桥接，不造成项目论文丢失。
- 验证新增 pin/order 字段 round-trip，并验证旧 YAML 缺字段可加载。

## 4. 执行任务

1. 扩展 `ProjectPaperLink` 模型，补齐 pin/order 字段和兼容解析。
2. 为 `ProjectPaperLinkRepository` 增加面向单条关系的 upsert、remove、toggle core、update useFor/folder/pin/order API。
3. 在 `AppViewModel` 增加关系编辑方法，UI 不再直接修改 `Paper.projectIDs` / `coreProjectIDs` 完成项目关系操作。
4. 重构 `PaperClassificationMenuItems` 和 Paper Inspector 的 Organization 区域，展示关系行与项目内字段。
5. 调整 `ProjectOverviewView` 的核心论文排序，使 pinned/order 生效。
6. 增加 Core Test Runner 覆盖关系编辑、兼容解析、Project Overview 排序所需的核心规则。
7. 更新 README 或 Next-Step 文档，说明关系仓库成为 UI 第一写入目标后的边界。
8. 运行 `swift run SciStationCoreTestRunner`。
9. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。

## 5. 验收标准

1. 用户在 Library Inspector 或 paper context menu 添加/移除项目关系时，`library/project_paper_links.yaml` 会被直接更新。
2. 用户切换核心文章状态时，关系文件中的 `is_core` 更新，Project Overview 的 Core Papers 同步变化。
3. 用户能为同一篇论文在不同项目内保存不同的 `use_for` 与 `folder_path`。
4. 关系文件新增 pin/order 字段后，旧关系文件仍可读取。
5. Project Overview 的核心论文列表优先显示 pinned/order 指定的论文。
6. `Paper.projectIDs` / `coreProjectIDs` 仍可作为兼容镜像读取，不会让旧 metadata 的项目关系消失。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 6. 非目标

- 不在本轮实现完整 Agent Panel。
- 不在本轮实现项目归档、删除影响预览或拖拽排序。
- 不在本轮删除 `Paper.projectIDs`、`coreProjectIDs`、`useFor` 等旧 metadata 字段。
- 不在本轮物理移动项目目录或改写旧 `raw/papers` 数据。

## 7. 风险与约束

- 关系仓库与旧 metadata 镜像处在双写/桥接期，必须明确优先级：UI 关系编辑以 `ProjectPaperLinkRepository` 为准，Paper metadata 继续负责论文级字段。
- `folderPath` 的语义需要谨慎：Library collection 是物理/全局分类，Project link folder 是项目内组织提示，不应自动移动论文目录。
- pin/order 增字段要保持 YAML 向后兼容，不能让旧 workspace 打不开。
- UI 编辑关系后要刷新当前 selected paper draft，避免 Inspector 显示旧状态。

## 8. 下一轮之后

任务书 14 完成后，建议进入 Agent Panel V1：在 AI Lab 中提供 goal 输入、plan-only 运行、tool call 审批、run history 和 Copilot Bridge 导出。项目生命周期控制可以在 Agent Panel 之后处理，除非用户更需要归档/排序/删除策略。

## 9. 2026-04-29 完成记录

本轮已完成任务书 14 的主体目标：项目-论文关系 UI 已切到 `ProjectPaperLinkRepository` 作为第一写入路径，`Paper.projectIDs` / `coreProjectIDs` 继续作为兼容镜像。

- `ProjectPaperLink` 新增 `is_pinned` 与 `sort_order`，旧 YAML 缺字段时默认未 pin、无排序值。
- `ProjectPaperLinkRepository` 新增单条关系 upsert、remove、core、useFor、folderPath、pin、sortOrder 编辑 API。
- `AppViewModel` 新增关系层状态与关系编辑方法，Library UI 不再通过直接修改 `Paper.projectIDs` / `coreProjectIDs` 完成项目关系操作。
- Paper Inspector 的 Organization 区域新增项目关系行，支持 membership、core、pin、项目内 `use_for` 和项目内 `folder_path`。
- Library 右键菜单中的项目归属、核心文章和 pin 操作已走关系仓库写入。
- Project Overview 的 Core Papers 排序已优先使用关系层 pin/order，再回退到 priority/rating/updatedAt。
- Core Test Runner 已覆盖 pin/order round-trip、单条关系编辑 API、旧 YAML 兼容和旧 metadata 桥接。

本轮验证：

- `swift run SciStationCoreTestRunner`：通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`：通过。

保留边界：项目内 `folder_path` 只作为项目关系层虚拟分类，不移动 Library collection；拖拽重排留给后续；Agent Panel 与项目生命周期控制不在本轮实现。

## 10. 下一轮入口

下一轮任务书见 [DOC/Proposal15.md](Proposal15.md)。

## 11. Question

1. 项目内 `folder_path` 是否只作为项目内虚拟分类显示，还是要联动 Library collection？建议第一版只做项目内虚拟分类，不移动论文目录。
2. pin/order 是否本轮一起落地？建议本轮先做 `is_pinned` 和 `sort_order` 的数据模型与 pin toggle，拖拽排序留到下一轮。
3. 关系 UI 完成后，下一轮优先做 Agent Panel V1，还是项目归档/排序/删除策略？
4. 旧 metadata 镜像是否需要在关系 UI 编辑后同步回写到 `meta.yaml`？建议第一版不强制回写，读取时由关系仓库 overlay，避免无意义 metadata churn。
