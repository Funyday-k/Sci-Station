# 任务书 36：Live Sidecar Wiring、Evidence Navigation 深化与 Workspace Template Foundation

更新时间：2026-05-05

> 本任务书承接任务书 35，并根据长期路线图与 Manual Test Protocol V1 重新收敛范围。P35 已完成 Production V1：citation/evidence critic、paper reading / related work / gap planning artifact、hybrid retriever fallback、run replay/debug manifest、runtime selector UI、AI Lab evidence/source UI。P36 的目标不是继续扩大 embedding 或 graph 范围，而是把 P35 的 UI/contract 接入真实 live runtime：让 runtime selector 真实影响新 run，建立 app-level sidecar supervisor，打通 `agent.start` production workflows，深化 evidence source navigation，生成真实 debug bundle，并补上 WorkspaceTemplate / WorkspaceModule 的最小基础 schema。

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

当前剩余风险集中在 live runtime wiring 和用户可审计体验：Swift UI 已能呈现 runtime/fallback/evidence 状态，但默认 `SciStationAgentService` 仍主要走 Swift loop；sidecar health 操作还没有绑定到可复用的 app-level supervisor session；evidence jump 仍偏向打开源文件而不是定位行范围或 PDF 页；debug bundle 还需要从 manifest 变成真实 zip；新一轮自定义 workspace / module 系统也需要最小 schema 起点。

根据长期规划，embedding persistent store、hybrid retrieval runtime 与 index health UI 拆到 P37；P36 只保留 embedding 相关兼容边界，不在本轮实现 sqlite-vec/LanceDB/Qdrant-local store。

## 2. 本轮目标

1. 将 AI Lab runtime selector 接入真实执行路径：Swift Loop、LangGraph Sidecar、Auto fallback 都能影响新 run。
2. 产品化 app-level sidecar supervisor session：health、restart、last crash、fallback reason、dependency status 可由 UI 实时读取。
3. 将 P35 Python production workflows 接入真实 sidecar `agent.start` path，而不是只作为 deterministic helper/test contract。
4. 深化 evidence navigation：从 source open 进入 Markdown/Wiki/annotations 行定位，PDF 有页码映射时进入 PDF Reader page。
5. 让 debug bundle 生成真实 zip，并在 UI 生成前展示文件清单与隐私提示。
6. 新增 WorkspaceTemplate / WorkspaceModule schema V0，为 P39-P41 的模块系统打基础。
7. 新增 Workspace creation wizard skeleton，只实现模板/模块配置的最小写入路径，不做完整自定义 UI。
8. 保持 sidecar 无 workspace 写权限；所有 artifact 保存和 todo 创建继续通过 Swift Permission Dock。

## 3. 实施任务

- [ ] [P36.1] Runtime selector live wiring。
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
  - `agent.start` 输出 run_id、runtime、workflow、artifact draft、critic_report、retrieval_trace 和 fallback metadata。

- [ ] [P36.4] Evidence navigation 深化。
  - Markdown/Wiki source jump 尽量定位到 line range，而不只是 Finder open。
  - `annotations.md` 支持 line range jump。
  - paper.md 有 page mapping 时跳到 PDF Reader 页。
  - stale/missing warning 保持不崩溃，并在 artifact preview 与 saved Wiki citation block 中一致显示。
  - 如果定位失败，UI 显示可理解原因并退回到打开源文件。

- [ ] [P36.5] Debug bundle 真实 zip 与隐私预览。
  - UI 生成前展示即将包含的文件清单。
  - 默认不包含 prompt/response 明文。
  - 显式 debug 模式只保存 redacted prompt/response。
  - zip 不包含 API key、private path inventory、`.env`、Keychain 内容。
  - debug bundle manifest 记录 redaction policy、included files、excluded sensitive patterns、run metadata。

- [ ] [P36.6] WorkspaceTemplate / WorkspaceModule schema V0。
  - 新增最小 `WorkspaceTemplate` 与 `WorkspaceModule` domain model。
  - 内置默认模块声明至少覆盖：paper-library、wiki、projects、materials、tasks、calendar、pdf-reader、ai-lab。
  - 模块声明支持 id、title、version、enabled、directories、routes、workflows、permission scope。
  - 新建或迁移 workspace 时写入：

```text
settings/workspace_template.yaml
settings/workspace_modules.yaml
```

  - 旧 workspace 打开后自动补默认模块配置，不删除用户数据。

- [ ] [P36.7] Workspace creation wizard skeleton。
  - 保留当前 Create Workspace 主路径。
  - 新增最小模板选择入口，至少支持 `Minimal Workspace` 与 `Literature Review` 两个内置模板。
  - 创建前可预览将写入的关键目录与 settings 文件。
  - 创建后生成对应 module config 和缺失目录。
  - AI 默认关闭；Keychain/API 配置不在创建流程中强制要求。

- [ ] [P36.8] Tests。
  - Swift CoreTestRunner：runtime selector drives new run path、sidecar health store updates panel state、debug bundle manifest and zip exclude secrets、evidence source jump opens line target descriptor、workspace template/module config writes and legacy migration。
  - Python tests：agent.start routes to production paper/related/gap workflows、critic report written to run directory、retrieval_trace written、debug bundle zip redaction、fallback metadata stable。
  - Xcode build must pass after UI/coordinator changes。

