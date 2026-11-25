# Sci-Station

Sci-Station 是本地优先的科研桌面工作台。一个应用内包括共享文献库、PDF 阅读与批注、项目 Wiki、材料、任务、文献发现和多席科研圆桌。启动窗口沿用 Sci-Station 的原生材料、字形与时序，Dock 与工作区使用圆桌图标。界面资产与字体随应用分发。

## 开始使用

打开按下方步骤构建的 `Sci-Station.app`。在科研工作台新建项目，把 PDF 导入文献库。进入阅读器选中一段文字，可保存批注或送入圆桌。从会议中审阅一项结论后，可保存到项目笔记或创建任务。

论文阅读、批注、Wiki、任务、材料和本地 PDF 文本转换均可离线使用。会话使用用户配置的 Magpie 模型，在应用设置注册 Sci-Station Agent，然后到 Magpie 的 Agents 页面选定模型。Sci-Station 连接本机回环地址上的 Magpie 网关，连接文件记录地址和模型，请求使用公开应用标识。模型供应商的登录与凭据由 Magpie 管理。联网导入、arXiv 发现和可选 MinerU 转换需要相应服务可用。MinerU Token 只随当前操作发送给 MinerU。系统日历和提醒事项仅在主动使用时申请权限。AI 实验室支持保存个人提示模板，以及选择公开 MCP 文本资源中的摘录作为会议材料。

## 数据与开发

新版从空工作区开始，使用独立应用目录 `~/Library/Application Support/Sci-Station Desktop`。文献保留原 PDF，科研项目可以关联明确选择的外部目录，会议记录与已审笔记分别存储。备份时先退出应用，再复制整个应用数据目录和自己关联的外部项目文件夹。

阅读位置保存在当前研究根的共享论文记录中，包含 PDF 指纹、页码、缩放和滚动位置。阅读位置独立于论文笔记及批注的修订号。新文本批注与会议摘录可以保存基于 PDFKit UTF-16 的字符区间及本地 OCR 标记。旧记录缺少这些可选字段时仍可打开，只有唯一匹配或能通过批注位置消除歧义的旧摘录会定位到具体文字。更新沿用论文记录的原子写入，回退时可恢复退出应用后保存的工作区副本。

### 任务记录与系统日历权限

共享任务只存于创建时的项目记录。关联项目可以编辑同一条任务，原始项目归档后仍可通过其他关联项目访问。工作区列表对有启用项目的任务只显示一次。修改项目关联时保留任务修订号以及原始项目和任务标识，重新发布后可更新对应的 Apple 提醒事项。

原型的 `research/records/<project>.json` 文件没有顶层版本号。新增任务字段兼容缺字段的旧记录，旧字段 `projectId` 和 `paperId` 提供默认关联，`doing` 读作 `inProgress`。打开工作区时不批量重写数据，保存任务时保留未知任务字段。原型旧版本只识别单个项目和单篇论文的关联。需要回退时，使用旧版本打开变更前的独立备份，分别保留新版数据和外部研究目录。现有 Swift Research Root 不做自动转换。

本地任务的创建、修改和月历视图支持离线使用。在系统日历页主动读取 Apple 日历、发布或更新 Apple 提醒事项时，分别申请对应的 macOS 权限。如权限被拒绝，在系统设置授予权限后可重试。授权或发布失败时仍可使用本地任务。

需要 Go 1.26、Xcode Command Line Tools 和 macOS 15 或更新版本。候选应用面向 Apple Silicon。构建使用已提交的 `go.mod`、`go.sum` 和界面资源，首次构建需获取 Go 依赖。以下命令从仓库根目录运行。

```sh
make -C RoundtableWorkstation test
make -C RoundtableWorkstation app
make -C RoundtableWorkstation verify
make -C RoundtableWorkstation run
```

默认产物是 `RoundtableWorkstation/Sci-Station.app`。`app`、`verify` 和 `run` 接受相同的 `APP_OUTPUT`。构建对候选 bundle 做启用 hardened runtime 的 ad-hoc 签名，通过验证后再替换原产物。要验证原生退出、端口与数据锁释放及重开，需要登录 macOS 图形会话并运行 `python3 RoundtableWorkstation/tests/macos-close-smoke.py RoundtableWorkstation/Sci-Station.app`。

`make -C RoundtableWorkstation headless` 生成可通过浏览器访问的本地服务。运行 `RoundtableWorkstation/build/bin/sci-station-server serve -data-dir /path/to/test-data`，访问 `http://127.0.0.1:18765/research`。原生启动、系统日历和系统对话框使用桌面模式。首次试用可在独立目录启动 `RoundtableWorkstation/Sci-Station.app/Contents/MacOS/sci-station app -data-dir /path/to/test-data`。

主要入口是 main.go、api.go、desktop_darwin.go，科研存储在 internal/research，会议编排在 internal/meeting，模型接入在 internal/gateway，界面在 static，应用打包脚本在 packaging/macos。原生启动窗口与 PDF 工具使用 Objective-C / AppKit / PDFKit，不需要 Swift 工程或 Python 服务。macOS 应用使用本地 ad-hoc 签名。
