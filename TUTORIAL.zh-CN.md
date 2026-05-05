# Sci-Station 试用教程

这份教程面向第一次试用 Sci-Station 的用户。默认英文教程见 [TUTORIAL.md](TUTORIAL.md)，项目介绍见 [README.md](README.md) 或 [README.zh-CN.md](README.zh-CN.md)。

## 1. 准备环境

需要：

- macOS 14 或更高版本
- Xcode 15 或更高版本
- 一个空文件夹作为 Research Root，例如 `~/Documents/SciStationTrial`

Research Root 是 Sci-Station 保存论文、Markdown、项目文件、任务、设置和 Agent 日志的地方。不要把源码仓库本身当作 Research Root，也不要在未检查前分享包含私人论文或未公开数据的 Research Root。

## 2. 运行 App

打开 Xcode 工程：

```bash
open Sci-Station.xcodeproj
```

在 Xcode 中：

1. 选择 `Sci-Station` scheme。
2. 运行目标选择 `My Mac`。
3. 按 `Command + R`。

如果只想验证核心文件系统和元数据逻辑，可以运行：

```bash
swift run SciStationCoreTestRunner
```

## 3. 创建 Research Root

1. 首屏点击 `Create Workspace`。
2. 选择一个空文件夹。
3. Sci-Station 会创建 `library/`、`projects/`、`wiki/`、`tasks/`、`settings/` 和 `.sci-station/` 等目录。
4. 重启一次 App，确认 macOS security-scoped bookmark 能自动恢复最近工作区。

如果 Research Root 被移动或删除，App 会清理失效 bookmark，并回到创建/打开工作区状态。

## 4. 导入第一篇论文

进入 Library 后可以从三种方式开始：

- 点击 `Import PDF`。
- 将 PDF 拖入 Library。
- 点击 `Add by Identifier`，粘贴 DOI、arXiv、PDF URL 或普通网页链接。

成功导入后，每篇论文会在 `library/papers/` 下生成目录，通常包含：

```text
paper.pdf
paper.md
meta.yaml
annotations.md
figures/
```

可以在 Inspector 中编辑标题、作者、年份、标签、阅读状态、优先级、评分、DOI、arXiv、abstract 和 BibTeX。PDF Reader 中保存的笔记会写入 `annotations.md`。

## 5. 把论文库变成项目

1. 在侧边栏或菜单中点击 `New Project`。
2. 填写项目名称、描述、图标和颜色。
3. 打开 Project Overview。
4. 把 project brief 当作 living proposal 来写。
5. 标记或关联核心论文，让项目有明确的阅读主线。

Project Overview 会汇总论文数、核心论文、项目文档和未完成任务，并连接 data、code、figures、outputs、wiki 和 shared context。

## 6. 使用 Wiki 写作

打开 Wiki 或项目文档，尝试：

- `Source` 模式编辑 Markdown。
- `Preview` 模式阅读渲染结果。
- `Split` 模式边写边看。
- `Cmd+S` 保存。
- 使用 `;eq`、`;fig`、`;todo`、`;paper` 等 snippets。
- 编写 YAML frontmatter 和 `[[wikilink]]`。

Markdown 预览支持 GFM 表格、代码块、图片和 KaTeX 公式。

## 7. 使用 Materials 管理真实工作文件

Materials 用来浏览用户真正会操作的研究文件。默认扫描：

```text
data/
code/
figures/
outputs/
scripts/
prompts/
shared_research.md
```

Markdown、Python、文本、图片和 PDF 可以直接预览。其他文件可用 Finder、默认 App、VS Code 或 VSCodium 打开。

Python 文件可以准备 VS Code task，并记录所选 Python 环境。你可以使用系统 Python、workspace `.venv` 或手动选择的虚拟环境。

## 8. 在上下文中阅读 PDF

从 Library 打开论文后，内置 PDF Reader 支持：

- `Cmd+F` 搜索。
- `Cmd+G` / `Shift+Cmd+G` 查找下一处/上一处。
- 翻页、缩放和导航。
- 在 Notes 面板编辑论文笔记。
- 创建关联当前论文的任务。
- 从 Citations 面板复制或导出 BibTeX。
- 打开 DOI、arXiv、INSPIRE、URL 或 PDF URL。

这样阅读动作会和元数据、笔记、任务、引用保持在同一个上下文里。

## 9. 管理任务和日历

Sci-Station 会把本地 todo 保存到 Research Root。Calendar 和 Apple Reminders 联动是可选能力：

- 如果允许 macOS 权限，Dashboard 可以显示 Calendar/Reminders 标题，并把 workspace todo 发布到 Apple Reminders。
- 如果拒绝权限，本地 todo 仍然可用。

发布后的 todo 会在 `tasks/todos.yaml` 中写入 `external_source`、`external_identifier`、`external_updated_at`、`completed_at` 和 `due_time` 等映射字段。

## 10. 配置可选 AI 功能

核心 App 不依赖 AI。需要测试 AI 时，进入 `Settings -> AI Lab`：

1. 选择 OpenAI-compatible provider。
2. 填写 Base URL、Model、Temperature 和 Max Tokens。
3. 在安全输入框中填写 API Key。
4. 点击 `Save Settings`。
5. 先用 `Test Connection` 验证连接。

安全边界：

- API Key 保存到 macOS Keychain。
- workspace settings 不保存明文 API Key。
- `.sci-ai/sci-station/` 只保存可提交的产品 preset 和模板。
- `.sci-ai/workspace.local/`、`.claude/`、`.mcp.json` 和 `.env*` 属于本机配置，不应提交或分享。
- AI/Agent 工作流的写入动作仍需要通过权限层确认。

MinerU PDF 转 Markdown 也需要试用者自己的 API Token。没有 token 时会降级使用本地 PDFKit 提取。

## 11. 分享或审查前检查

分享 checkout 或 Research Root 前建议运行：

```bash
git status --short
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
git grep -n -I -i -E '(api[_ -]?key|secret|token|password|bearer|private[_ -]?key|client[_ -]?secret|refresh[_ -]?token|oauth)' -- . ':!DOC/**'
```

确认没有真实凭据、本机 research 数据、`.env*`、`.mcp.json`、`.claude/`、`.sci-ai/workspace.local/`、DerivedData、archive、`.app`、`.zip`、`.dSYM` 或 `.xcresult` 混入分享内容。

## 12. 已知试用边界

- Sci-Station 当前是本地优先试用/开发构建，不是 notarized 公共发布版。
- 网络功能依赖用户配置、用户网络和第三方服务状态。
- 高质量 PDF 转 Markdown 依赖 MinerU。
- Apple Reminders 当前以发布和本地映射为主，完整双向同步属于后续工作。
- MCP server 执行仍受模板、状态展示和权限模型约束。
