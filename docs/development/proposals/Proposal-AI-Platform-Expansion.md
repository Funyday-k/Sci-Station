# AI Platform Expansion Proposal

Status: Planned

本 Proposal 记录 AI Lab、Agent Runtime、Prompt、Skill、MCP、RAG、Recommendation 和 Harness 的后续发展计划。它不是当前已完成能力说明；进入实施前，需要按目标版本拆成更小的执行 Proposal 或实施任务。

## 适用范围

- `Sci-Station/Agent/`
- `Sci-Station/LLM/`
- `Sci-Station/Recommendation/`
- `Sci-Station/UI/AILabWorkspaceView.swift`
- `Sci-Station/UI/SettingsViews.swift`
- `AgentRuntime/`
- `.sci-ai/`
- `.sci-station/agent/`

## 维护与触发

当以下任一情况发生时更新本 Proposal：

- AI Lab 的运行模式、工具权限、Prompt 策略或写回路径发生变化。
- 新增 Prompt library、Skill registry、MCP connector、Agent Runtime workflow 或 evaluation harness。
- Sidecar 从实验性路径升级为生产路径，或决定长期以 Swift Loop 作为主 runtime。
- RAG、Recommendation 或论文阅读工作流开始依赖新的索引、embedding、rerank 或外部工具。

## 当前判断

当前 AI 平台已经超过聊天 demo，但仍属于 beta 平台。Swift-native Agent Loop、工具权限、审批、debug event 和 UI timeline 是现有强项；sidecar、RAG、外部 MCP、Prompt/Skill 管理和 evaluation harness 仍需要补齐。

严格定位：

- Swift Loop 是近期生产主路径。
- Python sidecar / LangGraph runtime 暂时保持实验性定位，直到真实工具调用、真实检索、非 synthetic evidence、pytest 和 fallback 行为全部稳定。
- RAG 当前不能被包装成已完成的高质量语义检索；deterministic fallback 必须作为降级状态展示。
- AI Recommendation 当前是 AI-assisted recommendation，不是完全 AI-native ranking。
- Prompt、Skill、MCP 已有模型和局部桥接，但还不是完整可管理的扩展平台。

## 总目标

把 AI Lab 从 beta 研究助手升级为可扩展、可审计、可复现的本地科研协作平台。平台需要支持用户和 AI 协作调整 Prompt、启用 Skill、连接 MCP 工具、运行科研工作流，并通过 Harness 证明这些扩展不会绕过权限、泄漏 secret 或破坏本地数据。

## 非目标

- 不把未验证的 sidecar workflow 宣传为生产能力。
- 不允许 synthetic evidence 或 sample evidence 进入普通用户结果。
- 不允许 AI 静默修改系统 Prompt、MCP command、secret reference 或 workspace 写入配置。
- 不引入依赖云端状态的主路径；无 API key 时本地 Library、Wiki、Tasks、Recommendation 仍必须可用。
- 不在 README 或用户文档中描述未完成能力，除非明确标注为 roadmap。

## 平台原则

1. Local-first：用户 Research Root 是数据边界；AI 是增强层，不是本地功能的前置条件。
2. Auditable：每次运行记录 provider、model、Prompt version、enabled skills、MCP tools、runtime、tool calls、approval 和 evidence。
3. Reproducible：同一 run 能回看当时使用的 Prompt、Skill、工具定义、RAG index 状态和推荐配置。
4. Permissioned：任何 workspace write、external side effect、network tool、local command 都进入权限层。
5. Evidence-backed：论文阅读、相关工作、gap planning、推荐解释必须能回到 paper、PDF、Wiki 或 material 的来源。
6. Extensible but bounded：用户可以扩展 Prompt、Skill、MCP，但扩展必须有 manifest、风险等级、测试和禁用路径。

## 目标架构

