# Manual Test Protocol V1

更新时间：2026-05-05

> Manual Test Protocol 是 Sci-Station 在每个模块达到可运行状态后的固定人工验收流程。它不替代自动化测试，而是覆盖 UI 可用性、数据落盘、权限、状态恢复、错误提示、隐私边界和跨模块流转。

## 1. 定位

Sci-Station 是 macOS 本地优先科研工作站，核心数据落在用户选择的 Research Root。自动化测试负责验证模型、Repository、workflow contract、sidecar graph、Xcode build；手动测试负责验证用户是否真的能完成工作。

手动测试重点：

```text
用户是否能进入模块并理解状态
数据是否真实写入 Research Root
关闭重开 App 后状态是否恢复
权限/审批是否符合预期
空状态、失败状态、降级状态是否安全
Debug bundle / Keychain / API key 是否不泄漏
跨模块路径是否能走通
```

## 2. 文档结构

```text
DOC/ManualTestProtocol.md
DOC/manual-tests/
├── MT00_TestWorkspaceSetup.md
├── MT01_Workspace.md
├── MT02_Library.md
├── MT03_Wiki.md
├── MT04_Materials.md
├── MT05_TasksCalendar.md
├── MT06_PDFReader.md
├── MT07_AILab.md
├── MT08_SidecarRuntime.md
├── MT09_EvidenceArtifact.md
├── MT10_WorkspaceModules.md
├── MT11_GraphRecommendation.md
├── MT99_ReleaseRegression.md
└── runs/
```

每次执行结果写入：

```text
DOC/manual-tests/runs/YYYY-MM-DD_Pxx_ModuleName.md
```

## 3. 触发时机

### Skeleton Test

模块可打开页面、加载空状态、显示基础 UI 后立即执行。

```text
能否进入模块
空状态是否合理
导航是否正确
不会崩溃
不会误创建数据
```

### Happy Path Test

模块主流程能走通后执行。

```text
创建或导入数据
编辑数据
保存数据
重新打开后恢复
检查文件落盘位置
```

### Edge / Failure Test

错误处理、fallback、权限提示完成后执行。

```text
缺文件
坏 YAML/JSONL
空 workspace
重复导入
权限拒绝
sidecar 不可用
API key 缺失
stale / missing evidence
```

### Acceptance Regression Test

任务书收尾前执行该任务书指定 MT 用例和 MT99 partial regression。

## 4. 标准流程

### Step 0：记录前置条件

```text
测试日期：
测试人：
任务书编号：
Git commit：
macOS 版本：
Xcode 版本：
是否 clean build：
测试 workspace：Empty / Standard / Broken / Custom
AI enabled：
Sidecar enabled：
Embedding enabled：
```

### Step 1：运行自动化基线

```bash
swift run SciStationCoreTestRunner
python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

如果自动化基线失败，仍可继续探索性手动测试，但报告必须标记：

```text
自动化基线失败，本轮手动测试仅作为探索性记录，不作为最终验收。
```

### Step 2：准备标准测试工作区

见 `DOC/manual-tests/MT00_TestWorkspaceSetup.md`。

### Step 3：Smoke Test

```text
App 能启动
Workspace 能打开
Sidebar 没有异常
模块入口能点击
主页面能显示
空状态不崩溃
Inspector 不崩溃
菜单快捷键不崩溃
关闭重开 App 不崩溃
```

### Step 4：Happy Path Test

执行模块主路径，例如导入 PDF、编辑 Wiki、创建 todo、发起 AI Lab run。

### Step 5：Persistence Test

```text
写入后文件真实存在
关闭 App 后重新打开能恢复
外部修改文件后 App 能重新读取或显示可理解错误
workspace 移动或 bookmark 失效时能安全处理
```

### Step 6：Permission / Privacy Test

```text
AI 不未经批准写 workspace
sidecar 不直接写文件
API key 不出现在 workspace 明文文件
Debug bundle 不包含 .env / Keychain / secret / private path inventory
外部工具调用有审批或明确只读边界
```

### Step 7：Error / Fallback Test

```text
无 API key
sidecar 启动失败
Python 依赖缺失
PDF 缺失
paper.md 缺失
source line range 不存在
stale evidence
missing source
Reminders 权限拒绝
```

### Step 8：Integration Test

```text
Library -> PDF Reader -> annotations.md -> Evidence
Project -> Core Papers -> Related Work -> Wiki
Gap Planning -> Todo Drafts -> Permission Dock -> Tasks
Research Queue -> Add to Library -> Add to Project -> Reading Plan
Calendar -> Todo -> Apple Reminders
Materials -> VS Code -> outputs -> Project
```

### Step 9：Regression Mini-pass

每个任务书至少执行相关 MT + MT99 partial regression。

### Step 10：结论与问题分级

结论只能使用：

```text
PASS / CONDITIONAL PASS / BLOCKED / INCOMPLETE
```

问题分级：

| 等级 | 含义 | 处理要求 |
|---|---|---|
| S0 | 数据丢失、隐私泄漏、误写 workspace、崩溃 | 必须立即修复 |
| S1 | 主路径不可用 | 本任务书不能验收 |
| S2 | 重要功能异常但有 workaround | 可进入修复队列 |
| S3 | UI/文案/体验问题 | 可排后续优化 |
| S4 | 建议项 | 记录到 backlog |

## 5. Manual Test Ready

模块进入手动测试前必须满足：

```text
App 可构建
模块入口可访问
核心数据模型已接入
不会因为空 workspace 崩溃
有最小 sample data 或 seed data
主要按钮有 disabled/loading/error 状态
```

## 6. Manual Test Done

模块手动测试通过必须满足：

```text
主路径通过
重启恢复通过
数据落盘路径正确
空状态通过
至少 3 个错误状态通过
权限/隐私边界通过
与相邻模块的 integration path 通过
没有 S0/S1 问题
S2 问题有明确 follow-up
```

## 7. 测试报告模板

```markdown
# Manual Test Report

## Basic Info

- Date:
- Tester:
- Task:
- Module:
- Commit:
- macOS:
- Xcode:
- Workspace:
- AI enabled:
- Sidecar enabled:
- Embedding enabled:

## Automated Baseline

- swift run SciStationCoreTestRunner: PASS / FAIL / N/A
- python -m pytest AgentRuntime/tests: PASS / FAIL / N/A
- xcodebuild: PASS / FAIL / N/A

## Test Scope

- [ ] Smoke
- [ ] Happy Path
- [ ] Persistence
- [ ] Permission / Privacy
- [ ] Error / Fallback
- [ ] Integration
- [ ] Regression

## Test Cases

### Case 1

- ID:
- Title:
- Preconditions:
- Steps:
- Expected:
- Actual:
- Result: PASS / FAIL / BLOCKED / SKIPPED
- Notes:
- Screenshot / Log:

## Issues Found

| ID | Severity | Module | Description | Repro Steps | Status |
|---|---|---|---|---|---|

## Final Verdict

- Result: PASS / CONDITIONAL PASS / BLOCKED / INCOMPLETE
- Required fixes before merge:
- Can defer:
- Follow-up tasks:
```

## 8. 任务书嵌入模板

每份任务书末尾必须新增或更新：

```markdown
## 手动测试计划

本任务书完成后必须执行：

- MTxx:
- MTxx:
- MT99 partial regression:

新增或更新的手动测试用例：

- Case ID:
- Case ID:

允许跳过：

- Case ID:
- 原因：

阻塞验收的问题等级：

- S0:
- S1:
```
