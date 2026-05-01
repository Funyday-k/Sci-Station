# Sci-Station 试用教程

这份教程面向第一次拿到 Sci-Station 的试用者。建议先从源码运行，确认工作区和权限都正常后，再考虑打包 `.app` 分享。

## 1. 准备环境

- macOS 14 或更高版本
- Xcode 15 或更高版本
- 一个空文件夹作为 Research Root，例如 `~/Documents/SciStationTrial`

Research Root 是 Sci-Station 保存论文、Markdown、任务、设置和 Agent 日志的地方。不要把源码仓库本身当作 Research Root，也不要把包含私人资料的现有目录直接发给别人。

## 2. 运行 App

```bash
open Sci-Station.xcodeproj
```

在 Xcode 中选择 `Sci-Station` scheme，运行目标选择 `My Mac`，然后按 `Command + R`。

如果只想验证核心文件系统逻辑，可以在仓库根目录运行：

```bash
swift run SciStationCoreTestRunner
```

## 3. 创建 Research Root

1. App 首屏点击 `Create Workspace`。
2. 选择一个空文件夹。
3. Sci-Station 会自动创建 `library/`、`projects/`、`wiki/`、`tasks/`、`settings/`、`.sci-station/` 等目录和种子文件。
4. 之后重启 App 会尝试通过 macOS security-scoped bookmark 自动恢复最近的 Research Root。

如果 Research Root 被移动或删除，App 会清理失效 bookmark，并回到创建/打开工作区的状态。

## 4. 导入第一篇论文

可以用三种方式开始：

- 在 Library 中点击 `Import PDF`。
- 将 PDF 拖进 Library。
- 点击 `Add by Identifier`，粘贴 DOI、arXiv、PDF URL 或普通网页链接。

导入后，每篇论文会在 `library/papers/` 下生成标准目录，通常包含：

```text
paper.pdf
paper.md
meta.yaml
annotations.md
figures/
```

`meta.yaml` 保存标题、作者、年份、标签、阅读状态、DOI、arXiv、BibTeX 等元数据。`annotations.md` 保存阅读笔记。

## 5. 建立项目与 Wiki

1. 在侧边栏点击 `New Project`。
2. 填写项目名称、描述、图标和颜色。
3. 打开 `Project Overview`，查看项目介绍、核心论文、项目文档和任务概览。
4. 点击 `Open Project Brief` 或进入 Wiki，编辑 Markdown 页面。

Wiki 支持 Source、Preview 和 Split 视图，也会解析 YAML frontmatter 和 `[[wikilink]]`。默认 snippets 包含 `;eq`、`;fig`、`;todo`、`;paper`。

## 6. 使用 Materials

Materials 用来浏览当前项目或 Research Root 下的用户材料。常用目录包括：

```text
data/
code/
figures/
outputs/
scripts/
prompts/
shared_research.md
```

Markdown、Python、文本、图片和 PDF 可以直接预览。其他文件可用默认 App、Finder 或 VS Code 打开。Python 文件可以准备 VS Code task，也可以选择系统 Python、workspace `.venv` 或手选虚拟环境。

## 7. 配置可选 AI 功能

AI 功能不是试用 App 的必需项。需要时再进入 Settings -> AI Lab：

1. 选择 OpenAI-compatible provider。
2. 填写 Base URL、Model、Temperature 和 Max Tokens。
3. 在 `API Key` 中填写自己的 key。
4. 点击 `Save Settings`，再用 `Test Connection` 测试。

安全边界：

- API Key 保存到 macOS Keychain。
- `settings.yaml` 不写入 API Key。
- `.sci-ai/sci-station/` 只能保存可提交的 preset 和模板。
- `.sci-ai/workspace.local/`、`.claude/`、`.mcp.json` 用于本机 agent bridge 配置，不要提交或分享。

MinerU PDF 转 Markdown 也需要试用者自己的 API Token。Token 同样保存到 Keychain。

## 8. Calendar 与 Reminders 权限

Tasks 可以和 Apple Calendar / Reminders 联动。首次使用时 macOS 会弹出权限请求：

- 允许后，Sci-Station 可以读取日历/提醒事项标题，并把 workspace todo 发布到 Apple Reminders。
- 拒绝后，本地 todo 仍可使用，只是不会同步到系统 Reminders。

## 9. 分享前检查

发给别人前建议运行：

```bash
git status --short
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
git grep -n -I -i -E '(api[_ -]?key|secret|token|password|bearer|private[_ -]?key|client[_ -]?secret|refresh[_ -]?token|oauth)' -- . ':!DOC/**'
```

确认没有真实凭据、本机 research 数据、`.env*`、`.mcp.json`、`.claude/`、`.sci-ai/workspace.local/`、DerivedData、archive、`.app`、`.zip`、`.dSYM` 或 `.xcresult` 混入分享包。

## 10. 已知试用边界

- 这是本地优先试用版，不是公证发布版。
- LLM、MinerU、Crossref、arXiv、INSPIRE 等网络能力依赖用户网络和第三方服务状态。
- PDF 转 Markdown 的高质量转换依赖 MinerU；没有 token 时会降级使用本地 PDFKit 提取。
- Apple Reminders 当前以发布和本地记录为主，完整双向同步仍在后续迭代。
- AI Lab 的写入类工具仍需要权限确认，MCP server 当前以模板和状态展示为主。
