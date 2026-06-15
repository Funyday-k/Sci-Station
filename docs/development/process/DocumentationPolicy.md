# 文档维护规则

## 文档分层

- 用户文档：`docs/README*.md`、`docs/TUTORIAL*.md`。
- 用户反馈入口：`docs/user-feedback/`，其中原始 inbox/drafts/archive-local 被 Git 忽略。
- 开发入口：`docs/DEVELOPER.md`、`docs/development/README.md`。
- 模块文档：`docs/development/modules/`。
- 版本与发布：`docs/development/versioning/`、`docs/development/releases/`。
- Proposal：`docs/development/proposals/`。
- 测试：`docs/development/testing/`。
- 模板：`docs/development/templates/`。

## 旧任务书策略

旧的线性 Proposal 任务书不再作为长期知识库。已完成任务的长期信息应迁移到：

- 模块文档。
- Release record。
- Changelog。
- 测试策略。

## 新文档要求

新增文档必须说明：

- 适用范围。
- 维护者或触发更新场景。
- 相关代码入口。
- 与版本、测试或发布的关系。

## 内容生命周期

希望落地的内容必须沿固定路径沉淀，避免愿望、计划和事实混在一起：

```text
user-feedback/inbox -> roadmap/Backlog.md -> Proposal -> implementation summary -> changelog/release record
```

- `Backlog.md` 只放未进入当前版本的机会点和后续方向。
- `roadmap/Current.md` 只放当前版本目标和完成定义。
- `proposals/` 放可执行计划，可以有未勾选任务，但必须写清非目标、验证和收尾条件。
- `modules/` 放长期不变量、代码入口和发布前检查，不放一次性的任务流水账。
- `releases/` 和 `CHANGELOG.md` 只写已完成或明确 known issue 的事实。
- 代码中的 `TODO`、`placeholder`、`stub` 必须链接到 Proposal、Backlog 条目或明确的兼容原因；没有归属的留白应删除或迁移到文档。

## 更新时机

- 新功能完成：更新模块文档、changelog、release record。
- 新数据路径：更新 `architecture/WorkspaceData.md` 和对应模块文档。
- 新测试方式：更新 `testing/`。
- 新版本流程：更新 `versioning/`。

## 禁止事项

- 不在文档中保存 API key、token、私人文件路径或用户论文内容。
- 不提交 `docs/user-feedback/inbox/`、`drafts/` 或 `archive-local/` 中的原始反馈。
- 不把临时对话总结当作永久规范，除非已整理到模块文档。
- 不让 Proposal 长期承担架构文档职责。
