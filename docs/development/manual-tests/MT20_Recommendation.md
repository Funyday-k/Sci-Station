# MT20：Recommendation Engine V1 手动测试

更新时间：2026-05-17
状态：Core Layer 已自动化覆盖；App UI / Scheduler / live external retrieval 待 Layer B/C 后执行完整手测。

## 目标

验证 P49 Recommendation Engine V1 在 Sci-Station 中保持 local-first、可解释、可审批，并能吸收 daily feed 新论文候选而不绕过 Research Queue 审批闭环。

## 前置条件

- 已运行 `swift run --quiet SciStationCoreTestRunner`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 使用包含 Paper Library、Citation Graph、AI Lab、Research Queue 的测试 workspace。
- recommendation 模块默认关闭；测试时通过 Settings → Modules 显式启用。

## Core Layer 自动化确认

| ID | 标题 | 自动化覆盖 |
|---|---|---|
| MT20-P49C-01 | Config YAML round-trip | `recommendationConfigYAMLRoundTripsDailySourceSettings` |
| MT20-P49C-02 | Daily feed JSONL import | `dailyFeedCandidateImporterMapsExternalArxivCandidates` |
| MT20-P49C-03 | Daily feed 与 Queue tail dedup | `recommendationCandidateGathererDedupsDailyFeedAndQueueTail` |
| MT20-P49C-04 | Local-interest ranking + queue suppression | `recommendationScorerRanksByLibraryInterestAndSuppressesFinished` |
| MT20-P49C-05 | Snapshot / history / P48 payload | `recommendationPipelineWritesSnapshotAndQueuePayload` |

## Layer B/C 手动测试（待 UI / Scheduler / live retriever 落地后执行）

| ID | 标题 | 期望 |
|---|---|---|
| MT20-P49-01 | 启用 recommendation 模块 | `/recommendations` route 与 Home Recommendations panel 出现；禁用后隐藏 |
| MT20-P49-02 | Refresh recommendations | 生成 snapshot + `recommendation_note`；列表展示 top-K + reason |
| MT20-P49-03 | Approve recommendation note | P48 Research Queue 追加 entry，`source = recommendation` |
| MT20-P49-04 | Feature breakdown | 展示 6 个 feature，值与 snapshot 一致且均在 0..1 |
| MT20-P49-05 | Daily feed import | arXiv `2604.22012v1` 归一化为 `arxiv:2604.22012` 并进入候选池 |
| MT20-P49-06 | 30 分钟重复刷新 | 第二次同 candidate hash 跳过，不重复生成 draft |
| MT20-P49-07 | finished / dismissed suppression | 已完成或忽略论文被明显压制，不进入 top-K |
| MT20-P49-08 | scope 切换 | workspace / active project 候选不同；snapshot scope 正确 |
| MT20-P49-09 | 模块禁用 | route / panel / tool 隐藏或拒绝；既有 snapshot 不删除 |
| MT20-P49-10 | cadence = daily | App 前台第二天触发一次 scheduled run；后台不跑 daemon |
| MT20-P49-11 | external network opt-in | 未 opt-in 时 live retriever 不发起网络请求；opt-in 后只拉 metadata/abstract，不抓 PDF full text |

## 阻塞判定

```text
S0: 推荐流程上传 paper full text / user prompt / API key，或绕过 Draft Inbox 直接写 Queue。
S1: Recommendation route 打开崩溃；Approve 后 Queue entry 丢失；module disabled 后 route/panel/tool 仍可用；live retriever 未 opt-in 即发起网络请求。
```
