# 任务书 39.12：AI Lab 论文 QA 体验、诊断隐私与 Release Gate 收口

更新时间：2026-05-07
状态：Implemented / Automation Passed / Manual UI Pending
优先级：S1 / Release Blocking
承接：P39.11 已完成 legacy `raw/papers` 索引兼容、摘要读取、search fallback、`list_papers.abstract`、retrieval diagnostics 和 `paper.md` 质量检查。

---

## 1. 背景

P39.10 和 P39.11 已经把 AI Lab 的核心工具链路拉通：模型请求不再被 synthetic tool transcript 破坏，论文正文和摘要读取有 deterministic preflight，legacy `raw/papers` 能直接被索引，PDFKit fallback 的可读性风险也能被检查。

下一轮需要把这些能力收口成发布前可操作体验：用户要能在 AI Lab / Library 中看到“当前论文是否能回答问题、索引是否真的可用、诊断是否可复制且不泄漏敏感信息”，同时 release gate 要能覆盖自动化与手动测试。

---

## 2. 本轮目标

1. AI Lab source / retrieval 面板直接显示 selected paper 的 index + `paper.md` health。
2. Library inspector 复用 `PaperMarkdownQualityInspector`，让用户不进 Settings 也能检查 `paper.md`。
3. Retrieval diagnostic copy 需要脱敏，并明确列出 selected source、chunks、fallback、error、paper.md quality。
4. Provider failure fallback 增加“重试当前问题 / 复制诊断 / 展开工具证据”的明确 UI action。
5. Release gate 收口 P39.10-P39.12 的自动化测试、手动测试和残余 warning 记录。

---

## 3. 实施任务

### [P39.12.1] AI Lab source health panel

- 在 AI Lab workspace/source 区显示 selected paper：`paper.md` exists/empty、extraction engine、PDFKit fallback warning、chunks、last rebuild status。
- 状态文案必须中英双语，且不能只依赖 Settings 页面。
- `chunks=0` 时提供可执行操作：Check paper.md、Rebuild Source、Open paper.md、Open migration report（若存在）。

### [P39.12.2] Library inspector paper.md health

- Library inspector 展示 `PaperMarkdownQualityReport.summary` 和前 3 条 issues。
- 提供 `Check paper.md` / `Open paper.md` / `Convert with MinerU` 入口。
- PDFKit fallback 不阻断阅读，但应以 warning 形式提示图像、扫描页、复杂公式、图表/表格可能不完整。

### [P39.12.3] Diagnostic privacy and copy contract

- `copyAgentRetrievalDiagnostic()` 输出必须脱敏：不得包含 API key、token、完整用户主目录绝对路径、provider credential。
- Diagnostic payload 包含：runtime selection、sidecar fallback、selected source relative path、index status、chunks、paper.md quality codes、last provider failure code。
- 增加测试覆盖 secret-looking values 不进入 diagnostic copy。

### [P39.12.4] Provider failure action polish

- provider 失败 fallback UI 展示三项操作：Retry、Copy Diagnostic、Show Tool Evidence。
- 保留当前中文 fallback 文案，同时补齐英文界面文案。
- 工具证据展开时显示 read-only tool order、paper id、source path、heading/range、truncation 状态。

### [P39.12.5] Release gate document and manual test run

- 更新 `docs/development/ManualTestProtocol.md` 或 `docs/development/manual-tests/MT07_AILab.md`，覆盖 P39.10-P39.12。
- 新增本轮 manual test run 记录路径：`docs/development/manual-tests/runs/`。
- 将既有非本轮 warning（例如 `ChatMarkdownWebView` WebKit actor-isolation warning）列入 release risk，而不是混入 P39.12 修复范围。

---

## 4. 验收标准

1. 用户在 AI Lab 和 Library inspector 都能看到 selected paper 的 `paper.md` health。
2. `raw/papers` 与 `library/papers` 的 selected source 都能显示 index/quality 状态和下一步操作。
3. Diagnostic copy 不包含 secrets 或不必要的绝对路径。
4. Provider failure fallback 有可点击/可执行的 retry、copy diagnostic、show evidence 路径。
5. P39.10-P39.12 release gate 文档包含自动化、手动测试和残余风险。

---

## 5. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议新增自动化测试：

```text
agentRetrievalDiagnosticRedactsSecretsAndAbsoluteHomePaths
paperMarkdownQualityReportFeedsLibraryInspectorState
aiLabSourceHealthShowsRawAndLibraryPaperStatus
providerFailureFallbackExposesRetryDiagnosticEvidenceActions
manualTestProtocolIncludesP3910ToP3912Gate
```

手动测试：

```text
MT07-P39.12-01: AI Lab selected source health for library/papers
MT07-P39.12-02: AI Lab selected source health for raw/papers
MT07-P39.12-03: Library inspector Check paper.md
MT07-P39.12-04: Provider failure fallback actions
MT07-P39.12-05: Copy diagnostic redaction
MT99-P39.12-01: Release regression gate
```

---

## 6. Questions

1. P39.12 是否优先把 health panel 放到 AI Lab 右侧 source 面板，还是先放到 Library inspector？
2. Diagnostic copy 是否允许包含 workspace-relative source paths 和 paper titles，还是 release gate 要进一步匿名化 title？
3. Provider failure fallback 的 Retry 是否应复用同一 thread/run context，还是新建一次 run 并链接到原 run？
4. P39.12 是否把既有 `ChatMarkdownWebView` WebKit actor-isolation warning 纳入本轮修复，还是仅记录为 release risk 后推？

---

## 7. 实施结果

- 已修复 DeepSeek thinking-mode tool replay 检测、context/tool budget 可见 fallback、balanced JSON plan extraction、Figure/Fig/图 caption fallback。
- 已在 AI Lab 增加 source health、provider failure actions、tool evidence preview；已在 Library Inspector 增加 paper.md Health。
- 已增加 diagnostic redaction，Copy Diagnostic 不输出 API key/token/完整用户主目录绝对路径。
- 已更新 `MT07_AILab`、`MT99_ReleaseRegression`，并新增 P39.12 manual test run 与 P39.13 下一轮任务书。
- 自动化已通过：`swift run SciStationCoreTestRunner`、`xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 人工 UI 验证仍需在 macOS App 内执行；`ChatMarkdownWebView` actor-isolation warning 继续记录为 release risk。