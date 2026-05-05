# MT11：Graph / Recommendation 手动测试

更新时间：2026-05-05

## 目标

为后续 Research Graph、Citation Graph、Research Queue、Recommendation Engine 和 Reading Plan 预留手动测试框架。P36 不执行本文件，P44-P50 开始逐步启用。

## 适用触发点

- P44 Research Graph Data Model V1 后执行数据模型与索引相关用例。
- P45 Citation Graph V1 后执行 citation neighborhood 用例。
- P46 Graph UI V1 后执行图谱交互用例。
- P48-P50 Research Queue / Recommendation / Reading Plan 后执行推荐用例。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT11-01 | Paper node index | Library paper 生成 graph node |
| MT11-02 | Project node index | Project 生成 graph node |
| MT11-03 | Citation edge parse | 本地 citation edge 可见 |
| MT11-04 | Missing reference warning | 找不到本地论文时显示 external placeholder |
| MT11-05 | Paper neighborhood | 单篇论文 cites / cited by 可浏览 |
| MT11-06 | Project citation graph | 核心论文关系可过滤 |
| MT11-07 | Node detail inspector | 节点详情与源文件一致 |
| MT11-08 | Node action: Add to project | 操作经审批或明确写入路径 |
| MT11-09 | Generate reading order | 输出可解释 reading path |
| MT11-10 | Research Queue item | 推荐项有 status 和 reason |
| MT11-11 | Recommendation explanation | 推荐理由可追溯到 evidence / graph / keyword |
| MT11-12 | Feedback loop | dismiss/not relevant/already known 被记录 |
| MT11-13 | Add to Library / Add to Project | 不自动导入，用户确认后写入 |
| MT11-14 | Weekly reading plan | 计划能转 todo/calendar preview |

## 隐私边界

```text
不默认上传用户论文全文
不做无限信息流
不自动导入论文
推荐理由必须可解释
所有写入仍走 Permission Dock 或明确用户操作
```

## 阻塞问题

```text
S0: 推荐/图谱流程泄漏用户全文或 secret；自动写入 workspace
S1: graph index 破坏 Library/Project 主路径；推荐项无理由且无法追踪来源
```
