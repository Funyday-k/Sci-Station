# 任务书 39：Workspace Module Registry V1 与内置模块声明系统

更新时间：2026-05-06

> 本任务书承接任务书 38。P38 负责把 AI artifact draft 纳入 Draft Inbox、Evidence Inspector、Permission Dock V2、saved artifact lineage 和 approval history。P39 的目标不是继续扩展 artifact UI，而是让 Sci-Station 明确知道一个 workspace 启用了哪些内置模块，以及这些模块贡献哪些目录、route、project tab、workflow、artifact kind 和 approval scope。

## 1. 背景

P36 已引入 `WorkspaceTemplate` / `WorkspaceModule` schema V0，P38 则把 AI 产物从临时结果推进为可审阅、可批准、可保存、可追溯的产品对象。下一步进入自定义工作区和模块化架构前，需要一个稳定的 Workspace Module Registry V1：

```text
Workspace open / migration
-> read enabled modules
-> resolve built-in module registry
-> show/hide routes and project tabs
-> expose module workflows
-> declare module artifact kinds
-> declare approval scopes and write path hints
-> feed P40 workspace templates and P41 module settings
```

没有 P39，后续 P40 Workspace Creation Wizard、P41 Module Customization Settings、P43 Project Space Tabs、P54-P57 特化模块都会缺少统一声明层。P39 要把 Sci-Station 从固定功能集合推进为可配置、本地优先、可审计的科研工作站平台。

## 2. 本轮目标

1. 定义 `WorkspaceModule` schema V1，支持 stable id、title、version、enabled、dependencies、routes、project tabs、directories、workflows、artifact kinds、approval scopes 和 permissions。
2. 建立 built-in module registry，覆盖当前已有核心模块和未来近期模块。
3. 在 Research Root 中读取和持久化 `settings/workspace_modules.yaml`。
4. 旧 workspace 打开后自动迁移到默认模块配置，不破坏用户数据。
5. 未启用模块不显示对应 UI route、project tab 或 workflow entry。
6. 模块可声明自己产生哪些 artifact kind，以及需要哪些 approval scope，但不能绕过 P38 Permission Dock V2。
7. 模块可声明目录和 repair metadata，为 P40 创建向导和 P41 设置页提供基础。
8. 保持 local-first 和 no dynamic code loading：P39 只做内置 registry，不做第三方插件市场。

## 2.1 实现约束

1. Module id 必须稳定、可序列化、可迁移；禁止把 UI 显示名作为持久化主键。
2. `settings/workspace_modules.yaml` 不得包含 API key、Keychain、provider raw config、prompt/response 明文或绝对隐私路径清单。
3. 禁用模块只隐藏 UI、route、project tab 和 workflow entry，不删除用户目录、artifact records、run artifacts 或 saved lineage。
4. Module 声明 approval scope 只用于 UI 提示、权限解释和 Permission Dock 请求分类；不能自动授予写权限。
5. Sidecar 不得通过 module registry 获得 workspace 任意写权限；所有写入仍由 Swift host + Permission Dock V2 执行。
6. P39 不做 P40 创建向导 UI，也不做 P41 完整启用/禁用设置页；只提供 registry、persistence、migration 和最小可见 gating。
7. P39 不做第三方插件、动态代码加载、远程模块下载或模块脚本执行。
8. Built-in registry 必须 deterministic，测试中可比较 registry snapshot。

## 2.2 WorkspaceModule schema V1 建议

```yaml
schema_version: 1
modules:
  - id: code-research
    title: Code Research
    version: 1
    enabled: true
    pinned: false

    dependencies:
      - projects
      - wiki
      - ai-lab

    directories:
      - path: projects/*/code/
        required: false
        repairable: true
      - path: projects/*/data/
        required: false
        repairable: true
      - path: projects/*/experiments/
        required: false
        repairable: true
      - path: projects/*/outputs/
        required: false
        repairable: true

    routes:
      - id: code
        path: /code
      - id: experiments
        path: /experiments
      - id: datasets
        path: /datasets

    project_tabs:
      - id: code
        title: Code
      - id: data
        title: Data
      - id: experiments
        title: Experiments

    workflows:
      - experiment_planning
      - run_log_summary
      - paper_to_code_checklist

    artifact_kinds:
      - experiment_plan
      - experiment_report
      - run_log_summary

    approval_scopes:
      - artifact_save
      - wiki_write
      - todo_create

    permissions:
      write_paths:
        - projects/*/wiki/
        - projects/*/tasks/
        - projects/*/outputs/
```

## 2.3 内置模块清单 V1

P39 至少声明这些内置模块：

```text
projects
paper-library
wiki
materials
tasks
calendar
pdf-reader
ai-lab
code
datasets
experiments
citation-graph
recommendation
writing
theory-notes
```