```text
AI Lab UI
├── Chat / Thread / Timeline / Approval / Evidence / Diagnostics
├── Prompt Library editor
├── Skill Manager
├── MCP Connector Manager
└── Harness / Run Diagnostics

Agent Core
├── Swift Loop runtime       production default
├── Prompt resolver          system/mode/workflow/user overrides
├── Tool host + permission   read/write/network/local command gating
├── Skill registry           bundled/user/workspace sources
├── MCP gateway/client       internal server + external connector support
└── Run ledger               versions, approvals, evidence, failures

Knowledge Layer
├── RAG index                paper/wiki/material chunks
├── Evidence references      source hash, line/page, stale state
├── Recommendation signals   rule + AI review + feedback + novelty
└── Evaluation workspace     golden fixtures and regression scenarios

AgentRuntime Sidecar
├── Experimental workflows   paper reading / related work / gap planning
├── Host bridge              tools, resources, llm, embedding
├── Fallback coordination
└── Protocol/schema/version diagnostics
```

## 阶段 1：稳定当前 AI 主路径

目标：把当前 Swift Loop、LLM provider、AI Lab UI 和 Recommendation 的基础路径稳定下来。

任务：

- 统一 API key 解析：connection test、paper summary、recommendation AI search、recommendation AI evaluation 和 Agent run 都使用同一套 resolved key 逻辑。
- 修正 Settings / AI Lab 中与实际能力不一致的文案，例如工具可用性、Conversation mode 与 tool loop 的边界。
- 明确 runtime 文案：Swift Loop 是 production default；sidecar 是 experimental。
- 为无 key、provider failure、empty response、context budget stop、write approval denied 建立最小回归。
- 确保 debug bundle 和 app events 不记录 secret、完整 API key 或本机 private config。

验收：

- 无 API key 时 AI 入口不崩溃，且本地 Library、Wiki、Tasks、Recommendation 可用。
- Provider 失败时 UI 显示可理解的失败状态和重试路径。
- 写入工具被审批拦截，拒绝后不会丢失 draft。
- `swift run --quiet SciStationCoreTestRunner` 通过。
- macOS Debug build 通过。

## 阶段 2：Prompt Library 与 Prompt Diff

目标：让用户能管理 Prompt，让 AI 能提出 Prompt 修改建议，但所有生产 Prompt 修改都可审计、可回滚。

Prompt 类型：

- System Prompt：全局身份、证据、权限、语言和格式规则。
- Mode Prompt：ask、agent、plan、writeback、recommendation 等模式差异。
- Workflow Prompt：paper reading、related work、gap planning、citation critic。
- Task Prompt：paper summary、recommendation search、recommendation evaluation、todo draft。
- User Prompt Draft：当前 thread/project 的输入草稿。

任务：

- 建立 Prompt manifest：id、scope、kind、version、locale、owner、updated_at、risk、variables、body。
- 建立 Prompt resolver：按 app default、workspace override、project override、thread draft 合成最终 Prompt。
- 每次 run 记录 Prompt snapshot 或 hash，至少能回看 id、version、scope 和 body hash。
- UI 提供 Prompt Library：查看、复制、编辑、禁用、恢复默认、比较差异。
- AI 可以生成 Prompt patch，但必须展示 diff、理由、影响范围和回滚点，由用户确认后写入。
- Prompt 修改不能绕过 secret policy；Prompt body 中疑似 API key、private key、token 必须阻止保存或要求明确处理。

建议存储：

- App bundled defaults：随代码或资源发布。
- Workspace overrides：第一步使用 `.sci-station/agent/profile.json` 管理 prompt template override、skill toggle 和 MCP server 覆盖配置；后续如需要大段 prompt body 或多文件 diff，再拆到 `.sci-station/agent/prompts/`。
- Run snapshot：`.sci-station/agent/runs/<run_id>/prompt_snapshot.json`。

验收：

- 用户能覆盖 paper summary Prompt，并在下一次 summary run 中看到使用的 Prompt version。
- AI 建议修改 Prompt 时只生成 patch，不直接写入。
- Prompt 回滚后，新 run 使用旧版本；历史 run 仍能回看当时版本。
- Prompt harness 覆盖 variable missing、secret-looking value、invalid manifest、diff approval。

