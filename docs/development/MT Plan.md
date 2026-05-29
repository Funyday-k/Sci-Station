下面我建议额外建立一套独立的 **手动测试流程 Manual Test Protocol V1**。它不替代自动化测试，而是作为每个模块“基本实现后”的固定验收流程。

核心思想是：

> **每个模块达到可运行状态后，立即进入手动测试；不是等整个任务书完成后才测试。**

这样可以尽早发现交互、数据落盘、权限、状态恢复、边界提示、空状态等自动化测试不容易覆盖的问题。

---

# 一、手动测试体系的定位

目前项目已经有自动验证基础，例如 P35/P36 都要求运行：

```bash
python -m pytest AgentRuntime/tests
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

这些命令已经是 P35/P36 的强制验证路径 [1][2]。但自动测试更适合验证：

```text
数据模型是否正确
Repository 是否可读写
workflow contract 是否稳定
sidecar graph 是否输出预期结构
Xcode 是否可构建
```

手动测试则重点验证：

```text
用户是否真的能用
UI 状态是否清楚
错误提示是否可理解
数据是否真的落在 Research Root
重启 App 后状态是否恢复
权限和审批是否符合预期
空状态、失败状态、降级状态是否安全
```

Sci-Station 当前是 macOS 本地优先科研工作站，核心数据落在用户选择的 Research Root，包含论文库、项目 Wiki、材料、任务、日历、PDF Reader 和 AI Lab 等模块 [3]。因此手动测试必须围绕“本地工作区真实使用路径”来设计。

---

# 二、建议新增一份长期文档

建议新增：

```text
docs/development/ManualTestProtocol.md
docs/development/manual-tests/
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
└── MT99_ReleaseRegression.md
```

之后每个任务书末尾都加一节：

```text
手动测试要求：
- 必须执行哪些 MT 用例
- 新增或修改哪些 MT 用例
- 哪些用例允许暂时 skipped
- skipped 原因
- 手动测试结论
```

---

# 三、手动测试触发时机

建议把手动测试分成 4 个触发点。

## 1. 模块骨架完成后：Skeleton Test

当一个模块已经可以打开页面、加载空状态、显示基础 UI 时，立刻测：

```text
能否进入模块
空状态是否合理
导航是否正确
不会崩溃
不会误创建数据
```

例如 Workspace Module Registry 做到一半时，就可以测试“禁用模块后入口是否隐藏”。

---

## 2. 核心路径完成后：Happy Path Test

当模块的主流程能走通时，测试最常见路径。

例如 Library：

```text
导入 PDF
生成 paper.pdf / paper.md / meta.yaml / annotations.md
在 Library 中出现
打开 PDF Reader
编辑 metadata
重启 App 后仍存在
```

---

## 3. 边界状态完成后：Edge / Failure Test

当错误处理、空状态、fallback、权限提示完成后，测试：

```text
缺文件
坏 YAML
空 workspace
重复导入
权限拒绝
sidecar 不可用
API key 缺失
source missing
stale evidence
```

P35/P36 都明确要求 stale/missing evidence warning、fallback reason、debug bundle 隐私清单等用户可理解状态 [1][2]。

---

## 4. 任务书收尾前：Acceptance Regression Test

在任务书完成前跑一遍该任务书相关模块的完整手动验收。

例如 P36 收尾前，必须手动验证：

```text
切换三种 runtime selector 后分别发起新 AI Lab run
sidecar crash 后查看 fallback/replay
生成 debug bundle 并检查隐私清单
点击 evidence 定位 Markdown 行或 PDF 页
```

这些正是 P36 的手动验证要求 [2]。

---

# 四、每个模块的标准手动测试流程

每个模块完成后都按下面 10 步走。

---

## Step 0：确认测试前置条件

测试前先记录：

```text
测试日期：
测试人：
任务书编号：
Git commit：
macOS 版本：
Xcode 版本：
是否 clean build：
是否使用 sample workspace：
是否开启 AI：
是否开启 sidecar：
是否开启 embedding：
```

建议固定写入：

```text
docs/development/manual-tests/runs/YYYY-MM-DD_Pxx_ModuleName.md
```

---

## Step 1：运行自动化基线

手动测试前先运行自动化基线：

```bash
swift run SciStationCoreTestRunner
python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

如果这一步失败，仍然可以继续做手动探索测试，但测试报告必须标记：

```text
自动化基线失败，本轮手动测试仅作为探索性记录，不作为最终验收。
```

