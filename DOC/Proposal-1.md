# 任务书 24：AI Lab Project Lifecycle Control V1

更新时间：2026-05-01

## 1. 本轮结论

任务书 23 已把 Agent Platform core 接入 AI Lab Runtime UI V1：AI Lab 现在能读取 session event timeline，显示 Permission Dock、Hook Activity、MCP Server 状态、Preset Manager，并保留现有 `LLMProvider.complete` 主路径，同时提供 OpenAI-compatible Provider V2 wrapper skeleton。

任务书 23.5 已在任务书 24 前插入并完成 AI Lab dialog-first UI refinement：主屏改为 context bar + thread timeline + bottom composer dock + pending permission dock + runtime rail。任务书 24 应基于这个新 UI 形态，把生命周期 summary 和 suggestion 放入 Project Overview 与 AI Lab runtime rail，而不是回退到旧的 Agent Panel Details 面板结构。

下一轮应重新审议并实现“项目生命周期控制”。结论是：项目生命周期控制是合理的，但不应被设计成自动推进项目的 agent loop。它更适合作为 project-level runtime rail：把项目阶段、核心材料、todo、paper 状态、wiki/proposal、agent session events 和 validation 连接起来，让用户能看见当前研究项目处于什么阶段、缺什么证据、下一步动作是否已被验证。

第一版只做可见、可解释、手动确认的生命周期控制：不自动改变项目阶段，不自动执行工具，不把 agent 建议直接写成永久状态；agent 可生成建议，但用户必须显式确认。

## 2. 重新审议：生命周期控制边界

### 2.1 为什么值得做

- Sci-Station 已有 project registry、project overview、paper links、todos、wiki/materials 和 AI Lab thread/run/session events，但这些信息仍分散。
- 研究工作天然有阶段：发现问题、整理文献、形成 proposal、实验/材料准备、执行、评审、归档。
- Agent runtime 已能审计工具与 hooks；项目生命周期可以把“agent 做了什么”和“项目推进到哪里”挂接起来。

### 2.2 为什么不能做成自动推进

- 项目阶段属于用户研究判断，不应由模型或工具结果自动写入。
- 生命周期状态会影响 UI、任务优先级和 agent context；错误自动推进会放大误导。
- 任务书 23 的安全边界仍然有效：workspace 写入、外部 side effect、MCP side effect 都必须经过 permission layer。

### 2.3 V1 设计原则

1. Read-first：先汇总项目状态与证据，不先做写入自动化。
2. Manual transitions：阶段切换必须由用户点击确认。
3. Evidence-linked：每个阶段状态要能追溯到 papers、todos、wiki/materials、proposal 或 session events。
4. Agent suggestions are drafts：agent 只能提出 lifecycle suggestion，不直接永久写入 project registry。
5. Local-first：生命周期状态写入 research root 内的非敏感项目状态文件，不能写入 `.sci-ai/sci-station/` preset。

## 3. 当前代码基线

- `ResearchProject` 已包含 id、name、description、relativePath、defaultTags、archive/collapse 等基础字段。
- Project Overview 已显示项目层总览，但还没有明确 lifecycle stage/health/next action rail。
- AI Lab thread/run 已按 project conversation 组织，并可读取 session events；AI Lab 主 UI 已是 dialog-first session + right runtime rail。
- Todo、paper link、wiki/materials 已具备项目关联信息。
- Agent runtime 已可显示 permission、hook、MCP、preset、session timeline 状态。

## 4. 执行任务

### 4.1 Project Lifecycle Core Model

1. 增加 Swift-native lifecycle model，建议包括：
   - `ProjectLifecycleStage`：inbox / literatureReview / proposalDraft / experimentPlanning / activeExecution / review / archived。
   - `ProjectLifecycleHealth`：onTrack / needsInput / blocked / stale。
   - `ProjectLifecycleEvidence`：paper、todo、wiki page、material、agent session event、manual note。
   - `ProjectLifecycleSuggestion`：agent 或规则生成的草案，不自动生效。
2. 状态持久化优先写入 project-local 非敏感文件，例如 `projects/<project>/project_lifecycle.json` 或 research root registry 的兼容扩展；本轮实现前先选择最小迁移风险路径。
3. 保持旧 project registry 可读取；缺失 lifecycle 文件时生成 default derived state，不破坏旧工作区。

