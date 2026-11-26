# Sci-Station

> 当前版本：0.2.0
> 支持平台：Apple Silicon Mac，macOS 15 或更新版本
> 发布阶段：Developer Preview

Sci-Station 是一个本地优先的科研工作台。论文库、PDF 阅读、项目 Wiki、材料、任务与日历、AI 实验室和多席圆桌共用一个 Go/Wails 桌面应用。论文、笔记、任务和会议记录存放在你选择的科研工作区；已有项目的文件夹可在项目中单独授权。

[English](docs/README.en.md) · [中文教程](docs/TUTORIAL.zh-CN.md)

## 开始使用

安装 Go 1.26 和 Xcode Command Line Tools，在仓库根目录运行：

```sh
make run
```

应用打开后，从「工作区」菜单选择「创建工作区」，选一个空文件夹。再次使用时可打开同一个工作区。新建项目后，在论文库导入一份 PDF，将它加入项目，并在阅读器选中一段文字。你可以保存批注，也可以把原文送入圆桌，在审阅后保存项目笔记或任务。

从源码构建的 Go/Wails 工作台包含当前开发线的功能。[GitHub Releases](https://github.com/Funyday-k/Sci-Station/releases) 提供已发布的预览版本。首次从旧工作台切换时请按[工作区与恢复指南](docs/workspaces.md)使用新工作区，并保留原始研究目录及备份。

## 主要功能

- **论文库与 PDF**。导入 PDF 或按 DOI、arXiv 等标识查找论文。不同项目可共用一份论文和 PDF，各自设置核心论文、固定项与排序。可组织集合和标签、导出引用、恢复阅读位置以及重新定位已保存的原文证据。
- **项目、Wiki 与材料**。在项目里管理笔记、双向链接、引用图谱和实际研究文件。外部目录的授权可撤回；项目记录和共享论文仍可查阅。
- **任务、日历与发现**。本地任务可以关联多个研究项目和论文。在线发现记录检索、候选与反馈；也可导入现有推荐清单。Apple 日历及提醒事项只在主动使用时申请权限。
- **AI 实验室与圆桌**。单席运行和多席讨论可引用论文、笔记与已授权的材料。研究人员可回看原文、讨论和报告，明确确认是否将建议保存为项目笔记或任务。圆桌还能显示受支持本地 CLI 的文件修改审批，批准后的写入由该 CLI 执行。

论文、批注、Wiki、任务、材料和本地 PDF 文本转换均能离线使用。可选模型连接需要自行配置 Magpie 网关或直接模型服务；直接模型的 API Key 和可选的 MinerU Token 可保存到 macOS 钥匙串。网络导入、arXiv 检索以及其他外部服务会在使用相应功能时连接。详细步骤见[中文教程](docs/TUTORIAL.zh-CN.md)。

## 参与开发

- [开发者指南](docs/DEVELOPER.md)介绍代码结构、构建和验证。
- [贡献指南](CONTRIBUTING.md)和[仓库治理](docs/GOVERNANCE.md)规定评审和发布流程。
- [变更记录](CHANGELOG.md)记录开发线及历史版本。
- [安全报告](SECURITY.md)提供私下报告途径。

本项目采用 [MIT License](LICENSE)。第三方图标与资源的来源见[品牌资产](docs/brand-assets.md)。