---

## Step 2：准备标准测试工作区

建议准备 3 类 workspace。

### A. Empty Workspace

用于测试首次创建、空状态、目录补齐。

```text
ManualTestWorkspace_Empty/
```

### B. Standard Workspace

用于常规功能测试。

建议包含：

```text
3 篇 paper
1 个 project
project overview
core papers
wiki pages
existing todos
materials 文件
code 文件
图片
PDF
annotations.md
```

P35 的测试 fixture 也要求 sample workspace 至少包含 3 篇 `paper.md`、1 个 project、project core papers、wiki/project overview 和 existing todos [1]。

### C. Broken Workspace

用于错误恢复测试。

包含：

```text
缺失 meta.yaml
损坏 paper_index.yaml
缺失 paper.md
缺失 PDF
损坏 todos.yaml
缺失 settings/
移动过的 workspace
source_hash 变化的 evidence
```

---

## Step 3：Smoke Test

每个模块都必须先跑最小冒烟测试：

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

建议所有模块共享一个 `MT00_Smoke.md`。

---

## Step 4：Happy Path Test

测试用户最常用的一条主路径。

例如 Wiki 模块：

```text
打开 Wiki
新建页面
输入 Markdown
切换 Preview
插入公式
Cmd+S 保存
切换页面
重新打开 App
确认内容仍在
确认文件落盘到 wiki/
```

README 中已经列出 Wiki 支持 Markdown 编辑、Cmd+S 保存、Source/Preview/Split、GFM、表格、代码块、图片和 KaTeX 公式等能力，可以直接转成手动测试用例 [3]。

---

## Step 5：Persistence Test

所有模块必须测试：

```text
写入后文件是否真实存在
关闭 App 后重新打开是否恢复
修改文件后 App 是否能重新读取
workspace 移动或 bookmark 失效时是否能处理
```

因为 Sci-Station 的核心原则是文件系统优先，核心数据落在用户可见目录中 [3]。

---

## Step 6：Permission / Privacy Test

凡是涉及 AI、写文件、外部工具、Keychain、debug bundle 的模块都必须测权限边界。

重点检查：

```text
AI 是否未经批准写入 workspace
sidecar 是否直接写文件
API key 是否出现在 workspace 明文文件
debug bundle 是否包含敏感信息
.env 是否被打包
Keychain 内容是否泄漏
```

P35/P36 都明确要求 sidecar 不获得 workspace 写权限，所有 artifact 保存和 todo 创建继续通过 Swift Permission Dock [1][2]。

---

## Step 7：Error / Fallback Test

测试失败状态是否可理解。

例如：

```text
无 API key
sidecar 启动失败
Python 依赖缺失
embedding store 不可用
PDF 缺失
paper.md 缺失
source line range 不存在
stale evidence
missing source
Reminders 权限拒绝
```

P36 明确要求 sidecar health panel 显示 Python version、sidecar version、protocol/schema version、dependency check、last crash、fallback reason [2]。

---

## Step 8：Integration Test

测试模块之间是否能串起来。

例如：

```text
Library -> PDF Reader -> annotations.md -> Evidence
Project -> Core Papers -> Related Work -> Wiki
Gap Planning -> Todo Drafts -> Permission Dock -> Tasks
Research Queue -> Add to Library -> Add to Project -> Reading Plan
Calendar -> Todo -> Apple Reminders
Materials -> VS Code -> outputs -> Project
```

Sci-Station 已经有 Library、Projects、Wiki、Materials、Tasks、Calendar、PDF Reader、AI Lab 等多个模块，手动测试要重点关注模块之间的流转 [3]。

---

## Step 9：Regression Mini-pass

每完成一个新模块后，至少跑一组轻量回归：

```text
Workspace create/open
Library import PDF
Wiki edit/save
Todo create
PDF Reader open/search
Materials preview
AI Lab open
Settings open
```

避免新功能破坏旧主路径。

---

## Step 10：测试结论与问题分级

每次手动测试必须输出结论：

```text
通过 / 有条件通过 / 阻塞 / 未测完
```

问题分级建议：

| 等级 | 含义 | 处理要求 |
|---|---|---|
| S0 | 数据丢失、隐私泄漏、误写 workspace、崩溃 | 必须立即修复 |
| S1 | 主路径不可用 | 本任务书不能验收 |
| S2 | 重要功能异常但有 workaround | 可进入修复队列 |
| S3 | UI/文案/体验问题 | 可排后续优化 |
| S4 | 建议项 | 记录到 backlog |

