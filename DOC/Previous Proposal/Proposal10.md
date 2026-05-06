# 任务书 10：Materials 工作区与 VS Code 联动

## 审阅意见

任务书 9 已完成 Markdown 工作台、AI 产物收束和 snippets 底座。新的问题来自项目材料层：科研项目不仅有论文和 Wiki，还会有代码、图片、数据、输出、脚本、prompt 等文件。它们需要在 Sci-Station 内可读、可定位、可预览，同时不能把 settings、refs、tasks、imports 这类系统文件暴露成日常材料。

本轮已加入 Materials 入口和 dot-prefixed 隐藏约定。最新审阅后，VS Code 联动方向保持合理：Sci-Station 作为科研 workstation 负责项目上下文、材料组织、论文导入与知识沉淀；VS Code / VSCodium 负责代码编辑、运行、terminal、kernel 和 diagnostics。当前先聚焦 Python，避免把 Sci-Station 做成完整 IDE。

同时，论文导入入口需要支持真实使用场景：用户经常一次粘贴多个 DOI、arXiv、PDF URL 或网页链接，因此 Add by Link 应支持批量自动分割、顺序导入、失败项保留。

## 本轮已实施

1. 左侧栏新增 Materials 一级入口。
2. Materials 扫描用户材料路径：`inbox/`、`data/`、`code/`、`figures/`、`outputs/`、`scripts/`、`prompts/`、`shared_research.md`。
3. Materials 隐藏系统路径：`.sci-station/`、`settings/`、`refs/`、`tasks/`、`imports/`。
4. 点号开头的文件或目录视为内部/隐藏内容，不进入 Materials。
5. Workspace 创建/打开时补齐 `.sci-station/`，作为后续内部状态和 VS Code bridge cache 的约定位置。
6. Materials 支持 Markdown、文本、图片、PDF 预览。
7. Materials 支持 Open、Reveal in Finder、Open in VS Code。
8. Project Overview 的 Data、Code Reading、Figures、Outputs 入口改为跳转 Materials。
9. Core Test Runner 覆盖 Materials 扫描、settings 隐藏和 dot-prefixed 隐藏规则。
10. Python 文件在 Materials 中单独识别和预览。
11. Python 材料新增运行面板：System Python、workspace `.venv`、手选 venv 三种运行来源。
12. 支持在 Terminal 中直接运行当前 Python 文件，运行脚本写入 `.sci-station/runs/`。
13. 支持创建 workspace `.venv`，并把当前 Python 环境选择写入 `.sci-station/python_environment.txt`。
14. 支持准备 VS Code 运行任务：写入 `.vscode/tasks.json`，并在 `.sci-station/vscode/last_python_run.json` 记录 bridge 状态，然后打开 workspace 与当前代码文件。
15. Add by Link 与完整导入窗口支持批量输入，按换行、逗号、分号、空白自动分割并去重。
16. 批量导入复用现有 remote import service 顺序导入，失败项留在输入框中，成功项进入 Library。
17. Core Test Runner 覆盖批量链接分割、Python material 分类、VS Code Python task bridge。

## VS Code 联动思路

### 第一阶段：文件与文件夹打开

- 继续使用 macOS `NSWorkspace` 查找 VS Code / VS Code Insiders / VSCodium bundle。
- 支持打开整个 workspace folder。
- 支持打开选中文件。
- 如果找不到 App bundle，回退到 `vscode://file/...` URL handler。
- 如果仍不可用，回退系统默认 App。

### 第二阶段：桥接状态文件（已完成 V1）

- 在 `.sci-station/vscode/` 下保存 bridge 状态，例如最近打开文件、当前 project root、推荐任务、kernel hint。
- Sci-Station 写入状态，VS Code 扩展或任务读取状态。
- 状态文件必须是可重建缓存，不能成为唯一数据源。
- 当前 V1 写入 `last_python_run.json`，记录 Python 文件、运行模式和 VS Code task label。

### 第三阶段：Python 运行 V1（已完成）

