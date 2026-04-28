# 任务书 11：AI Agent 底座、Copilot Bridge 与科研动作自动化

更新时间：2026-04-28

## 审阅意见

任务书 10 已把 Materials、VS Code Bridge、Python 运行和批量导入体验向前推进了一轮。现在更重要的方向不是继续把 Sci-Station 做成 IDE，而是把已经存在的论文、Wiki、Todo、Calendar、Materials、LLM 总结能力统一成“可被 agent 调用的应用动作层”。

本轮已阅读两类参考结构：

1. GitHub Copilot Chat prompts 目录：其核心不是单个 prompt，而是 instructions、prompts、skills、agents、hooks、debug log 等可组合 primitives。
2. DaMaSCUS-SUN `.trellis` 目录：其价值在于轻量项目记忆，包含项目规范、研究工作流、个人 journal、版本和开发者元信息。

Sci-Station 的方向应借鉴这些结构，但不能把外部 agent 系统照搬进 App。正确做法是构建自己的 agent kernel，让模型只负责计划和解释，实际写入动作全部通过 Sci-Station 的 typed tools 和 repository/service 层执行。

## 关于 GitHub Copilot 接入的判断

当前不应把 VS Code 内部 Copilot Chat extension 当成可直接嵌入 App 的后端，也不应读取或复用用户的 Copilot token。GitHub Copilot Chat 在 VS Code 中可用，不等于 macOS App 有稳定公开的 Chat API 可直接调用。

本轮建议采用两层策略：

1. **主路径：OpenAI-compatible Provider** 继续作为 Sci-Station 内置 LLM 调用接口，保持可配置、可替换、可测试。
2. **Copilot Bridge：导出 agent request** 到 `.sci-station/agent/copilot-bridge/`，让 VS Code / Copilot 或未来轻量 VS Code extension 读取同一份上下文和 tool contract，生成 agent plan 后再回到 Sci-Station 执行。

这样既能利用用户手头可用的 Copilot，又不会把不稳定的 VS Code 内部实现绑进 Sci-Station 核心。

## 本轮基线

1. 已有 `LLMProvider`、`OpenAICompatibleProvider`、`LLMConfiguration`、`KeychainAPIKeyStore`。
2. 已有 `PaperSummaryService`、`PaperSummaryPromptBuilder`、`LLMWritebackService`。
3. 已能从选中论文触发 LLM Summary，并预览后 Replace / Append / Save Draft。
4. 已有 Todo、Paper、Collections、Tags、Markdown、Wiki、Calendar、Materials 等可转成 agent tools 的应用服务。
5. 目前缺少统一 agent plan、tool registry、权限确认、运行日志、Copilot Bridge 和可扩展 tool contract。

## 总体目标

任务书 11 的主目标是建立 Sci-Station AI Agent V1：

```text
User Intent
  -> Agent Context Builder
  -> LLM / Copilot Bridge Planner
  -> Typed Agent Plan
  -> User Approval Gate
  -> Sci-Station Tools
  -> Repository / Service Writeback
  -> Agent Run Log
```

原则：用户能在软件里做的事情，agent 未来也应该能做；但 agent 不能绕开权限、不能直接改文件、不能在用户不知情时上传论文全文或执行外部命令。

## 首批已落地底座

本轮已经先落了 core 层骨架，位置为 `Sci-Station/Agent/`：

1. `AgentModels`：run mode、tool definition、tool call、plan、tool result、workspace snapshot。
2. `AgentWorkspaceContextBuilder`：把当前 workspace、论文和 Todo 压成模型可读上下文。
3. `AgentPromptBuilder`：把用户目标、workspace context 和 tools 组合为 agent planner prompt。
4. `AgentPlanParser`：从 LLM/Copilot 输出中提取 typed JSON plan。
5. `AgentToolRegistry` / `AgentToolExecutor`：注册工具、确认门控、执行工具、返回结果。
6. `CreateTodoAgentTool`：agent 可创建 workspace Todo。
7. `UpdatePaperClassificationAgentTool`：agent 可更新论文 tags、categories、priority、status。
8. `AgentRunLogger`：写入 `.sci-station/agent/runs.jsonl`。
9. `AgentCopilotBridgeExporter`：导出 Copilot Bridge prompt 和 manifest。

## 下一轮目标

### 目标 1：Agent UI V1

- 新增右侧或独立 AI Agent Panel。
- 支持输入自然语言任务。
- 显示 agent plan、tool calls、影响文件、风险等级。
- 写入型 tool 必须让用户显式确认。
- 支持 plan-only、approve-and-run、cancel。

