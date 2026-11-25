# Sci-Station

Sci-Station 是本地优先的科研桌面工作台。一个应用内包括共享文献库、PDF 阅读与批注、项目 Wiki、材料、任务、文献发现和多席科研圆桌。启动窗口沿用 Sci-Station 的原生材料、字形与时序，Dock 与工作区使用圆桌图标。界面资产与字体随应用分发。

## 开始使用

解压 macOS 应用包，打开 Sci-Station.app。在科研工作台新建项目，把 PDF 导入文献库。进入阅读器选中一段文字，可保存批注或送入圆桌。从会议中审阅一项结论后，可保存到项目笔记或创建任务。

论文阅读、批注、Wiki、任务、材料和本地 PDF 文本转换均可离线使用。会话使用用户配置的 Magpie 模型，在应用设置注册 Sci-Station Agent，然后到 Magpie 的 Agents 页面选定模型。Sci-Station 连接本机回环地址上的 Magpie 网关，连接文件记录地址和模型，请求使用公开应用标识。模型供应商的登录与凭据由 Magpie 管理。联网导入、arXiv 发现和可选 MinerU 转换需要相应服务可用。MinerU Token 只随当前操作发送给 MinerU。系统日历和提醒事项仅在主动使用时申请权限。AI 实验室支持保存个人提示模板，以及选择公开 MCP 文本资源中的摘录作为会议材料。

## 数据与开发

新版从空工作区开始，使用独立应用目录 `~/Library/Application Support/Sci-Station Desktop`。文献保留原 PDF，科研项目可以关联明确选择的外部目录，会议记录与已审笔记分别存储。备份时先退出应用，再复制整个应用数据目录和自己关联的外部项目文件夹。

需要 Go 1.26、Xcode Command Line Tools 和 macOS。当前分发包针对 Apple Silicon。构建使用已提交的 go.mod/go.sum，首次构建需获取依赖。

```sh
make test
make app
open Sci-Station.app
```

`make headless` 生成可通过浏览器访问的本地服务。运行 `build/bin/sci-station-server serve -data-dir /path/to/test-data`，访问 `http://127.0.0.1:18765/research`。原生启动、系统日历和系统对话框使用桌面模式。首次试用可在独立目录启动 `Sci-Station.app/Contents/MacOS/sci-station app -data-dir /path/to/test-data`。

主要入口是 main.go、api.go、desktop_darwin.go，科研存储在 internal/research，会议编排在 internal/meeting，模型接入在 internal/gateway，界面在 static，应用打包脚本在 packaging/macos。原生启动窗口与 PDF 工具使用 Objective-C / AppKit / PDFKit，不需要 Swift 工程或 Python 服务。macOS 应用使用本地 ad-hoc 签名。