## 阶段 3：Skill Registry 与 Skill Manager

目标：把 Skill 从被动 markdown 文件加载升级为可管理、可审计、可测试的能力扩展。

Skill 来源：

- App bundled：随 Sci-Station 发布，默认可信。
- User global：用户全局 Skill，需要显示来源和风险。
- Workspace：Research Root 内 Skill，默认 untrusted。

Skill manifest 字段：

- id、name、description、version、author。
- capabilities。
- risk：read-only、writes-workspace、network、external-side-effect、destructive。
- allowed_tools。
- required_resources。
- required_mcp_servers。
- prompt_injection_policy。
- test_scenarios。

任务：

- 建立 Skill Manager UI：安装、启用、禁用、查看说明、查看允许工具、查看风险和来源。
- Workspace Skill 默认不自动启用；启用前展示风险和文件路径。
- Skill 参与 Prompt resolver：只把启用且匹配的 Skill 摘要注入上下文，必要时按需加载正文。
- Skill 可以声明允许工具范围，不能扩大用户在 Settings 中禁用的工具范围。
- AI 可以建议启用 Skill，但必须说明匹配原因、风险和所需工具。
- Skill 修改或新增必须通过 extension harness。

验收：

- 一个 read-only Skill 可被用户启用并影响 Agent 行为。
- 一个 workspace untrusted Skill 在启用前显示风险确认。
- 一个请求写入或 network 工具的 Skill 不会自动获得权限。
- Skill selection、risk gating、allowed tools 和 disabled skill 都有测试。

## 阶段 4：MCP Connector Platform

目标：让 Sci-Station 既能把内部工具通过 MCP 暴露给 sidecar，也能作为 MCP client 接入外部工具，同时保持权限、凭据和审计边界。

MCP 模式：

- Internal gateway：Sci-Station 工具以 `tools/list`、`tools/call` 暴露给 sidecar 或本机组件。
- External local command：启动本地 MCP server，例如 Zotero、文件系统、科研工具。
- External remote HTTP/SSE：连接远程 MCP endpoint。

任务：

- 建立 MCP connector registry：id、display_name、transport、command/url、allowed_tools、timeout、credential references、enabled state。
- Local command MCP 必须有启动/停止/health/liveness、stderr capture、crash reason 和 disable path。
- Remote MCP 必须支持 header secret reference，不把 secret 写入 run log。
- MCP tool discovery 结果需要进入工具白名单和权限层。
- 所有 MCP 写操作、local command、network side effect 都必须返回 approval required 或进入现有 approval UI。
- UI 显示 product preset 和 local workspace config 的差异，支持禁用单个 server 或单个 tool。
- 记录每次 run 使用的 MCP server id、tool name、server version/status 和 permission decision。

验收：

- `tools/list` 能列出内部 Sci-Station read-only tools。
- `tools/call` 调用 read-only tool 可自动返回结果。
- 写工具或 external side effect 返回 approval required，并能在 UI 中继续或拒绝。
- 本地 MCP 配置缺 command、远程 MCP 缺 url、secret reference 无法解析时，显示明确错误。
- MCP harness 覆盖 local command disabled、remote unavailable、tool whitelist、approval required、secret redaction。

## 阶段 5：Runtime 战略与 Sidecar 收敛

目标：决定并落实生产 runtime 策略，避免 Swift Loop 和 sidecar 长期双轨但边界不清。

路线选择：

- 路线 A：Swift Loop 长期作为 production runtime；sidecar 只承担重型 workflow、evaluation、UI test 和实验编排。
- 路线 B：sidecar 升级为 production runtime；Swift Loop 作为 fallback。

共同任务：

- 明确 runtime selector UI 和文档，不把 experimental workflow 写成 production。
- Sidecar 启用真实 tool-call policy 前，不允许普通路径产生用户可见写回。
- 移除普通路径中的 synthetic/sample evidence，保留测试 fixture 必须标注 fixture。
- Sidecar health 记录 protocolVersion、schemaVersion、appVersion、pythonVersion、dependency status 和 fallback reason。
- Sidecar unavailable 或 crashed 时稳定 fallback 到 Swift Loop，并把原因写入 timeline。

