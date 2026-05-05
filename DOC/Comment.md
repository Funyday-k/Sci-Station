可以。我先说明边界：我不能在这里把整个 Xcode 工程像本地 IDE 一样完整编译、逐行调试；但我已经基于你提供的 README/仓库上下文，以及 Agent 目录中可见的核心代码结构，做了架构判断。我的结论是：

**不要在 Swift 里继续自研完整 agent 框架。建议保留 Sci-Station 现有 Swift App、权限 UI、本地文件系统与 Repository 层，把成熟 agent runtime 作为本地 sidecar 嵌入。首选方案是：LangGraph Python 作为主 agent 编排框架 + MCP 作为工具/知识接口标准 + 可选 OpenAI Agents SDK Sandbox 处理代码执行/长任务。**

---

## 1. 你现在的 Agent 能力大致处于什么阶段

从项目描述看，Sci-Station 已经有很好的“科研工作台底座”：本地 Research Root、论文库、Wiki、Materials、Tasks、PDF Reader、项目视图、AI Lab、权限面板、hook、session event、run log 等都已经搭起来了，而且数据原则是本地优先，核心数据落在用户可见目录中 [1]。LLM API Key 也已经通过 Keychain 保存，settings 只保存非敏感配置 [1]。

但目前 Agent 本身更像是一个 **plan-and-execute 原型**，不是成熟的长期运行 agent：

- 有 `AgentPlanner`：让 LLM 生成一个结构化 plan。
- 有 `AgentToolRegistry` / `AgentToolExecutor`：注册和执行工具。
- 有基础工具：列论文、读论文、搜索论文、创建 todo、更新论文分类、写 markdown plan。
- 有审批：写入工具需要用户确认。
- 有 JSONL run log、thread、draft、session events。
- 有 hooks、permission dock、MCP UI 的雏形，但 README 也明确说当前阶段“不启动 MCP server”，外部 side-effect MCP tools 仍需进入 permission layer [1]。

这说明你现在强的是 **产品壳、知识库结构、权限与本地文件模型**，弱的是：

1. 没有真正的多轮 agent loop。  
2. 没有 durable checkpoint / resume。  
3. 没有工具调用后的反思、重试、分支、子任务分解。  
4. 没有成熟的 RAG / citation / evidence pipeline。  
5. MCP 还只是 UI/配置边界，没有成为真正的工具协议层。  
6. 代码执行、文件编辑、实验复现等能力还没有沙箱化。  
7. 当前工具数量少，且工具语义仍是 app 内部函数，不是可扩展插件系统。  

所以正确方向不是“把现在的 Swift Agent 继续堆复杂”，而是把它改造成 **Sci-Station Agent Host**，让成熟 runtime 来做循环、状态机、human-in-the-loop、checkpoint、多 agent 协作。

---

## 2. 推荐总架构

我建议的目标架构：

```text
Sci-Station.app  SwiftUI / macOS
│
├─ AI Lab UI
│  ├─ Chat / thread
│  ├─ Plan viewer
│  ├─ Permission Dock
│  ├─ Event timeline
│  └─ Diff / approval / resume UI
│
├─ Swift Domain Layer
│  ├─ PaperRepository
│  ├─ MarkdownRepository
│  ├─ TodoRepository
│  ├─ ProjectPaperLinkRepository
│  ├─ Workspace / Materials / PDF services
│  └─ Keychain / settings / security-scoped bookmark
│
├─ SciStationAgentBridge
│  ├─ start_run
│  ├─ stream_events
│  ├─ approve_tool_call
│  ├─ deny_tool_call
│  ├─ cancel_run
│  └─ get_checkpoint
│
└─ Local Agent Runtime Sidecar  Python
   │
   ├─ LangGraph Orchestrator
   │  ├─ graph state
   │  ├─ checkpoint
   │  ├─ human interrupt
   │  ├─ subgraphs
   │  └─ streaming events
   │
   ├─ MCP Client
   │  └─ connects to Sci-Station MCP Server
   │
   ├─ Optional RAG Layer
   │  ├─ SQLite FTS
   │  ├─ sqlite-vec / Qdrant / LanceDB
   │  └─ local index metadata
   │
   └─ Optional Code Sandbox
      ├─ OpenAI Agents SDK sandbox
      ├─ local .venv runner
      └─ restricted filesystem mount
```