建议默认启用：

```text
projects
paper-library
wiki
materials
tasks
calendar
pdf-reader
ai-lab
```

建议默认禁用或隐藏为 future/experimental：

```text
code
datasets
experiments
citation-graph
recommendation
writing
theory-notes
```

## 3. 实施任务

- [x] [P39.1] `WorkspaceModule` model and schema V1。
  - 定义 stable module id、title、version、enabled、pinned、dependencies、directories、routes、project_tabs、workflows、artifact_kinds、approval_scopes、permissions。
  - 为 module id、route id、workflow id、artifact kind、approval scope 增加 validation。
  - 支持 schema_version，保留未来 migration 空间。

- [x] [P39.2] Built-in module registry。
  - 建立 deterministic built-in registry。
  - 覆盖 P39 内置模块清单 V1。
  - 每个模块至少声明 title、default enabled state、routes/project tabs/workflows/artifact kinds 的最小集合。
  - 为 future/experimental 模块提供 registry entry，但默认不强制显示 UI。

- [x] [P39.3] Module dependency declaration。
  - 支持 module dependencies。
  - dependency 缺失、禁用或版本不兼容时显示 warning。
  - 不自动删除用户数据，不自动禁用 dependent module；只影响 UI gating 和 workflow availability。

- [x] [P39.4] Module-provided routes and project tabs。
  - 将 workspace-level routes 和 project-level tabs 接入 module registry。
  - 未启用模块不显示对应入口。
  - 默认 sidebar 仍保持简洁：Home、Projects、Library、Calendar、AI Lab、Settings。
  - Project Space 可读取 module-contributed tabs，为 P43 做准备。

- [x] [P39.5] Module-provided directories and repair metadata。
  - 模块可声明 required/optional/repairable 目录。
  - P39 只做目录状态检测和 repair metadata，不做完整 repair UI。
  - 目录缺失不得阻塞打开 workspace，除非是已有核心 workspace structure 的 S0 缺失。

- [x] [P39.6] Module-provided workflows。
  - AI Lab workflow list 根据 enabled modules 过滤。
  - `paper_reading`、`related_work`、`gap_planning` 继续属于 ai-lab / paper-library / wiki / tasks 组合。
  - experimental workflows 在默认禁用模块中不显示。

- [x] [P39.7] Module-provided artifact kinds。
  - 模块声明可产生的 artifact kind。
  - Draft Inbox 可按 module / artifact kind 过滤。
  - Unknown artifact kind 必须以 safe fallback 显示，不导致 App crash。

- [x] [P39.8] Module permission and approval scopes。
  - 模块声明 `approval_scopes` 和 `permissions.write_paths`。
  - Permission Dock V2 显示 module/source scope 说明。
  - 声明权限不等于授予权限；最终写入仍需 Swift host 审批。

- [x] [P39.9] Settings persistence and legacy workspace migration。
  - 读取和写入 `settings/workspace_modules.yaml`。
  - 旧 workspace 无该文件时生成默认配置。
  - 迁移失败时显示可理解错误，并允许继续以默认核心模块打开。
  - 不改写用户原始资料目录。

- [x] [P39.10] Tests and delivery record。
  - Swift CoreTestRunner 覆盖 module schema parse/encode、built-in registry snapshot、dependency warning、route gating、workflow gating、artifact kind mapping、legacy migration。
  - Python tests 如涉及 sidecar workflow metadata，需要覆盖 module/workflow payload schema。
  - Xcode build 必须通过。
  - 更新手动测试报告，至少覆盖 workspace open、module gating、AI Lab workflow filtering、Draft Inbox artifact kind filtering、privacy scan。

## 4. 非目标

```text
不做第三方插件市场
不做动态代码加载或模块脚本执行
不做远程模块下载 / MCP OAuth 模块安装
不做完整 Workspace Creation Wizard UI（P40）
不做完整 Module Customization Settings UI（P41）
不删除禁用模块的数据
不绕过 P38 Permission Dock V2
不让 sidecar 获得 workspace 任意写权限
不做 Graph / Recommendation / Timeline 的完整实现
```

## 5. 验收标准

