# 用户需求与问题入口

这个目录是给用户或产品 owner 写原始想法、需求、Bug、问题和新功能设想的入口。

这里不是长期开发文档。长期开发文档由 AI 维护在 `docs/development/` 中。

## 使用方式

1. 复制 `FeedbackItemTemplate.md`。
2. 把副本放到 `inbox/` 目录。
3. 用自然语言写清楚你想要什么、遇到什么问题、为什么重要。
4. 让 AI 读取 `inbox/` 中的条目，并转换为正式开发文档。

## 本地目录

以下目录是本地工作区，不会提交到 Git：

```text
docs/user-feedback/inbox/          待 AI 整理的原始需求、问题和想法
docs/user-feedback/drafts/         用户或 AI 临时整理中的草稿
docs/user-feedback/archive-local/  已处理原始条目的本地归档
```

如果目录不存在，可以直接创建。

## AI 转换目标

AI 读取这里的原始内容后，应把它整理到正式文档中：

- 新功能或较大改动：`docs/development/proposals/`
- 长期产品方向：`docs/development/roadmap/`
- 模块规则或架构知识：`docs/development/modules/` 或 `docs/development/architecture/`
- 测试要求：`docs/development/testing/`
- 发布影响：`docs/development/releases/` 和 `CHANGELOG.md`
- 用户说明：`docs/README*.md` 或 `docs/TUTORIAL*.md`

## 隐私规则

- 不要把 API key、token、账号密码或私人论文内容写进可提交文档。
- 原始反馈默认只保存在被 Git 忽略的 `inbox/`、`drafts/` 或 `archive-local/` 中。
- AI 转换时只保留可公开、可维护、可执行的信息。