- [ ] [P36.9] 手动测试与交付记录。
  - 按 `DOC/ManualTestProtocol.md` 执行本轮手动测试。
  - 必须执行：MT07 AI Lab partial、MT08 Sidecar Runtime、MT09 Evidence / Artifact、MT10 Workspace Module / Template、MT99 partial regression。
  - 新增或更新的手动测试用例必须记录到 `DOC/manual-tests/`。
  - 手动测试报告写入：`DOC/manual-tests/runs/YYYY-MM-DD_P36_LiveSidecar.md`。
  - skipped 用例必须写明原因；S0/S1 问题阻塞 P36 验收。

## 4. 明确推迟到 P37 的范围

以下内容不在 P36 实现，但 P36 必须保持兼容边界，避免 P37 返工：

```text
EmbeddingStore protocol 的完整实现
sqlite-vec / LanceDB / Qdrant-local persistent store
chunk schema migration and index health UI
source_hash stale chunk rebuild
hybrid retrieval rerank / dedupe production tuning
embedding provider settings UI
```

P36 可以保留 P35 的 FTS-only fallback 与 optional embedding contract，不要求落地持久化 embedding index。

## 5. 非目标

- 不做 shell/python/code execution sandbox。
- 不让 sidecar 获得 workspace 写权限。
- 不让 sidecar 持有 API key 或直接访问 Keychain。
- 不做远程 MCP OAuth。
- 不做完整多 agent 自主协作。
- 不做完整 Workspace Module Registry UI。
- 不做插件市场或第三方模块系统。
- 不做 citation graph、recommendation、Research Queue。
- 不做云同步。

## 6. 验收标准

1. Runtime selector 能真实影响新 run 的 runtime，fallback 可解释且可审计。
2. Sidecar health panel 显示真实 health/dependency/crash/fallback 状态，Restart/Open run directory/Export debug bundle 均连接真实行为。
3. Paper reading、related work、gap planning production workflows 通过 sidecar `agent.start` path 输出 artifact draft、evidence、critic report 与 retrieval trace。
4. Evidence navigation 能定位到 Markdown/Wiki/annotations line target；PDF page mapping 可用时进入 PDF Reader 页；定位失败时有安全 fallback。
5. Debug bundle zip 默认不含敏感信息，生成前有隐私清单，manifest 记录 redaction policy。
6. 新建或迁移 workspace 后存在最小 `workspace_template.yaml` 与 `workspace_modules.yaml`，旧 workspace 不丢数据。
7. Workspace creation wizard skeleton 至少能用 Minimal / Literature Review 模板创建 workspace 并预览目录结构。
8. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。
9. P36 指定手动测试完成，且没有未解决的 S0/S1 问题。

## 7. Tests

必须运行：

```bash
python -m pytest AgentRuntime/tests
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充 targeted validation：

```text
get_errors for edited Swift/SwiftUI files
manual inspection of debug bundle zip contents
manual inspection of generated settings/workspace_modules.yaml
```

如果自动化基线失败，仍可继续做探索性手动测试，但交付记录必须标记：

```text
自动化基线失败，本轮手动测试仅作为探索性记录，不作为最终验收。
```

## 8. 手动测试计划

本任务书完成后必须执行：

```text
MT07 AI Lab partial
MT08 Sidecar Runtime
MT09 Evidence / Artifact
MT10 Workspace Module / Template
MT99 Release Regression partial
```

重点验证：

```text
Runtime selector 是否真实影响新 run
Sidecar health panel 是否显示真实状态、fallback reason、last crash、dependency check
agent.start 是否进入 paper_reading / related_work / gap_planning production workflows
Evidence 是否能定位 Markdown/Wiki/annotations line range 与 PDF page
Debug bundle zip 是否不含 API key/.env/Keychain/private path inventory
Workspace template/module settings 是否写入 Research Root
禁用或缺失模块目录时是否不删除用户数据
```

新增或更新的手动测试用例：

```text
MT08-01 到 MT08-11
MT09-01 到 MT09-11
MT10-01 到 MT10-12
MT99 partial regression
```

允许跳过：

```text
MT08 sidecar crash replay 深入场景：仅在无法稳定注入 crash 时允许 skipped，并必须记录替代验证。
MT09 PDF page mapping：仅在测试 fixture 缺少 page mapping 元数据时允许 skipped，并必须记录 fixture 缺口。
```

阻塞验收的问题等级：

```text
S0: 数据丢失、隐私泄漏、sidecar 直接写 workspace、debug bundle 泄漏 secret、App crash
S1: runtime selector 无效、agent.start 主路径不可用、evidence source jump 全部失败、workspace 创建不可用
```

## 9. 交付记录

完成实现后补充：

```text
完成日期：
Git commit：
自动化测试结果：
手动测试报告：DOC/manual-tests/runs/YYYY-MM-DD_P36_LiveSidecar.md
已知问题：
推迟到 P37 的事项：
```

## 10. Questions

1. P36 是否继续保持“live runtime + template foundation”的收敛范围，而把 embedding persistent store 明确交给 P37？当前建议为是。
2. Workspace creation wizard skeleton 是否先只支持 Minimal / Literature Review 两个模板？当前建议为是，避免 P36 与 P40 范围重叠。
3. Evidence navigation 是否先完成 Markdown/Wiki/annotations line target，再补 PDF page mapping？当前建议为是，因为 line target 可直接复用 `AgentEvidenceRef`。
4. Debug bundle 是否在 P36 中做真实 zip 和隐私预览？当前建议为是，这是 sidecar 产品化验收的关键边界。