- 对 `.py` 文件展示 Python 运行工具条。
- VS Code 路径：Sci-Station 写 `.vscode/tasks.json`，然后打开 VS Code workspace 与文件，由 VS Code terminal 承担运行与显示。
- Terminal 路径：Sci-Station 生成 `.command` 脚本并打开 Terminal，适合作为无需 VS Code extension 的直接运行方式。
- Python 环境路径：System Python、workspace `.venv`、手选 venv。workspace `.venv` 可由 Sci-Station 发起创建。

### 第四阶段：VS Code Extension

- 提供一个轻量 VS Code extension：读取 Sci-Station workspace root。
- 在 VS Code 侧显示 Sci-Station Materials、Pinned Papers、Project Tasks。
- 支持从 VS Code 命令面板回跳 Sci-Station 的 Project/Wiki/Paper。
- 支持把当前编辑文件关联到 Project artifact 或 paper note。

### 第五阶段：Kernel 与任务运行

- 对 `code/`、`scripts/`、`data/` 下的 Python/R/Julia/Notebook 文件提供 kernel hint。
- Sci-Station 只组织上下文和记录输出，不直接替代 VS Code kernel。
- VS Code 负责实际运行、terminal、debug、diagnostics。
- 运行产物回写 `outputs/`，图片回写 `figures/`，摘要回写 `wiki/projects/`。

## 下一轮目标

### 目标 1：Materials 筛选与预览增强

- 增加类型筛选：All、Code、Figures、Data、Outputs、Prompts。
- 增加搜索框，按文件名和相对路径过滤。
- 增加 CSV/JSON 简易结构化预览。
- 增加图片缩放和原始尺寸显示。

### 目标 2：VS Code Bridge V1

- 保留 `.vscode/tasks.json` 与 `.sci-station/vscode/last_python_run.json` 的 V1 形态。
- 下一步研究 VS Code extension 能否自动读取 bridge 状态并直接触发 task。
- 增加运行历史记录与 outputs/figures 回写入口。

### 目标 3：Project Artifact Metadata

- 为材料文件增加轻量 metadata：用途、关联 paper、关联 task、备注。
- metadata 可存为 sidecar，例如 `filename.sci.yaml`，但应默认隐藏在 Materials 中。
- Project Overview 显示最近 material activity。

### 目标 4：VS Code Extension 设计草案

- 定义 extension command 列表。
- 定义 Sci-Station bridge file schema。
- 定义从 VS Code 回跳 Sci-Station 的 URL scheme 或 file-based handoff。

### 目标 5：批量导入增强

- 批量导入时显示每条链接的行内进度。
- 支持从剪贴板自动识别 DOI/arXiv 列表。
- 对失败项提供重试按钮和失败原因详情。

## 验收标准

1. Materials 只显示用户材料，不显示 settings、refs、tasks、imports、`.sci-station` 和点号文件。
2. Code、figure、Markdown、PDF 可在 Materials 中预览或打开。
3. Open in VS Code 能打开 workspace 或选中文件，并在找不到 VS Code 时有合理回退。
4. Python 文件可在 Materials 中预览，并能准备 VS Code 运行任务或通过 Terminal 运行。
5. 用户可选择 System Python、workspace `.venv` 或手选 venv；可从 Sci-Station 发起创建 `.venv`。
6. Add by Link 支持多链接批量粘贴、自动分割、顺序导入和失败项保留。
7. `.sci-station/` 创建、Materials 隐藏规则、批量输入解析、VS Code Python task bridge 有测试覆盖。
8. README 与手动检查清单更新。
9. `swift run SciStationCoreTestRunner` 和 Xcode macOS build 通过。

## 风险与约束

- Sci-Station 不应承担 IDE 的职责；代码运行和 diagnostics 应交给 VS Code。
- 自动触发 VS Code task 需要 extension 或更深 URI/命令桥接；当前 V1 先准备 task 并打开 workspace。
- Bridge 状态必须是缓存，不应锁定用户文件结构。
- Dot-prefixed 约定要兼容 macOS 隐藏文件习惯，不应误删或迁移用户已有文件。
- 系统目录隐藏只影响 Materials 显示，不影响 Settings/Wiki/Tasks 等专门页面读取自己的数据。
