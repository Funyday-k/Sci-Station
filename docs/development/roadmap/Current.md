# 当前版本路线图

## 当前版本

- Version：`0.1.1`
- Branch：`release/0.1.1`
- 类型：Patch beta
- 目标：在 `0.1.0` 基础上完成文档重构、版本管理、发布流程和 0.1.x 稳定化入口。

## 0.1.1 范围

### 必做

- 重建 `docs/development/` 信息架构。
- 建立版本号、分支、tag、build number 和发布记录规则。
- 建立 AI 可执行 Proposal 模板。
- 建立 changelog 和 release record 模板。
- 建立 `0.1.1` Proposal 和 release record。
- 更新根 README / developer docs / AgentRuntime README 的旧路径引用。

### 可选

- 递增 Xcode `MARKETING_VERSION` 到 `0.1.1`。
- 递增 `CURRENT_PROJECT_VERSION`。
- 添加 About/diagnostics 中更清晰的 beta 通道显示。

### 不做

- 不引入大功能。
- 不改变用户数据 schema。
- 不重构 AppViewModel 或 UI 架构。
- 不更改 AI provider 行为。

## 完成定义

- 文档目录可从 `docs/development/README.md` 导航。
- 旧 Proposal 任务书不再作为开发入口。
- `CHANGELOG.md` 有 `0.1.1` 草稿。
- `releases/0.1.1.md` 有发布清单。
- `proposals/Proposal-0.1.1.md` 可直接交给 AI 执行。
