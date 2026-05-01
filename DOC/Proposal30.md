# 任务书 30：MinerU UX GUI Regression and Workspace Cleanup

更新时间：2026-05-01

## 1. 本轮目标

任务书 29 已完成真实 MinerU 转换闭环、AI Knowledge 深层 Markdown 上下文修复、Library 转换 UX 跟进、Copilot legacy 删除和 paper-doc-todo core smoke。任务书 30 聚焦真实 App GUI 回归、外部工作区历史产物清理策略、转换可观测性和轻量本地化收束。

## 2. 已验证状态

- Test_Workspace 的 3 篇 DM 论文当前均为 `extraction_engine: mineru_api`，并生成 `figures/mineru` 本地资产。
- Garani 论文第 5 节蒸发率内容已进入 AI Knowledge prompt，不再被 10k excerpt 截断。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。
- 代码层 Copilot legacy 已删除；部分既有外部工作区可能仍残留历史 `.sci-station/agent/copilot-bridge/` 文件。

## 3. 执行任务

### 3.1 App GUI Regression

1. 用 Xcode 构建后的 App 打开 `/Users/funyday/Documents/Test_Workspace`。
2. 在 Settings -> Library 确认 MinerU API 设置展示、保存和语言偏好文案正常。
3. 在 Library 表格确认 3 篇论文显示 `已转换`，badge 旁“查看 Markdown”入口能打开对应 `paper.md`。
4. 对已转换论文重新触发转换，确认覆盖提示、跳过/失败/fallback 信息和最终状态清晰。
5. 在 AI Knowledge sheet 中确认 PDF -> MD 入口仍可用，并且转换状态不会被刷新清空。

### 3.2 Live AI Answer Regression

1. 在 AI Lab 选择 3 篇 DM 论文作为 AI Knowledge。
2. 直接询问 Garani 论文第 5 节蒸发率公式。
3. 确认回答能引用转换后的 Markdown 深层内容，而不是再次声称只能看到第 4 页。
4. 记录所用 provider、model、prompt context 状态和失败信息。

### 3.3 Workspace Legacy Artifact Cleanup

1. 评估是否需要提供一次性清理历史 `.sci-station/agent/copilot-bridge/` 文件的迁移/按钮/开发者命令。
2. 若实现，默认只清理当前 workspace 的 legacy generated artifacts，不影响 run/thread/session logs。
3. 清理前后写入可审计状态消息，避免静默删除用户可能想保留的 prompt 文件。

### 3.4 Conversion Observability

1. 在批量转换结果中记录每篇论文的 engine、fallback reason、耗时和资产数量摘要。
2. 考虑在 badge tooltip 或转换结果区显示 `mineru_api` / `pdfkit_fallback` / asset count。
3. 给真实 MinerU 返回的常见失败码补充用户可理解的错误说明。

### 3.5 Localization Sweep V3

1. 继续收敛 Library / AI Lab / Settings 转换路径的中英文混杂。
2. 保留 API 原始错误和技术字段英文，但外层操作文案遵守语言偏好。
3. 不引入完整 i18n framework。

## 4. 非目标

- 不恢复 Copilot 特殊 provider 或 Bridge exporter。
- 不引入向量数据库。
- 不自动无限执行 agent loop。
- 不绕过工具审批。
- 不做完整 GUI 自动化测试框架。

## 5. 验收标准

1. App GUI 中 Library 的 MinerU 设置、转换状态和“查看 Markdown”入口经过手动回归。
2. Live AI answer 能从 Garani 转换后 Markdown 回答第 5 节蒸发率公式。
3. 对历史 Copilot Bridge workspace artifact 有明确保留或清理策略，并在代码/文档中落地。
4. 转换结果能让用户看懂成功、fallback、失败、资产数量和下一步操作。
5. `swift run SciStationCoreTestRunner` 通过。
6. `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。

## 6. Question

1. 历史 workspace 中已有的 `.sci-station/agent/copilot-bridge/` 文件下一轮要保留、提示用户手动删除，还是提供一键清理？建议提供开发者区一键清理并带确认。
2. 转换 badge 是否只显示 `已转换/已回退/失败`，还是加一个资产数量短提示？建议 tooltip 显示资产数量，表格中不增加额外文字。
3. Live AI answer regression 是否使用当前默认 provider/model 做真实问答，还是继续用 inspect provider 做可重复 smoke？建议两者都做：真实问答用于体验，可重复 smoke 用于回归。
4. 是否把 Test_Workspace 的 smoke plan/todo 标记为可清理测试产物？建议保留本轮记录，下一轮提供清理选项。

## 7. 完成记录

待执行。