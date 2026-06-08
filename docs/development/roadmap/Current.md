# 当前版本路线图

## 当前版本

- Version：`0.2.0`
- Branch：`release/0.2.0`
- 类型：Minor beta（本轮变更较多，统一归入更大的 0.2.0 版本号）
- 目标：在 `0.1.0` 基础上完成文档重构与版本管理，落地性能/设计系统地基（Phase 0），并交付一轮 AI Lab + PDF 阅读器的 UI/UX 改进。

## 0.2.0 范围

### 必做

- 重建 `docs/development/` 信息架构，建立版本号、分支、tag、build number 和发布记录规则。
- 建立 AI 可执行 Proposal、changelog、release record 模板。
- 建立 `0.2.0` Proposal 和 release record。
- 更新根 README / developer docs / AgentRuntime README 的旧路径引用。
- Phase 0 地基（见 `proposals/Proposal-Phase0-Foundations.md`）：扩展设计 tokens、组件库，抽出 `TodoQueries` 与 `AgentStreamStore`。
- AI/PDF UX 反馈修复（见 `../../user-feedback/`）：汉化 AI 模式标签、约束「思考过程」框宽度、隐藏工具调用行时间、右栏可见的拖拽手柄、选中文本「询问 AI」快捷动作。

### 进行中

- PDF 右栏 Tab 栏改为竖向图标样式。
- 窄栏下 AI 对话输入框固定在底部，并做专门的窄布局优化。

### 可选

- 递增 Xcode `MARKETING_VERSION` 到 `0.2.0`。
- 递增 `CURRENT_PROJECT_VERSION`。
- 添加 About/diagnostics 中更清晰的 beta 通道显示。

### 不做

- 不改变用户数据 schema。
- 不更改 AI provider 行为。
- 不提交构建产物、私有工作区数据或密钥。

## 完成定义

- 文档目录可从 `docs/development/README.md` 导航。
- 旧 Proposal 任务书不再作为开发入口。
- `CHANGELOG.md` 有 `0.2.0` 记录。
- `releases/0.2.0.md` 有发布清单。
- `proposals/Proposal-0.2.0.md` 可直接交给 AI 执行。
- 已落地的代码改动通过 `SciStationCoreTestRunner` 与 macOS Debug 构建。
