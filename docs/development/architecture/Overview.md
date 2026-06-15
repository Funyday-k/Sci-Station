# 架构总览

Sci-Station 是一个本地优先的 macOS 科研工作台。核心形态是：SwiftUI 应用、本地 Research Root、领域仓储、可选 AI runtime 和发布可追踪的开发流程。

## 高层结构

```text
用户操作
  ↓
SwiftUI Shell / Feature Views
  ↓
AppViewModel / 应用协调层
  ↓
领域服务与仓储
  ↓
Research Root / Keychain / 系统服务 / 可选 Sidecar
  ↓
UI 状态、debug events、diagnostics、release evidence
```

## 代码边界

- `Sci-Station/App/`：应用状态、启动、诊断、窗口协调。
- `Sci-Station/UI/`：SwiftUI 页面、Shell、模块 UI。
- `Sci-Station/Workspace/`：Research Root、模块配置、workspace 模板。
- `Sci-Station/Library/`、`PDF/`、`Wiki/`：论文、阅读、笔记主路径。
- `Sci-Station/Recommendation/`、`Tasks/`：论文推荐，以及推荐结果到阅读 Todo 的闭环。
- `Sci-Station/Agent/`、`LLM/`：AI Lab、工具、权限、provider 抽象。
- `AgentRuntime/`：Python sidecar、UI test runner 和实验性编排。
- `Tools/`：SwiftPM 核心测试 runner 和 UI probe。

## 设计原则

- **本地优先**：论文、笔记、任务和日志默认留在用户选择的 Research Root。
- **文件可读**：优先使用 Markdown、YAML、JSONL、BibTeX、PDF 等可审计格式。
- **兼容优先**：新增字段使用兼容解码；不兼容变化必须写 migration 或阻止打开。
- **AI 可选**：没有 API key 时，核心科研资料管理仍应可用。
- **发布可追踪**：每个测试包都要能定位版本、构建号、commit、测试结果和 known issues。

## 变更入口选择

- 用户可见功能：先写 Proposal，再改领域层，最后接 UI。
- 数据格式变化：先改 schema 文档和测试，再改读写逻辑。
- AI 工具变化：先定义权限、输入输出和审计事件，再接 agent flow。
- UI 性能变化：先定位 invalidation / layout / IO 来源，再做局部化优化。
