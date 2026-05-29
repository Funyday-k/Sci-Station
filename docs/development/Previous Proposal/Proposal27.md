# 任务书 27：AI Lab Workflow Polish and API Markdown Conversion

更新时间：2026-05-01

## 1. 本轮目标

任务书 26 已完成 Conversation 可用性修复、OpenAI-compatible streaming V1、MinerU-first conversion path、project/thread scoped preferences，以及 Test_Workspace 的数据层 smoke 检查。本轮根据 2026-05-01 用户反馈修订为：打磨 AI Lab 的真实聊天体验、统一语言设置入口、把论文 Markdown 转换切到 MinerU API 工作流并补齐批量/自动转换入口，同时移除 GitHub Copilot 特殊化入口，后续模型统一按 API provider 接入。

## 1.1 用户反馈与决策

1. AI Lab 设置中的最近结果需要折叠，或提供查看入口并用弹窗展示完整信息。
2. 语言需要统一，或在基本设置里加入中文/英文设置。
3. Markdown 转换应参考本机 `sync-papers` 技能原型，使用 MinerU API 方式；新论文加入时自动转换；论文列表显示转换是否成功；右键提供转换 Markdown；支持多选批量转换。
4. AI Lab 发送逻辑改为 Return 直接发送，Shift+Return 换行，避免换行和发送同时发生。
5. AI 生成字符动画不能暴露 JSON，只显示要发送的内容本身。
6. GitHub Copilot 不再作为特殊 SDK/Bridge 路径处理，本轮先删除特殊入口；未来与 DeepSeek/OpenAI-compatible 等一样作为普通 API 模型接入。
7. Question 4 已回答：Test_Workspace smoke 的 todo 默认生成“阅读/总结”类任务。

## 2. 已验证状态

- SwiftPM core validation 通过。
- Xcode macOS build 通过。
- Conversation 模式不再因为自然语言或 Markdown 输出缺少 JSON 而报错。
- New Chat 会显示空 timeline。
- 生成中 Return 不再触发 Stop。
- AI Lab 气泡支持 Markdown 渲染。
- OpenAI-compatible provider 已支持 SSE delta streaming。
- MinerU 默认命令已设为 `mineru`；命令不可用时 fallback 到 PDFKit。
- Test_Workspace 位于 `~/Documents/Test_Workspace`，包含 3 篇 PDF；当前 `paper.md` 都还是 `status: not_extracted` stub。

## 3. 执行任务

### 3.1 Conversation Chat Protocol and Input UX

1. 为 Conversation 模式引入独立 chat response model，不再要求 JSON。
2. Plan / Assistant 保持 `AgentPlan` JSON schema 和 tool approval flow。
3. Session event replay 同时支持 chat message 与 plan message。
4. UI 中 Conversation 输出不再显示 “Assistant Summary” 类 plan 残留概念。
5. 输入框 Return 发送，Shift+Return 换行，且一次按键只执行一个动作。
6. 流式/字符动画只显示自然语言内容，隐藏 JSON envelope、schema 或 plan 字段。

### 3.2 AI Lab Settings and Language

1. AI Lab 设置中的最近结果默认折叠，或只显示摘要并提供查看完整结果弹窗。
2. 在基本设置加入 App 语言选项：跟随系统、中文、English。
3. 至少让新改动的 AI Lab/设置文案通过语言设置统一取值，避免同一屏中英文混杂。

### 3.3 MinerU API Markdown Conversion

1. 参考 sync-papers 技能的 MinerU API 工作流：上传、轮询、下载 zip、选择主 Markdown、写入 paper 文档目录。
2. 新论文加入后自动排队转换 Markdown。
3. 论文列表/详情显示 Markdown 转换状态标签：未转换、转换中、成功、失败。
4. 论文右键提供“转换为 Markdown”；多选时支持批量转换。
5. 对 Test_Workspace 的 3 篇论文执行真实 MinerU API 或明确记录 API token/网络等 fallback 原因。
6. 检查生成的 `paper.md` 是否包含正文结构、标题、页/章节内容。

### 3.4 Paper-Doc-Todo End-to-End Smoke

1. 选择 Test_Workspace 全部论文作为 AI knowledge。
2. Conversation：询问 3 篇论文的共同主题、差异和下一步阅读建议。
3. Plan：生成 root `wiki/plans/` 下的研究计划草稿。
4. Assistant：审批创建至少 1 个“阅读/总结”todo，并确认工具调用可审查、可拒绝、可回放。
5. 在任务书记录截图/日志观察和失败点。

