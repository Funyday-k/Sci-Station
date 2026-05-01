# 任务书 28：MinerU Asset Restoration, Conversion UX, and Task-Book Review

更新时间：2026-05-01

## 1. 本轮目标

任务书 27 已完成 AI Lab 输入体验、Conversation 可见输出、Hook 最近结果弹窗、基本语言偏好、MinerU API-first Markdown 转换入口、论文转换状态 badge、右键/批量转换，以及 GitHub Copilot 特殊入口隐藏。本轮根据最新反馈调整优先级：先修复 MinerU 转换后 `paper.md` 中图片引用悬空的问题，再把批量转换结果摘要补全，并把真实 API smoke 与 paper-doc-todo E2E 收束到下一任务书中继续跑。

## 2. 已验证状态

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -quiet -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过；仅有多个 My Mac destination 的 Xcode warning。
- `~/Documents/Test_Workspace` 的 LLM Keychain token 存在。
- `~/Documents/Test_Workspace#mineru-api` 的 MinerU API Keychain token 已配置；token 只保存在 Keychain，不写入仓库文件。
- Test_Workspace 当前 3 篇 `paper.md` 仍是 `extraction_engine: pdfkit_fallback`，需要在新版本中重新触发 MinerU API 转换来生成带图片资产的 Markdown。
- GitHub Copilot 在 UI/provider 选择/新 workspace seed 中已隐藏，但部分旧 configuration/store/exporter 源码仍保留，未暴力删除以降低本轮构建风险。

## 3. 执行任务

### 3.1 MinerU 图片资产恢复

1. MinerU API zip 解压后继续保留 `mineru-api-output` 诊断目录。
2. 读取 `full.md` 或最大 Markdown 文件时，识别 Markdown 图片语法 `![](...)` 与 HTML `<img src="...">`。
3. 对本地相对图片路径，从 zip 解压目录复制图片到论文目录 `figures/mineru/`。
4. 重写 `paper.md` 图片路径为相对论文 Markdown 的稳定路径，例如 `figures/mineru/images/figure-1.png`。
5. 跳过 `http`、`https`、`data:`、`mailto:` 等外部或内联资源；不把 zip 外路径复制进论文目录。

### 3.2 MinerU API Smoke 准备

1. 用 mock URLProtocol 模拟 MinerU batch upload、signed upload、poll result、zip download。
2. 在测试 zip 中放入 `full.md`、PNG 与 WebP 图片，验证最终 `paper.md` 链接和图片落盘。
3. 真实 Test_Workspace API smoke 留到 Proposal29：需要用户从 App UI 重新触发 3 篇 PDF 的 MinerU 转换，以使用已经修复的资产复制逻辑并避免在任务书修订阶段静默消耗外部 API 配额。

### 3.3 Paper-Doc-Todo End-to-End Smoke

1. 选择 Test_Workspace 的 3 篇论文作为 AI Knowledge。
2. Conversation：询问共同主题、关键差异和下一步阅读建议，确认回答基于转换后的 Markdown 内容。
3. Plan：生成 root `wiki/plans/` 下的研究计划草稿。
4. Assistant：审批创建至少 1 个“阅读/总结”todo，确认工具调用可审查、可拒绝、可回放。
5. 记录 session event timeline、permission dock、tool result 与失败点。

### 3.4 Localization Sweep V1

1. 扫描 AI Lab、Settings、Library 转换相关界面，把本轮新增的中英文混杂文案统一到语言偏好入口。
2. 为常见状态文案补中文/英文对照：转换状态、API 设置保存、转换失败、无 PDF、正在转换。
3. 不在本轮做完整 app i18n 框架；只做当前活跃路径的轻量统一。

### 3.5 API Provider Cleanup V2

1. 评估是否删除遗留 `GitHubCopilotConfiguration*`、bridge exporter 和相关方法，还是保留为未暴露 legacy code。
2. 若删除，确保 workspace seed、settings、provider enum、core tests 和 Xcode build 都不再依赖它们。
3. 设计普通 API provider 模板：DeepSeek、OpenAI、OpenRouter、Moonshot/其他 OpenAI-compatible endpoint 都走相同配置模型。
4. 确认 UI 不再把任何厂商模型提升为特殊地位。

### 3.6 Conversion UX Follow-Up

1. 在转换中状态提供更明确的 row-level 进度或最近错误 tooltip。
2. 对批量转换增加结果摘要：成功、失败、跳过无 PDF、跳过已有 Markdown。
3. 评估是否给“已转换”badge 添加“查看 Markdown”快捷入口。

## 4. 非目标

- 不引入向量数据库。
- 不自动无限执行 agent loop。
- 不绕过工具审批。
- 不把完整 i18n/localization framework 做进本轮。
- 不把 Copilot 作为特殊 SDK provider 恢复到 UI。

## 5. 验收标准

1. MinerU mock API 转换能写出 `extraction_engine: mineru_api` 的 `paper.md`。
2. 转换 zip 内 PNG/WebP 图片被复制到 `figures/mineru/`。
3. Markdown `![](...)` 与 HTML `<img src="...">` 都被重写为稳定相对路径。
4. 批量转换摘要包含成功、失败、无 PDF 跳过、已有 Markdown 跳过。
5. SwiftPM core validation 通过。
6. Xcode macOS build 通过。
7. 真实 Test_Workspace MinerU API smoke 与 paper-doc-todo E2E 被明确转入下一任务书。

## 6. Question

1. 下一轮是否直接在 App 中对 Test_Workspace 的 3 篇 PDF 跑真实 MinerU API smoke？建议是。
2. 跑真实转换时是否允许覆盖当前 `pdfkit_fallback` 的 `paper.md`？建议允许覆盖，以验证图片资产修复。
3. Copilot 遗留源码要彻底删除，还是保留为隐藏 legacy 以便以后参考？建议删除 UI 入口已完成，源码删除放在下一轮单独处理。
4. Paper-doc-todo E2E 是否以 Test_Workspace 的 3 篇暗物质论文作为固定 smoke 数据？建议是。

## 7. 完成记录

已按修订范围执行。

- 修复 `PaperMarkdownConversionService`：MinerU API zip 解压后会复制本地图片资产到论文目录 `figures/mineru/`，并重写 Markdown/HTML 图片引用。
- 新增核心验证：mock MinerU API 返回带图片的 zip，验证 `paper.md` 生成、PNG/WebP 落盘、图片链接重写。
- 完善转换 UX：批量转换完成消息现在区分成功、失败、无 PDF 跳过、已有 Markdown 跳过；无 PDF 行写入 tooltip 诊断信息。
- 已运行 `swift run SciStationCoreTestRunner`，通过。
- Xcode build 需要在最终验证阶段复跑。
- 真实 Test_Workspace MinerU API smoke、paper-doc-todo E2E、Copilot legacy 源码去留，转入 `DOC/Proposal29.md`。