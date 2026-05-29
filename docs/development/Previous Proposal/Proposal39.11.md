# 任务书 39.11：论文读取、检索索引、legacy raw/papers 迁移与 Paper QA 稳定性修复

更新时间：2026-05-07
状态：Implemented / Validated
优先级：S1 / Release Blocking
承接：P39.10 已完成 AI Lab 核心对话、preflight evidence、thinking-mode replay sanitizer、provider failure fallback 和 Swift Loop fallback 稳定性修复。

---

## 1. 背景

P39.10 修复后，AI Lab 的下一条关键链路是论文是否真的可读、可索引、可解释。当前风险集中在四处：

- legacy `raw/papers/.../paper.md` 能被 Library 加载，但不一定能被 AI retrieval index 索引；
- `search_papers` 仍偏字面搜索，中文自然语言摘要问题容易空结果；
- “第一篇论文摘要是什么”需要稳定映射到 Abstract 或第一页正文 fallback；
- PDFKit fallback 生成的 `paper.md` 对图表、扫描页和复杂公式不可完全信任，需要可见质量提示。

---

## 2. 本轮目标

1. `raw/papers/.../paper.md` 不再触发 selected source is not indexable。
2. 提供 legacy raw papers 到 `library/papers` 的迁移路径，冲突必须可见且不可静默覆盖。
3. “第一篇论文的摘要是什么”稳定走 `list_papers -> read_paper_section(Abstract)` 或 `read_paper(page: 1)`。
4. `search_papers` 空结果后仍能读取正文 fallback。
5. `list_papers` payload 包含 metadata abstract。
6. paper.md / MinerU / PDFKit fallback 状态可解释。
7. Rebuild Source 后能明确显示 chunks、fallback、error 或 disabled 状态。

### 本轮执行修订

- 优先直接兼容 `raw/papers` 索引，同时保留 migration 入口；用户无需先迁移才能重建检索索引。
- legacy migration 目标路径固定为 `library/papers/{collection}/{paper-id}`，冲突以 report 可见化，禁止静默覆盖。
- `Check paper.md` 先实现为可复用 core inspector，并在 Settings / Retrieval diagnostics 中暴露给用户。
- PDFKit fallback 作为 warning 进入 P39.11 验收；不阻止 release，但必须在 UI / diagnostics / payload 中可解释。
- 本轮新增与修改的用户可见文案必须提供中文/英文双语言分支。

---

## 3. 实施任务

### [P39.11.1] legacy raw/papers 迁移入口

新增 Settings / Library 入口，用于把：

```text
raw/papers/{collection}/{paper-id}/
```

迁移到：

```text
library/papers/{collection}/{paper-id}/
```

要求保留 `paper.pdf`、`paper.md`、`meta.yaml`、`annotations.md`、`figures/`，并更新 paper metadata 中的 directory、raw markdown、annotations 和 collection path。目标已存在时生成 conflict report。

### [P39.11.2] legacy raw/papers 索引兼容

更新 authorized resource provider 和 sidecar initialization allowed roots，使 `raw/papers` 与 `library/papers` 一样可被 AI retrieval 读取。`isIndexable()` 和 `classify()` 必须识别 `raw/papers/**/paper.md` 与 `annotations.md`。

### [P39.11.3] 摘要意图识别

扩展 `AgentPaperIntentRouter`：识别 `abstract` / `摘要`，并在 ordinal paper 问题中设置 `sectionHint = "Abstract"` 和适合检索的 query。

### [P39.11.4] search 空结果 fallback 到 read_paper

调整 preflight/read 策略：只有真正读取过 section 或 line range 才跳过 `read_paper(page: 1)`；否则使用 `read_paper` 作为正文 fallback。

### [P39.11.5] list_papers payload 增加 abstract

在 paper payload 中加入 `abstract` 字段。若 metadata 已有摘要，模型可先使用 metadata abstract，再决定是否继续读取正文。

### [P39.11.6] 检索索引状态解释优化

