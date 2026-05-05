# 任务书 36：Live Sidecar Wiring、真实 Embedding Store 与 Evidence Navigation 深化

更新时间：2026-05-05

> 本任务书承接任务书 35。P35 已完成 Production V1：citation/evidence critic、结构化科研 workflow artifact、hybrid retriever fallback、run replay/debug manifest、runtime selector 持久化与 AI Lab evidence/source UI。P36 的目标是把 P35 的契约和 UI 从“可验证 V1”推进到 live runtime：让默认 AI Lab 可以按选择器真正进入 LangGraph sidecar，补齐 sidecar health/restart/export 的真实操作，落地持久化 embedding store，并把 evidence jump 从 Finder open 深化到源文本定位和 PDF 页映射。

## 1. 背景

P35 后，系统已经具备以下稳定基础：

```text
Citation Critic / Evidence Critic
Paper Reading / Related Work / Gap Planning production artifacts
FTS + optional embedding hybrid retriever contract
AgentEvidenceRef sourceJump
run replay / critic_report / retrieval_trace / debug manifest
runtime selector persistence and fallback copy
AI Lab evidence expansion and source open affordance
```

当前剩余风险集中在 live runtime wiring：Swift UI 已能呈现 runtime/fallback/evidence 状态，但默认 `SciStationAgentService` 仍主要走 Swift loop；sidecar health 操作还没有绑定到一个可复用的 app-level supervisor session；embedding store 仍是可选 V1 contract / test path，尚未持久化到 sqlite-vec 或 LanceDB。

## 2. 本轮目标

1. 将 AI Lab runtime selector 接入真实执行路径：Swift Loop、LangGraph Sidecar、Auto fallback 都能影响新 run。
2. 产品化 app-level sidecar supervisor session：health、restart、last crash、fallback reason、dependency status 可由 UI 实时读取。
3. 将 P35 Python production workflow 接入真实 sidecar start path，而不是只作为 deterministic helper/test contract。
4. 落地 embedding persistent store V1：优先 sqlite-vec，保留 LanceDB/Qdrant-local config 空间。
5. 深化 evidence navigation：从 source open 进入 Markdown/Wiki 行定位，PDF 有页码映射时进入 PDF Reader page。
6. 让 debug bundle 生成真实 zip，并在 UI 生成前展示文件清单与隐私提示。
7. 保持 sidecar 无 workspace 写权限；所有 artifact 保存和 todo 创建继续通过 Swift Permission Dock。

## 3. 实施任务

- [ ] [P36.1] Runtime selector 接入执行路径。
  - `WorkspacePreferences.agentRuntimeSelection` 驱动新 run 的 runtime 选择。
  - `Swift Loop` 强制使用 `LegacySwiftAgentRuntime`。
  - `LangGraph Sidecar` 优先启动 sidecar；不可用时显示 fallback reason，并按策略降级。
  - `Auto fallback` 在 sidecar health ready 时走 LangGraph，否则走 Swift Loop。
  - 已完成 run replay 不受 selector 改变影响。

- [ ] [P36.2] App-level sidecar supervisor 与 health store。
  - 新增 app/session scoped sidecar runtime coordinator。
  - Health state 至少包含 Python version、sidecar version、protocol/schema version、dependency check、last crash、fallback reason。
  - Settings / AI Lab Runtime panel 的 Restart sidecar、Open run directory、Export debug bundle、Disable sidecar for workspace 连接真实行为。
  - 运行中 crash 后 UI 显示最后成功 checkpoint，并允许用户选择 replay 或 fallback。

- [ ] [P36.3] Production workflows 接入 sidecar `agent.start`。
  - `paper_reading` 使用 P35 production note structure 和 critic report。
  - `related_work` 生成 `projects/{project-id}/wiki/related_work.md` artifact draft 和 `evidence.json`。
  - `gap_planning` 生成 `projects/{project-id}/wiki/research_plan.md` artifact draft 和 todo drafts。
  - sidecar 对 workspace 写入只发 approval request，不直接写文件。

