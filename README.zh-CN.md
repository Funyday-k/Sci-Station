# Sci-Station

**Sci-Station 是一个面向 macOS 的本地优先科研工作站。** 它把论文库、项目知识、PDF 阅读、材料文件、任务日历和可选 AI 工作流放在同一个产品体验里，并把核心数据保存在用户选择的本地 Research Root 中。

> 默认英文入口见 [README.md](README.md)。试用教程提供 [English](TUTORIAL.md) 和 [中文](TUTORIAL.zh-CN.md) 两个版本。

## 产品出发点

科研项目常常从分散的 PDF、笔记、代码、数据、图表、todo、浏览器链接和半成稿 proposal 开始。Sci-Station 希望把这些内容收束到一个用户可见、可审计、可带走的 Research Root：它既是文件夹，也是科研工作的产品化工作台。

Sci-Station 的核心原则是：

- **本地优先**：论文、笔记、项目文件、任务、AI 运行日志和生成 artifact 都放在你选择的本地目录里。
- **科研原生结构**：从论文、项目、Wiki、材料、图表、输出、任务和引用出发，而不是只做通用文件管理。
- **可审计 AI**：LLM/Agent 是可选能力；凭据进 Keychain，写入动作走权限确认，证据引用和运行日志可回看。

## 项目特色

- **一个 Research Root，而不是新的黑盒仓库**：工作区是普通目录树，可用 Finder、VS Code、备份工具或 Git 选择性管理。
- **论文库连接项目上下文**：导入论文后会生成元数据、笔记、引用信息、Wiki 页面和项目关系。
- **Markdown 作为知识层**：project brief、paper notes、concepts、methods、research gaps 和 shared context 都是可编辑 Markdown。
- **Materials 面向真实工作文件**：data、code、figures、scripts、prompts、outputs 可以在 App 中预览，也可以交给 VS Code 或外部工具。
- **PDF 阅读连接科研动作**：内置 Reader 把 metadata、notes、tasks、citations、links、abstract 和文件面板放在同一处。
- **AI Lab 有明确边界**：用户自带 provider，敏感信息进 Keychain，写入工具需要授权，运行结果留审计日志。

## 当前能力

- macOS SwiftUI 三栏工作区界面。
- 创建、打开、修复 Research Root，并通过 security-scoped bookmark 恢复最近工作区。
- 支持 PDF 拖入、文件选择、DOI、arXiv、PDF URL 和普通链接导入。
- 论文元数据保存到 `meta.yaml`，支持 BibTeX、标签、阅读状态、优先级、评分、abstract 和标识符。
- Library 支持搜索、排序、列配置、多选、批量操作、复制引用和 PDF 预览。
- Project Overview 汇总项目介绍、核心论文、项目文档、科研 workflow 和任务概览。
- Wiki 编辑器支持 Source、Preview、Split、frontmatter、`[[wikilink]]`、backlinks、snippets、GFM、图片和 KaTeX。
- Materials 可浏览 Markdown、Python、文本、图片、PDF、数据、代码、图表、输出、脚本和 prompt 文件。
- VS Code / VSCodium bridge 支持打开工作区文件和准备 Python run task。
- Todo / Calendar 支持本地任务和可选 Apple Calendar / Reminders 联动。
- PDF Reader 支持搜索、翻页、缩放、笔记、相关任务、引用、链接和文件面板。
- AI Lab V1 支持项目会话、plan review、permission dock、run/thread history、hooks、MCP preset 展示和审计日志。

当前版本仍是试用/开发构建，不是 notarized 公共发布版。

## 快速开始

要求：

- macOS 14 或更高版本
- Xcode 15 或更高版本

运行：

```bash
open Sci-Station.xcodeproj
```

在 Xcode 中选择 `Sci-Station` scheme，运行目标选择 `My Mac`，按 `Command + R`。

首次启动建议：

1. 点击 `Create Workspace`。
2. 选择一个空文件夹作为 Research Root，不要选择源码仓库本身。
3. 在 Library 中导入 PDF，或用 `Add by Identifier` 添加 DOI、arXiv、PDF URL、网页链接。
4. 创建项目，在 Project Overview 中开始写 project brief 和核心论文笔记。
5. 用 Materials 管理 data、code、figures、scripts、prompts 和 outputs。
6. 只有需要 AI 时，再到 `Settings -> AI Lab` 配置自己的 OpenAI-compatible provider。

完整流程见 [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md)。

## 工作区结构

Research Root 是用户可读的目录：

```text
ResearchRoot/
├── .sci-station/
├── library/
│   └── papers/{paper-id}/
│       ├── paper.pdf
│       ├── paper.md
│       ├── meta.yaml
│       ├── annotations.md
│       └── figures/
├── projects/{project-id}/
│   ├── project.yaml
│   ├── shared_research.md
│   ├── wiki/
│   ├── tasks/
│   ├── data/
│   ├── code/
│   ├── figures/
│   └── outputs/
├── wiki/
├── refs/
├── settings/
├── tasks/
├── imports/
├── data/
├── prompts/
├── scripts/
├── code/
├── figures/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

## 隐私与凭据

- 仓库和构建产物不应包含 API key、OAuth token、refresh token、client secret、private key、本机 MCP 配置或私人科研数据。
- LLM API Key 和 MinerU API Token 通过安全输入保存到 macOS Keychain。
- `settings.yaml` 只保存 base URL、model、temperature、max tokens 等非敏感设置。
- 论文、笔记、任务、Agent 日志和生成文件留在用户选择的 Research Root 中。
- `.sci-ai/sci-station/` 只放可版本化的产品 preset、schema、skills、hooks、commands、MCP template 和 secret reference。
- `.sci-ai/workspace.local/`、`.claude/`、`.mcp.json`、`.env*`、打包产物和本机 research 数据都不应提交。

## 验证

核心验证：

```bash
swift run SciStationCoreTestRunner
```

App 构建：

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

Python sidecar 测试：

```bash
python -m pytest AgentRuntime/tests
```

## 相关文档

- [README.md](README.md)：英文默认项目介绍。
- [TUTORIAL.md](TUTORIAL.md)：英文试用教程。
- [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md)：中文试用教程。
- [.sci-ai/README.md](.sci-ai/README.md)：AI 配置边界。
- [.sci-ai/sci-station/README.md](.sci-ai/sci-station/README.md)：内置 AI preset 说明。
- `DOC/`：开发任务书、Proposal 和手动测试记录。