UI / diagnostics 文案区分：Ready、Fallback deterministic retrieval、Error not indexable、Disabled FTS-only。`chunks=0` 时给出 paper.md/path/rebuild 指引。

### [P39.11.7] paper.md 可读性检查

新增 `Check paper.md` 检查：文件存在性、是否为空、extraction engine、Abstract/Figure/display math/figures assets。PDFKit fallback 时提示图片、扫描页、复杂公式和图表可能不可读，并建议配置 MinerU 或补充 annotations。

---

## 4. 验收标准

1. `raw/papers/.../paper.md` 可重建索引，或给出明确迁移/索引错误。
2. legacy paper migration 不覆盖已有目标目录，并生成 conflict report。
3. “第一篇论文的摘要是什么”稳定读取 Abstract 或第一页正文。
4. `search_papers` 空结果不会直接结束正文读取链路。
5. `list_papers` payload 含 `abstract`。
6. PDFKit fallback 的图表/公式限制对用户可见。
7. `Rebuild Source` 后 `chunks > 0` 或显示明确原因。

---

## 5. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议新增自动化测试：

```text
authorizedResourceProviderIndexesLegacyRawPaperMarkdown
embeddingIndexControllerRebuildsLegacyRawPaperSource
legacyRawPaperMigrationCopiesToLibraryPapers
agentPaperIntentRouterMapsAbstractToAbstractSection
agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch
listPapersPayloadIncludesAbstract
paperMarkdownQualityInspectorDetectsPDFKitFallback
```

手动测试：

```text
MT07-P39.11-01: raw/papers 论文 Rebuild Source
MT07-P39.11-02: raw/papers -> library/papers 迁移
MT07-P39.11-03: 第一篇论文摘要
MT07-P39.11-04: 蒸发率公式
MT07-P39.11-05: search 空结果后 fallback read page 1
MT07-P39.11-06: PDFKit fallback paper.md 可读性提示
```

---

## 6. 本轮完成记录

更新时间：2026-05-07
状态：Implementation complete; validation passed.

已完成：

- `raw/papers` 已加入 authorized resource provider 和 sidecar initialization allowed roots，`raw/papers/**/paper.md` 与 `annotations.md` 可直接索引。
- legacy migration 保持固定目标 `library/papers/{collection}/{paper-id}`，继续生成 conflict/report，不覆盖已有目标。
- `abstract` / `摘要` 已进入 `AgentPaperIntentRouter`，ordinal paper 摘要问题稳定映射到 `sectionHint = "Abstract"` 和双语检索 query。
- preflight 搜索空结果或 section 未成功读取时，会 fallback 到 `read_paper(page: 1)`。
- `list_papers` paper payload 已包含 metadata `abstract`。
- Retrieval diagnostics 已区分 Ready、Fallback deterministic retrieval、Error not indexable、Disabled FTS-only，并在 `chunks=0` 时给出 paper.md / path / rebuild 指引。
- 新增 `PaperMarkdownQualityInspector`，检查 paper.md 存在性、空文件、extraction engine、Abstract/摘要、figure references、display math、figures assets 和 PDFKit fallback 限制。
- Settings / Library 相关 migration、retrieval、paper.md 检查入口补齐中英双语展示。

验证：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

结果：两项均通过。Xcode 构建仍有既有 `ChatMarkdownWebView` WebKit actor-isolation warning，非本轮改动引入。

## 7. 已回答的 Questions

1. 已优先完成“直接兼容 raw/papers 索引”；migration UI/服务保留为可选整理路径。
2. legacy migration 目标路径固定为 `library/papers/{collection}/{paper-id}`，冲突以 report 显示，不允许静默覆盖。
3. `Check paper.md` 先以 core inspector + Settings Retrieval 面板入口交付，后续可复用到 Library inspector / AI Lab source 面板。
4. PDFKit fallback 作为 warning 允许进入 P39.12，但 release 前必须在 diagnostics 和手动测试中可见。