其中：

- **Swift App 继续负责产品体验、文件系统、权限、Keychain、本地数据。**
- **LangGraph 负责 agent 状态机、循环、checkpoint、human-in-the-loop。**
- **MCP 负责把 Sci-Station 的知识库能力暴露成标准工具。**
- **OpenAI Agents SDK Sandbox 可作为“代码执行/长任务 worker”，不是主编排框架。**

---

## 3. 为什么首选 LangGraph，而不是 CrewAI / AutoGen / Semantic Kernel / 纯 OpenAI Agents SDK

### 首选：LangGraph

你的场景非常适合 LangGraph，因为 Sci-Station 不是简单聊天机器人，而是：

- 长任务：读几十篇论文、归纳 gap、写 proposal。
- 有状态：项目、论文、Wiki、任务、材料、运行记录。
- 需要暂停审批：写文件、改元数据、创建任务、运行代码。
- 需要可恢复：agent 可能跑一半等待用户批准。
- 需要多角色：文献管家、论文阅读器、Wiki 作者、实验助手、项目经理。

LangGraph 的核心价值正好是：**stateful、durable、human-in-the-loop、streaming、multi-step orchestration**。

### OpenAI Agents SDK：适合作为可选执行层

OpenAI Agents SDK 现在对 OpenAI 模型、tool calling、sandbox、文件/命令执行支持越来越好。如果你未来明确绑定 OpenAI 模型，它可以做主框架。但你的 README 里写的是 OpenAI-compatible API 设置 [1]，说明你可能希望兼容不同 provider。那 LangGraph 更灵活。

我的建议是：

- **主控：LangGraph**
- **代码执行/文件操作 sandbox：可选接 OpenAI Agents SDK Sandbox**
- **模型调用：仍保留 OpenAI-compatible provider 配置**

### LlamaIndex：适合做知识/RAG，不适合做主编排

LlamaIndex 在论文、文档、索引、query engine、citation retrieval 方面很强。你可以把它作为：

- paper.md / wiki / materials 的索引层
- semantic search
- evidence retrieval
- citation-aware synthesis

但主 agent 状态机还是 LangGraph 更合适。

### CrewAI：适合快速多角色 demo，不建议做你的底座

CrewAI 对“多个角色协作”上手快，但你的核心需求是本地知识库、严格审批、可恢复状态机、工具安全、复杂工作流。CrewAI 的抽象偏高，后期反而可能卡住。

### Microsoft Agent Framework / Semantic Kernel

如果你是 .NET / Azure / enterprise stack，它很强。但你的项目是 Swift macOS 本地优先工具，直接嵌入 Microsoft Agent Framework 会引入过重生态依赖，不是最自然。

---

## 4. 关键设计：把 Sci-Station 做成 MCP Server

你现在已有很多 Swift Repository 和 Service。不要让 Python sidecar 直接乱读 Research Root 文件，也不要重写一套 Python Repository。更好的做法是：

**由 Sci-Station 暴露一个本地 MCP Server，把内部能力包装成标准 tools/resources/prompts。**

### 4.1 MCP Tools 设计

先分三类。

#### A. Read-only tools，默认自动允许

```text
list_projects
get_project_overview
list_papers
search_papers
read_paper_metadata
read_paper_markdown
read_paper_section
search_wiki
read_wiki_page
list_materials
read_material
list_tasks
get_backlinks
get_related_papers
```

这些工具不修改 workspace，可以默认 allow，但仍记录 session events。

#### B. Workspace write tools，必须审批

```text
create_wiki_page
patch_wiki_page
replace_wiki_page
create_todo
update_todo
update_paper_metadata
link_paper_to_project
set_core_paper
add_tags_to_paper
import_identifier
move_material
create_project_note
```

