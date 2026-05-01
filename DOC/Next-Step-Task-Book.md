# Sci-Station 下一阶段任务书

更新时间：2026-05-01

## 1. 当前阶段结论

任务书 12 已按当前代码重新审阅并更新，并完成关键收尾：新论文默认进入 `library/papers`、旧 `raw/papers` 兼容读取、独立项目-论文关系仓库、Agent root/current project context 和核心验证覆盖。

任务书 13 已完成旧论文库迁移工作流的第一版：Settings 的 Library 区域能显示 legacy paper 数量、ready/conflict 计数和目标路径预览，并支持用户确认后复制 ready 条目到 `library/papers`，跳过冲突并写出 JSON 迁移报告。

任务书 14 已完成项目-论文关系 UI 主数据源切换：Library Inspector 和右键菜单的项目归属、核心文章、pin、项目内用途和项目内文件夹写入 `ProjectPaperLinkRepository`，Project Overview 的 Core Papers 已优先使用关系层 pin/order 排序。

任务书 15 已完成 Agent Panel V1：AI Lab 支持 goal 输入、plan-only 生成、逐项审批写入工具、执行结果、run history 和 Copilot Bridge 导出。

任务书 16 已完成 Mac 基础体验第一阶段：第一批菜单命令和快捷键、Library 搜索与删除文案、Wiki 保存与未保存提示、Reader 搜索快捷键、可访问性和空状态下一步操作已落地。

任务书 17 已完成 Library 原生表格体验 V1：Library 列表切换为 SwiftUI `Table`，排序状态写入 workspace preferences，selection set 支持单选/多选，Inspector 多选摘要、Copy Citation、Copy BibTeX 和选择集 BibTeX 导出已落地；列拖拽和任意列顺序恢复因 SwiftUI `Table` 限制暂停到后续。

任务书 18 已按用户方向改为 AI Lab Codex-style 会话体验 V1：AI Lab 支持 Global/Project conversation 选择、按项目过滤 run history、对话 timeline、New Chat、打开历史 run，以及可折叠 Context、Plan、Tool Calls、History 和 Copilot Bridge 区域；plan-only 和 tool approval 安全模型保持不变。

任务书 19 已完成 AI Lab 对话优先与 Thread 化准备：conversation scope 改为跟随 Sidebar 当前项目，AI Lab 首屏压缩为 compact header + thread strip + prompt composer + timeline，Agent Panel 细节统一收到折叠区；`AgentThread` 与 `.sci-station/agent/threads.jsonl` 已落地，New Chat 首次成功 plan 后落盘，prompt draft 先做 session 内保存，Auto Run Loop 预留 disabled 入口并记录 read-only 自动/写入审批策略，Agent workspace 路径和同类诊断信息移入 Settings。

任务书 20 已完成 AI Lab Thread 管理与计划复用 V1：thread 重命名、归档/隐藏、空 pending draft 丢弃、历史 orphan run 手动归并、thread-level prompt draft 持久化到 `.sci-station/agent/drafts.json`、历史 prompt 复制到 New Chat，以及未来 Auto Run Loop 权限/停止条件说明均已落地。

任务书 21 已定稿为 Library Table V2 与 GitHub Copilot SDK 接口适配：下一轮优先补齐列布局、选择集批量编辑和 Quick Look，同时按 `DOC/Github Copilot` 接入手册为 AI Lab 增加 OAuth/GitHub App user token、每用户 Copilot client、token 安全边界和组织校验的 adapter 方案。

任务书 21 已完成第一版并补齐 GitHub OAuth 登录入口：Library 表格列顺序管理、多选批量编辑、Space/Preview PDF fallback、GitHub Copilot SDK experimental 配置与 token 分类、安全 adapter 边界、Connect GitHub 跳转 github.com、`sci-station://github-copilot/callback` 回调和 token exchange relay 边界均已落地；Copilot SDK 仍保持 experimental，不替换现有 DeepSeek/OpenAI-compatible provider。

