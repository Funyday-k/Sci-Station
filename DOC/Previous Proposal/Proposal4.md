# 任务书 4：LLM 总结闭环可用化与安全写回

## 背景

任务书 1 到 3 已经把 Sci-Station 从本地论文目录管理推进到 Zotero 风格科研工作台：工作区结构、PDF 导入、Wiki 页面、Collections、彩色标签、Dashboard、Todo、Identifier/Link 导入、专注 PDF Reader 和 OpenAI-compatible LLM 设置都已经具备雏形。

本轮审阅代码后发现，下一步最值得做的不是继续横向铺新模块，而是把已经接上的 LLM 主链路打磨到真正可用：能拿到足够的论文文本，能稳定报告 API 错误，能预览后安全写回，并且不会在保存草稿时误改论文阅读状态。

## 当前发现

### 已具备的基础

- `LLMConfiguration`、`LLMConfigurationStore`、`KeychainAPIKeyStore` 已存在。
- `OpenAICompatibleProvider` 已能构造 chat completions 请求。
- `PaperSummaryPromptBuilder`、`PaperSummaryService`、`LLMWritebackService` 已存在。
- Library Inspector 已有 `Summarize with LLM` 按钮。
- Summary Preview 已支持 Replace、Append、Save Draft 三种操作。
- Core Test Runner 已覆盖基础 LLM 请求构造和配置文件不写入 API Key。

### 缺失和问题

1. LLM Provider 仍是具体类型耦合，缺少明确的 `LLMProvider` 抽象和统一错误模型。
2. OpenAI-compatible API 调用没有检查 HTTP 状态，也没有解析 API 错误；失败时可能只得到空字符串。
3. `paper.md` 默认只是 `not_extracted` 占位文本，LLM 总结很容易没有真实论文内容可用。
4. `Save Draft` 写回模式会和 Replace/Append 一样把论文状态更新为 `summarized`，这会误导后续阅读管理。
5. `Save Draft` 草稿文件名固定，重复保存可能覆盖旧草稿。
6. 任务书 3 已经加入专注 PDF Reader，但 Inspector 里仍嵌着完整 PDF 阅读器，阅读空间和交互职责仍然重复。
7. LLM prompt、写回安全性和草稿行为缺少测试。

## 目标

### 目标 1：稳定 LLM Provider 边界

- 新增 `LLMProvider` 协议。
- 新增统一的 LLM provider 错误类型。
- `OpenAICompatibleProvider` 实现该协议。
- API 返回非 2xx、格式错误或空内容时给出明确错误。

### 目标 2：让总结输入更接近真实论文内容

- `PaperSummaryService` 继续读取 `meta.yaml`、`paper.md`、`annotations.md` 和已有 wiki 页面。
- 当 `paper.md` 仍是占位或内容过短时，尝试从本地 `paper.pdf` 抽取文本作为 LLM 输入。
- 对输入文本做长度上限，避免一次请求过大。

### 目标 3：安全写回和草稿语义修正

- Replace / Append 明确修改 wiki 页面，并在成功后把论文状态标为 `summarized`。
- Save Draft 只写草稿文件，不修改正式 wiki 页面，也不把论文状态标为 `summarized`。
- Save Draft 使用不覆盖旧草稿的文件名。

### 目标 4：清理 PDF 阅读职责重复

- 保留专注式 PDF Reader 作为主要阅读入口。
- Paper Inspector 不再嵌入完整 PDF 阅读器，只保留元数据和进入阅读模式的动作。

### 目标 5：补强核心验证

- Prompt Builder 测试应覆盖 metadata、paper.md、annotations 和已有 wiki 内容。
- LLM 写回测试应覆盖 Append、Replace、Save Draft 和草稿不覆盖。
- 保持 API Key 不写入普通设置文件。

## 执行任务

### 任务 A：LLM Provider 抽象与错误处理

- 新增 `LLMProvider` 协议。
- 新增 `LLMProviderError`。
- 重写 OpenAI-compatible response parsing。
- 非 2xx 响应应抛出包含状态码和错误信息的错误。

### 任务 B：论文正文输入兜底

- 在 `PaperSummaryService` 中识别 `paper.md` 占位内容。
- 占位或过短时使用 PDFKit 从本地 PDF 抽取文本。
- Prompt 中保留 raw markdown、PDF 抽取文本、annotations 和 existing wiki。

### 任务 C：写回服务语义修正

- `LLMWritebackService.write` 返回写回结果。
- Save Draft 返回草稿 URL，并标记未修改正式 wiki。
- App 写回时仅在 Replace / Append 成功后更新 `status = summarized`。

### 任务 D：PDF Reader UI 清理

- 移除 Paper Inspector 内的完整 Embedded PDF Reader。
- 继续保留 `Read in App` 和 `Open in Default Viewer` 动作。

### 任务 E：验证补强

- 为 Prompt Builder 增加上下文完整性检查。
- 为 Writeback Service 增加草稿不覆盖和正式 wiki 修改检查。
- 运行 `swift run SciStationCoreTestRunner`。

## 验收标准

1. LLM Provider 对 HTTP 错误、格式错误和空响应有明确错误。
2. 当 `paper.md` 是占位文本时，LLM 总结流程会尝试读取本地 PDF 文本。
3. 用户点击 Save Draft 后不会修改正式 wiki，也不会把论文状态改为 summarized。
4. 多次 Save Draft 不会覆盖旧草稿。
5. Paper Inspector 不再承担完整 PDF 阅读器职责。
6. Core Test Runner 通过。

## 本轮执行结果

### 已完成

- 已新增 `LLMProvider` 协议与 `LLMProviderError`。
- 已增强 OpenAI-compatible provider 的请求解析和错误处理。
- 已让 `PaperSummaryService` 在 `paper.md` 过短或仍是占位时尝试抽取 PDF 文本。
- 已让 LLM prompt 包含更完整的 metadata、raw markdown、annotations、existing wiki，并提示不要编造信息。
- 已让 `LLMWritebackService` 返回写回结果，并为草稿生成不覆盖旧文件的路径。
- 已修正 Save Draft 后误标 `summarized` 的状态问题。
- 已从 Paper Inspector 移除内嵌完整 PDF Reader，专注阅读回到 PDF Reader section。
- 已补充 prompt builder 与 writeback service 的核心验证。

### 已执行验证

- `swift run SciStationCoreTestRunner` 通过。

## 后续建议

1. 下一轮可以为 LLM Summary Preview 增加 Replace Sections 模式，只替换 `TL;DR`、研究问题、方法等固定段落，避免整页替换。
2. 可以把 PDF 抽取出的正文缓存回 `paper.md`，并把 `status: not_extracted` 更新为 `extracted`。
3. 可以增加 LLM 调用历史，写入 `outputs/llm-runs/` 或 `imports/import_history.yaml` 风格的透明记录。