---

# 五、标准手动测试报告模板

建议每次测试都按这个模板写。

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

- swift run SciStationCoreTestRunner: PASS / FAIL
- python -m pytest AgentRuntime/tests: PASS / FAIL / N/A
- xcodebuild: PASS / FAIL

## Test Scope

本轮测试覆盖：

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

- Result: PASS / CONDITIONAL PASS / BLOCKED
- Required fixes before merge:
- Can defer:
- Follow-up tasks:
```

---

# 六、模块级手动测试清单

下面给出每个主要模块的手动测试重点。

---

## MT01：Workspace 手动测试

### 目标

验证 workspace 创建、打开、恢复、目录补齐、偏好保存。

当前项目支持创建本地 ResearchWorkspace、打开已有工作区、自动补齐缺失目录和种子文件，并用 security-scoped bookmark 恢复最近 workspace [3]。

### 测试用例

```text
MT01-01 创建空 workspace
MT01-02 打开已有 workspace
MT01-03 最近 workspace 自动恢复
MT01-04 workspace 被移动或删除后的失效处理
MT01-05 缺失目录自动补齐
MT01-06 settings/workspace_preferences.yaml 读写
MT01-07 Reveal in Finder
MT01-08 不允许直接选择源码仓库根目录时的提示
```

### 验收重点

```text
不误删已有数据
不覆盖用户文件
目录结构符合预期
重启后能恢复
权限提示清楚
```

---

## MT02：Library 手动测试

### 目标

验证论文导入、元数据、搜索、批量操作、collection、BibTeX。

当前 Library 支持 PDF 导入、拖入 PDF、Add by Identifier、meta.yaml、citekey、paper id、搜索、批量设置阅读状态/优先级/评分/tags 等 [3]。

### 测试用例

```text
MT02-01 Import PDF
MT02-02 Drag PDF
MT02-03 Add by DOI
MT02-04 Add by arXiv
MT02-05 Add by PDF URL
MT02-06 批量 Add by Link
MT02-07 编辑 meta.yaml 字段
MT02-08 搜索 title/author/tag/DOI/arXiv/abstract/BibTeX
MT02-09 多选批量 tag
MT02-10 多选批量 status/priority/rating
MT02-11 删除论文确认路径
MT02-12 重启后论文仍存在
```

---

## MT03：Wiki / Markdown 手动测试

### 目标

验证 Markdown 编辑、保存、预览、frontmatter、wikilink、backlink、snippet。

当前 Wiki 支持 Markdown 页面扫描、应用内编辑保存、Cmd+S、Unsaved 标记、Source/Preview/Split、GFM、表格、代码块、图片和 KaTeX 公式 [3]。

### 测试用例

```text
MT03-01 新建 Wiki 页面
MT03-02 编辑并 Cmd+S 保存
MT03-03 未保存切换页面提示
MT03-04 Source/Preview/Split 切换
MT03-05 表格渲染
MT03-06 代码块渲染
MT03-07 KaTeX 公式渲染
MT03-08 图片相对路径渲染
MT03-09 YAML frontmatter 解析
MT03-10 [[wikilink]] outgoing links
MT03-11 backlinks
MT03-12 snippets 触发
```

---

## MT04：Materials / VS Code 手动测试

### 目标

验证材料浏览、预览、隐藏系统目录、VS Code 打开、Python run bridge。

当前 Materials 默认扫描 inbox、data、code、figures、outputs、scripts、prompts 和 shared_research.md，并隐藏 settings、refs、tasks、imports、.sci-station 等系统目录 [3]。

### 测试用例

```text
MT04-01 Materials 显示用户材料
MT04-02 settings/ 不显示
MT04-03 .sci-station/ 不显示
MT04-04 Markdown 预览
MT04-05 Python 预览
MT04-06 图片预览
MT04-07 PDF 预览
MT04-08 Reveal in Finder
MT04-09 Open workspace in VS Code
MT04-10 Open selected file in VS Code
MT04-11 创建 workspace .venv
MT04-12 Run in VS Code 写入 tasks.json
MT04-13 Terminal run 生成 .command
```

---

## MT05：Tasks / Calendar / Reminders 手动测试

### 目标

验证 todo、due date、priority、Apple Reminders 发布、Calendar 显示。

当前 Dashboard 月历能显示本地 todo、workspace calendar event 和 Apple Calendar/Reminders 标题；Todo 支持 due date、priority、notes、编辑删除，并可发布到 Apple Reminders [3]。

### 测试用例

```text
MT05-01 新建 todo
MT05-02 编辑 todo
MT05-03 删除 todo
MT05-04 设置 due date
MT05-05 设置 priority
MT05-06 添加 related paper id
MT05-07 Calendar 显示 todo
MT05-08 发布到 Apple Reminders
MT05-09 拒绝系统权限后本地 todo 仍可用
MT05-10 重启后 todo 保留
```

---

## MT06：PDF Reader 手动测试

### 目标

验证 PDF 打开、搜索、页码、缩放、Notes、Tasks、Citations、Links。

当前 PDF Reader 支持页码、Cmd+F、Cmd+G、Shift+Cmd+G、缩放、PDFKit 历史前进/后退，右侧栏支持 Metadata、Notes、Tasks、Citations、Links、Abstract、Files [3]。

### 测试用例

```text
MT06-01 打开 PDF
MT06-02 页码跳转
MT06-03 Cmd+F 搜索
MT06-04 Cmd+G 下一处
MT06-05 Shift+Cmd+G 上一处
MT06-06 缩放
MT06-07 Notes 保存到 annotations.md
MT06-08 Reader Tasks 创建 todo
MT06-09 Citations 复制 BibTeX
MT06-10 导出 .bib
MT06-11 Links 打开 DOI/arXiv/URL/PDF URL
MT06-12 缺失 PDF 时显示错误不崩溃
```

---

## MT07：AI Lab 基础手动测试

### 目标

验证 AI Lab 对话、project scope、thread、plan、Permission Dock、run history。

当前 AI Lab 是对话优先的 Agent Panel，conversation scope 跟随当前项目，并有 thread strip、prompt composer、session event timeline、Permission Dock、hook activity、MCP servers 等区域 [3]。

### 测试用例

```text
MT07-01 打开 AI Lab
MT07-02 切换 project scope
MT07-03 New Chat 创建 pending thread
MT07-04 第一次成功 plan 后写入 threads.jsonl
MT07-05 prompt draft 切换项目后恢复
MT07-06 生成 plan
MT07-07 Permission Dock 展示 tool risk
MT07-08 read-only tool auto-allow
MT07-09 write tool 默认 ask
MT07-10 allow once
MT07-11 deny
MT07-12 历史 run 重新打开
MT07-13 损坏 JSONL 行不阻止历史读取
```

---

## MT08：Sidecar Runtime 手动测试

### 目标

验证 P36 重点：runtime selector、sidecar health、fallback、restart、debug bundle。

P36 要求 Runtime selector 真实影响新 run，Sidecar health panel 显示真实 dependency/crash/fallback 状态，debug bundle 生成真实 zip 且默认不含敏感信息 [2]。

### 测试用例

```text
MT08-01 选择 Swift Loop 后发起新 run
MT08-02 选择 LangGraph Sidecar 后发起新 run
MT08-03 选择 Auto fallback 后发起新 run
MT08-04 sidecar 不可用时显示 fallback reason
MT08-05 Restart sidecar
MT08-06 Open run directory
MT08-07 Disable sidecar for workspace
MT08-08 sidecar crash 后显示 last checkpoint
MT08-09 replay 已完成 run 不受 selector 改变影响
MT08-10 Export debug bundle
MT08-11 检查 zip 不包含 API key/.env/Keychain/private path inventory
```

---

## MT09：Evidence / Artifact / Citation Critic 手动测试

### 目标

验证 evidenceRefs、source jump、stale/missing warning、critic 阻断、low confidence 保存。

P35 要求每条 evidence 可跳转到 `relative_path + line range`，citation critic 检查 unsupported claims、stale evidence、weak evidence、overclaims，并且无 evidence 的核心 claim 不能直接进入 final approval [1]。

### 测试用例

```text
MT09-01 生成 paper reading artifact
MT09-02 展开 evidenceRefs
MT09-03 点击 evidence 跳转 paper.md line range
MT09-04 点击 evidence 跳转 annotations.md line range
MT09-05 点击 evidence 跳转 wiki line range
MT09-06 有 PDF page mapping 时跳转 PDF 页
MT09-07 修改 source_hash 后显示 stale evidence
MT09-08 删除 source 后显示 missing source
MT09-09 unsupported claim 被 critic 阻断
MT09-10 用户选择保存为 low confidence draft
MT09-11 保存后 Wiki citation block 保留 metadata
```

---

## MT10：Workspace Module / Template 手动测试

### 目标

验证未来模块化工作区能力。

### 测试用例

```text
MT10-01 创建 Minimal Workspace
MT10-02 创建 Literature Review Workspace
MT10-03 创建 Theory Research Workspace
MT10-04 创建 Code Research Workspace
MT10-05 创建 Writing Project Workspace
MT10-06 Custom 勾选模块
MT10-07 预览目录结构
MT10-08 创建后 settings/workspace_modules.yaml 正确
MT10-09 禁用模块后 Sidebar 入口隐藏
MT10-10 禁用模块不删除已有数据
MT10-11 依赖缺失时显示 warning
MT10-12 Repair missing directories
```

---

# 七、针对任务书的手动测试嵌入方式

以后每份任务书都建议增加固定章节。

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

例如 P36 可以这样写：

```text
P36 手动测试要求：