1. workspace 可读取 `settings/workspace_modules.yaml`；缺失时自动生成默认模块配置。
2. Built-in module registry deterministic，核心模块和 future/experimental 模块均有稳定声明。
3. 未启用模块不显示对应 route、project tab 或 workflow entry。
4. 模块可声明目录、route、project tab、workflow、artifact kind、approval scope 和 permission write path hint。
5. dependency 缺失或禁用时显示 warning，不删除用户数据。
6. 旧 workspace 打开后自动迁移到默认模块配置，迁移失败可用默认核心模块继续打开。
7. Draft Inbox / Permission Dock V2 可读取 module 声明用于 artifact kind 过滤和 approval scope 说明。
8. 禁用模块不删除 artifact records、run artifacts、saved lineage 或用户目录。
9. `settings/workspace_modules.yaml`、debug bundle 和 diagnostic 不包含 API key、Keychain、`.env`、provider raw response 或 prompt/response 明文。
10. Python tests、SwiftPM CoreTestRunner、Xcode build 均通过，或交付记录明确环境阻塞。

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
manual inspection of settings/workspace_modules.yaml for schema_version and no secrets
registry snapshot comparison for deterministic built-in modules
legacy workspace open without settings/workspace_modules.yaml
disabled module route/workflow/project tab gating
Draft Inbox filter by module / artifact kind
Permission Dock approval scope display
debug bundle scan for no secret/prompt/response plaintext
```

## 7. 手动测试计划

本任务书完成后必须执行：

```text
MT01 Workspace partial
MT07 AI Lab partial
MT09 Evidence / Artifact partial
MT10 Workspace Modules partial
MT99 Release Regression partial
```

P39 新增或重点手动测试用例：

```text
MT10-P39-01: legacy workspace opens and creates default workspace_modules.yaml
MT10-P39-02: disabling a module hides its route without deleting data
MT10-P39-03: dependency warning appears when dependent module is disabled
MT10-P39-04: AI Lab workflow list follows enabled modules
MT10-P39-05: Draft Inbox filters by module and artifact kind
MT10-P39-06: Permission Dock shows module approval scope but still requires user approval
MT10-P39-07: future/experimental module exists in registry but is hidden by default
MT10-P39-08: module config/debug bundle privacy scan contains no secrets or prompt/response plaintext
MT99 partial regression: workspace open, sidebar, Projects, Library, AI Lab, Settings, Draft Inbox, debug bundle
```

允许跳过：

```text
Full P41 enable/disable settings UI: P39 只要求 minimal gating 和 config persistence。
Full P40 creation wizard flow: P39 只要求 registry 和 default module config。
Graph/recommendation/timeline module full workflows: P39 只声明模块，不实现完整功能。
```

阻塞验收的问题等级：

```text
S0: workspace 无法打开、module config 写入 secret、禁用模块删除用户数据、sidecar 获得写权限、App crash
S1: 默认模块迁移失败且无 fallback、route/workflow gating 失效、Permission Dock scope 绕过审批、Draft Inbox artifact kind 映射导致主路径不可用
```

## 8. 交付记录

完成实现后补充：

```text
完成日期：2026-05-06
Git commit：未提交
自动化测试结果：
- `swift run SciStationCoreTestRunner` 通过。输出包含既有 CoreGraphics PDF 噪声日志。
- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests` 通过，28 passed。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` 通过。输出包含既有 `ChatMarkdownWebView` actor-isolation warnings。
手动测试报告：DOC/manual-tests/runs/2026-05-06_P39_WorkspaceModuleRegistry.md
已知问题：P38 Draft Inbox 完整生命周期尚未落地，因此 P39 本轮实现 artifact kind safe fallback 与 AI Lab artifact metadata display，不重做 Draft Inbox store/filter UI。
推迟到 P40 的事项：Workspace Creation Wizard、template -> module config generation、directory preview、privacy/AI setup page
推迟到 P41 的事项：Module settings page、enable/disable UX、pin to sidebar、project-level module visibility、directory repair UI
```

## 9. P38 依赖与继承边界

P39 假设 P38 已建立以下边界或至少已明确任务书约束：

```text
ArtifactDraft / ArtifactRecord / ArtifactApproval schema
Draft Inbox store and UI
Evidence Inspector and Evidence Health
Permission Dock V2
Saved artifact lineage
sidecar no-write boundary
```

P39 不应重新实现 P38 的 artifact lifecycle。模块只声明 artifact kind 和 approval scope；artifact 的审阅、保存、拒绝、归档、恢复、lineage 和 approval history 仍由 P38 产物生命周期负责。

## 10. Questions

1. P39 是否只做内置 module registry，不做第三方插件市场？当前建议为是。
2. Future/experimental 模块是否先进入 registry 但默认禁用或隐藏？当前建议为是。
3. 禁用模块是否只隐藏 UI / workflow，不删除目录、artifact records 或 run artifacts？当前建议为是。
4. Module approval scope 是否只用于 Permission Dock 解释和过滤，不自动授予写权限？当前建议为是。
5. P39 是否先用 `settings/workspace_modules.yaml` 作为持久化文件，P40/P41 再扩展创建和设置 UI？当前建议为是。