这些工具必须在 Swift UI 的 Permission Dock 里展示：

- 工具名
- 参数
- 影响路径
- diff
- 风险等级
- allow once / deny / edit arguments / ask agent to revise

#### C. High-risk tools，默认禁止或沙箱

```text
run_python
run_shell
install_package
open_external_url
call_external_api
write_code_file
delete_file
bulk_modify_files
```

这些需要更严格策略：

- 默认 deny 或 ask。
- 只允许在 workspace `.venv` 或 sandbox 里执行。
- 文件写入只允许进入 `.sci-station/agent/runs/{run_id}/artifacts/`，再由用户批准合并。

---

## 5. 推荐的 LangGraph 状态机

你可以把科研 agent 分成几个子图。

### 5.1 顶层 Router Graph

```text
User Input
   ↓
Intent Router
   ↓
┌───────────────────────────────┐
│ literature_review_graph        │
│ paper_reading_graph            │
│ wiki_writing_graph             │
│ project_planning_graph         │
│ task_management_graph          │
│ experiment_code_graph          │
│ import_and_triage_graph        │
└───────────────────────────────┘
   ↓
Final Response + Artifacts
```

### 5.2 文献综述 Graph

```text
clarify_scope
   ↓
retrieve_candidate_papers
   ↓
read_key_papers
   ↓
extract_claims_methods_gaps
   ↓
build_evidence_table
   ↓
draft_related_work
   ↓
critic_check_citations
   ↓
approval_before_write
   ↓
write_wiki_or_project_doc
```

产物：

```text
projects/{project-id}/wiki/literature_review.md
wiki/gaps/{topic}.md
wiki/methods/{method}.md
.sci-station/agent/runs/{run-id}/evidence.json
```

### 5.3 单篇论文精读 Graph

```text
load_paper_metadata
   ↓
read_abstract_intro
   ↓
read_method
   ↓
read_experiments
   ↓
extract_contributions
   ↓
extract_limitations
   ↓
generate_structured_note
   ↓
approval_before_write
   ↓
update paper.md / annotations.md / wiki/papers/{citekey}.md
```

### 5.4 项目规划 Graph

```text
load_project_context
   ↓
load_core_papers
   ↓
analyze_current_tasks
   ↓
propose_milestones
   ↓
generate_todos
   ↓
approval_before_task_creation
   ↓
write_project_plan
```

### 5.5 代码/实验 Graph

```text
inspect_code_materials
   ↓
plan_experiment
   ↓
approval_before_execution
   ↓
run_in_sandbox
   ↓
collect_outputs
   ↓
summarize_results
   ↓
approval_before_commit
   ↓
write_report / update figures / create tasks
```

---

## 6. 你现有 Swift Agent 层应该怎么改

不要全删。建议改造成 façade。

### 6.1 保留的部分

保留：

- `SciStationAgentService` 对 UI 的接口。
- `AgentRunLogger`
- `AgentSessionEventLogger`
- `AgentThreadRepository`
- `AgentPromptDraftRepository`
- `AgentPermissionEvaluator`
- Permission Dock UI
- Hook Activity UI
- Preset Manager UI
- LLM Settings / Keychain / provider config

这些是产品资产。

### 6.2 替换的部分

逐步弱化或替换：

- `AgentPlanner`：不再让 Swift 自己 prompt LLM 生成 JSON plan。
- `AgentPlanParser`：只作为 legacy fallback。
- `AgentToolExecutor`：不再直接执行全部工具，改成 MCP tool gateway。
- Built-in tools：迁移为 MCP tools，或通过 `SciStationToolHost` 统一暴露。

### 6.3 新增一个 Agent Runtime Adapter

Swift 侧定义协议：

```swift
public protocol ExternalAgentRuntime: Sendable {
    func startRun(_ request: AgentRunRequest) async throws -> AsyncThrowingStream<AgentRuntimeEvent, Error>
    func resumeRun(runID: String, decision: AgentHumanDecision) async throws
    func cancelRun(runID: String) async throws
    func loadCheckpoint(runID: String) async throws -> AgentCheckpoint?
}
```