### 4.2 Lifecycle Summary Builder

1. 根据 project papers、core papers、open todos、wiki/materials、recent agent events 构建只读 summary。
2. 输出阶段证据与缺口：
   - 是否有核心 paper。
   - 是否有 open todo。
   - 是否有 proposal/wiki 页面。
   - 最近 agent run 是否有未处理 permission 或 failed tool。
   - 是否有 validation 记录。
3. summary builder 放在 SwiftPM-covered core，避免把逻辑写进 SwiftUI。

### 4.3 Project Overview Lifecycle Rail

1. Project Overview 增加 lifecycle rail：stage、health、evidence count、blocked reason、next suggested action。
2. 阶段切换使用显式按钮或菜单，必须展示将写入的位置和变化摘要。
3. 不自动归档项目；archived 仍沿用现有 archive 语义或后续统一。

### 4.4 AI Lab Lifecycle Panel

1. AI Lab Details 增加 Project Lifecycle section，显示当前 project lifecycle summary。
2. Agent plan 可引用 lifecycle summary 作为上下文，但不能直接改 stage。
3. Permission Dock 与 lifecycle 联动：如果工具写入 lifecycle 文件，必须显示 `tool.write_workspace` 和 path preview。
4. Hook Activity 增加 lifecycle validation reminder：阶段切换或生命周期写入后提示记录验证。

### 4.5 Agent Suggestions Flow

1. 增加 lifecycle suggestion 草案模型：stage suggestion、reason、evidence links、recommended todos。
2. Agent plan 只生成 suggestion draft；用户确认后才写入 lifecycle state 或 todos。
3. Suggestion draft 写入 `.sci-station/agent/` 或 project-local draft 文件，不写 tracked preset。

### 4.6 Tests and Validation

1. 增加 lifecycle model round-trip 测试。
2. 增加 summary builder 测试：papers/todos/wiki/events 组合能产出正确 health 与 evidence。
3. 增加旧工作区缺失 lifecycle 文件时的兼容测试。
4. 增加 lifecycle write path permission summary 测试。
5. 运行 `swift run SciStationCoreTestRunner`。
6. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 5. 非目标

- 不启用无限 Auto Run Loop。
- 不让 agent 自动推进 lifecycle stage。
- 不把 lifecycle 状态写入 `.sci-ai/sci-station/` tracked preset。
- 不把 project lifecycle 与 Apple Calendar/Reminders 做双向自动同步。
- 不在本轮实现完整项目管理系统、甘特图或团队协作权限。
- 不让 MCP side effect 工具绕过 permission layer。

## 6. 验收标准

1. Core lifecycle model 可 Codable round-trip。
2. Lifecycle summary builder 能从 project papers、todos、wiki/materials 和 session events 生成 stage/health/evidence/gap summary。
3. Project Overview 显示 lifecycle rail，并支持手动 stage transition 草案。
4. AI Lab 显示 Project Lifecycle section，并能把 lifecycle summary 纳入 plan context。
5. Lifecycle 写入路径进入 permission dock，并显示 permission key、risk、policy 和 path preview。
6. 旧 workspace 没有 lifecycle 文件时仍可打开并显示 derived default state。
7. Agent suggestion 只作为 draft，不自动写入永久状态。
8. `swift run SciStationCoreTestRunner` 通过。
9. Xcode macOS build 通过。

## 7. Question

1. Lifecycle state V1 应写 project-local `projects/<project>/project_lifecycle.json`，还是扩展 root project registry？建议 project-local，迁移风险更低。
2. Stage 列表是否采用 inbox / literatureReview / proposalDraft / experimentPlanning / activeExecution / review / archived？建议先采用这组，后续允许自定义。
3. Project Overview 是否作为 lifecycle rail 的主入口，AI Lab 只显示 summary 与 suggestion？建议是。
4. Agent lifecycle suggestion 是否只能保存为 draft，必须用户确认后才写入 stage/todo？建议是。
5. 是否在任务书 24 只做手动 stage transition，不做自动推进规则？建议是。

## 8. 完成记录

待执行。