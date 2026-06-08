# AI 辅助开发流程

本文件定义如何让 AI 基于 Proposal 完成任务、总结任务、形成 changelog，并辅助打包新版本。

## 输入给 AI 的材料

每次任务开始时提供：

- 当前分支和目标版本。
- `proposals/Proposal-<version>.md`。
- 相关模块文档。
- 已知 blocker / known issues。
- 必须运行的验证命令。

## AI 执行规则

AI 必须：

1. 先阅读 Proposal 和相关模块文档。
2. 给出简短计划。
3. 实现前定位权威代码入口。
4. 小步修改，避免无关重构。
5. 更新 Proposal 任务状态。
6. 更新模块文档中的长期约束。
7. 更新 `CHANGELOG.md` 的 Unreleased 部分。
8. 更新 `releases/<version>.md` 的验证和变更记录。
9. 输出实现总结。

AI 不应：

- 删除用户数据或 Research Root。
- 修改无关功能。
- 把 secret、API key、私人路径写入文档或日志。
- 在未说明兼容策略时改变持久化格式。

## 任务完成总结格式

使用 `templates/ImplementationSummaryTemplate.md`，至少包含：

- 完成内容。
- 修改文件。
- 数据格式影响。
- 验证结果。
- 未完成项。
- Changelog 条目。
- 发布风险。

## 打包前 AI 检查

AI 可以辅助完成：

- 检查版本号和 build number。
- 汇总 commits 和 changelog。
- 核对 release checklist。
- 生成 release notes 草稿。
- 标记 known issues。

AI 不应自动执行签名、notarization、删除构建产物或发布上传，除非用户明确要求并确认命令。
