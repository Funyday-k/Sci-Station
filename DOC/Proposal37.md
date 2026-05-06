# 任务书 37：Embedding Persistent Store 与 Retrieval Runtime

更新时间：2026-05-06

> 本任务书承接任务书 36。P36 已完成 live runtime wiring、app-level sidecar coordinator、`agent.start` production workflows、evidence source jump 深化、debug bundle zip 与 WorkspaceTemplate / WorkspaceModule schema V0。P37 的目标是把 P35/P36 保留的 optional embedding contract 推进为真实可用的本地持久化检索能力，同时继续保持 FTS-only fallback、local-first 隐私边界和 evidence 可审计输出。

## 1. 背景

P35 已建立 hybrid retriever contract 与 FTS fallback，P36 则明确把 embedding persistent store 推迟到 P37，避免 live runtime 与 index runtime 在同一轮相互放大风险。当前系统已经具备：

```text
SidecarRuntimeCoordinator / LangGraph sidecar live path
paper_reading / related_work / gap_planning production artifact drafts
retrieval_trace.json / critic_report.json / evidence.json run artifacts
AgentEvidenceRef sourceJump line target and PDF page mapping
WorkspaceTemplate / WorkspaceModule schema V0
Debug bundle zip and redaction manifest
```

剩余缺口是：检索仍以 FTS-only 或 deterministic sample 为主，embedding index 没有持久化、source change 后没有 chunk stale 检测、retrieval_trace 还不能稳定解释 embedding score / rerank / dedupe 的生产路径。

## 2. 本轮目标

1. 新增 `EmbeddingStore` protocol，抽象本地持久化向量索引、chunk metadata、source hash 与查询结果。
2. 优先实现 sqlite-vec store；不可用时提供 deterministic fallback store，保证 CI 和无依赖环境仍可运行。
3. 通过 Swift host 建立 `embedding.embed` / `embedding.respond` proxy 边界，sidecar 不直接持有 API key 或 Keychain 权限。
4. 定义 chunk schema version、source hash、stale chunk 与 migration 规则。
5. 将 FTS + embedding hybrid retrieval 变成 production path，并输出可审计的 rerank / dedupe / fallback metadata。
6. 在 UI 中新增最小 indexing status：disabled、ready、indexing、stale、fallback、error。
7. 保持 sidecar 无 workspace 任意写权限；embedding index 写入路径由 Swift host 控制并可审计。

## 3. 实施任务

- [ ] [P37.1] `EmbeddingStore` protocol。
  - 定义 upsert chunks、delete by source、mark stale、query、stats、vacuum/migrate 等最小接口。
  - `EmbeddingChunk` 至少包含 id、source path、source type、source hash、chunk index、text hash、embedding model、schema version、metadata。
  - `EmbeddingSearchResult` 返回 score、rank、source location、snippet、evidence metadata。

- [ ] [P37.2] sqlite-vec store implementation。
  - 优先使用本地 sqlite / sqlite-vec 可用路径。
  - store path 建议落在 Research Root 内的 `.sci-station/index/embeddings/`。
  - 如果 sqlite-vec 扩展不可用，不阻塞 App 启动，自动降级 deterministic fallback。
  - 不把 API key、prompt、response 明文写入 index。

- [ ] [P37.3] deterministic fallback store。
  - 为 CI、离线开发和缺少 sqlite-vec 的机器提供稳定结果。
  - 使用 deterministic hashing / lexical score，不依赖外部服务。
  - retrieval_trace 必须明确标记 fallback store 与原因。

- [ ] [P37.4] Swift `embedding.embed` / `embedding.respond` proxy。
  - embedding provider 配置与 API key 仍由 Swift / Keychain 管理。
  - sidecar 只能请求 embedding operation，不能直接读取 Keychain 或持有明文 secret。
  - proxy 返回 redacted request metadata、model id、token/latency summary 和错误码。

- [ ] [P37.5] chunk schema version and migration。
  - 定义 `chunk_schema_version`。
  - schema mismatch 时显示 migration required 或自动轻量迁移。
  - migration 不删除用户原始资料；失败时可安全回退 FTS-only。

- [ ] [P37.6] `source_hash` stale chunk detection。
  - 对 paper.md、annotations.md、wiki pages、project materials 计算 source hash。
  - source change 后标记 stale，并在查询结果、artifact preview、retrieval_trace 中显示。
  - 支持按 source 重建，不要求 P37 完成全量后台索引队列。

- [ ] [P37.7] hybrid retrieval rerank / dedupe production path。
  - FTS result 与 embedding result 合并、去重、rerank。
  - evidenceRefs 必须保留可打开 source jump 的 path / line / PDF page metadata。
  - retrieval_trace 记录 FTS score、embedding score、rerank reason、dedupe reason、fallback reason。

- [ ] [P37.8] Indexing status UI。
  - Settings 或 AI Lab runtime/retrieval panel 显示 embedding status。
  - 至少显示 disabled、ready、indexing、stale、fallback、error。
  - 提供最小操作：rebuild current project、rebuild selected source、open index directory。
  - API key 缺失时显示可理解状态，不阻塞 FTS-only run。

