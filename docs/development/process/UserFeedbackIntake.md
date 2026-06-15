# 用户反馈 Intake 流程

本文件定义 AI 如何把用户在 `docs/user-feedback/` 中写下的原始需求、问题、Bug 和新功能想法，转换为可执行、可维护的正式开发文档。

## 角色分层

- `docs/user-feedback/`：本地人类输入层。面向用户或产品 owner，用自然语言记录原始想法；它不是公开文档入口。
- `docs/user-feedback/inbox/`：本地原始输入区，被 Git 忽略，不作为长期知识库。
- `docs/development/`：AI 维护的开发知识库。面向 AI 和开发执行，不要求用户深度阅读。
- `docs/README*.md`、`docs/TUTORIAL*.md`：用户可读说明。只保留稳定、必要、简短的信息。

## Intake 原则

AI 必须：

1. 把原始反馈当作输入材料，而不是最终文档。
2. 先提炼目标、范围、非目标、影响模块和验证方式。
3. 把可执行工作转换为 Proposal、roadmap、module docs、testing docs、release record 或 changelog。
4. 不把原始反馈中的私人路径、账号、API key、论文内容或临时情绪性描述复制到可提交文档。
5. 如果反馈含糊，先列出需要用户确认的问题，再创建正式 Proposal。

AI 不应：

- 直接提交 `docs/user-feedback/inbox/`、`drafts/` 或 `archive-local/` 中的原始文件。
- 让用户反馈文档替代 Proposal。
- 把未确认的想法写成已承诺的 release scope。
- 把用户本地环境细节写进长期开发文档。

## 转换规则

| 原始反馈类型 | 目标文档 |
|---|---|
| 新功能、较大重构 | `docs/development/proposals/Proposal-<version>.md` |
| 小 Bug 或修复 | 当前 Proposal 的 task、相关 module doc、testing doc |
| 产品方向或暂不做的想法 | `docs/development/roadmap/Backlog.md` |
| 当前版本必须完成的目标 | `docs/development/roadmap/Current.md` |
| 模块长期约束 | `docs/development/modules/` |
| 架构或数据边界 | `docs/development/architecture/` |
| 测试或验收要求 | `docs/development/testing/` |
| 用户可见变化 | `CHANGELOG.md` 和 `docs/development/releases/<version>.md` |
| 用户帮助内容 | `docs/README*.md` 或 `docs/TUTORIAL*.md` |

## AI Intake 步骤

1. 读取用户指定的反馈文件，或扫描 `docs/user-feedback/inbox/`。
2. 按类型、优先级、目标版本和影响模块分类。
3. 判断是否需要追问；如果需要，先输出问题，不创建正式任务。
4. 对明确可执行的反馈，创建或更新正式开发文档。
5. 在正式文档中记录来源摘要，而不是原始文件全文。
6. 更新 `CHANGELOG.md`、release record 和测试要求。
7. 输出 intake summary，列出已转换、待确认和不处理项。

## 来源记录格式

正式 Proposal 可以记录：

```text
Source feedback: local user-feedback item summarized by AI; raw file is gitignored.
```

如果需要保留可追溯性，只记录本地文件名或简短摘要，不记录私人内容。

## 处理完成

原始反馈处理完后，用户可以在本地把文件移动到：

```text
docs/user-feedback/archive-local/
```

该目录同样被 Git 忽略。
