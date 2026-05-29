# 任务书 AT：AI Usage Testing 框架 (Sci-Station)

更新时间：2026-05-26
状态：P-AT.1a/b/c/d/e + P-AT.2 + P-AT.3a/b + P-AT.3d smoke skeleton 已落地；live smoke 当前 3/5 通过，2/5 受 SciStationUIProbe Accessibility 权限阻塞，后续再继续。
优先级：S2 / Roadmap Stage 3 横切基础设施
承接：P48 `ResearchQueueStore`、P49 Recommendation、P50 Reading Plan 以及当前整体打磨阶段；该任务给现有核心模块提供统一回归基线。

---

## 1. 动机与目标

到当前整体打磨阶段，Sci-Station 已有：

```text
70+ 模块（Library / Queue / Home Widgets / Citation Graph / Recommendation / AI Lab …）
30+ 类调试事件（agent.* / queue.* / graph.* / home.widget.* …）
~20 份 MT (Manual Test) 文档（docs/development/manual-tests/...）
```

人工跑 MT 是当前回归唯一手段，但：

```text
1. MT 用例数 × 模块数已经超出单人维持能力。
2. 复杂回归（drag-snap-back / 跨 widget interaction / 多 panel coordination）
   靠肉眼比对，肉眼会漏。
3. 手工测试无法覆盖 SwiftUI runtime warning、accessibility 树漂移、跨语言切换。
4. 我们已经具备非常规整的事件流 + yaml 落盘约定（P44–P49 系统性产物），
   理论上可以让 AI 自动跑 MT、自动比对、自动出报告。
```

任务书 AT 的目标：

```text
不替换 docs/development/MT-*.md 用例文档；
为每个 MT 配一个 scenarios/MT-xx-YY.yaml（机器可读副本）；
让 AI 用 Accessibility API + XCUITest 双驱执行；
跑完通过 3 条独立通道断言：
  1. 事件流（app_events.jsonl）
  2. 文件落盘（research-root yaml/jsonl/md）
  3. 视觉（截图 baseline diff / 多模态 LLM / SwiftUI warning）
任一通道失败即生成 markdown report + 自动开 issue。
```

---

## 2. 总体架构

```text
                                ┌──────────────────────────────────────┐
                                │  Sci-Station App (Debug build)        │
                                │  - emits AppDebugEvent → app_events.jsonl
                                │  - persists yaml/jsonl into research-root
                                │  - exposes accessibility tree (uitest.* AXIDs)
                                │  - serves Test Bridge socket (debug only)
                                └──────────────────────────────────────┘
                                              ▲                    ▲
                                              │ a11y / XCUITest    │ socket
                                              │                    │
┌──────────────────────────────┐   ┌────────────────────────────────────┐
│ scenarios/MT-xx-YY.yaml      │──►│  AgentRuntime/sci_station_agent/   │
│ (manual-test machine copy)   │   │  uitest/  (Python orchestrator)    │
└──────────────────────────────┘   │   - Scenario / Step / Assertion    │
                                   │   - EventLogProbe                  │
                                   │   - FileProbe                      │
                                   │   - (P-AT.4) VisualProbe           │
                                   │   - drivers/                       │
                                   │       - NullDriver  (unit tests)   │
                                   │       - AccessibilityDriver (P-AT.3)│
                                   │       - XCUITestDriver      (P-AT.3)│
                                   └────────────────────────────────────┘
                                                  │
                                                  ▼
                                   ┌────────────────────────────────────┐
                                   │ docs/development/manual-tests/runs/MT-xx-YY/...md│
                                   │ (markdown report; one per run)     │
                                   └────────────────────────────────────┘
```

---

## 3. 三条断言通道

### 3.1 事件通道 `event`

读取 `<researchRoot>/.sci-station/debug/app_events.jsonl`。
每条记录形如：

