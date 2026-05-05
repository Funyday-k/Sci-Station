下面是我对你**已修改后的 P33 / P34 任务书**的再次审核，以及对任务书末尾 Questions 的明确回答。

## 总体结论

这版修改是正确的，已经从“未来架构设计”变成了“承接 P32 已落地实现的协议迁移与 sidecar 落地计划”。

尤其是 P33 现在已经明确把第一优先级放在 **P32 provisional schema migration**，包括迁移 P32 的 approval、human decision、pending tool call、fingerprint、pause reason、stable tool result 与 legacy pending checkpoint，而不是并行再造一套新协议 [1]。这点非常关键。

P34 也已经从“直接上 LangGraph + 三个 workflow”改为 **Fake Sidecar First**，并设置了 P33 dependency gate，明确 P34 不再理解 P32 legacy pending checkpoint，必须依赖 P33 的 run directory、persistent ledger、ToolHost、MCP Gateway 与 runtime envelope [2]。这个边界是对的。

我的判断是：

> **P33 / P34 现在可以进入执行。P33 按 migration → runtime façade → run directory/ledger → ToolHost adapter → MCP Gateway 的顺序做；P34 按 fake sidecar → real sidecar handshake → read-only tools → FTS evidence → 单篇论文精读的顺序做。**

---

# 一、对 P33 修改版的审核

## 1. P33 的定位已经正确

P33 新标题改成：

> P32 Agent Protocol Migration、Runtime Façade 与 MCP Gateway

这个比之前更准确。因为 P32 已经完成了 Swift-native loop，并且实施记录明确指出 P32 的 `AgentApprovalRequest`、`AgentHumanDecisionAction`、checkpoint shape 仍是 provisional，write ledger 还是内存态，stable JSON tool result 的 evidence 仍为空数组 [3]。

所以 P33 现在不应该只是“新增 façade”，而应该先做协议迁移。新版已经体现了这一点。

## 2. P33 的关键修改是必要的

新版 P33 已经补上了几条非常重要的内容：

1. **P32 provisional protocol migration**  
   迁移 P32 的 approval、human decision、pending tool call、fingerprint、pause reason、legacy pending checkpoint 和 stable tool result [1]。

2. **AgentToolArguments 兼容层**  
   保留 `AgentToolCall.argumentsJSON`，同时新增 `AgentToolArguments.rawJSON / canonicalJSON / value`，避免一次性重写 P32 loop、旧 run log、tool registry 和 planner path [1]。

3. **AgentRunDirectoryStore**  
   把长期 run 目录定义为：

   ```text
   .sci-station/agent/runs/{run_id}/
   ├── checkpoint.json
   ├── events.jsonl
   ├── tool_calls.jsonl
   ├── approvals.jsonl
   └── tool_results/
   ```

   并规定 P32 的 `pending_tool_calls.jsonl` 只作为 legacy fallback 读取 [1]。

4. **Persistent execution ledger**  
   把 P32 的内存 write ledger 升级为持久 `tool_calls.jsonl`，防止 App 重启、sidecar resume 或重复 Allow once 后重复执行写入 [1]。

5. **ToolHost adapter-first**  
   第一版 `SciStationToolHost` 包装现有 `AgentToolRegistry`，不重写所有工具 [1]。这个非常实际，能降低 P33 的迁移风险。

6. **Hook ask/deny 语义与 P32 对齐**  
   明确 deterministic safety policy 是不可绕过阻断层；hook `.ask` 不直接等价于 `approvalRequired`；generic `PreToolUse` reminder 不得暂停 read-only tool [1]。

这些修改都应保留。

---

# 二、P33 还建议微调的地方

P33 目前已经很完整，但我建议再补 5 个很小但重要的点。

## P33 建议 1：把 `AgentHumanDecisionAction` 的枚举值统一掉

P32 中 provisional enum 是：

```swift
allowOnce
denyAndContinue
denyAndStop
reviseWithFeedback
editArguments
```

而 P33 迁移段里写了：

```text
allowOnce、deny、editArguments、askAgentToRevise
```

这里出现了命名不一致。建议 P33 最终固定为：

```swift
public enum AgentHumanDecisionAction: String, Codable, Sendable {
    case allowOnce
    case denyAndContinue
    case denyAndStop
    case reviseWithFeedback
    case editArguments
}
```

然后做 legacy alias：

```text
deny -> denyAndStop
askAgentToRevise -> reviseWithFeedback
```

这样和 P32 已实现 runner 行为一致，也避免 UI / sidecar / Permission Dock 出现三套命名。

## P33 建议 2：`AgentApprovalRequest` 加入 fingerprint 字段

