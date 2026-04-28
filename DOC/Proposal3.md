# 任务书 3：PDF 导入与阅读体验修正

## 背景

当前 Sci-Station 在论文导入与阅读体验上存在三处核心问题：

1. 本地 PDF 导入时依赖 PDF 自带元数据，实际质量很差，导致标题、作者、年份大多不可靠。
2. 内嵌 PDF 阅读器放在右侧 inspector 内，阅读空间不足，无法形成专注阅读流程。
3. Library 页头部按钮过多，标题区被压缩；通过链接导入论文的交互不够直接。

本任务书聚焦于修正上述三个问题，并将改动直接落到当前代码中。

## 目标

### 目标 1：重构本地 PDF 导入的元数据来源

- 不再把 PDF 自带 document attributes 作为主要元数据来源。
- 导入本地 PDF 时，优先从 PDF 正文中提取 DOI 与 arXiv 标识符。
- 若识别出 DOI，则优先抓取远程元数据；若 DOI 不可用，则回退到 arXiv 元数据抓取。
- 若远程元数据抓取失败，才退回到文件名级别的兜底信息。

### 目标 2：新增专注式 PDF Reader 模式

- 在侧边栏增加独立的 PDF Reader 入口。
- 点击后，应用切换到专门的 PDF 阅读模式，而不是继续把阅读器塞在 inspector 里。
- 阅读模式继续沿用现有页码记录逻辑，保证 last page 可回写。

### 目标 3：修复 Library 页头布局并优化 Link 导入流程

- 拆开 Library 标题区与操作区，避免标题被按钮挤压。
- 将通过链接导入论文改为显式按钮触发。
- 点击按钮后显示链接输入框与导入操作，而不是让用户在拥挤的头部区域里处理复杂交互。

## 执行任务

### 任务 A：本地 PDF 标识符识别与远程元数据抓取

- 在导入链路中增加 DOI / arXiv 识别能力。
- 为 DOI 增加远程 metadata provider 与 mapper。
- 将本地 PDF 导入改为“识别标识符 -> 拉取远程 metadata -> 生成 Paper”的流程。
- 让 DOI 预览也走真实元数据抓取，避免只显示裸 DOI。

### 任务 B：专门的 PDF 阅读模式

- 增加 PDF Reader section。
- 调整根视图布局：进入 PDF Reader 时，从常规三栏切换为侧栏 + 全页阅读器。
- 在 Toolbar 和 Paper Inspector 中补充进入阅读模式的快捷入口。

### 任务 C：Library 头部与链接导入体验

- 将 Library 页头改为两层布局：标题说明一行，搜索与操作按钮一行。
- 新增 Quick Link Import 面板。
- 保留完整 Identifier Import sheet，同时支持在 Library 中快速粘贴链接并直接导入。

## 验收标准

### 验收 1：PDF 导入

- 导入本地 PDF 时，不再优先使用 PDF document attributes 作为标题与作者来源。
- 若 PDF 正文中包含 DOI 或 arXiv 标识符，应优先生成对应远程元数据。
- 导入后 Paper 的 title、authors、year、doi、arxiv、url、abstract、categories 应尽量由远程数据补齐。

### 验收 2：PDF 阅读

- 侧边栏存在独立的 PDF Reader 入口。
- 选中含本地 PDF 的论文后，可以切换到全页 PDF 阅读模式。
- 翻页后 lastReadPage 仍然会被保存。

### 验收 3：Library UI

- Library 标题不再被头部按钮挤压。
- 存在 Add by Link 按钮。
- 点击后会展开输入框，允许预览并导入链接、DOI、arXiv 或 PDF URL。

## 本轮执行结果

### 已完成

- 已将本地 PDF 导入改为基于 DOI / arXiv 识别与远程元数据抓取。
- 已新增 DOI metadata provider，并让 DOI 预览走真实抓取逻辑。
- 已增加专门的 PDF Reader 模式，并在侧边栏、Toolbar、Inspector 中提供入口。
- 已重排 Library 页头，并加入 Add by Link 按钮与展开式输入面板。

### 已执行验证

- `swift run SciStationCoreTestRunner` 通过。
- 相关 SwiftUI 文件已通过编辑器诊断，无新增类型错误。

## 后续建议

1. 为 DOI metadata mapper 补一组纯 JSON 单元样例，减少后续接口回归风险。
2. 为 PDF Reader 模式补充“上一篇 / 下一篇论文”切换能力。
3. 为 Quick Link Import 面板增加输入框自动聚焦与最近导入历史。