```json
{
  "event": "queue.append",
  "workspaceID": "ws-xxx",
  "projectID": "proj-yyy",
  "payload": {"source": "library.import", "paperID": "p1"}
}
```

合法事件名由 `Sci-Station/Agent/AppDebugEventName.swift` 集中登记。
SciStationCore test runner 强制：

```text
appDebugEventNameRegistryCoversAllEmittedEvents()
appDebugEventNameRegistryFollowsNamingConvention()
```

新增 `recordAppDebugEvent("...")` 必须同时：

```text
1. 在 AppDebugEventName 加一个 case；
2. 在 main.swift 的 emittedEventAllowList 追加 raw value。
```

### 3.2 文件通道 `file`

读取 research-root 下的 yaml / jsonl / json / md 持久化产物：

```text
research-root/queue/queue.yaml          (P48)
research-root/.sci-station/debug/...    (debug)
research-root/projects/<id>/...         (project-scoped artifacts)
research-root/library/<id>/meta.yaml    (P34)
```

`FileProbe.matches(path, loader=..., expected_subset=...)` 做递归子集匹配，
列表是无序、支持重复的子集匹配（见 `_subset_match`）。

### 3.3 视觉通道 `visual`（P-AT.4 延后）

```text
- 截图保存到 runs/<MT>/screenshots/<step>.png
- 与 baselines/<MT>/<step>.png 做像素 diff（默认）
- 启用 LLM 模式时，把 baseline + actual 一起喂给 vision model 出语义 diff
```

骨架阶段 visual assertion 直接返回 fail，但不阻塞 event/file 通道。

#### 3.3.1 SwiftUI runtime warning 流（P-AT.1d 已落地）

SwiftUI 的 "purple banner" runtime warnings 走 `os_log_fault` 到子系统
`com.apple.runtime-issues`，stderr 抓不到。
`Sci-Station/Testing/SwiftUIRuntimeWarningCapture.swift` 在 DEBUG 启动
时挂载 `OSLogStore` 轮询，把这些条目写到：

```text
<researchRoot>/.sci-station/debug/swiftui_warnings.log
```

格式（一行一条）：

```text
<ISO8601>\t<subsystem>\t<category>\t<process>\t<message>
```

scenarios 用普通 `file` 通道断言，无需独立通道：

```yaml
- channel: file
  description: No SwiftUI runtime warnings during the scenario.
  args:
    path: .sci-station/debug/swiftui_warnings.log
    loader: text
    expected_equals: ""
```

Python 侧解析器在 `sci_station_agent.uitest.files.parse_swiftui_warnings_log`。
非 DEBUG build 不创建该文件，scenario 在 release 上跳过这条断言；
P-AT.6 会加 `--profile=debug` flag 来强制要求 debug build。

---

## 4. Accessibility 标签命名

### 4.1 命名空间

`Sci-Station/Testing/UITestAccessibilityID.swift` 暴露强类型 namespace：

```swift
UITestAccessibilityID.Sidebar.tab(WorkspaceRoute.Top.library.rawValue)
// → "sidebar.tab.library"
UITestAccessibilityID.Home.widget("today")
// → "home.widget.today"
UITestAccessibilityID.Library.paper("arxiv-2604.22012")
// → "library.paper.arxiv-2604.22012"
UITestAccessibilityID.Queue.row("queue:workspace:p1")
// → "queue.row.queue:workspace:p1"     (terminal segment允许 :)
```

`UITestAccessibilityID.isValidIdentifier(_:)` 在 DEBUG 校验。

### 4.2 当前覆盖（P-AT.1c 已落地）

```text
Sidebar (TopSidebarView.swift)
  - sidebar.tab.<top>                每个一级路由按钮
  - sidebar.project_tree.toggle      项目树折叠按钮
  - sidebar.project.create           "+" 新建项目按钮
Home Widgets (HomeWidgetDashboardView.swift)
  - home.widget.<id>                 ForEach(visibleItems) 每个卡片
Queue (QueueTabView.swift)
  - queue.list                       LazyVStack 容器
  - queue.row.<entryID>              ForEach(filteredEntries) 每行
Library (LibraryViews.swift)
  - library.list                     Table 容器
  - library.paper.<id>               Table cell valueView
```

