# Recommendation 与阅读

> **变更说明**：独立的 Research Queue 与 Reading Plan 模块已移除。阅读不再是单独的
> 队列/计划，而是统一收敛为 Tasks 中的待办（Todo）。本文件仅保留 Recommendation 模块说明。

## 范围

负责论文推荐，以及从推荐到论文库 / 阅读待办的链路。

## 关键代码入口

- `Sci-Station/Recommendation/`
- `Sci-Station/UI/Recommendation/`
- `Sci-Station/UI/Home/`

## 数据路径

- `.sci-station/recommendations/config.yaml`
- `.sci-station/recommendations/history.jsonl`
- `.sci-station/recommendations/notes/*.json`
- `.sci-station/recommendations/feedback.jsonl`

## 不变量

- Recommendation 排序应可解释；AI review 不应成为唯一排序依据。
- Recommendation candidate 持久化必须避免 raw full text 泄漏。
- 推荐可一键加入论文库或创建阅读待办（Tasks）。
- Home / Project Dashboard 只消费轻量 summary，避免引入高频刷新。

## 0.1.x 重点

`0.1.x` 阶段优先做稳定性和链路 polish：

- 推荐结果一键加入论文库。
- 推荐结果可创建阅读待办（Tasks）。
- 所有路径均有空态、错误态和重启恢复。

## 发布前检查

- Recommendation 无 API key 时给明确降级，不影响本地功能。
- 推荐反馈（like/dislike/save/open_pdf/ignore）持久化并影响排序。
- 相关 debug event 不包含论文正文、wiki 正文、secret 或绝对路径。