验收：

- 用户能在 diagnostics 中看到当前 runtime 和 fallback reason。
- Sidecar 不可用时 Agent run 不崩溃，Swift Loop 可继续回答或给出明确降级。
- Sidecar workflow 不再把 synthetic evidence 当真实证据返回。
- AgentRuntime pytest 和 Swift core checks 都能作为改动门禁运行。

## 阶段 6：RAG 与 Evidence System

目标：把检索从 fallback/metadata-first 升级为证据驱动的科研检索层。

任务：

- 建立真实 embedding provider 抽象；deterministic fallback 只作为明确降级状态。
- 对 paper、PDF text、Wiki、materials 建立统一 chunk schema。
- 每个 chunk 记录 source_path、source_type、source_hash、line range、page range、heading、embedding model、schema version。
- 查询结果记录 FTS score、embedding score、rerank score、dedupe reason、source freshness。
- UI 显示 index status：fresh、stale、missing、fallback、migration required。
- Agent 最终回答引用 evidence id；无法找到证据时说明查询路径和失败原因。

验收：

- 针对当前论文提问时，回答能引用 paper id、path、line/page 或 heading。
- 修改 paper.md 后 index 显示 stale，并能触发重建。
- Embedding provider 不可用时，系统明确降级到 FTS-only，不伪装成语义检索。
- RAG harness 覆盖 stale index、fallback、missing source、evidence citation。

## 阶段 7：科研 Workflow 产品化

目标：把 paper reading、related work、gap planning、citation critic 从实验流程升级为真实 workspace 驱动工作流。

任务：

- Paper reading：读取真实 paper.md/PDF text，生成结构化阅读笔记、关键公式、方法、局限、可引用 evidence。
- Related work：基于真实项目论文和 Wiki 生成主题矩阵，保留每条 claims 的来源。
- Gap planning：从 evidence matrix 生成研究 gap、实验建议和 Todo draft。
- Citation critic：检查生成文本中的引用覆盖、证据不足、过度概括和缺失反例。
- 所有 workflow 输出区分 draft、approval-ready、written。
- 写回 Wiki、paper notes、Tasks 前展示 target path、diff/summary、risk 和 approval。

验收：

- 真实 workspace 中至少一个 paper reading workflow 能生成带 evidence 的 note。
- Related work 不使用 sample evidence。
- Gap planning 生成 Todo draft，但默认不直接写入。
- 拒绝审批后 artifact draft 仍可查看和复制。

## 阶段 8：Recommendation AI 化

目标：把推荐系统从 AI-assisted search/comment 升级为可解释的 AI-native ranking，同时保留无 key fallback。

任务：

- AI search strategy、AI evaluation、feedback signal、project similarity、seed similarity、novelty、quality 和 recency 进入统一 score explanation。
- AI evaluation 不只作为 comment，应能在下一轮 ranking 中作为有边界的 feature。
- 支持项目领域配置，避免默认 CS category 误导非 CS research root。
- 反馈闭环继续增强：save、ignore、like、dislike、import Library、create reading Todo 都影响后续排序。
- 每次 recommendation run 记录候选来源、query strategy、category boundary、AI model、fallback reason 和 score breakdown。

验收：

- 无 API key 时仍能跑规则推荐，并显示 AI evaluation unavailable。
- 有 API key 时，AI strategy 和 AI evaluation 能进入 score explanation。
- 用户反馈会影响后续 recommendation run。
- 推荐结果说明不会声称读过未检索或未提供的全文。

## 阶段 9：Harness 框架升级

目标：把现有 UI scenario harness 扩展成 AI 平台质量门禁。

现有 harness 定位：

- UI Scenario Harness：通过 step、driver、event/file/visual assertions 验证 App 行为。
- 当前强项是 event/file 双通道和可插拔 driver。
- 当前短板是 visual baseline deferred，且还不能验证 Prompt/Skill/MCP/evaluation contract。

