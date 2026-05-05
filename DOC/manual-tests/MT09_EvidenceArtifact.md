# MT09：Evidence / Artifact / Citation Critic 手动测试

更新时间：2026-05-05

## 目标

验证 evidenceRefs、source jump、stale/missing warning、critic 阻断、low confidence draft 和 artifact metadata 保存。

## 适用触发点

- P36 必须执行 MT09。
- 修改 evidence UI、artifact preview、citation critic、source jump、PDF page mapping 时执行。

## 前置条件

- Standard Workspace 至少包含 1 篇有 `paper.md` 和 `annotations.md` 的论文。
- Broken Workspace 至少包含 stale source 或 missing source 场景。
- 如需 PDF page jump，测试 fixture 应包含 page mapping 元数据。

## 测试用例

| ID | 标题 | 期望 |
|---|---|---|
| MT09-01 | 生成 paper reading artifact | artifact draft 包含 evidenceRefs 与 critic report |
| MT09-02 | 展开 evidenceRefs | 显示 source、line range、confidence、source_hash 状态 |
| MT09-03 | 点击 evidence 跳转 paper.md line range | 定位到对应行或显示 fallback reason |
| MT09-04 | 点击 evidence 跳转 annotations.md line range | 定位到对应行或显示 fallback reason |
| MT09-05 | 点击 evidence 跳转 wiki line range | 定位到对应 wiki 行 |
| MT09-06 | 有 PDF page mapping 时跳转 PDF 页 | 打开 PDF Reader 并定位页码 |
| MT09-07 | 修改 source_hash 后显示 stale evidence | artifact preview 与 saved citation block 都显示 stale |
| MT09-08 | 删除 source 后显示 missing source | 不崩溃，显示 missing source warning |
| MT09-09 | unsupported claim 被 critic 阻断 | 不能直接 final approval |
| MT09-10 | 用户选择保存为 low confidence draft | UI 明确 warning，保存 metadata |
| MT09-11 | 保存后 Wiki citation block 保留 metadata | run_id、evidenceRefs、confidence/source 状态可追踪 |

## P36 重点

```text
line range target descriptor
PDF page fallback
stale/missing warning consistency
low confidence save path does not hide critic warning
evidence metadata survives writeback
```

## 允许跳过

```text
MT09-06: 测试 fixture 缺少 page mapping 元数据时可 skipped，必须记录 fixture 缺口。
```

## 阻塞问题

```text
S0: unsupported claim 可无提示写入 final；source jump 导致崩溃；保存时丢失用户文件
S1: evidenceRefs 不显示；Markdown/annotations line target 全部失败；critic 阻断失效
```