任务书 21 追加修订已将 OpenCode + Claude Code 双平台借鉴计划落到当前工作区预设：`.claude` hooks、skills 与 `.mcp.json` 已作为 Sci-Station 内置 agent preset 的原型；任务书 22 已制定为 Swift-native Agent Platform 预设化迁移 V1。

任务书 22 已完成 Swift-native Agent Platform core 第一版：agent/subagent profile、permission rule/evaluator、hook definition/engine、plugin/skill/command/MCP schema、session event log、tool metadata 扩展和 Provider V2 skeleton 均已进入 SwiftPM core，并新增纯逻辑验证；AI Lab 已显示 core/provider/preset/permission/hook/MCP 状态摘要，`.sci-ai/` 已区分可进 GitHub 的 Sci-Station product preset 与本机 workspace AI 配置。

任务书 23 已完成 AI Lab Agent Platform Runtime UI V1：session event timeline、permission dock、hook activity、MCP server 状态、preset manager、Provider V2 OpenAI-compatible wrapper 和 `.sci-ai` 边界验证均已落地；主路径仍保持保守 permission model，不启用无限 Auto Run Loop。

任务书 23.5 已完成 AI Lab dialog-first UI refinement：AI Lab 主屏改为 context bar + thread timeline + bottom composer dock + pending permission dock + runtime rail，借鉴 opencode-dev 的 session/composer/dock 模式，但不引入 OpenCode runtime 依赖，也不改变 agent core 安全边界。

任务书 24 已制定为 Project Lifecycle Control V1：重新审议项目生命周期控制的合理边界，把它定位为 project-level runtime rail，而不是自动推进项目的 agent loop；第一版只做可见 summary、manual transition 和 agent suggestion draft。

迁移收束见 [DOC/Proposal13.md](Proposal13.md)，关系 UI 收束见 [DOC/Proposal14.md](Proposal14.md)，Agent Panel 收束见 [DOC/Proposal15.md](Proposal15.md)，Mac 基础体验收束见 [DOC/Proposal16.md](Proposal16.md)，Library 原生表格见 [DOC/Proposal17.md](Proposal17.md)，AI Lab 会话体验见 [DOC/Proposal18.md](Proposal18.md)，Thread 化准备见 [DOC/Proposal19.md](Proposal19.md)，Thread 管理见 [DOC/Proposal20.md](Proposal20.md)，Library V2 与 Copilot SDK adapter 见 [DOC/Proposal21.md](Proposal21.md)，Agent Platform core 见 [DOC/Proposal22.md](Proposal22.md)，AI Lab runtime UI 见 [DOC/Proposal23.md](Proposal23.md)，AI Lab dialog-first UI refinement 见 [DOC/Proposal23.5.md](Proposal23.5.md)，下一轮执行方案见 [DOC/Proposal24.md](Proposal24.md)。

## 2. 当前代码基线

