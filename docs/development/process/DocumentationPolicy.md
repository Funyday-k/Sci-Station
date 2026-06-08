# 文档维护规则

## 文档分层

- 用户文档：`docs/README*.md`、`docs/TUTORIAL*.md`。
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

## 更新时机

- 新功能完成：更新模块文档、changelog、release record。
- 新数据路径：更新 `architecture/WorkspaceData.md` 和对应模块文档。
- 新测试方式：更新 `testing/`。
- 新版本流程：更新 `versioning/`。

## 禁止事项

- 不在文档中保存 API key、token、私人文件路径或用户论文内容。
- 不把临时对话总结当作永久规范，除非已整理到模块文档。
- 不让 Proposal 长期承担架构文档职责。