新增三层 harness：

1. UI Scenario Harness
   - 保留 click/type/drag/test_bridge/event/file assertions。
   - 覆盖 AI Lab thread、prompt draft、approval card、runtime fallback、MCP status。

2. Extension Contract Harness
   - 验证 Prompt manifest、Prompt diff、Skill manifest、MCP config、tool whitelist、permission decision。
   - 不启动完整 App 也能跑 CI contract test。
   - 检查 secret redaction、untrusted skill gating、local command disabled、remote MCP unavailable。

3. Evaluation Harness
   - 使用 golden research root。
   - 覆盖 paper reading、RAG query、related work、gap planning、recommendation ranking。
   - 不要求模型输出逐字一致，但要求 evidence coverage、no synthetic evidence、fallback visibility、write approval。

任务：

- 固定 Python venv/pytest 入口，避免测试环境不可用。
- 为 AI extension 新增 fixtures：valid/invalid Prompt、trusted/untrusted Skill、local/remote MCP config。
- 建立 small golden workspace，用极小论文/Wiki/material 测证据链。
- 报告输出到 development testing runs，包含 scenario id、runtime、provider mode、fixture、pass/fail、known limitation。

验收：

- 新增 Prompt、Skill、MCP preset 前必须能跑 extension harness。
- AI/Agent 改动至少跑 core checks；涉及 sidecar/harness 时跑 AgentRuntime pytest。
- evaluation harness 能发现 synthetic evidence、missing citation、secret leak、write without approval。

## 数据与安全要求

- API key、token、client secret 只能进入 Keychain 或本机安全配置。
- `.mcp.json`、`.env*`、`.sci-ai/workspace.local/` 不进入公开分享包。
- Prompt、Skill、MCP config 都必须区分 tracked preset 和 local workspace override。
- Debug bundle 默认不包含完整 Prompt/response；需要显式开启时也必须脱敏。
- Local command MCP 默认 disabled，启用时展示 command、arguments、working directory、allowed tools 和风险。
- Workspace Skill 默认 untrusted，不能自动获得 write/network/destructive 权限。

## 发布前检查

AI/Agent 相关发布前至少检查：

- No-key path：AI 入口不崩溃，本地功能可用。
- Provider failure：可见错误、重试路径、debug event 脱敏。
- Prompt：version/hash 记录、diff approval、回滚可用。
- Skill：trusted/untrusted 来源、risk、allowed tools。
- MCP：status、tool whitelist、approval required、secret redaction。
- RAG：fresh/stale/fallback/missing source 状态。
- Recommendation：AI unavailable fallback、score explanation、feedback loop。
- Sidecar：health、fallback、pytest、无 synthetic evidence。
- Harness：UI scenario、extension contract、evaluation smoke。

## 实施顺序建议

1. 先做阶段 1，稳定现有用户可见路径。
2. 再做阶段 2 和 3，让 Prompt 与 Skill 可管理、可审计。
3. 然后做阶段 4，用 MCP registry 把外部工具接入权限层。
4. 随后选择阶段 5 的 runtime 战略，避免 sidecar 长期半成品化。
5. 最后推进 RAG、workflow、recommendation 和 evaluation harness。

## 完成定义

当以下条件满足时，AI 平台可以从 beta AI Lab 升级为可扩展 AI platform：

- 用户能查看和管理 Prompt、Skill、MCP，并能理解风险。
- AI 可以建议扩展配置变更，但所有生产写入都有 diff、审批和回滚。
- 每次 Agent run 可回看 Prompt、Skill、MCP、runtime、provider、tool calls、approval 和 evidence。
- Paper reading、related work、gap planning 和 recommendation 不依赖 synthetic evidence。
- RAG 提供真实 evidence trace，fallback 状态明确可见。
- Harness 能在开发和发布前捕获权限绕过、secret 泄漏、证据缺失和扩展 manifest 错误。