- 全局研究根目录和多项目 registry 已存在。
- Home 与 Sidebar 已支持多项目。
- Todo 已支持项目归属和全局视图。
- 新导入论文默认进入 `library/papers`。
- 旧 `raw/papers` 继续兼容读取，避免破坏旧 workspace。
- `library/project_paper_links.yaml` 已保存项目-论文关系。
- `PaperRepository` 会桥接关系仓库与旧 paper metadata 字段。
- Library Inspector 与 paper context menu 的项目关系编辑已直接写入 `ProjectPaperLinkRepository`。
- `ProjectPaperLink` 已支持 `is_pinned` 与 `sort_order`，旧 YAML 可兼容读取。
- Agent snapshot 和工具上下文已包含 root/current project。
- AI Lab 已提供 Codex-style 会话 V1：conversation 跟随 Sidebar 当前项目、thread strip、workspace-persisted draft、plan-only、tool approval、tool results、thread timeline、prompt composer、可折叠上下文/计划/工具/历史和 Copilot Bridge export。
- Mac 基础体验第一阶段已完成：菜单命令、`Cmd+N` New Project、`Cmd+F` 搜索、`Cmd+S` Wiki 保存、Reader Find Next/Previous、删除文案、accessibility label 和空状态操作。
- `LegacyPaperMigrationService` 已能生成 `raw/papers` 到 `library/papers` 的 dry-run 计划，并执行 copy-only 迁移报告。
- Library 原生表格体验 V1 已完成：SwiftUI `Table`、排序模型、selection 同步、右键菜单、Copy Citation/Copy BibTeX 和批量 BibTeX 导出准备。
- AI Lab Thread 管理与计划复用 V1 已完成；Library Table V2 与 GitHub Copilot SDK OAuth 接口适配第一版已完成。
- AI Lab 23.5 对话式交互已完成：主区域优先显示 thread timeline，底部 composer dock 负责输入和次级操作，Permission Dock 前置到 composer 上方，runtime details 进入右侧 rail。
- 当前工作区已有 Claude Code 原型预设：`.claude/settings.json`、`SessionStart` / `PreToolUse` hooks、agent platform skill、research workflow skill，以及受限到仓库的 filesystem MCP 配置。
- Agent Platform core 第一版已完成：`AgentProfile`、`SubagentProfile`、permission rules、hook engine、plugin/skill/command/MCP schema、session events、tool metadata 和 Provider V2 request/response skeleton 已有 SwiftPM 验证。
- `.sci-ai/sci-station/` 已保存可进 GitHub 的 research-core product preset；`.sci-ai/workspace.local/`、`.claude/` 和 `.mcp.json` 是本机 AI bridge 配置，不进 GitHub。

## 3. 下一阶段主线

```text
Global Research Root
  -> Safe Legacy Paper Migration
  -> Project-Paper Link UI
  -> Agent Panel V1
  -> Mac Foundation UX
  -> Native Library Table
  -> Codex-style AI Lab + Threads
  -> AI Lab Thread Management V1
  -> Library Table V2 + GitHub Copilot SDK Adapter
  -> Agent Platform Presets + Swift-native Migration
  -> AI Lab Agent Platform UI Integration
  -> AI Lab Dialog-First Interaction Refinement
  -> Project Lifecycle Controls
```

## 4. 主要目标

### 4.1 旧论文库迁移

- 检测 `raw/papers` legacy paper。
- 提供 dry-run 迁移计划。
- 展示冲突、目标路径和迁移报告。
- 用户确认后迁移到 `library/papers`。
- 保证迁移后同一 paper id 不重复显示。

### 4.2 项目-论文关系 UI

- UI 编辑项目归属和核心文章时优先写入 `ProjectPaperLinkRepository`。
- 保留 `Paper.projectIDs` / `coreProjectIDs` 作为兼容镜像。
- 增加项目内用途、文件夹、pin/order 等关系层字段。
- Project Overview 的 Core Papers 使用关系层 pin/order 排序。

### 4.3 Agent Panel V1

- 在全局 AI Lab 下显示 Codex-style Agent Panel。
- 支持 Global/Project conversation，按 project context 生成计划和执行 approved tools。
- 展示 root、conversation project、project papers、project todos 和可用工具。
- 支持 plan-only、工具审批、执行结果、timeline 和按项目过滤的 run history。
- 支持 Copilot Bridge 导出。

### 4.4 AI Lab Thread 管理

- Thread 可重命名、归档/隐藏，并保留旧 `threads.jsonl` 兼容读取。
- 历史 orphan run 可手动整理为新 thread，或加入当前同 project thread。
- Prompt draft 从 session 保存评估升级为 workspace 持久化。
- 历史 plan 可复用 prompt，但不自动执行工具。
- Auto Run Loop 继续保持 disabled，只补权限矩阵和停止条件说明。

### 4.5 Mac 基础体验

- 补齐第一批菜单命令和快捷键。
- Library 搜索接入系统预期入口，并修正删除确认文案。
- Wiki 支持 `Cmd+S` 保存和 dirty indicator。
- PDF Reader 支持 `Cmd+F` 搜索聚焦和 Find Next/Previous。
- 关键 icon-only buttons 增加 accessibility label。
- Library/Wiki/Materials/Projects 空状态提供下一步操作。

