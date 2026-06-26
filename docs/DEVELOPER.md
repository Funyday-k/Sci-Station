# 开发者文档：软件架构与功能开发

本文面向准备阅读、修改或扩展 Sci-Station 的开发者。产品介绍见 [../README.md](../README.md)，用户试用教程见 [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md)，新版开发文档中心见 [development/](development/)。

## 总体架构

Sci-Station 的核心形态是：macOS SwiftUI 应用 + 本地科研根目录 + 领域仓储服务 + 可选 AI 运行时。

```text
用户操作
  ↓
SwiftUI 视图层
  ↓
AppViewModel / 应用状态协调层
  ↓
领域服务与仓储
  ↓
Research Root 本地文件、SQLite、Keychain、可选系统集成
  ↓
界面刷新 / 任务记录 / AI 审计日志
```

设计原则：

- **本地优先**：默认读写用户选择的科研根目录，不把论文、笔记、任务和运行日志放进远端服务。
- **文件可读**：核心数据尽量使用 Markdown、YAML、BibTeX、PDF、图片、源码和普通数据文件。
- **领域分层**：论文、项目、任务、图谱、推荐、AI 等能力分别放在独立目录，UI 通过应用状态层组合。
- **AI 可选且可审计**：LLM 配置、工具权限、运行记录、证据引用和产物输出都有明确边界。
- **先模型后界面**：新增功能优先明确数据模型、持久化和验证，再接入 SwiftUI 交互。

## 代码目录地图

```text
Sci-Station/
├── Sci_StationApp.swift          应用入口、场景和设置窗口
├── ContentView.swift             根视图入口
├── App/                          AppViewModel、应用状态、首页数据
├── UI/                           SwiftUI 页面、组件、Shell、设置、首页、模块视图
├── Workspace/                    科研根目录、bookmark、创建/修复、偏好设置
├── Library/                      论文模型、元数据、仓储、搜索、标注
├── Importer/                     PDF 导入流水线
├── Import/                       DOI、arXiv、URL 等标识符导入服务
├── MetadataProviders/            Crossref、arXiv、INSPIRE 等元数据提供者
├── PDF/                          PDFKit 阅读器、阅读状态、标注支持
├── Markdown/                     Markdown、frontmatter、wikilink、backlink 支持
├── Wiki/                         Wiki 页面生成、编辑和索引
├── Collections/                  论文集合
├── Tags/                         标签模型与仓储
├── Tasks/                        待办模型与仓储
├── Calendar/                     本地日历模型和 Apple Calendar / Reminders 集成
├── Recommendation/               推荐工作流和推荐结果
├── Graph/                        论文/项目图谱数据与工作流
├── LLM/                          LLM provider 配置和调用抽象
├── Agent/                        AI Lab 模型、工具、权限、日志、runtime bridge
├── Localization/                 本地化支持
├── PluginKit/                    插件 manifest 和扩展点基础
├── Persistence/                  通用持久化支持
└── Testing/                      UI 测试标识、测试辅助常量

AgentRuntime/                     Python sidecar runtime 与 UI 测试编排器
Tools/SciStationCoreTestRunner/   SwiftPM 核心验证 runner
Tools/SciStationUIProbe/          UI 自动化探针
docs/                            项目文档、截图、开发资料
```

## 运行时层次

### 1. 应用入口与 Shell

[../Sci-Station/Sci_StationApp.swift](../Sci-Station/Sci_StationApp.swift) 负责 macOS 应用入口、窗口、设置和命令注册。[../Sci-Station/ContentView.swift](../Sci-Station/ContentView.swift) 进入根视图后，主要界面由 `UI/` 下的 Shell、首页、论文库、项目空间、PDF、Wiki、AI 实验室等页面组成。

Shell 相关文件集中在 [../Sci-Station/UI/Shell/](../Sci-Station/UI/Shell/)，负责侧边栏、项目空间 tab、路由持久化、工具栏命令和响应式布局。新增主导航或项目 tab 时，优先检查这里，而不是直接在某个页面里硬编码入口。

### 2. 应用状态协调层

[../Sci-Station/App/AppViewModel.swift](../Sci-Station/App/AppViewModel.swift) 是当前应用状态的主要协调者，负责把 Workspace、Library、Project、Wiki、Tasks、AI Lab 等领域服务组合给 UI 使用。