P33 验收标准已经要求 Permission Dock pending item 包含 idempotency fingerprint [1]，但 `AgentApprovalRequest` struct 里还没有显式字段。

建议加入：

```swift
public var fingerprint: String
```

或者：

```swift
public var idempotencyKey: String
```

否则 Permission Dock、ledger、resume 三方会各自重新计算，容易不一致。

推荐：

```swift
public struct AgentApprovalRequest: Codable, Sendable, Identifiable {
    public var id: String
    public var runID: String
    public var toolCallID: String
    public var tool: String
    public var risk: AgentToolRisk
    public var permissionKey: String
    public var arguments: AgentToolArguments
    public var targetPaths: [String]
    public var fingerprint: String
    public var diffPreview: String?
    public var summaryPreview: String?
    public var reason: String
    public var rollbackHint: AgentRollbackHint?
    public var expiresAt: Date?
    public var suggestedDecisions: [AgentHumanDecisionAction]
}
```

## P33 建议 3：run directory 需要补 `events.jsonl` 的所有权

P33 的 run directory 示例包含 `events.jsonl`，但实施任务里对 events 的 owner 描述还可以更硬一点。

建议补一句：

```text
events.jsonl 由 Swift Host 作为最终 owner 写入；LegacySwiftAgentRuntime 直接写 host sequence，LangGraph sidecar event 经 Swift canonicalize 后再写入。
```

这和 P33 已定义的 sequence owner 规则一致 [1]。

## P33 建议 4：ToolHost adapter 要定义“禁止 side effect 的 dry-run/diff 阶段”

P33 要求写 Markdown/Todo/Paper metadata 工具尽量生成 diff/summary 后再请求审批 [1]。但为了实现这个能力，ToolHost 需要区分：

```text
previewApproval / buildApprovalRequest
execute
```

建议新增 ToolHost 方法：

```swift
public func buildApprovalRequest(
    for call: AgentToolCall,
    context: AgentToolContext
) async throws -> AgentApprovalRequest
```

并规定：

```text
buildApprovalRequest 不得产生 workspace side effect，只能做 schema validation、target path extraction、diff/summary preview、fingerprint 计算。
```

否则“生成 diff”本身可能误触写入。

## P33 建议 5：Skill 可降为 P33-G，不阻塞主线

新版 P33 已经写了执行顺序，P33-A 到 P33-D 是 P34 硬依赖，Skill 排在最后 [1]。这个安排正确。

我建议在 P33 验收/交付里再明确：

```text
若 P33 runtime/schema/ledger/ToolHost 主线完成但 Skill 三级披露未完全产品化，可以作为 P33-G 延后，不阻塞 P34 fake sidecar。
```

这样可以避免 P34 被 Skill loader 的 UI/metadata 细节卡住。

---

# 三、对 P34 修改版的审核

## 1. P34 的新定位非常正确

P34 标题改成：

> Fake Sidecar First、LangGraph Sidecar、Local RAG 与科研 Workflow MVP

这是非常好的修改。P34 现在明确要求先用 fake sidecar 验证协议与恢复路径，再接真实 LangGraph graph [2]。这能有效隔离问题来源：

```text
先验证:
Swift Process 管理
stdio JSON-RPC 双向调用
event envelope parsing
sequence canonicalization
approval resume
fallback

再验证:
LangGraph state
workflow routing
FTS evidence
LLMProxy
```

这个顺序是工程上最稳的。

## 2. P34 的 dependency gate 是必要的

P34 现在明确规定开始前必须满足：

- P33 `AgentRuntimeEventEnvelope` 已落地。
- P32 provisional approval / pending checkpoint / stable tool result 已迁移。
- `LegacySwiftAgentRuntime` 可包装 P32 `AgentLoopRunner`。
- `SciStationToolHost` 已成为唯一工具入口。
- MCP Gateway V1 可 `tools/list` / `tools/call`。
- run directory / checkpoint / approvals / persistent tool ledger 已可读写 [2]。

并且明确：

> 若 dependency gate 未通过，P34 只能做 fake sidecar 协议测试，不得让 Python sidecar 兼容 P32 legacy pending 文件 [2]。

这是非常正确的边界。

## 3. P34 对三个 workflow 的范围收缩合理

P34 现在规定：

- 单篇论文精读是 MVP 的真实 workflow。
- related work 和 gap planning 第一轮可以作为 sample/fake/beta graph，不阻塞 MVP 完成 [2]。

这个比之前“一口气做三个 production graph”合理很多。因为 P34 同时涉及 sidecar、JSON-RPC、LLMProxy、FTS、evidence、approval/resume，如果三个 workflow 都要求生产级，会导致范围过大。

---

# 四、P34 还建议微调的地方

P34 也已经很完整，我只建议补 5 个小点。