### 4.3 后续要补的模块（P-AT.3 时再加）

```text
- Settings 面板（Module Settings 等）
- AI Lab 工具栏 / Permissions inspector
- PDF Reader annotation 列表
- Wiki 页面树
```

---

## 5. Scenario 文件格式

### 5.1 顶级字段

```yaml
id: MT02-01                # 必需；与 docs/development/manual-tests 文件名对齐
title: "Import a PDF ..."  # 必需；进 markdown 报告标题
tags: [P02, library, ...]  # 选；ai_test.sh tag:p49-core 用来挑场景
setup:                     # 选；preflight 配置
  research_root_required: true
  preconditions: [...]
steps: [...]               # 必需，至少 1 项
assertions: [...]          # 必需，至少 1 项
```

### 5.2 步骤 `step.kind`（MVP）

```text
click           target=<axid>
type            target=<axid>, value=<str>
drag            target=<axid>, to=<axid>
wait_for_event  event=<str>, timeout_seconds=<float>
sleep           seconds=<float>
test_bridge     command=<str>, args=<dict>          (P-AT.1e)
```

新增 step.kind 必须同时改 `runner.py::_execute_step` + 文档。

### 5.3 断言 `assertion.channel`

```text
event   args.event / args.payload_contains / args.workspace_id ...
file    args.path / args.loader / args.expected_subset / args.expected_equals
visual  args.baseline / args.diff_mode / args.tolerance        (P-AT.4)
```

`expect_pass: false` 用于"必须失败"的反向断言（极少用）。

### 5.4 第一份 scenario

`AgentRuntime/sci_station_agent/uitest/scenarios/MT02-01_import_pdf.yaml`
覆盖 Library import → Queue append 链路，断言事件 + queue.yaml 落盘 + 视觉。

---

## 6. 阶段拆分

### P-AT.1 基础打底（已落地）

```text
[done] 1a 扩充 AppDebugEventName 枚举至覆盖所有 emit 点
[done] 1b 加 SciStationCore test：emit 事件 ⊆ 注册事件、命名规范
[done] 1c 4 个高频模块加 accessibilityIdentifier
[done] 1d SwiftUIRuntimeWarningCapture (OSLogStore 轮询 → swiftui_warnings.log)
            workspace 打开时挂载，Debug-only，2s 轮询；line 格式由
            SciStationCore lint 锁住，Python 侧由 parse_swiftui_warnings_log
            读取。MT02-01 首个 scenario 已加 "log 必须为空" 断言。
[done] 1e Test Bridge：Debug-only Unix socket，命令白名单 < 20 条
            已支持 ping / workspace.open / route.select /
            library.import.attachFixturePDF / queue.append。
```

P-AT.1e 已落地；MT02-01 通过 bridge 注入 fixture PDF，不再弹文件选择器。

### P-AT.2 Python 编排器骨架（已落地）

```text
[done] 2a sci_station_agent/uitest/  (scenario / events / files / runner / report)
[done] 2b 第一份 scenario MT02-01 + pytest 覆盖：22 cases 全绿
```

### P-AT.3 实驱动

