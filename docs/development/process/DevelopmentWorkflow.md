# 日常开发流程

## 标准流程

1. 确认当前版本目标：`roadmap/Current.md`。
2. 创建或更新对应 Proposal：`proposals/Proposal-<version>.md`。
3. 明确改动范围、数据路径、测试门禁和 release 影响。
4. 实现代码和文档。
5. 运行自动化验证。
6. 更新模块文档、changelog 和 release record。
7. 合并前检查 Git diff，确认没有 secret、构建产物或私人 Research Root。

## 分支命名

- `release/<version>`：版本稳定和发布分支。
- `feature/<slug>`：用户可见功能。
- `fix/<slug>`：bug 修复。
- `docs/<slug>`：纯文档调整。
- `chore/<slug>`：构建、脚本、整理。

## 变更分类

- Feature：用户可见新增能力。
- Fix：bug 或回归修复。
- Performance：性能和响应性。
- Docs：文档。
- Test：测试和验证。
- Chore：构建、配置、整理。

## 提交前检查

- 是否更新了对应模块文档。
- 是否更新了 `CHANGELOG.md`。
- 是否需要更新 `releases/<version>.md`。
- 是否影响 workspace schema 或 feature schema。
- 是否需要补测试或手动测试记录。