- [ ] [P36.4] Embedding persistent store V1。
  - 优先实现 sqlite-vec store；如果环境不可用，提供 deterministic local fallback 并记录 warning。
  - embedding request 走 Swift `embedding.embed` / `embedding.respond` proxy，不把 API key 交给 sidecar。
  - index schema version 可迁移；source_hash 变化后 chunk 标记 stale 或重建。
  - FTS-only disabled path、embedding-enabled path、hybrid dedupe/rerank 均有测试。

- [ ] [P36.5] Evidence navigation 深化。
  - Markdown/Wiki source jump 尽量定位到 line range，而不只是 Finder open。
  - `annotations.md` 支持 line range jump。
  - paper.md 有 page mapping 时跳到 PDF Reader 页。
  - stale/missing warning 保持不崩溃，并在 artifact preview 与 saved Wiki citation block 中一致显示。

- [ ] [P36.6] Debug bundle 真实 zip 与隐私预览。
  - UI 生成前展示即将包含的文件清单。
  - 默认不包含 prompt/response 明文。
  - 显式 debug 模式只保存 redacted prompt/response。
  - zip 不包含 API key、private path inventory、`.env`、Keychain 内容。

- [ ] [P36.7] Tests。
  - Swift CoreTestRunner：runtime selector drives new run path、sidecar health store updates panel state、debug bundle manifest and zip exclude secrets、evidence source jump opens line target descriptor、embedding store marks stale chunks。
  - Python tests：agent.start routes to production paper/related/gap workflows、critic report written to run directory、retrieval_trace written, sqlite-vec store migration/fallback, debug bundle zip redaction。
  - Xcode build must pass after UI/coordinator changes。

- [ ] [P36.8] 验证与交付记录。
  - 必须运行：

```bash
python -m pytest AgentRuntime/tests
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

  - 手动验证：切换三种 runtime selector 后分别发起新 AI Lab run；sidecar crash 后查看 fallback/replay；生成 debug bundle 并检查隐私清单；点击 evidence 定位 Markdown 行或 PDF 页。

## 4. 非目标

- 不做 shell/python/code execution sandbox。
- 不让 sidecar 获得 workspace 写权限。
- 不让 sidecar 持有 API key 或直接访问 Keychain。
- 不做远程 MCP OAuth。
- 不做完整多 agent 自主协作。
- 不做云同步。

## 5. 验收标准

1. Runtime selector 能真实影响新 run 的 runtime，fallback 可解释且可审计。
2. Sidecar health panel 显示真实 health/dependency/crash/fallback 状态。
3. Paper reading、related work、gap planning production workflows 通过 sidecar start path 输出 artifact draft、evidence、critic report。
4. Embedding persistent store V1 可选启用，FTS-only fallback 始终可用。
5. Evidence navigation 能定位到 Markdown/Wiki/annotations line target，PDF page mapping 可用时进入 PDF Reader 页。
6. Debug bundle zip 默认不含敏感信息，生成前有隐私清单。
7. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。

## 6. Questions

1. P36 是否优先做 `Runtime selector live wiring -> app-level sidecar health coordinator`？当前建议为优先，因为它能把 P35 的 UI/contract 变成真实运行路径。
2. Embedding persistent store 是否优先选择 sqlite-vec？当前建议为是；如果本地依赖不可用，则保留 deterministic fallback 并记录 warning。
3. Evidence navigation 是否先做 Markdown/Wiki line target，再做 PDF page mapping？当前建议为是，因为 line target 可直接复用 `AgentEvidenceRef`，PDF 页映射依赖额外转换元数据。
4. Debug bundle 是否在 P36 中做真实 zip 下载/打开，而不是只保留 manifest？当前建议为是，并在生成前展示隐私清单。