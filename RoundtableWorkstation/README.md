# Sci-Station

Sci-Station 是本地优先的科研桌面工作台。一个应用内包括共享文献库、PDF 阅读与批注、项目 Wiki、材料、任务、文献发现和多席科研圆桌。启动窗口沿用 Sci-Station 的原生材料、字形与时序，Dock 与工作区使用圆桌图标。界面资产与字体随应用分发。

## 开始使用

打开按下方步骤构建的 `Sci-Station.app`。在科研工作台新建项目，把 PDF 导入文献库。进入阅读器选中一段文字，可保存批注或送入圆桌。从会议中审阅一项结论后，可保存到项目笔记或创建任务。

论文阅读、批注、Wiki、任务、材料和本地 PDF 文本转换均可离线使用。会话使用用户配置的 Magpie 模型，在应用设置注册 Sci-Station Agent，然后到 Magpie 的 Agents 页面选定模型。Sci-Station 连接本机回环地址上的 Magpie 网关，连接文件记录地址和模型，请求使用公开应用标识。模型供应商的登录与凭据由 Magpie 管理。联网导入、arXiv 发现和可选 MinerU 转换需要相应服务可用。MinerU Token 只随当前操作发送给 MinerU。系统日历和提醒事项仅在主动使用时申请权限。AI 实验室支持个人提示模板、项目 Markdown 技能及公开 MCP 文本摘录。

## 导航与恢复

菜单、项目模块、阅读器和圆桌共用窗口上方的导航。浏览器的前进和后退可返回已访问的页面。复制阅读器或会议地址可以保留相应项目、论文和证据位置。在同一工作区再次启动时，桌面通过 `/resume` 进入最近打开的位置。已归档的项目、缺少的论文或停用的模块会转到可用的上级页面。

每个根下的 `workspace-navigation.json`（版本 1）只记录最近一次导航及其定位参数。备份和还原该文件可以恢复入口位置。缺少此文件时从首页打开，较新的版本或损坏记录保留原样，桌面从首页打开。论文、会议和批注由对应服务保存。

## AI 实验室技能与 MCP

在 AI 实验室选择项目后，可从本机导入带 YAML 元数据的 Markdown 科研技能。预览内容后确认导入，再分别启用并信任该内容版本。每次单席运行或交给圆桌前，可以选用一个已启用且受信任的技能。技能正文作为方法指引写入该会话。工具权限仍由相应的 CLI 审批流程处理。导入范围限于用户选择的 Markdown 文件。

公共 MCP 资源使用公开 HTTPS 地址。项目可以保存并停用此地址。列出目录和读取资源各自需要确认。连接失败时仍可继续使用项目原文和本地技能。选入会话的资源摘录包含服务地址、资源 URI 和原文 SHA-256。需要鉴权、stdio 或调用工具的 MCP 服务由所用 CLI 管理。受支持的 CLI 文件审批会在圆桌中显示。

这些偏好保存在当前研究根的项目记录中。旧记录默认关闭公共 MCP 且没有项目技能。若需要回退，退出应用后从同一工作区备份还原项目记录。

## 数据与开发

新版首次启动会要求选择或创建一个空工作区。文献保留原 PDF，科研项目可以关联明确选择的外部目录，会议记录与已审笔记分别存储。旧 Go 原型的默认应用数据目录是 `~/Library/Application Support/Sci-Station Desktop`。

在桌面应用的「PDF 转换」中，可以保存、替换或清除 macOS 钥匙串中的 MinerU Token。保存后，重新打开同一应用数据目录即可留空使用；在另一台 Mac 或新的数据目录中使用时，需要重新保存 Token。浏览器模式支持一次性输入。

「设置 → 模型来源 → 直接模型」支持将 OpenAI-compatible 服务配置到圆桌与 AI 实验室的同一模型目录。填写 API Base URL、服务端模型 ID、温度和可选输出限制，再单独保存 API Key 到 macOS 钥匙串。连接测试只发送一句固定测试提示，可用输入框临时填入的 Key。HTTPS 服务需要 Key，本机回环地址也支持无凭证 HTTP 服务。更改已保存 Key 对应的服务地址前应先清除 Key。

直接模型配置保存在应用数据目录的 `provider-profiles.json`。版本 1 保存列表顺序、配置 ID 和非敏感字段，在更新时保留未知字段。未知版本或损坏文件会让直接模型配置暂时不可用，原文件保留在原处。恢复时退出应用并还原此文件及原应用数据目录，Keychain 按原目录、配置 ID 和服务地址解析凭证。旧 Swift 配置由原应用保管，新版配置由用户单独创建。

### 从 Go 原型备份与恢复

切换之前，退出 Go 原型，等待进程完全结束，并暂停对其数据目录的其他写入。在源码的 `RoundtableWorkstation` 目录运行以下命令。为备份和恢复各选一个全新的绝对路径，确认其父目录已经存在。使用单独的私有备份位置保存科研资料。原型曾以 `-data-dir` 启动时，请把示例中的 `prototype` 改为实际数据路径。

```sh
prototype="$HOME/Library/Application Support/Sci-Station Desktop"
backup="/absolute/path/to/private-storage/sci-station-prototype-backup"
recovery="/absolute/path/to/private-storage/sci-station-recovery-check"
go run -tags nogui ./cmd/prototype-data backup -source "$prototype" -destination "$backup"
go run -tags nogui ./cmd/prototype-data verify -source "$backup"
go run -tags nogui ./cmd/prototype-data restore -source "$backup" -destination "$recovery"
```