然后实现：

```swift
public actor LangGraphAgentRuntime: ExternalAgentRuntime {
    private let transport: AgentRuntimeTransport

    public func startRun(_ request: AgentRunRequest) async throws -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        try await transport.stream(method: "agent.start", payload: request)
    }

    public func resumeRun(runID: String, decision: AgentHumanDecision) async throws {
        try await transport.call(method: "agent.resume", payload: [
            "run_id": runID,
            "decision": decision
        ])
    }

    public func cancelRun(runID: String) async throws {
        try await transport.call(method: "agent.cancel", payload: [
            "run_id": runID
        ])
    }
}
```

Transport 可以先用：

1. `Process` + stdio JSON-RPC  
2. 后续再换 localhost HTTP / WebSocket  
3. 正式发布时可 bundle 一个 helper  

---

## 7. Python sidecar 的结构

建议仓库新增：

```text
AgentRuntime/
├── pyproject.toml
├── sci_station_agent/
│   ├── main.py
│   ├── server.py
│   ├── graph/
│   │   ├── state.py
│   │   ├── router.py
│   │   ├── literature_review.py
│   │   ├── paper_reading.py
│   │   ├── wiki_writing.py
│   │   ├── project_planning.py
│   │   └── experiment_code.py
│   ├── mcp_client/
│   │   ├── client.py
│   │   └── tools.py
│   ├── rag/
│   │   ├── indexer.py
│   │   ├── retriever.py
│   │   └── citations.py
│   ├── safety/
│   │   ├── policy.py
│   │   └── approvals.py
│   └── storage/
│       ├── checkpoints.py
│       └── events.py
└── tests/
```

LangGraph State 示例：

```python
from typing import TypedDict, Annotated, Literal
from langgraph.graph.message import add_messages

class SciStationAgentState(TypedDict):
    run_id: str
    thread_id: str | None
    project_id: str | None
    selected_paper_id: str | None
    user_goal: str
    messages: Annotated[list, add_messages]
    intent: str | None
    plan: dict | None
    evidence: list[dict]
    draft_artifacts: list[dict]
    pending_approval: dict | None
    approved_actions: list[dict]
    denied_actions: list[dict]
    final_response: str | None
```

approval node：

```python
def approval_gate(state: SciStationAgentState):
    risky_actions = [
        a for a in state.get("draft_artifacts", [])
        if a.get("risk") in {"writes_workspace", "runs_code", "external_side_effect"}
    ]

    if not risky_actions:
        return {"pending_approval": None}

    return interrupt({
        "type": "approval_required",
        "actions": risky_actions,
        "message": "这些操作需要用户确认后才能执行。"
    })
```

---

## 8. RAG / 知识索引建议

你的项目已经有：

- `library/papers/{paper-id}/paper.md`
- `meta.yaml`
- `annotations.md`
- `wiki/`
- `projects/{project-id}/wiki/`
- `materials`
- `tasks`
- `shared_research.md`

建议建立一个本地索引：

```text
.sci-station/index/
├── chunks.sqlite
├── embeddings.sqlite
├── paper_chunks.jsonl
├── wiki_chunks.jsonl
└── material_chunks.jsonl
```

### 8.1 第一阶段：SQLite FTS

先不要急着上向量库。第一版用：

- SQLite FTS5
- title / abstract / author / tag / citekey / BibTeX / wiki links
- chunk path + line range
- updated_at 增量更新

这样与你的本地优先原则一致。

### 8.2 第二阶段：Embedding

再支持：

- sqlite-vec
- LanceDB
- Qdrant local
- 或者可选 OpenAI-compatible embedding API

### 8.3 Agent 必须输出 evidence

所有严肃科研回答都要求：

