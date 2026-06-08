# Sci-Station 开发文档中心

本目录是 Sci-Station 的开发、测试、版本和发布文档入口。旧的线性 Proposal 任务书已移除，后续开发改为“版本目标 + 模块文档 + 可执行 Proposal + 发布记录”的结构。

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

## 新开发流程

1. 在 `roadmap/Current.md` 确认当前版本目标。
2. 用 `templates/ProposalTemplate.md` 创建 `proposals/Proposal-<version>.md`。
3. AI 或开发者按 Proposal 执行任务，并在 Proposal 内记录完成状态。
4. 实现完成后，用 `templates/ImplementationSummaryTemplate.md` 写总结。
5. 按 `testing/ReleaseRegression.md` 和对应模块测试完成验证。
6. 更新 `CHANGELOG.md` 和 `releases/<version>.md`。
7. 按 `versioning/ReleaseProcess.md` 打 tag、归档构建包。

## 当前版本

- 当前基线：`0.1.0` beta
- 当前分支：`release/0.1.1`
- 当前工作：`proposals/Proposal-0.1.1.md`
- 发布记录：`releases/0.1.1.md`

## 维护原则

- 一个版本只维护一个主 Proposal。
- 已完成任务不再堆积在根目录，最终沉淀到模块文档、release record 和 changelog。
- 所有用户可见变化都必须进入 `CHANGELOG.md`。
- 所有数据格式变化都必须记录 schema、兼容策略和回滚策略。
- 所有 AI 执行任务都必须能从 Proposal 追溯到实现总结和测试结果。
