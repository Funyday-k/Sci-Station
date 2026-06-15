# 开发模块索引

本目录按长期维护模块组织开发说明。完成一个 Proposal 后，应把长期有效的设计约束、数据路径、测试入口和常见陷阱沉淀到对应模块，而不是继续堆在任务书中。

## 模块列表

- `ShellAndNavigation.md`：窗口、启动、侧边栏、ProjectSpace、toolbar、路由恢复。
- `HomeWidgetsAndLayout.md`：首页/项目小组件、尺寸体系、四列单位网格、拖拽重排。
- `VisualDesignSystem.md`：色彩、密度、Liquid Glass 视觉边界、优秀产品参考和跨模块 UI 一致性。
- `WorkspaceAndModules.md`：Research Root、workspace module、插件贡献、设置。
- `LibraryPDFWiki.md`：论文库、PDF reader、Wiki、Markdown。
- `RecommendationReadingTodo.md`：Recommendation 和阅读 Todo 闭环；独立 Queue / ReadingPlan 已退役。
- `AILabAndRuntime.md`：AI Lab、agent tools、LLM、sidecar、权限。
- `TestingDiagnostics.md`：debug events、diagnostics、UI test bridge、测试证据。
- `Performance.md`：SwiftUI 性能、AppViewModel invalidation、启动和滚动性能。

## 模块文档写法

每个模块文档应包含：

- 负责范围。
- 关键代码入口。
- 主要数据路径。
- 不变量和禁止回归点。
- 常用测试命令。
- 发布前检查项。