### 4.6 Library 原生表格

- SwiftUI `Table` 已替换自定义 Library 列表。
- title、authors、year、updated、rating、priority、status 排序已写入 workspace preferences。
- selected paper / Inspector 同步、多选摘要和选择集 BibTeX 导出已完成。
- 单篇论文右键菜单已保留，并新增 Copy Citation / Copy BibTeX。
- 后续需要继续处理列顺序/列宽、Table header 原生排序细节和更多批量编辑。

### 4.7 项目生命周期

- 项目归档/取消归档。
- 项目排序和拖拽重排。
- 保守删除策略：第一版优先归档，不做物理删除。

### 4.8 Library Table V2

- 列显示、顺序和宽度状态继续使用 workspace preferences，并兼容旧配置。
- 若 SwiftUI `Table` 无法稳定支持完整列顺序/列宽持久化，应记录阻塞并采用可维护的替代入口。
- 多选论文支持批量 status、priority、rating、folder 和 tag 编辑。
- 项目关系批量编辑优先写入 `ProjectPaperLinkRepository`，作为本轮可选项。
- Space / Quick Look 为有 PDF 的论文提供快速预览，无 PDF 时给出非阻塞说明。
- 第一版使用现有外部 PDF opening 作为 Space / Preview fallback，后续可再接 `QLPreviewPanel`。

### 4.9 GitHub Copilot SDK 接口适配

- 继续保留现有 Copilot Bridge prompt/manifest 文件导出。
- 新增面向 GitHub Copilot SDK 的 provider/adapter 抽象，支持 OAuth 或 GitHub App user token、每用户 client、model、required org 和未连接状态。
- GitHub OAuth client secret 不得进入桌面端、workspace 配置或仓库文件。
- Connect GitHub 会打开 GitHub OAuth authorize 页面，并通过 `sci-station://github-copilot/callback` 接收 code/state。
- OAuth code-to-token 交换必须通过 token exchange relay / backend 完成，桌面端不保存 client secret。
- 用户 access token / refresh token 只能进入 Keychain 或后续安全后端，不写入 settings、preferences、agent log、thread log、drafts 或 Copilot Bridge manifest。
- 明确支持 `gho_`、`ghu_`、`github_pat_` token 类型，`ghp_` classic PAT 不作为推荐路径。
- Copilot SDK provider 不绕过 plan-only 和逐项 tool approval 安全边界。
- 第一版只实现 experimental adapter 边界与设置入口，不真正替换现有 agent provider。

### 4.10 Agent Platform 预设化迁移

- 吸收 OpenCode 的 agent runtime、session event、tool registry、permission、MCP 和 provider 抽象，但保持 Swift-native 实现。
- 吸收 Claude Code 插件的 manifest、commands、agents、skills、hooks、settings、MCP preset、validator 和安全治理模式。
- 当前 `.claude` hooks、skills 和 `.mcp.json` 作为工作区级原型，后续产品化到 Sci-Station 内置 preset registry 与 UI 管理。
- 第一批核心模型覆盖 `AgentProfile`、`AgentMode`、`SubagentProfile`、`AgentPermissionRule`、`AgentHookDefinition`、`AgentPluginManifest`、`AgentSessionEvent` 和 `MCPServerConfiguration`。
- 权限层统一 allow / ask / deny，所有 workspace 写入、shell、MCP side effect 和外部网络动作继续可审计。
- Hook engine 第一版优先支持 `SessionStart`、`PreToolUse`、`PostToolUse` 和 `Stop`。
- Plugin / skill / command schema 优先服务科研 workflow：paper review、proposal drafting、experiment planning、library curation、code/data review。
- Session event log 与现有 `runs.jsonl` 并行，不破坏旧历史。

## 5. 建议优先级