## P34 建议 1：fake sidecar 应该有独立 fixture 文件

P34 现在要求 fake sidecar 覆盖 initialize、health、agent.start、approval_required、agent.resume、final_response、run_failed [2]。

建议补充：

```text
fake sidecar 的事件序列使用 JSON fixture 文件驱动，避免测试逻辑写死在 Python 代码里。
```

例如：

```text
AgentRuntime/tests/fixtures/
├── run_success_paper_reading.jsonl
├── run_approval_then_resume.jsonl
├── run_failed.jsonl
├── sidecar_crash_after_approval.jsonl
└── handshake_timeout.jsonl
```

这样 Swift CoreTestRunner 可以复用 fixture，后续真实 sidecar 的回归也能复用。

## P34 建议 2：`llm.respond` 默认禁用 tool calling，但要有显式字段

P34 已经规定 `llm.respond` 默认禁用 provider-native free tool calling，只有专门的 ToolCallingNode 才允许返回 tool calls [2]。

建议在 JSON-RPC request 里显式加入：

```json
{
  "allowToolCalls": false
}
```

或者：

```json
{
  "toolCallPolicy": "disabled"
}
```

可选值：

```text
disabled
structured_only
tool_calling_node_only
```

MVP 用：

```text
disabled
```

这样 Python sidecar 和 Swift LLMProxy 都不会误解 `tools: []` 与 `tools: non-empty` 的语义。

## P34 建议 3：`IndexableDocumentSnapshot` 应避免传真实 file URL

P34 里 `IndexableDocumentSnapshot` 包含 `allowed_read_url` 或等价 file handle/path [2]。考虑 macOS security-scoped bookmark 和 workspace 安全边界，建议优先传：

```text
relative_path + resource_id
```

然后 Python 通过：

```text
resources/read
```

向 Swift 请求内容。

也就是说，MVP 最安全路径是：

```text
Python 不直接 open 文件。
Python 调 resources/list_indexable_documents 得到 snapshot。
Python 调 resources/read(relative_path/resource_id) 读取内容。
```

如果为了性能允许 Python 直接读文件，也建议只在 development mode 或明确授权模式启用。

## P34 建议 4：FTS owner 最好明确为“sidecar 维护，Swift 授权输入”

P34 已经说第一版可由 Python 建索引，但文件发现优先使用 Swift 授权快照 [2]。建议再明确一句：

```text
P34 MVP 中 chunks.sqlite 的 writer 是 sidecar；Swift 是授权文档清单与写入锁协调者。后续可迁移为 Swift-owned index service。
```

否则后面可能出现 Swift 和 Python 都尝试写 `.sci-station/index/chunks.sqlite`。

## P34 建议 5：单篇论文精读 workflow 的最低 evidence 要求再具体一点

建议给 Workflow 1 加上最低验收：

```text
单篇论文精读至少生成:
- contributions: >= 3 条，均有 evidenceRefs
- methods: >= 2 条，均有 evidenceRefs
- limitations: >= 2 条，允许标记 low confidence
- todo drafts: 可选，但如生成必须引用对应 paper id
```

这样“生成 artifact draft + evidence”不会变成只有一段泛泛总结。

---

# 五、对 P33 Questions 的回答

## Q1：P33 第一优先级是否确认按 `P32 migration -> runtime façade -> run directory/ledger -> ToolHost adapter -> MCP Gateway` 执行？

**确认。**

我建议更精确地排成：

```text
1. P33.0  P32 provisional schema migration
2. P33.0a AgentRunDirectoryStore
3. P33.0b Persistent execution ledger
4. P33.0c AgentToolResult wire-format V1
5. P33.1  AgentRuntimeEventEnvelope / protocol model
6. P33.2  LegacySwiftAgentRuntime
7. P33.3  AI Lab dependency inversion + FakeExternalAgentRuntime
8. P33.4  SciStationToolHost adapter
9. P33.5  MCP Gateway V1
10. P33.7 deterministic safety policy / hooks
11. P33.6 Skill 三级披露
12. P33.8 Permission Dock richer schema UI
```

也就是说，我会把 `run directory / ledger / tool result V1` 放在 `LegacySwiftAgentRuntime` 真正稳定前一起完成，因为 runtime resume 和 event replay 依赖它们。

## Q2：Skill 三级披露、安全 hooks、richer approval request 是否都放进 P33 同一轮完成？

**可以放在 P33，但要切片，不要阻塞主线。**

建议优先级：

```text
必须完成:
- richer approval schema
- deterministic safety policy
- secret/path blocking
- hook deny blocks prompt/tool call

可以延后:
- Skill 三级披露完整 UI
- workspace skill trust prompt 的产品化细节
- Tier 3 references/scripts 资源浏览体验
```

