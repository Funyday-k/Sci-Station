# MT12：Home / Project Dashboard V2 手动测试

更新时间：2026-05-08

## 目标

验证 P42 的 Workspace Home 三段式聚合与 Project Dashboard V2：Today / Active Projects / AI Review、空状态、模块禁用回退、debug event 与 Project Overview 顶部 dashboard panel。

## 前置条件

- 已运行 `swift run SciStationCoreTestRunner`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 准备一个 Empty Workspace 与一个 Standard Workspace。
- 如需验证 AI Review，准备至少一个 AI Lab waiting-for-approval run 或 artifact draft run。
- 打开 Settings -> Developer 并启用 debug logging；P42 的 Home/Project Dashboard 事件也会强制写入 `.sci-station/debug/app_events.jsonl`。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT12-P42-01 | 打开 Home | 顶部显示 workspace name、module summary、workflow ready badge；Today / Active Projects / AI Review 三段聚合面板可见 |
| MT12-P42-02 | 全空 workspace | Today / Active Projects / AI Review 显示 Create Project / Add Paper / Create Todo / Open AI Lab onboarding；不 crash |
| MT12-P42-03 | 1 个 project + 0 个 paper + 1 个 todo | Today 中 todo 出现；Active Projects 列出该 project 且 stage = exploration；AI Review 空 |
| MT12-P42-04 | 当前 project 有 waiting-for-approval run | Today.Pending AI Drafts 与 AI Review.Needs Approval 显示该 draft；点击进入 Draft Inbox 或 AI Lab fallback |
| MT12-P42-05 | Artifact / critic report 含 stale evidence | AI Review.Stale Evidence 出现条目；点击进入 Draft Inbox 或 AI Lab fallback |
| MT12-P42-06 | Project Dashboard V2 | ProjectOverviewView 顶部出现 Dashboard Panel；StageBadge / core papers / open gaps / recent artifacts / next deadline 正确 |
| MT12-P42-07 | 大数据集（100+ todos / 50+ drafts） | Home snapshot 构建保持流畅；`home.aggregate.duration_ms` 目标小于 300ms |
| MT12-P42-08 | Aggregator 故意失败 | 面板显示 temporarily unavailable + Retry；写入 `home.aggregate.error` |
| MT12-P42-09 | 切换语言（zh / en） | 新增 Home / Project Dashboard 文案跟随 `appLanguage` 切换 |
| MT12-P42-10 | 关闭 `tasks` 模块 | Today 的 todo/deadline 卡片显示模块关闭引导；点击 Settings 可进入 Modules |

## Debug Event 检查

打开 `.sci-station/debug/app_events.jsonl`，确认至少出现：

```text
home.aggregate
home.cache.invalidate
home.panel.action
project_dashboard.render
project_dashboard.stage_inferred
```

payload 不应包含 todo title、paper title、draft 正文、绝对路径或 secret；只允许 id、count、duration、stage、rule 等脱敏字段。

## P42 Partial Regression

```text
MT12-P42-01
MT12-P42-02
MT12-P42-03
MT12-P42-06
MT12-P42-10
MT99-01 或 MT99-02
MT99-07
MT99-10
MT99-11
MT99-14
```

## 阻塞判定

```text
S0: Home / Project Dashboard 打开即 crash；debug payload 泄漏正文或 secret；模块禁用导致数据被删除。
S1: Home 三段面板不可见；Project Overview 顶部无 Dashboard Panel；Settings -> Modules 后导航 fallback 崩溃。
```