### 目标 2：Copilot Bridge V1

- 在 Sci-Station 中生成 `.sci-station/agent/copilot-bridge/*.prompt.md` 和 manifest。
- VS Code Bridge 或手动流程可打开该 prompt。
- Copilot 只负责产出 plan JSON，不直接修改 Sci-Station 数据。
- Sci-Station 导入 plan 后仍走本地 tool approval gate。

### 目标 3：Agent Tool 扩展

优先把现有用户动作逐步工具化：

- Todo：新增、更新、完成、删除。
- Paper：自动打标签、设优先级、设阅读状态、建议 collection。
- Wiki：创建论文页、追加 AI note、生成 research gap 页面。
- LLM：总结论文、比较多篇论文、生成 related work 草稿。
- Import：从 DOI/arXiv/URL 列表创建导入计划。
- Materials：整理输出文件、归档 figures、关联到论文或项目页。

### 目标 4：Agent Memory 与 Project Context

- 在 `.sci-station/agent/` 保存 run log、pending plans、bridge requests。
- 借鉴 Trellis，增加轻量项目上下文文件：project spec、workflow、journal。
- `shared_research.md` 继续作为人工与 LLM 共享上下文。
- 每次 agent 运行记录 goal、plan、tool results、修改路径和错误。

### 目标 5：安全与隐私边界

- 默认 plan-only，不默认执行写入。
- 所有 workspace writes 必须显示 modified paths。
- 外部副作用工具单独标记 `externalSideEffect`。
- 云端 LLM 请求前显示将发送的上下文摘要。
- API Key 继续只进 Keychain。
- 不读取或复用 VS Code Copilot 内部 token。

## 执行任务

### 任务 A：Agent Panel

- 新增 Agent section 或 Inspector panel。
- 输入自然语言 goal。
- 调用 `SciStationAgentService` 生成 plan。
- 渲染 tool calls、risk、requires confirmation、arguments。
- 支持用户逐项批准。

### 任务 B：Plan 导入与 Copilot Bridge

- 提供 Export to Copilot Bridge。
- 提供 Import Agent Plan JSON。
- 验证 JSON plan 的 tool name 必须存在于 registry。
- 导入后的执行仍走本地确认。

### 任务 C：工具扩展第一批

- 完成 Todo update / complete / delete tools。
- 增加 Generate Wiki Page tool。
- 增加 Summarize Selected Paper tool。
- 增加 Suggest Paper Classification tool，该 tool 只生成建议，不直接写回。

### 任务 D：运行日志与审计视图

- 在 `.sci-station/agent/runs.jsonl` 显示最近运行。
- Agent Panel 可展开查看上次修改路径和错误。
- 支持重新打开 pending plan。

### 任务 E：验证补强

- Core runner 覆盖 plan parser、approval gate、tool writeback。
- UI 手动检查覆盖 plan-only、approved writes、cancel、不合法 JSON。
- Xcode macOS build 通过。

## 验收标准

1. 用户能在 Sci-Station 输入“给当前论文添加一个阅读 Todo”，看到 plan，并确认后写入 `tasks/todos.yaml`。
2. 用户能输入“把当前论文分类为 simulation / dark-matter，优先级设为 high”，确认后写回 `meta.yaml`。
3. 未确认的写入型 tool 不会修改 workspace。
4. 每次 agent run 都写入 `.sci-station/agent/runs.jsonl`。
5. Copilot Bridge 能导出可由 VS Code/Copilot 阅读的 prompt 与 manifest。
6. Copilot 生成的 plan 只能作为输入，Sci-Station 仍负责验证和执行。
7. SwiftPM Core Test Runner 通过。
8. Xcode macOS build 通过。

## 风险与约束

- Copilot 不能作为当前 App 内直接后端承诺；第一版只能做 bridge。
- Agent tool 不应直接进行 ad hoc 文件修改，必须走 repository/service。
- 分类、总结、写作类输出必须可预览、可撤销或至少可审计。
- 外部命令、Python 运行、包安装、日历/提醒事项同步都属于高风险工具，必须单独确认。
- 不要把 agent 设计成聊天玩具；核心指标是能否稳定完成科研工作流中的真实动作。

## 后续建议

任务书 12 可以把重点放在 Agent UI、Copilot Bridge import/export 和 Wiki/LLM tools 扩展。任务书 11 的底层框架已经可以作为后续所有 AI 自动化能力的统一入口。