修改它时要注意：

- 不要把复杂业务逻辑长期堆在 ViewModel 里；能下沉到领域服务或仓储的逻辑应下沉。
- 很多状态是 `private(set)`，SwiftUI 视图应通过 ViewModel 方法或 binding 入口修改。
- 该项目使用 MainActor 默认隔离，跨 actor 或非隔离 helper 需要特别注意 Swift 6 并发警告。

### 3. 领域服务与仓储

每个业务域通常包含三类代码：

- **模型**：描述业务对象，例如论文、任务、图谱节点、推荐结果。
- **仓储**：负责从科研根目录读写 YAML、Markdown、JSONL、SQLite 或其它文件。
- **服务**：组织导入、搜索、生成、同步、转换、权限判断等操作。

新增功能时，优先找到最接近的领域目录。例如论文导入改 [../Sci-Station/Import/](../Sci-Station/Import/) 或 [../Sci-Station/Importer/](../Sci-Station/Importer/)，任务和阅读待办改 [../Sci-Station/Tasks/](../Sci-Station/Tasks/)，推荐改 [../Sci-Station/Recommendation/](../Sci-Station/Recommendation/)。只有确认领域层已经表达清楚后，再接 UI。

### 4. 本地科研根目录

科研根目录是产品的数据边界。应用应把用户数据写在用户选择的目录里，而不是写入源码仓库。

典型结构：

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

[../Sci-Station/Workspace/](../Sci-Station/Workspace/) 负责创建、打开、修复和恢复科研根目录。新增持久化文件时，应先判断它属于全局 workspace、library paper、project，还是 AI run artifact，避免把数据散落到难以备份的位置。

### 5. AI Lab 与 Agent runtime

AI 相关代码分两层：

- Swift 应用内的 [../Sci-Station/Agent/](../Sci-Station/Agent/) 和 [../Sci-Station/LLM/](../Sci-Station/LLM/)：负责生产默认 Swift Loop、配置、权限、工具定义、运行日志、UI 状态和 LLM 调用抽象。
- Python 的 [../AgentRuntime/](../AgentRuntime/)：负责实验性 sidecar runtime 原型、测试夹具和 UI 测试编排器。不要把 sidecar workflow 写成生产默认能力，除非对应 Proposal 明确升级。

AI 能力的边界：

- API Key、token、secret 必须进入 macOS 钥匙串或本机安全配置，不写入仓库和科研根目录的普通文本。
- 读操作可以自动化，但写操作必须经过权限模型和用户确认。
- 运行产物、证据引用、工具调用、错误和 debug bundle 要可回看；AI Lab 主界面应能展示 runtime、evidence、writeback、Prompt/MCP 等协作状态。
- 产品内置 preset 放在 [../.sci-ai/sci-station/](../.sci-ai/sci-station/)，本机桥接配置放在 `.sci-ai/workspace.local/`，不要提交本机 secret。
- 用户可管理的 Prompt override、Skill toggle 和 MCP server 覆盖配置放在 `.sci-station/agent/profile.json`。该文件属于 Research Root 本地状态；默认初始化为空列表，不写入 API key、token、完整 provider response 或完整运行记录。
- Prompt override 已进入 Swift Loop 执行链，并在 run metadata / `prompt_snapshot.json` 中记录 id、version、hash 和 surface。
- Prompt patch review 必须展示 diff、rationale/source、影响范围、rollback hint 和 Apply/Reject；`Restore Default` 表示移除 workspace override，不表示回滚历史 patch tree。
- Skill resolver 已进入 runtime：只加载 Profile 中明确启用且匹配的 Skill；workspace Skill 默认 untrusted，未显式 trusted 时不读取正文，且 Skill 只能收窄工具范围。Skill Manager 的导入/启用/信任必须有用户确认和 profile 审计路径。
- Local command MCP 只有在配置显式设置 `is_enabled: true` 时才启动；进程通过 stdio JSON-RPC 连接，不经过 shell。Remote HTTP/SSE MCP 支持实验性 JSON-RPC discovery、ping/liveness、credential reference 解析、失败/backoff 和 crash/credential 状态诊断。发现的工具使用 `mcp__<server>__<tool>` 名称，并始终经过 Agent approval、allowlist 和权限模型。
- 生产回答不能使用 synthetic/sample evidence。需要证据时必须来自真实 paper、PDF、Markdown、Wiki、Graph artifact 或其它本地来源；测试 fixture 必须清楚标注。