P33 的硬依赖应该是 protocol、runtime、run directory、ledger、ToolHost、MCP Gateway。Skill 是重要能力，但不应阻塞 P34 fake sidecar。

## Q3：P34 的 LangGraph sidecar 是否应在 P33 完成后立刻推进？

**可以推进，但只推进 fake sidecar 和协议 harness；真实 LangGraph 要等 P33 dependency gate 通过。**

也就是说：

```text
P33 未完全完成前:
可以做 fake sidecar fixture、stdio JSON-RPC harness、Python package skeleton。

P33 dependency gate 通过后:
再接真实 LangGraph graph、LLMProxy、FTS、workflow。
```

这样不会让 Python sidecar 被迫兼容 P32 legacy checkpoint，也不会提前把协议债带进 P34。

---

# 六、对 P34 Questions 的回答

## Q1：P34 是否确认按 `fake sidecar -> real sidecar handshake -> read-only tools -> FTS evidence -> 单篇论文精读` 顺序推进？

**确认。**

推荐执行顺序：

```text
P34-M1: fake sidecar + LangGraphAgentRuntime 协议
P34-M2: real sidecar initialize / health / lifecycle events
P34-M3: Swift LLMProxy + read-only Gateway tools
P34-M4: FTS index + AgentEvidenceRef bridge
P34-M5: 单篇论文精读真实 workflow
P34-M6: related work beta
P34-M7: gap planning beta
```

不要先写 LangGraph 复杂 graph。先确保 sidecar 生命周期、event envelope、approval/resume 和 fallback 能稳定跑通。

## Q2：Related work 与 gap planning 在 P34 第一轮是否接受 sample/fake/beta graph？

**接受，而且建议这样做。**

P34 MVP 的 production workflow 只要求单篇论文精读即可。related work 和 gap planning 更依赖：

- 更好的 retrieval。
- citation critic。
- project context quality。
- core paper clustering。
- evidence table 稳定性。
- task generation 的审批体验。

这些可以先用 sample/fake/beta graph 验证 runtime 协议，不要强行在 P34 第一轮做成 production 质量。

## Q3：FTS 第一版是否优先由 Swift 提供 `resources/list_indexable_documents`？

**推荐优先做 Swift 授权快照。**

理由是 Sci-Station 已经有本地 Research Root、Materials 扫描规则、隐藏目录规则、工作区结构和 security-scoped bookmark 访问边界。让 Python 直接 walk workspace 容易重复实现规则，也容易越界。

推荐读取路径：

```text
Python -> resources/list_indexable_documents
       -> 得到 IndexableDocumentSnapshot
       -> Python -> resources/read
       -> Swift 返回授权内容
       -> Python 写 FTS index
```

如果为了开发效率保留 Python walk fallback，也应限制为：

```text
development mode only
allowedRoots only
ignoredGlobs enforced
no hidden/system dirs
```

---

# 七、最终建议

我建议你只再做下面这些小修，然后就可以开工。

## P33 最后补 5 条

```text
1. 统一 AgentHumanDecisionAction 命名:
   allowOnce / denyAndContinue / denyAndStop / reviseWithFeedback / editArguments。

2. AgentApprovalRequest 增加 fingerprint 或 idempotencyKey 字段。

3. 明确 events.jsonl 由 Swift Host 作为最终 owner 写入。

4. ToolHost 增加 buildApprovalRequest / previewApproval 阶段,且该阶段不得产生 side effect。

5. Skill 三级披露可作为 P33-G,不阻塞 P34 dependency gate。
```

## P34 最后补 5 条

```text
1. fake sidecar 使用 JSON fixture 驱动事件序列。

2. llm.respond request 增加 allowToolCalls 或 toolCallPolicy 字段。

3. IndexableDocumentSnapshot 优先返回 resource id / relative path,Python 通过 resources/read 读内容,避免默认直接 file URL。

4. 明确 chunks.sqlite 在 P34 MVP 中由 sidecar 写入,Swift 提供授权快照与锁协调。

5. 单篇论文精读 workflow 增加最低 evidence 验收要求。
```

---

## 最终判断

**P33 / P34 当前版本已经足够成熟，可以进入开发。**

P33 的主线是：

> 把 P32 已实现的 Swift loop 临时协议迁移成长期协议，并建立 runtime façade、run directory、persistent ledger、ToolHost 和 MCP Gateway。

P34 的主线是：

> 先用 fake sidecar 验证协议，再接真实 LangGraph；MVP 只强制完成单篇论文精读，related work / gap planning 先 beta 化。

这套顺序风险最低，也最符合你现在 Sci-Station 的实际源码状态。