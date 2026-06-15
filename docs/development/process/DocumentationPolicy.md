# 文档维护规则

## 文档分层

- 用户文档：`docs/README*.md`、`docs/TUTORIAL*.md`。
- 本地反馈输入：`docs/user-feedback/`，其中原始 inbox/drafts/archive-local 被 Git 忽略，只能由流程文档引用，不作为公开文档入口。
- 开发入口：`docs/DEVELOPER.md`、`docs/development/README.md`。
- 模块文档：`docs/development/modules/`。
- 版本与发布：`docs/development/versioning/`、`docs/development/releases/`。
- Proposal：`docs/development/proposals/`。
- 测试：`docs/development/testing/`。
- 模板：`docs/development/templates/`。

## 文档状态

每份长期文档都应能归入一个状态：

- Active：当前事实或当前流程，允许被 README、developer docs 和模块文档引用。
- Planned：尚未实现的目标，只能放在 `roadmap/Backlog.md`、`roadmap/Current.md` 或 Proposal。
- Completed：已落地的版本记录，沉淀到 implementation summary、release record 和 changelog。
- Archived：历史执行记录，只保留追溯价值，不再作为架构或产品事实来源。
- Local-only：用户原始反馈、本地草稿、临时调查结果，不进入 release 文档。

公开用户文档只能引用 Active 和 Completed 内容。Planned 内容如果出现在 README，必须明确写成 roadmap，而不能写成已可用能力。

## 来源真相表

| 内容类型 | 唯一来源 | 不能放在 |
|---|---|---|
| 当前可用能力 | README、module docs、release record | Backlog |
| 当前版本目标 | `roadmap/Current.md`、当前 Proposal | README 功能列表 |
| 后续机会点 | `roadmap/Backlog.md` | release record |
| 可执行计划 | `proposals/Proposal-<version>.md` | module docs |
| 长期架构/模块边界 | `architecture/`、`modules/` | Proposal |
| 用户原始输入 | 本地 `docs/user-feedback/` | README、release record |
| 版本事实 | `releases/`、`CHANGELOG.md` | Backlog |

当两个文档冲突时，按上表选择更高优先级的来源，并把另一个文档改成引用或摘要。

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

## 术语规范

- 使用 `Todo` 表示应用内任务；中文统一写“待办”。
- 使用 `reading Todo` / “阅读 Todo”表示推荐或论文阅读后续动作；不再使用独立的 `ReadingPlan` 模块名。
- 使用 `Recommendation` 表示推荐工作流；不再恢复独立 `Queue` 产品概念，除非 Proposal 明确重新设计。
- 使用 `Graph` 表示论文/项目图谱数据和工作流。
- 使用 `Agent Runtime` 表示 Python sidecar 或外部 AI 执行层；使用 `AI Lab` 表示应用内用户界面。
- 使用 `Research Root` / “科研根目录”表示用户数据边界；不要写成本机源码仓库。
- 使用 `Proposal` 表示可执行计划；不要把一次性任务书长期当作模块说明。

## 留白管理

文档和代码都允许存在未完成内容，但必须可追踪：

- 用户可见文案不能出现 `placeholder`、`stub`、`not implemented` 或内部阶段号。
- 代码里的临时留白使用 `Pending:`、`Compatibility:` 或 `Unavailable:` 开头，并指向 Backlog、Proposal 或兼容理由。
- Proposal 中未完成任务必须保留验收条件；如果推迟到未来版本，应同步到 Backlog。
- 模块文档不得写“未来会做”但不指向 Backlog 或 Proposal。
- Release record 只能写已完成事实和已知问题，不能承诺未来功能。

## 文档卫生扫描

每次大规模文档整理后，至少运行：

```bash
python3 Tools/scripts/check-docs-hygiene.py
```

脚本中的 `ERROR` 必须修复。`WARN` 不一定是错误，例如历史 release、Proposal 章节标题和明确的退役说明可以保留；但每个命中都应归类为 Active、Planned、Completed、Archived 或 Local-only。

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
- 不在 README 或 developer docs 中直接暴露本地反馈 inbox 作为公开入口。
