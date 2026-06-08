# Sci-Station 开发文档中心

本目录是 Sci-Station 的开发、测试、版本和发布文档入口，主要由 AI 阅读和维护。旧的线性 Proposal 任务书已移除，后续开发改为“用户反馈 intake + 版本目标 + 模块文档 + 可执行 Proposal + 发布记录”的结构。

## 文档结构

```text
docs/development/
├── architecture/     架构边界、数据模型、运行时说明
├── modules/          按产品/技术模块维护的开发说明
├── process/          日常开发流程、AI 执行流程、文档维护规则
├── proposals/        当前和未来版本的可执行开发 Proposal
├── releases/         每个版本的发布记录、验证结果、已知问题
├── roadmap/          当前方向和后续 backlog
├── templates/        Proposal、总结、Changelog、发布清单模板
├── testing/          自动化、手动回归、UI smoke 和发布门禁
└── versioning/       版本号、分支、tag、打包和发布规则
```

用户原始需求、问题和新功能想法放在 `../user-feedback/`。其中 `inbox/`、`drafts/` 和 `archive-local/` 是本地 gitignored 区域；AI 读取后再转换为本目录中的正式开发文档。

## 新开发流程

1. 用户在 `../user-feedback/inbox/` 写原始需求、Bug、问题或新功能想法。
2. AI 按 `process/UserFeedbackIntake.md` 将原始反馈转换为 roadmap、Proposal、module docs 或 testing docs。
3. 在 `roadmap/Current.md` 确认当前版本目标。
4. 用 `templates/ProposalTemplate.md` 创建或更新 `proposals/Proposal-<version>.md`。
5. AI 或开发者按 Proposal 执行任务，并在 Proposal 内记录完成状态。
6. 实现完成后，用 `templates/ImplementationSummaryTemplate.md` 写总结。
7. 按 `testing/ReleaseRegression.md` 和对应模块测试完成验证。
8. 更新 `CHANGELOG.md` 和 `releases/<version>.md`。
9. 按 `versioning/ReleaseProcess.md` 打 tag、归档构建包。

## 当前版本

- 当前基线：`0.1.0` beta
- 当前分支：`release/0.2.0`
- 当前工作：`proposals/Proposal-0.2.0.md`
- 发布记录：`releases/0.2.0.md`

## 维护原则

- 一个版本只维护一个主 Proposal。
- 用户原始反馈不直接成为长期开发文档，必须由 AI intake 后沉淀到正式目录。
- 已完成任务不再堆积在根目录，最终沉淀到模块文档、release record 和 changelog。
- 所有用户可见变化都必须进入 `CHANGELOG.md`。
- 所有数据格式变化都必须记录 schema、兼容策略和回滚策略。
- 所有 AI 执行任务都必须能从 Proposal 追溯到实现总结和测试结果。