## 功能开发流程

### 新增一个用户可见功能

1. **确定所属领域**：先判断功能属于论文库、项目空间、Wiki、任务、图谱、推荐、AI，还是 Shell/设置。
2. **设计数据模型**：新增或扩展模型时，明确字段默认值、迁移策略、序列化格式和兼容旧数据的行为。
3. **实现仓储或服务**：把文件读写、网络导入、解析、索引、同步等逻辑放到领域层，不要直接写在 SwiftUI view 里。
4. **接入 AppViewModel**：通过窄方法或明确 binding 暴露给 UI。避免让视图直接修改深层仓储状态。
5. **构建 UI**：优先复用 `UI/` 下已有组件和设计 token。大页面拆成小 view，保持 body 清晰。
6. **补验证**：领域逻辑加到 `SciStationCoreTestRunner`；UI 或集成流程补手动测试文档；Python sidecar 改动跑 pytest。
7. **补文档**：用户可见行为更新 README/教程；开发流程或架构变化更新本文档或 `docs/development/`。

### 新增一个工作区模块或项目 tab

1. 在领域层准备模块数据和仓储。
2. 在 Shell 模型中定义 tab 或模块入口。
3. 在 builder/router 中注册显示名称、图标、路由和可用条件。
4. 在项目空间页面中接入对应 view。
5. 更新首页、快速操作或设置页中需要展示的模块状态。
6. 补手动测试：侧边栏入口、路由恢复、空状态、项目切换、窗口重启。

### 新增一个导入来源

1. 在 `Import/` 或 `MetadataProviders/` 增加 provider 或解析器。
2. 定义失败降级行为：网络失败、DNS 失败、元数据缺失时，应允许保存 link-only draft 或可恢复状态。
3. 把外部结果映射到论文元数据模型，不要把 provider 原始格式直接泄漏到 UI。
4. 在导入 UI 中展示明确的成功、部分成功、失败信息。
5. 补核心测试：标识符解析、元数据映射、失败降级、重复导入。

### 新增一个 AI 工具或工作流

1. 明确工具是只读还是写入；写入工具必须接权限确认。
2. 在 `Agent/` 中定义工具 schema、参数验证、错误分类和结果格式。
3. 如果需要 sidecar 编排，在 `AgentRuntime/` 中补协议和测试夹具。
4. 工具结果应引用证据位置，例如 paper id、wiki page、file path、section 或 task id。
5. 运行日志必须能复盘：输入、计划、工具调用、权限状态、输出和错误。
6. 补 UI 状态：pending、running、needs approval、failed、completed。

### 新增设置项

1. 判断设置属于应用偏好、workspace 设置、project 设置，还是 AI provider 设置。
2. 敏感值只存 Keychain；普通配置可写入 workspace 的 `settings.yaml` 或对应设置文件。
3. 设置页要提供当前值、空状态、验证错误和恢复默认入口。
4. 需要影响运行时的设置，应通过 ViewModel 或服务层统一刷新，不要让多个 view 各自读取文件。

## 验证入口

常用验证命令从仓库根目录执行：

```bash
swift run SciStationCoreTestRunner
```

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

```bash
python -m pytest AgentRuntime/tests
```

测试策略在 [development/testing/](development/testing/)，版本管理在 [development/versioning/](development/versioning/)，自动化 UI 测试编排器说明在 [../AgentRuntime/sci_station_agent/uitest/README.md](../AgentRuntime/sci_station_agent/uitest/README.md)。

## 开发约束

- 不提交私人 Research Root、论文 PDF、API key、token、`.env*`、`.mcp.json` 或本机 bridge 配置。
- 不把打包产物、DMG、zip、DerivedData、`.tmp/` 放入版本控制。
- 文档资料统一放在 `docs/`；根目录只保留主入口 README 和项目/构建必要文件。
- 新增 public-facing 功能时，同步考虑中文文案、英文说明、截图和手动测试路径。
- 保持本地文件格式可读、可恢复、可备份；不要为小功能引入难以审计的隐藏状态。