```text
[done] 3a AccessibilityDriver  基于 macOS Accessibility API（AXUIElement）
   定位用 AXIdentifier == uitestID。架构：
     Tools/SciStationUIProbe/main.swift  -- JSON-over-stdio CLI 包 AXUIElement
     AgentRuntime/.../drivers/accessibility.py -- subprocess 客户端，
       提供 click / type_text / find / tree / launch / terminate / drag
     send_test_bridge 通过 UnixSocketTestBridgeClient 转发到 App 内 Test Bridge
[done] 3b drag 支持      AXUIElement 不直接支持 drag；走 CGEventCreateMouseEvent
   合成 mouseDown / mouseDragged / mouseUp。home widget reorder 等
   scenario 已可表达。
[todo] 3c XCUITestDriver  新增 SciStationUITests target；Python 把 YAML
   编译为 JSON 注入 XCUITest，跑完 dump 结果。用于 SwiftUI 内部状态
   读取（@State 值、@FocusState、菜单层级）等 AX 抓不到的情况。
[partial] 3d smoke 套件      5 条 scenarios（import / queue reorder /
   home widget drag / wiki rename / agent prompt）已存在并可由 CLI 执行。
   当前 live signed Debug app 验证：MT03-01_wiki_rename、MT07-03_agent_prompt_draft、
   MT19-P48-06_queue_reorder 通过；MT02-01_import_pdf 与 MT18-P43.9-03_home_widget_drag
   受 SciStationUIProbe Accessibility trust 阻塞，不判定为产品代码回归。
```

P-AT.3a 设计要点：

```text
- 不在 Python 里调 AX API：pyobjc 可以，但 CFTypeRef 处理脆弱，
  且 Accessibility 权限是 per-binary，Python 解释器升级就要重新授权。
  Swift CLI 是稳定签名目标，授权一次长期生效。
- 无状态查找：每次 click/type 都重走 AX 树，不缓存元素 ref。简单 + 鲁棒；
  代价是大型场景慢一点，可在 3b 时按需加缓存。
- 三种 transport 注入：SubprocessTransport（真），PipeTransport（管道
  注入，灰盒），StubTransport（脚本响应，单元测试）。同一 Driver 类
  在三种环境下复用。
- 端到端 smoke：tests/uitest/test_accessibility_driver.py 里有一条
  optional pytest，在 .build/debug/SciStationUIProbe 存在时实际跑
  cmd: ping / cmd: permission 验证 wire protocol。
```

### P-AT.4 视觉通道

```text
4a baseline diff         默认 mode；像素差 > 阈值即 fail
4b LLM vision diff       手动开；把 baseline + actual 喂给 vision model
   (P-AT.1d 已落地 SwiftUI warning capture，走 file 通道而非 visual)
```

### P-AT.5 MCP 工具集成

```text
5a MCP server 暴露：
   ai_test.run_scenario(id)
   ai_test.list_scenarios(tag=)
   ai_test.tail_events(window=)
   ai_test.screenshot(target=, region=)
5b 让 Cascade 直调 ai_test.* 验证它自己的代码改动
```

### P-AT.6 CI 脚本

```text
scripts/ai_test.sh
  smoke              跑 P-AT.3c 的 5 条
  mt99               单条 scenario
  tag:p49-core       按 tag 过滤
  ci                 全量 + 输出 markdown 报告 + JUnit XML
```

---

## 7. 已交付的代码改动

