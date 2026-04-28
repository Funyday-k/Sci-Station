# 任务书 11：VS Code Bridge 自动运行、Python 环境与 Materials 增强

## 审阅意见

任务书 10 已把 Materials 从“可浏览材料”推进到“可运行 Python 的科研工作区入口”：Sci-Station 可以预览 Python，选择 System Python、workspace `.venv` 或手选 venv，准备 VS Code task，也可以用 Terminal 运行脚本。同时，论文 Add by Link 已支持多链接自动分割和批量导入。

下一轮不应把 Sci-Station 变成 IDE，而应把 bridge 做得更顺手：Sci-Station 继续负责项目上下文、材料关联、任务与论文导入；VS Code 负责真正的执行、terminal、debug、kernel 与诊断。核心问题是让“运行”从准备 task 变成更接近一键运行，并把运行历史、输出文件和材料元数据接起来。

## 本轮基线

1. `.py` 文件在 Materials 中独立识别并可预览。
2. Python 运行面板支持 System Python、workspace `.venv`、手选 venv。
3. Create `.venv` 会生成 Terminal `.command` 脚本并记录环境选择。
4. Run in VS Code 会写入 `.vscode/tasks.json` 与 `.sci-station/vscode/last_python_run.json`，再打开 workspace 与当前文件。
5. Terminal 运行会写入 `.sci-station/runs/*.command`。
6. Add by Link 与完整导入窗口支持批量粘贴、自动分割、顺序导入、失败项保留。
7. Core Test Runner 覆盖批量输入解析、Python material 分类和 VS Code task bridge。

## 下一轮目标

### 目标 1：VS Code Extension Bridge V1

- 设计一个轻量 VS Code extension，读取 `.sci-station/vscode/last_python_run.json`。
- 提供命令：Run Sci-Station Python Material。
- 命令执行当前 bridge task 或直接在 VS Code terminal 中运行记录的 Python 文件。
- 支持从 VS Code 命令面板打开 Sci-Station workspace context 文件。
- 扩展应只读取 bridge/cache 文件，不成为唯一数据源。

### 目标 2：运行历史与输出回写

- 在 `.sci-station/runs/history.jsonl` 记录每次运行的文件、运行模式、时间、退出码和输出目录提示。
- 在 Materials 中显示最近运行状态。
- 支持将运行产物归档到 `outputs/`，图片归档到 `figures/`。
- Project Overview 显示最近 material activity。

### 目标 3：Python 环境管理增强

- 显示当前解释器版本和是否可执行。
- 为 workspace `.venv` 提供安装依赖入口：从 `requirements.txt` 或手动输入 package list。
- 支持检测 `requirements.txt`、`pyproject.toml`、`environment.yml`。
- 在 `.sci-station/python_environment.txt` 外增加结构化配置版本，避免后续迁移困难。

### 目标 4：Materials 筛选与结构化预览

- 增加类型筛选：All、Code、Figures、Data、Outputs、Prompts。
- 增加搜索框，按文件名和相对路径过滤。
- 增加 CSV/JSON 简易结构化预览。
- 增加图片缩放和原始尺寸显示。

### 目标 5：批量导入体验增强

- 批量导入时显示每条链接的行内状态：pending、importing、success、failed。
- 支持失败项单独重试。
- 支持从剪贴板自动提取 DOI/arXiv/URL 列表。
- 支持导入结束后生成批量导入报告。

## 验收标准

1. VS Code extension 可读取 Sci-Station bridge 状态并运行当前 Python material。
2. 不安装 extension 时，现有 VS Code task 与 Terminal 运行路径仍可用。
3. 每次 Python 运行都有可查看的历史记录。
4. Materials 可按类型筛选和搜索。
5. CSV/JSON 至少提供基础表格或格式化预览。
6. 批量导入可看到每条链接的进度和失败原因。
7. README 与手动检查清单更新。
8. SwiftPM Core Test Runner、Xcode macOS build 通过；若加入 VS Code extension，则补充 extension 单元或 smoke test。

## 风险与约束

- VS Code extension 不应绕过用户权限或自动执行未知脚本；第一次运行应清楚显示将运行的文件和解释器。
- Python package 安装需要用户确认，不能静默修改环境。
- 运行历史是辅助索引，可重建或清理，不应承载唯一科研数据。
- Materials 搜索和预览不能扫描系统目录或 dot-prefixed 内部目录。