### 3.5 Streaming Robustness

1. 处理 OpenAI-compatible streaming 中断、空 delta、错误 JSON chunk。
2. Stop 后保留 partial response，并允许用户继续追问。
3. 为 streaming parser 增加最小核心测试。

### 3.6 API Provider Cleanup

1. 删除或隐藏 GitHub Copilot 特殊 SDK/Bridge 入口。
2. 模型选择只展示已成功配置的普通 API provider/model。
3. 保留未来扩展点：新增模型都按相同 provider adapter 方式出现，不在 UI 中特殊化。

## 4. 非目标

- 不引入向量数据库。
- 不自动无限执行 agent loop。
- 不绕过工具审批。
- 不把 Project Wiki 普通 UI 写入问题混入本轮。

## 5. 验收标准

1. Conversation 模式可直接显示普通 Markdown 聊天回复，且不会进入 JSON parse error path。
2. Test_Workspace 的 3 篇论文完成真实 MinerU 或明确记录 fallback 原因。
3. 完成一次 paper-doc-todo end-to-end smoke：读论文、问答、计划、审批 todo。
4. Stop/partial streaming 行为可复现。
5. SwiftPM core validation 通过。
6. Xcode macOS build 通过。
7. AI Lab 最近结果不再在设置页直接铺开完整长文本。
8. 基本设置存在语言选项，至少新改动区域遵守该设置。
9. 论文列表/右键/多选批量能触发 Markdown 转换，并能看到转换状态。
10. GitHub Copilot 特殊入口已删除或隐藏。

## 6. Question

1. 你是否愿意先在本机安装/暴露 `mineru`，还是下一轮我继续把 fallback 路径做得更完整？
2. Conversation 模式是否可以彻底脱离 JSON，只把 Plan / Assistant 保持结构化？
3. 下一轮新增模型时，是否只保留 OpenAI-compatible API 这一类通用入口，还是要为常用厂商预置模板？
4. Test_Workspace smoke 的 todo 创建默认使用“阅读/总结”类任务。

## 7. 完成记录

已完成本轮可在当前环境落地的实现与验证。

- Conversation 模式已改为自然 Markdown 回复路径：Plan / Assistant 继续使用结构化 `AgentPlan`，Conversation prompt 明确禁止 JSON / tool_calls / envelope metadata；若模型仍返回 JSON envelope，UI 只提取可见回答字段。
- AI Lab composer 已改为 Return 发送、Shift+Return 换行；生成中 Return 不再同时插入换行和发送。
- Hook Activity 最近结果已改为短摘要 + “查看”弹窗，完整 `additionalContext` 不再直接铺满设置/运行面板。
- 基本设置新增语言偏好：跟随系统、中文、English；本轮新增 UI 文案开始走 `localized` 入口。
- Markdown 转换已改为 MinerU API-first：创建上传 URL、PUT PDF、轮询 batch result、下载 zip、解压并优先选择 `full.md`；无 token、API 或网络失败时降级 PDFKit fallback，并把原因写入 `paper.md` frontmatter。
- 新论文导入后会自动进入 Markdown 转换队列；Library 表格标题列和 AI Knowledge 选择器显示转换状态 badge；单篇右键可“转换为 Markdown”，多选右键可“批量转换 Markdown”。
- OpenAI-compatible streaming 增加空 delta / 坏 JSON chunk 忽略逻辑；流式字符动画不再暴露 JSON 片段。
- GitHub Copilot 的特殊 provider 选择、Copilot Bridge UI、Copilot SDK 设置入口和新 workspace seed 已删除或隐藏；模型入口回到普通 OpenAI-compatible API provider。
- 新增核心验证覆盖语言/MinerU preference roundtrip、JSON envelope 可见内容提取、OpenAI stream delta parser。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -quiet -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过；只出现多个 My Mac destination 的 Xcode 常规 warning。
- `get_errors` 检查 touched Swift 文件与核心目录，无错误。

限制与转入下一轮：

- Test_Workspace 的 LLM token 已存在，但 MinerU API token 缺失：`~/Documents/Test_Workspace#mineru-api` 未在 Keychain 中找到。因此本轮无法做真实 MinerU API 转换 smoke；该项进入任务书 28 的第一优先级。
- Paper-doc-todo end-to-end smoke 仍需要在真实 MinerU 转换后跑一次完整 App 交互，避免继续基于 `status: not_extracted` stub 评估论文内容。