- [ ] [P37.9] Tests and delivery record。
  - Swift CoreTestRunner 覆盖 protocol、sqlite/fallback store、source_hash stale、hybrid rerank/dedupe、retrieval_trace。
  - Python tests 覆盖 sidecar embedding request contract、fallback metadata、production workflow 使用 hybrid retriever。
  - Xcode build 必须通过。
  - 更新手动测试报告，至少覆盖 MT07 partial、MT09 retrieval/evidence partial、MT99 partial regression。

## 4. 非目标

```text
不做完整后台索引队列和调度器
不做云向量数据库或远程 Qdrant 服务
不做插件市场或第三方 embedding provider UI
不让 sidecar 直接读取 Keychain / API key
不让 sidecar 任意写 workspace 目标文件
不做 P38 Draft Inbox / Artifact Lifecycle
不做 citation graph、recommendation、Research Queue
不做完整 Workspace Module Registry UI
```

## 5. 验收标准

1. 未开启 embedding 或 provider 不可用时，FTS-only path 正常，workflow 不崩溃。
2. sqlite-vec 可用时，embedding chunks 能持久化、查询并参与 hybrid retrieval。
3. sqlite-vec 不可用时，deterministic fallback store 自动接管，retrieval_trace 清楚解释 fallback。
4. `source_hash` 改变后，相关 chunks 被标记 stale，并在 evidence/retrieval UI 与 trace 中可见。
5. Hybrid retrieval 返回的 evidenceRefs 仍可 source jump，不丢 path、line、PDF page metadata。
6. sidecar 不持有 API key，不直接访问 Keychain，不把 secret 写入 index/debug bundle。
7. Indexing status UI 能显示 ready/stale/fallback/error 等关键状态。
8. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充 targeted validation：

```text
get_errors for edited Swift / SwiftUI files
manual inspection of retrieval_trace.json for FTS / embedding / rerank / fallback metadata
manual inspection of .sci-station/index/embeddings for absence of API key / prompt / response plaintext
manual stale-source test by editing paper.md or annotations.md and rebuilding selected source
```

## 7. 手动测试计划

本任务书完成后必须执行：

```text
MT07 AI Lab partial
MT09 Evidence / Artifact retrieval partial
MT99 Release Regression partial
```

P37 新增或重点手动测试用例：

```text
MT09-P37-01: FTS-only fallback run returns evidenceRefs and retrieval_trace
MT09-P37-02: Embedding enabled run writes local index and uses hybrid retrieval
MT09-P37-03: sqlite-vec unavailable falls back without crashing
MT09-P37-04: source_hash changed marks chunks/evidence stale
MT09-P37-05: rebuild selected source clears stale state
MT09-P37-06: retrieval_trace shows FTS score, embedding score, rerank and dedupe reason
MT09-P37-07: index/debug artifacts contain no API key, .env, Keychain export, prompt/response plaintext
MT99 partial regression: workspace open, AI Lab, Settings, Wiki save, Tasks, privacy scan
```

允许跳过：

```text
sqlite-vec native extension path: 如果当前机器无法加载扩展，可标记 skipped，但 deterministic fallback 与 trace 必须通过。
provider-backed real embedding call: 如果没有可用 API key，可标记 skipped，但 Swift proxy contract 与 fallback path 必须通过。
```

阻塞验收的问题等级：

```text
S0: secret 泄漏、index/debug bundle 写入 API key、数据丢失、App crash、sidecar 直接读取 Keychain
S1: FTS-only fallback 不可用、embedding path 导致 AI Lab 主流程不可用、evidenceRefs 丢失 source jump metadata、index migration 破坏 workspace
```

## 8. 交付记录

完成实现后补充：

```text
完成日期：
Git commit：
自动化测试结果：
手动测试报告：DOC/manual-tests/runs/YYYY-MM-DD_P37_EmbeddingRetrieval.md
已知问题：
推迟到 P38 的事项：Artifact Lifecycle、Draft Inbox、Evidence Inspector、Permission Dock V2
```

## 9. P36 完成态与剩余风险

P36 已完成并验证：

```text
runtime selector live wiring
app-level SidecarRuntimeCoordinator
sidecar agent.start production workflow routing
debug bundle zip and redaction manifest
WorkspaceTemplate / WorkspaceModule schema V0
Minimal Workspace / Literature Review creation skeleton
evidence line target and PDF page mapping
SwiftPM CoreTestRunner / Python pytest / Xcode build
```

P36 剩余风险：

```text
交互式 macOS UI 手动点击未在工具环境执行，P36 手动报告为 CONDITIONAL PASS。
sidecar crash replay 深入注入仍需要真实 UI/manual pass 补充。
```

P37 必须避免扩大到 P38 的 artifact lifecycle；本轮只做 retrieval/index runtime 与最小 status UI。

## 10. Questions

1. P37 是否优先实现 sqlite-vec，并把 LanceDB / Qdrant-local 继续作为后续备选？当前建议为是。
2. Embedding provider real API call 是否在 P37 只做 Swift proxy contract，默认仍允许 deterministic fallback？当前建议为是，确保无 key 环境可验收。
3. Index store 路径是否采用 `.sci-station/index/embeddings/`？当前建议为是，便于 debug、清理和隐私边界检查。
4. P37 的 indexing UI 是否先放在 Settings / AI Lab retrieval panel，而不做完整后台队列界面？当前建议为是。
5. source change 后是否先实现 selected source / current project rebuild，而不做全 workspace 自动后台重建？当前建议为是。