1. 下一轮按 [DOC/Proposal24.md](Proposal24.md) 做 Project Lifecycle Control V1：project-local lifecycle state、summary builder、Project Overview lifecycle rail、AI Lab lifecycle section 和 agent suggestion draft。
2. Library 后续可继续评估 `QLPreviewPanel`、真正列宽持久化或 `NSTableView` wrapper。
3. GitHub Copilot 后续需确定 OAuth relay / GitHub App / PKCE 方案后，才接入真实 SDK session。
4. Auto Run Loop 继续保持 disabled，不进入自动连续执行实现。

## 6. 验收标准

1. 用户能看到当前 root 是否还有 legacy `raw/papers` 论文。
2. 用户能确认并执行一次迁移到 `library/papers`。
3. 迁移报告写入 root 可见位置。
4. Library 不重复显示同一 paper id。
5. UI 修改项目-论文关系会更新 `library/project_paper_links.yaml`。
6. Agent Panel 能基于 Sidebar 当前项目生成计划。
7. Agent Panel 能逐项批准写入工具。
8. Agent run log 含 current project id，并能按 project conversation 过滤。
9. AI Lab thread 可重命名、归档/隐藏，且旧 `threads.jsonl` 记录兼容读取。
10. 历史 orphan run 可手动归并到同 project thread，且不重写 `runs.jsonl`。
11. Prompt draft 可在切换 project/thread 后恢复；若实现持久化，重启后也可恢复。
12. Auto Run Loop 仍保持 disabled，并说明未来权限矩阵与停止条件。
13. 菜单命令、`Cmd+F`、`Cmd+S`、删除文案和空状态符合 [DOC/Proposal16.md](Proposal16.md) 的第一阶段要求。
14. Library 原生表格、排序和 selection 行为符合 [DOC/Proposal17.md](Proposal17.md) 的 V1 要求。
15. Library Table V2 能管理列布局；如无法完整支持列顺序/列宽持久化，完成记录说明 SwiftUI `Table` 阻塞和替代方案。
16. 多选论文可批量编辑 status、priority、rating、folder 和 tags。
17. Space / Quick Look 或 fallback 预览入口对有 PDF 的论文可用。
18. GitHub Copilot SDK adapter 不保存 client secret 或用户 token 到明文 workspace 文件。
19. AI Lab 保留 Copilot Bridge export，并能表达 GitHub Copilot provider 的未连接/连接状态。
20. Agent Platform core models 能表达 profile、permission、hook、plugin、session event 和 MCP server 配置。
21. Permission rule 支持 allow / ask / deny，并能按工具、命令和路径匹配。
22. Hook model 支持 `SessionStart`、`PreToolUse`、`PostToolUse` 和 `Stop` 的第一版语义。
23. Plugin manifest、skill frontmatter、command template 和 MCP config 有 parser / validator 草案。
24. MCP 配置不会把 secret value 序列化到 workspace。
25. Session event log 与现有 `runs.jsonl` 并行，不破坏旧历史。
26. SwiftPM Core Test Runner 通过。
27. Xcode macOS build 通过。

## 7. Question

1. Library Table V2 是否优先保持 SwiftUI `Table`，只有明确阻塞时再局部引入 `NSTableView` wrapper？建议是。
2. 批量项目关系编辑是否纳入任务书 21，还是先只做 paper metadata 批量编辑？建议纳入可选项。
3. Quick Look 是否必须使用 `QLPreviewPanel`，还是允许先用现有内置 Reader / PDF opening 作为 Space fallback？建议允许 fallback。
4. GitHub Copilot SDK 接口本轮是否只做安全 adapter 边界和设置草案，不真正替换现有 provider？建议是。
5. GitHub OAuth token exchange 是否必须通过后端 relay，而不是桌面端保存 client secret？建议必须通过后端 relay 或后续明确的 GitHub App/PKCE 方案。
6. 任务书 22 是否先完成 Agent Platform core models、permission、hook、plugin/MCP schema，再重构 AI Lab UI？建议是。
7. Session event log 是否应与现有 `runs.jsonl` 并行一段时间，而不是立即替换？建议并行。
8. OpenCode 子进程 bridge 是否暂缓，先做 Swift-native core？建议暂缓。