```text
Sci-Station/Agent/AppDebugEventName.swift               (扩充至 ~80 cases + lint helper)
Sci-Station/App/AppViewModel.swift                       (debug.mode.changed / debug.log.opened 改名;
                                                           workspace 打开时挂 SwiftUIRuntimeWarningCapture;
                                                           Debug Test Bridge command handler)
Sci-Station/App/UITestBridgeServer.swift                  (new, P-AT.1e; Debug-only Unix socket)
Sci-Station/Testing/UITestAccessibilityID.swift          (new)
Sci-Station/Testing/UITestAccessibilityIDViewModifier.swift (new)
Sci-Station/Testing/SwiftUIRuntimeWarningCapture.swift   (new, P-AT.1d)
Sci-Station/UI/Shell/TopSidebarView.swift                (a11y 标签)
Sci-Station/UI/Home/Widgets/HomeWidgetDashboardView.swift (a11y 标签)
Sci-Station/UI/Queue/QueueTabView.swift                  (a11y 标签)
Sci-Station/UI/LibraryViews.swift                        (a11y 标签)
Tools/SciStationCoreTestRunner/main.swift                (+4 lint test)
Tools/SciStationUIProbe/main.swift                       (new, P-AT.3a/b; JSON-over-stdio AX bridge + CGEvent drag)
Package.swift                                            (+ Testing/ source; + SciStationUIProbe target)
AgentRuntime/sci_station_agent/uitest/                   (new module + parse_swiftui_warnings_log)
AgentRuntime/sci_station_agent/uitest/test_bridge.py      (new, P-AT.1e Python Unix socket client)
AgentRuntime/sci_station_agent/uitest/drivers/accessibility.py (new, P-AT.3a/b)
AgentRuntime/sci_station_agent/uitest/cli.py                  (P-AT.3d live smoke CLI；sandbox-safe bridge socket + research root)
AgentRuntime/sci_station_agent/uitest/scenarios/*.yaml        (5 条 P-AT.3d smoke scenarios)
AgentRuntime/tests/uitest/                               (7 个测试文件，新增 Test Bridge client coverage)
AgentRuntime/pyproject.toml                              (+ uitest extras: pyyaml)
docs/development/Proposal-AT.md                                       (本文)
```

### 7.1 验证命令

```bash
# Swift 单元 + 注册表 lint：
swift run --quiet SciStationCoreTestRunner

# 构建 AX 探针（P-AT.3a 必备）：
swift build --product SciStationUIProbe

# 完整 Xcode build（确保 a11y 改动不破)：
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station \
  -configuration Debug -destination 'platform=macOS' build

# Python 编排器：
.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q
```

四者全绿即视为 P-AT.1abcde + P-AT.2 + P-AT.3a/b 单元与构建通过。P-AT.3d live smoke 需要额外确保 SciStationUIProbe 具备 macOS Accessibility trust。

---

## 8. 不在范围（防止 scope creep）

```text
- 录制式测试（XCUI Recorder 风格）：明确不做，scenarios 必须人写
- 取代 docs/development/MT-*.md：MT 文档仍是 source of truth，scenarios 是机器副本
- 自动修 bug：发现失败只开 issue，不让 AI 自动 commit fix
- 跨平台：只跑 macOS；iPad / iPhone 不在 P-AT 阶段
```

---

## 9. 风险与对策

```text
A11y 标签随 UI 改名漂移
  → UITestAccessibilityID 强类型 + DEBUG isValidIdentifier 校验
  → 任何 scenario 引用未知 axid，driver 直接 fail-loud（详细错误指 axid）

事件命名漂移
  → AppDebugEventName.allCases 是唯一 truth；test runner 强制 emit ⊆ allCases

scenarios 与 docs/development/MT 文档失同步
  → P-AT.6 时加 lint：每个 docs/development/MT-xx-YY.md 必须有对应 scenarios/MT-xx-YY.yaml；
     反之不强求（scenario 可以更细）

Test Bridge 安全
  → Debug build only（#if DEBUG 编译）
  → 默认只在显式传入 --uitest-bridge 或 SCI_STATION_TEST_BRIDGE_SOCKET 时启动
  → Unix-domain socket；默认路径在 App Sandbox container 的 Data/tmp 下，可用 --uitest-bridge-socket 覆盖
  → 自动 research_root 默认在 App Sandbox container 的 Data/Documents 下，避免 /tmp 权限问题
  → 命令白名单；任何不在表里的字符串直接拒收
```

---

## 10. 后续启动建议

当前建议把 AT 作为整体打磨阶段的回归辅助；下一轮测试工作再继续 P-AT.3d 权限收口与 P-AT.6 脚本化。

```text
- P-AT.3b drag 已落地。
- P-AT.3d 5 条 smoke scenarios 已能加载并部分 live 通过。
- 余下主要是 macOS Accessibility trust / lsregister / instance reuse 等环境问题，不应继续阻塞功能与 UI 主线。
```
