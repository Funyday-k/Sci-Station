# Queue、Recommendation 与 Reading Plan

## 范围

负责 Research Queue、论文推荐、阅读计划，以及从推荐到队列再到阅读计划的闭环。

## 关键代码入口

- `Sci-Station/Queue/`
- `Sci-Station/Recommendation/`
- `Sci-Station/ReadingPlan/`
- `Sci-Station/UI/Queue/`
- `Sci-Station/UI/Recommendation/`
- `Sci-Station/UI/ReadingPlan/`
- `Sci-Station/UI/Home/`

## 数据路径

- `library/queue.yaml`
- `projects/*/queue.yaml`
- `.sci-station/queue/ingest_cursor.json`
- `.sci-station/recommendations/config.yaml`
- `.sci-station/recommendations/history.jsonl`
- `.sci-station/recommendations/notes/*.json`
- `.sci-station/recommendations/feedback.jsonl`
- `.sci-station/reading-plans/workspace.yaml`
- `projects/*/reading-plans/plans.yaml`

## 不变量

- Queue YAML 应能容忍局部坏 entry，不应导致整个 tab 崩溃。
- Recommendation 排序应可解释；AI review 不应成为唯一排序依据。
- Recommendation candidate 持久化必须避免 raw full text 泄漏。
- Reading Plan slot 状态变化应与 Queue 状态同步。
- Home / Project Dashboard 只消费轻量 summary，避免引入高频刷新。

## 0.1.x 重点

`0.1.x` 阶段优先做稳定性和闭环 polish：

- 推荐结果一键加入 Queue。
- Queue 中 active item 可生成 Reading Plan。
- Reading Plan 完成状态能回写 Queue。
- 所有路径均有空态、错误态和重启恢复。

## 发布前检查

- Queue add/remove/reorder/status change 重启后保留。
- Recommendation 无 API key 时给明确降级，不影响本地功能。
- Reading Plan generate/activate/archive/status change 可用。
- 相关 debug event 不包含论文正文、wiki 正文、secret 或绝对路径。