- `backup` 获取原型现有的进程锁，把应用目录中的记录、PDF、附件、项目文件、插件包和设置逐字节复制到 `data/`，使用 `manifest.json` 记录每个文件的大小和 SHA-256。运行时锁文件在重开时重新建立。工具拒绝符号链接、硬链接、挂载的子目录和数据目录内的外部项目。另行备份你明确选择的外部研究文件夹。
- `verify` 核对清单、共享文献及其 PDF、项目与附件、会议与附件、安装的插件包。历史笔记或任务可以保留已由用户删除的记录引用。备份清单格式为 v1，陌生的清单或插件注册表版本会导致验证失败。完整的备份仍可供人工取回原始文件。
- `restore` 在临时目录逐字节核验副本，再将托管项目路径指向目标目录，按能唯一确认的项目 ID 保留会议关联，停用外部项目目录授权，并清除恢复副本中的本机 CLI 路径覆盖。原始外部路径仍记录在备份的项目登记、项目记录和会议记录中。Keychain、Magpie 数据、供应商登录与 CLI 登录存储位于备份范围之外。恢复目标在数据和引用通过校验后才发布。原型目录、备份和当前工作区选择均保留。
- 在隔离副本中核对一篇 PDF、对应的批注或引用、项目文件和会议记录。可用明确的路径启动一次本地服务，例如 `build/bin/sci-station-server serve -data-dir "$recovery" -port 18766`，然后访问 `http://127.0.0.1:18766/research`。恢复的会议可供查阅，外部研究目录应按需重新明确授权。
- 如果验证或打开失败，继续使用此前的工作区，保留原型目录和备份。修复备份来源的问题，或者对同一备份使用另一处全新路径重试。备份和恢复命令均要求目的地尚不存在。

文献库在当前工作区的 `research/library/organization.json`（格式版本 1）保存共享集合、标签颜色和可选的文献库偏好。可以在文献库的「管理集合和标签」中设置默认导入集合，选择并调整显示列。已选集合优先于默认集合，导入时可另选目的地或明确选择未归类。默认排序可由表头调整。旧记录直接打开，使用默认列和未归类导入设置。

首次导入时，应用在当前工作区的 `research/library/refs/library.bib` 自动建立书目。后续新文献按引用键追加，保留已有条目、注释和宏。书目损坏或无法读取时，修正原文件后可重试导入。若导入在追加后失败，应用只在原有版本仍匹配时回滚该次追加。文献列表及阅读器里的「引文」可预览并复制 BibTeX、APA、MLA、Chicago、IEEE 和 RIS。手动保存 BibTeX 时由系统保存面板选择目的地。

重命名集合不会移动文献或 PDF，标签颜色定义与文献上的标签分别保存。无法读取组织记录或版本未知时，应用会保留原文件并报告错误。恢复时先退出应用，再从同一份备份恢复整个 `research/library` 目录，确保集合、文献记录、书目和 PDF 一致。

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

`make -C RoundtableWorkstation headless` 生成可通过浏览器访问的本地服务。运行 `RoundtableWorkstation/build/bin/sci-station-server serve -port 18765 -data-dir /path/to/test-data`，访问 `http://127.0.0.1:18765/research`。原生启动、系统日历和系统对话框使用桌面模式。首次试用可在独立目录启动 `RoundtableWorkstation/Sci-Station.app/Contents/MacOS/sci-station app -data-dir /path/to/test-data`。

Node 可加载 Playwright 时，可从仓库根目录运行 `node RoundtableWorkstation/tests/global-tasks-browser-smoke.cjs RoundtableWorkstation/build/bin/sci-station-server`。测试在无界面 Chromium 与临时工作区验证全局任务、日历和重启恢复。`SCI_STATION_SMOKE_CHROME` 可指定已安装的 Chrome 或 Chromium。

主要入口是 main.go、api.go、desktop_darwin.go，科研存储在 internal/research，会议编排在 internal/meeting，模型接入在 internal/gateway，界面在 static，应用打包脚本在 packaging/macos。原生启动窗口与 PDF 工具使用 Objective-C / AppKit / PDFKit，不需要 Swift 工程或 Python 服务。macOS 应用使用本地 ad-hoc 签名。

### 引用图谱数据

项目关系、引用位置和 AI 实验室中的图谱预览均从当前研究根目录的来源记录生成。确认加入后，AI 实验室会把图谱预览写入对应项目的未发送圆桌草稿。题名近似的候选会单独标注，默认路径查询跳过这些候选。

点击查询 INSPIRE 会向该服务发送所选论文的公开标识符。图谱可同时查看至多六个种子。每次成功查询保存一个版本为 1 的研究根目录缓存 `inspire-graph-<identity-sha256>.json`，包含论文标识、下载时间、至多 25 条参考文献和 25 篇引用论文。离线读取会标记缓存来源，跳过损坏或不受支持的缓存，下一次成功查询可重建对应文件。删除这些缓存可移除下载的图谱数据。笔记、论文记录、PDF 和会议记录保存在各自的来源目录。

在 `RoundtableWorkstation` 目录运行 `go test -race -tags 'nogui cli_browser_smoke' -run '^TestCLIEditReviewBrowser$' .`，可用 Playwright 和本机 Chromium 检查圆桌的 CLI 文件审批。测试用独立的模拟 CLI 进程通过标准输入输出申请修改临时项目文件，核对允许、拒绝、取消、断线及重开后的结果。