必须执行：
- MT08 Sidecar Runtime
- MT09 Evidence / Artifact
- MT07 AI Lab partial
- MT99 Regression partial

重点验证：
- Runtime selector 是否真实影响新 run
- Sidecar health panel 是否显示真实状态
- agent.start 是否进入 paper_reading / related_work / gap_planning
- Evidence 是否能定位 Markdown line range / PDF page
- Debug bundle zip 是否不含敏感信息
```

---

# 八、建议建立“测试准入”和“测试通过”标准

## 1. Manual Test Ready

模块进入手动测试前必须满足：

```text
App 可构建
模块入口可访问
核心数据模型已接入
不会因为空 workspace 崩溃
有最小 sample data 或 seed data
主要按钮有 disabled/loading/error 状态
```

---

## 2. Manual Test Done

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

---

# 九、建议的手动测试节奏

## 每日开发节奏

```text
上午：
- 开发模块功能

下午：
- 对当天完成的模块跑 Smoke + Happy Path

收尾：
- 记录问题
- 修 S0/S1
- S2/S3 进入 backlog
```

## 每个任务书中段

```text
跑模块级完整手动测试
重点测边界、错误、权限、持久化
```

## 每个任务书结束前

```text
跑任务书指定 MT
跑 MT99 partial regression
补齐 Manual Test Report
更新任务书交付记录
```

---

# 十、MT99：轻量回归测试建议

每完成一个任务书，建议都跑一遍 30–45 分钟的轻量回归。

```text
MT99-01 创建新 workspace
MT99-02 打开旧 workspace
MT99-03 导入 PDF
MT99-04 打开 PDF Reader
MT99-05 保存 annotations.md
MT99-06 新建 Wiki 页面并 Cmd+S
MT99-07 新建 todo
MT99-08 打开 Materials 并预览文件
MT99-09 打开 Projects
MT99-10 打开 AI Lab
MT99-11 打开 Settings
MT99-12 关闭并重启 App
MT99-13 最近 workspace 自动恢复
MT99-14 检查 Research Root 中是否出现异常敏感文件
```

---

# 十一、优先立即落地的 5 件事

我建议你下一步马上做这几件：

```text
1. 新建 docs/development/ManualTestProtocol.md
2. 新建 docs/development/manual-tests/MT00_TestWorkspaceSetup.md
3. 新建 docs/development/manual-tests/MT99_ReleaseRegression.md
4. 给 P36 增加“手动测试计划”章节
5. 准备三个标准测试 workspace：Empty / Standard / Broken
```

其中 Standard Workspace 应该至少包含：

```text
3 篇论文
1 个项目
core_papers.md
project_overview.md
existing todos
annotations.md
wiki 页面
materials 文件
code 文件
图片
PDF
```

这也和 P35 对 sample workspace 的要求一致 [1]。

---

# 十二、最终建议

后续每个模块都应该遵循这个节奏：

```text
实现模块骨架
-> Smoke Test
-> 实现主路径
-> Happy Path Test
-> 实现错误/权限/恢复
-> Edge Test
-> 接入相邻模块
-> Integration Test
-> 任务书收尾
-> Regression Test
-> 写 Manual Test Report
```

这样你的测试体系会从“任务书结束时检查一下”升级为：

> **模块一旦基本可用，就立刻按照固定流程进入手动测试，并持续回归。**

这对于 Sci-Station 这种本地优先、文件系统落盘、AI workflow、权限审批、sidecar runtime 混合架构的产品尤其重要。