```json
{
  "claim": "某方法在小样本设置下更稳定",
  "evidence": [
    {
      "source_type": "paper",
      "paper_id": "smith2024...",
      "path": "library/papers/.../paper.md",
      "lines": [120, 148],
      "quote": "短摘录",
      "confidence": 0.78
    }
  ]
}
```

这样 Wiki 写入时可以生成可追踪的科研笔记，而不是普通聊天总结。

---

## 9. 最小可行迁移路线

### Phase 0：冻结现有 Swift Agent API

目标：不要继续让 UI 直接依赖 `AgentPlanner` / `AgentToolExecutor`。

做：

- 定义 `ExternalAgentRuntime`
- 当前 Swift 内置 agent 包一层 `LegacySwiftAgentRuntime`
- AI Lab UI 只依赖 runtime protocol

收益：以后可以平滑切 LangGraph。

---

### Phase 1：做 Sci-Station MCP Server

先实现 stdio MCP server，暴露只读工具：

```text
list_papers
read_paper_markdown
search_papers
read_wiki_page
search_wiki
list_tasks
```

Swift 实现方式有两种：

#### 方案 A：Swift 原生 MCP Server

优点：直接复用 Repository。  
缺点：你要自己实现 MCP JSON-RPC 细节。

#### 方案 B：Python MCP Server + Swift CLI bridge

优点：MCP SDK 生态成熟，上手快。  
缺点：Python 需要调用 Swift CLI 或直接读文件，可能重复逻辑。

我建议：

- 短期用 Python MCP server 直接读 Research Root 文件。
- 中期把关键写入能力切回 Swift service，避免 Python 破坏数据一致性。
- 长期做 Swift 原生 MCP host。

---

### Phase 2：接入 LangGraph sidecar

实现三个 API：

```text
agent.start
agent.resume
agent.cancel
```

事件流统一成：

```json
{"type":"run_started","run_id":"..."}
{"type":"node_started","node":"retrieve_papers"}
{"type":"tool_call_requested","tool":"search_papers","args":{...}}
{"type":"tool_call_completed","tool":"search_papers","result_summary":"..."}
{"type":"approval_required","actions":[...]}
{"type":"artifact_draft","path":"wiki/plans/xxx.md","diff":"..."}
{"type":"final_response","content":"..."}
```

Swift AI Lab 直接把这些映射到现有 session timeline。

---

### Phase 3：先做 3 个高价值 workflow

不要一开始做“万能科研 agent”。先做最能体现 Sci-Station 价值的三个：

#### Workflow 1：单篇论文精读

用户说：

> 帮我精读当前 PDF，生成结构化笔记和待办。

Agent 做：

1. 读取 meta.yaml。
2. 读取 paper.md。
3. 提取贡献、方法、实验、局限。
4. 生成 `wiki/papers/{citekey}.md` 草稿。
5. 生成相关 todo 草稿。
6. 请求用户审批。
7. 写入文件和 tasks。

#### Workflow 2：项目 related work 草稿

用户说：

> 基于当前项目核心论文，写一版 related work。

Agent 做：

1. 获取 project core papers。
2. 检索 paper.md。
3. 生成 evidence table。
4. 按主题聚类。
5. 写 `projects/{project-id}/wiki/related_work.md` 草稿。
6. 用户审批后保存。

#### Workflow 3：研究计划 / gap 分析

用户说：

> 分析这个项目还有哪些 research gaps，拆成任务。

Agent 做：

1. 读 project overview。
2. 读 core papers。
3. 读 existing tasks。
4. 生成 gaps、hypotheses、next experiments。
5. 创建 todo 和 project plan 草稿。
6. 审批后写入。

这三个做好，你的知识平台 agent 就已经明显超越普通 PDF chat。

---

## 10. 权限系统要继续由 Swift 掌控

不要把审批逻辑完全交给 LangGraph。正确边界是：

```text
LangGraph 决定“想做什么”
Swift Permission Layer 决定“能不能做”
Sci-Station Repository 执行“怎么安全地做”
```

审批对象不要只是“工具名”，而应该是：

