# 任务书 29：Real MinerU Smoke and Paper-Doc-Todo E2E

更新时间：2026-05-01

## 1. 本轮目标

任务书 28 已修复 MinerU zip 图片资产恢复：转换结果中的本地图片会复制到论文目录 `figures/mineru/`，`paper.md` 中的 Markdown/HTML 图片链接会改写为稳定相对路径，并补齐批量转换结果摘要。任务书 29 聚焦真实工作区闭环：在 App 中对 Test_Workspace 重新跑 MinerU API 转换，确认图片可打开，再执行 paper-doc-todo 端到端 smoke。

## 2. 已验证状态

- MinerU API token 已保存在 `~/Documents/Test_Workspace#mineru-api` 的 Keychain account 中。
- `swift run SciStationCoreTestRunner` 已通过，其中包含 mock MinerU zip 图片恢复测试。
- Test_Workspace 当前 3 篇 `paper.md` 仍是 `extraction_engine: pdfkit_fallback`，需要重新转换来验证真实图片资产。
- GitHub Copilot UI 入口已隐藏；旧源码仍保留为 legacy code。

## 3. 执行任务

### 3.1 Real MinerU API Smoke

1. 在 Xcode 构建后的 App 中打开 `~/Documents/Test_Workspace`。
2. 选择 3 篇带 PDF 的论文，触发“转换为 Markdown”或 AI Knowledge 的 `PDF -> MD`。
3. 允许覆盖当前 `pdfkit_fallback` 的 `paper.md`。
4. 对每篇论文检查：
   - `paper.md` frontmatter 为 `extraction_engine: mineru_api`。
   - 正文不再是 `status: not_extracted` stub。
   - `paper.md` 中的图片链接指向 `figures/mineru/`。
   - `figures/mineru/` 下有真实 PNG/JPG/WebP/SVG 等图片文件。
5. 记录每篇论文的转换结果、失败信息、fallback reason 与耗时。

### 3.2 Paper-Doc-Todo E2E Smoke

1. 将 Test_Workspace 的 3 篇论文作为 AI Knowledge。
2. Conversation：询问共同主题、关键差异、下一步阅读建议，确认回答引用转换后的 Markdown 内容。
3. Plan：生成 root `wiki/plans/` 下的研究计划草稿。
4. Assistant：审批创建至少 1 个“阅读/总结”todo，确认工具调用可审查、可拒绝、可回放。
5. 检查 session event timeline、permission dock、tool result 与失败点。

### 3.3 Conversion UX Follow-Up V2

1. 已转换 badge 增加“查看 Markdown”快捷入口评估；如果交互清晰，则实现。
2. 转换失败 tooltip 展示最近错误，并避免在批量转换后被后续刷新清空。
3. 若真实 API 返回图片路径格式与 mock 不同，补充对应测试样例。

### 3.4 API Provider Cleanup Decision

1. 决定 legacy `GitHubCopilotConfiguration*`、bridge exporter 与相关测试是否删除。
2. 若删除，确保 workspace seed、settings、provider enum、core tests 和 Xcode build 不再依赖它们。
3. 普通 API provider 模板继续保持 OpenAI-compatible endpoint + model name + api key，不做厂商特殊优待。

### 3.5 Localization Sweep V2

1. 覆盖 AI Lab、Settings、Library 转换路径剩余中英文混杂文案。
2. 只做当前活跃路径轻量统一，不引入完整 i18n framework。
3. 保留技术诊断信息的英文原文，但外围 UI 状态遵守语言偏好。

## 4. 非目标

- 不引入向量数据库。
- 不自动无限执行 agent loop。
- 不绕过工具审批。
- 不把完整 i18n/localization framework 做进本轮。
- 不恢复 GitHub Copilot 特殊 provider UI。

## 5. 验收标准

1. Test_Workspace 的 3 篇 PDF 至少完成一次真实 MinerU API 转换尝试。
2. 成功转换的论文 `paper.md` 使用 `mineru_api`，并且图片链接可在本地文件系统解析。
3. 完成一次 paper-doc-todo E2E smoke，并能在 timeline 中回放关键事件。
4. 转换 UX 的失败/跳过/成功状态对用户可解释。
5. Copilot legacy 源码去留有明确结论和实现或记录。
6. `swift run SciStationCoreTestRunner` 通过。
7. `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。

## 6. Question

1. 下一轮真实 MinerU smoke 是否直接覆盖 Test_Workspace 当前 3 篇 `pdfkit_fallback` 的 `paper.md`？建议覆盖。
2. 若真实 API 转换耗时较长或失败，是否先保留已成功的论文并只重试失败项？建议是。
3. Copilot legacy 源码是否在下一轮彻底删除？建议如果 Xcode/SwiftPM 依赖清楚，就删除。
4. “已转换”badge 是否需要直接打开 `paper.md`，还是只保留右键/文档区入口？建议加一个轻量入口。

## 7. 完成记录

已完成。

- Real MinerU API smoke 已对 `~/Documents/Test_Workspace` 的 3 篇 DM 论文完成真实转换检查；当前 3 篇 `paper.md` 均为 `extraction_engine: mineru_api`。
   - `garani2017-dark-matter-sun`：`figures/mineru` 资产数 21，Markdown 中含 `figures/mineru/` 链接。
   - `sarkarxxxx-constraining-dark-matter`：`figures/mineru` 资产数 12，Markdown 中含 `figures/mineru/` 链接。
   - `widmark2017-thermalization-time-scales`：`figures/mineru` 资产数 10，Markdown 中含 `figures/mineru/` 链接。
- MinerU signed upload 已修复为不发送 `Content-Type` 的 PUT；mock 测试会在 upload endpoint 上断言 `Content-Type == nil`，并接受 2xx 上传响应。
- 转换结果状态已区分 `mineru_api` 成功、`pdfkit_fallback` 回退和失败；Library badge 增加 `已回退` 状态，并会展示 fallback reason。
- AI Knowledge 论文上下文截断已修复：被选入/选中的论文使用更长 Markdown/PDF excerpt，验证覆盖 Garani 第 5 节蒸发率内容，不再只截到前 10k 字符。
- MinerU API 设置已从 AI Lab 设置移动到 Library 设置栏目；普通 LLM provider 保持 OpenAI-compatible endpoint + model + API key。
- Library 已转换 badge 旁新增轻量“查看 Markdown”入口，单篇右键菜单也提供“查看 Markdown”。
- Copilot legacy 已按用户决策删除：`GitHubCopilotConfiguration*`、SDK adapter、Copilot Bridge exporter、AppViewModel 入口、URL scheme、workspace seed 目录和相关 core tests 均已清理；README 已同步删除 Copilot Bridge 说明。
- Paper-doc-todo E2E smoke 已完成：
   - Conversation prompt 检查包含 3 篇 AI Knowledge 论文和 Garani 深层第 5 节内容，conversation run 无工具调用。
   - Plan run 生成并审批写入 `wiki/plans/dm-paper-doc-todo-smoke.md`。
   - Assistant run 生成并审批创建 1 个 `mineru-smoke` 阅读/总结 todo。
   - `session_events.jsonl` 已记录 `permission_requested`、`permission_resolved`、`hook_result` 和 `tool_call_completed`。

验证：

- `get_errors` 对本轮改动的 Swift/SwiftUI 文件无诊断错误。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。

备注：

- 本轮真实 smoke 通过临时 runner 复用 `SciStationCore` 服务执行，未使用 GUI 自动化驱动 App；Xcode App target 已构建通过。下一轮可做一次手动 GUI 回归，确认 Library 设置位置、badge 入口和覆盖确认在真实窗口中的交互细节。