```json
{
  "tool": "patch_wiki_page",
  "risk": "writes_workspace",
  "permission_key": "wiki.write",
  "target_path": "projects/demo/wiki/related_work.md",
  "diff": "...",
  "reason": "根据 8 篇核心论文生成 related work 草稿",
  "rollback": {
    "backup_path": ".sci-station/agent/backups/..."
  }
}
```

UI 给用户四个按钮：

```text
Allow once
Deny
Edit arguments
Ask agent to revise
```

你 README 中已经有 Permission Dock、allow once、deny、correction feedback 等概念 [1]，所以这是顺着现有设计往成熟化推进。

---

## 11. 代码执行建议：必须沙箱化

科研工作台迟早会需要：

- 运行 Python 脚本
- 分析 CSV
- 生成图表
- 调 notebook
- 安装依赖
- 调外部 API

但这也是最大风险。

建议策略：

```text
默认：禁止 agent 直接运行 shell
低风险：只读查看代码文件
中风险：在 workspace .venv 中运行指定 Python 文件
高风险：安装包、联网、写代码、删除文件，必须二次审批
```

运行目录：

```text
.sci-station/agent/runs/{run-id}/sandbox/
├── input/
├── work/
├── output/
├── stdout.log
├── stderr.log
└── manifest.json
```

最终产物不要自动覆盖用户文件，而是生成 diff：

```text
outputs/report.md
figures/result.png
code/analysis_generated.py
```

用户确认后再合并。

---

## 12. 你可以保留的产品化优势

和很多 agent 框架相比，Sci-Station 已经有几个非常好的差异化点：

1. **本地 Research Root**：科研数据不是被上传到某个 SaaS。  
2. **论文库 + Wiki + Tasks + Materials 一体化**：比普通 ChatPDF 强。  
3. **macOS 原生体验**：PDF Reader、Finder、VS Code、Reminders 都有潜力。  
4. **权限 UI 已经开始设计**：这对真正可用的 agent 很关键。  
5. **可版本化 preset 与本机 local config 分层**：`.sci-ai/sci-station/` 和 `.sci-ai/workspace.local/` 的边界设计是对的 [1]。  

所以成熟 agent 框架不应该替代 Sci-Station，而应该成为它的“推理和工作流引擎”。

---

## 13. 最终推荐方案一句话版

**把 Sci-Station 定位为“本地科研知识平台 + Agent Host”，不要把它做成纯聊天工具。具体实现上：Swift App 保留 UI、Repository、权限和本地数据；新增本地 Python LangGraph sidecar 负责 agent loop、checkpoint、human-in-the-loop 和多 agent 工作流；通过 MCP 暴露论文、Wiki、项目、任务、材料、代码执行等能力；RAG 用本地 SQLite/FTS 起步，后续加 embedding；高风险执行通过沙箱和 Swift Permission Dock 审批。**

---

## 14. 推荐优先级

我会这样排：

1. **LangGraph sidecar + Sci-Station MCP Server**：主线。
2. **本地 FTS/RAG index**：让 agent 真正懂你的知识库。
3. **三个核心科研 workflow**：论文精读、related work、gap/task planning。
4. **权限 diff / approval / resume**：让 agent 可控。
5. **代码执行 sandbox**：后续增强。
6. **OpenAI Agents SDK Sandbox**：作为高级 code worker，可选接入。
7. **LlamaIndex**：作为 RAG/文档处理增强，而非主 orchestrator。
8. **CrewAI / Microsoft Agent Framework**：暂不作为核心底座。

参考框架资料：  
- OpenAI Agents SDK: https://developers.openai.com/api/docs/guides/agents  
- LangGraph: https://docs.langchain.com/oss/python/langgraph/overview  
- LlamaIndex Agents: https://developers.llamaindex.ai/python/framework/module_guides/deploying/agents/  
- Model Context Protocol: https://modelcontextprotocol.io/specification/2024-11-05/index  
- Microsoft Agent Framework: https://devblogs.microsoft.com/agent-framework/microsoft-agent-framework-version-1-0/