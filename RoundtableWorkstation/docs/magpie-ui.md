# Magpie 界面对照：本机 v0.1.4572

核对目标：Magpie **0.1.4572**，固定源码提交 **`4716a77ff9f8e6bd7ff64780f81674de0fee805e`**。核对日期：2026-11-23。设置清单来自该版本源码，界面呈现另用同一提交的官方前端与测试数据核对。真实账号及第三方插件可见的选项随安装情况变化。下列英文是该提交的界面原文，中文解释其作用；切换语言后显示译文。账户、模型、终端、插件及其自定义选项由实际安装和返回数据决定，不虚构用户现有列表。

源码以固定提交为准；官网是**当前文档**，只用来旁证机制，不能据此认定本机已有后来功能。特别是官网 Library 概述只列七类，而本版源码实际有十二个常规标签及一个条件标签，见下表。[源码主页][S0]；[官方入门](https://usemagpie.ai/docs/start)、[Library](https://usemagpie.ai/docs/library)、[隐私](https://usemagpie.ai/docs/privacy)。

## 1. 先认清窗口和导航

主窗口按 Work / Models / Insights / Extend 分组，设置在侧栏底部。可切换侧栏与顶栏标签；侧栏可拖宽，导航页可隐藏、重排，Providers 始终保留。窄屏使用折叠导航及 More pages；这只是布局，不是增加功能。窗口顶部还有重新扫描本机 agents、置顶、搜索设置、更新提示。桌面有快捷面板；浏览器访问是同一服务的另一个入口，不是本机桌面功能全有。[S1][S2]

| 一级页 | 次级内容、弹层和主要状态 | 呈现与理解方式 |
| --- | --- | --- |
| **Agents** | 已发现 agent 列表、隐藏/未安装条目、每个 agent 的设置弹层；模型选择器、推理强度、速度；底部 Profiles 新建/使用/重命名/删除。支持新安装后重新扫描。 | 一行一个 agent，图标和名称在左，模型/设置在右；选择器有 provider 侧栏、筛选、收藏、可输入未列出的 ID；未连接、已连接、配置被外部改动、发现错误分别呈现。换模型主要改变 agent 自身配置，下次新会话生效。 |
| **Sessions** | 按 agent/目录分组，搜索标题和对话内容、筛选 token 大小、阅读会话；复制恢复命令、终端打开、导出 Markdown；批量移动、删除；Trash 内恢复/永久删除/清空。首次选择是否读取本机历史；可选记录 gateway conversations。 | 会话列表/分组与阅读区，用户/助手/工具内容可折叠，长内容按需加载；正在写入的原生会话不能随意移动；删除进 Magpie 垃圾箱，不等于立即永久删除。与 Usage → Sessions 的统计视图不同。 |
| **Library** | **Instructions / Memory / MCP servers / Skills / Hooks / Environment variables / Subagents / Slash commands / Rules / Claude plugins / RTK / billion-context**；有 Pi 时另有 **Pi packages**。每项有编辑/新增/导入、按 agent 分配；MCP 与 Skills 有 Discover；顶部 Library folder、Backups；支持项目范围、原生已有资源和冲突提示。 | 资源行 + agent 开关/分配矩阵，编辑器/市场/备份弹层；Skills 可 Links/Copies、By agent、Each agent's own folder/共享目录；MCP 包含命令或 URL、OAuth、逐工具控制及 MCP router。由 agent 自己决定何时用技能/子代理，Magpie 并不代替 agent 做任务调度。 |
| **Providers** | Add provider 分为 Partners、Subscriptions、From plugins、厂商/中转/本机服务/Custom；导入已有配置。行展开账户、模型、额度/余额、测试、启停与编辑；有重新登录、插件安装、删除确认等弹层。 | provider 行、账户行、模型 chips/表格、额度条、密码字段和按需 Advanced。订阅可多账号；API provider 可多 key；登录中/待浏览器完成/失败/不可用/关停/配额用完各有状态。不能把 provider 名称当作最终回答模型证据。 |
| **Routing** | 实时请求舞台、agent→gateway→provider/account 的去向；展开请求、失败尝试、限流休息、分类器/规则决定、token/耗时/速度；可筛选、改变展开层级、Hide accounts，跳转 Routing groups/Settings。 | 连线、流动标记和渐进展开的真实追踪；动态来自 gateway 记录，不是模型之间的聊天或模型模拟角色。无请求时是等待/空状态。 |
| **Routing groups** | 新建/编辑/复制/删除组，成员模型和账户、策略、规则、分类器、fallback；手动选成员、测试、可见性和限流处理等。 | 组列表、成员 chips、排序/权重、条件规则编辑器。组是一个可选的路由 ID，把一个请求送去一个合适成员；**不是同时让所有成员发言**。 |
| **Gateway** | 运行状态/URL、局域网地址；Gateway keys、Account groups、新 key/轮换/撤销/限额等；Connect 代码片段；Models、Copy all ids；Recent calls / Show more；页内设置。 | 紧凑状态卡、可折叠连接/模型列表、可复制代码和最近请求行。keys 区在共享或允许网页访问等条件下出现，本机 agent 通常无需额外 gateway key。 |
| **Usage** | **Overview / Requests / Sessions / Context**；时间范围 Today / 24 hours / 7 days / 30 days / All，部分视图另有自定义范围。Overview：额度卡、token/cache/cost 图及 agent/model/account/key 分组；Requests：多维筛选、趋势/热图、逐请求详情、Export CSV、Request archive；Sessions：项目/时间/工具/skills 等统计和会话入口；Context：prompt 各组成、缓存、窗口占用与详情。 | 额度卡、指标条、图表、可折叠分组、表格和详情页；loading、无样本、读取失败、估算/缺少速度等有不同提示。gateway totals 与原生 session-log calls 的口径不同，界面有范围说明；直连厂商调用不自动算进 gateway totals。 |
| **Masking** | 7/30 天汇总；按 agent/provider/kind 筛选；**By request / By value**；单条请求前后对照、占位符、发现方式及动作；跳转 Privacy/Try it。 | 数量/类别图、请求列表、值列表、差异/原始等详情视图。展示脱敏实际记录；未启用或尚无记录时显示相应空状态。不能把 Hide accounts 的截图模糊当作请求已脱敏。 |
| **Plugins** | **Built-in / Discover / Installed**；搜索插件/npm、来源/类别筛选、Mirrors in China、安装、更新、启停、删除、详情/README、登录；外部插件可以追加自己的页面和设置。 | Built-in 是功能开关行；Discover 是卡片/列表；Installed 带版本和状态。安装/下载 Bun/登录/错误/需要更新逐项显示；正在使用的内置能力不能直接关掉。第三方页面在隔离容器中加载，失败有 Try again。 |
| **Settings** | 最多九节，按启用能力显示，见下文；跨节搜索也会定位到 agent、provider、routing group 和 Built-in 对应选项；离开未保存编辑会提示。 | 标题左、控件右，短说明/提示按需展开；复杂项使用下拉菜单、输入字段、details → Advanced 或编辑弹层。不是每页都需要一整张大表单。 |

页面证据：[Agents/Providers 与公共外壳][S1]、[Sessions][S3]、[Library][S4]、[Routing 与 groups][S5]、[Gateway][S6]、[Usage 外壳][S7]及[行为][S8]、[Context][S9]、[Masking][S10]、[Plugins][S11]。

## 2. 设置页逐节、逐项

默认约定：下表的 **Off / On** 就是该项的两个显示选项；“模型列表/账户列表/终端列表”是动态内容，不是固定写死的选项。多数分段开关即时保存，地址/密钥/长文本等按界面显示的 Apply、Save、Enter 或离开输入框保存；失败保留错误提示，不能当作已生效。九个类别是可能出现的完整集合；没有可显示设置行或对应功能关闭时会隐藏，Plugins 还要求已安装插件提供 settings panel，Observability 依赖其内置功能。定义见 [index.html:179][S12]、[renderSettings][S13]。

### 2.1 General

| 原文项目 | 可见选项与含义/条件 |
| --- | --- |
| Appearance | **System / Light / Dark**；Omarchy 环境有跟随其主题的条件说明。 |
| Accent color | **Default / Blue / Teal / Green / Orange / Pink / Graphite / Custom color**。 |
| Background image | **Choose… / Change / Remove**；接受 PNG/JPEG/GIF/WebP，最多 16 MB。 |
| Colorblind mode；Reduce motion；Loading bird | 各 **Off / On**：色觉友好图表、减少动画、加载小鸟。 |
| Language | **System / English / 简体中文 / 繁體中文 / 日本語 / Deutsch**。 |
| Gateway mode | **Automatic / On / Off**；服务/容器用途的简化模式。代码直接隐藏 Agents；Library 在 agentless 状态精简为 Instructions/MCP servers/Skills，并非所有环境整个 Library 都消失。 |
| Sidebar pages | 每个可用一级页显示/隐藏、拖动或 Alt+↑/↓ 排序、**Default order**；Providers **Always shown**。只在主窗口有侧栏时显示，属于当前浏览器的布局选择。 |
| Get started | 重开入门引导。 |
| Text size | **100 / 110 / 115 / 120 / 125 / 150%**；桌面窗口/面板；浏览器用浏览器自己的缩放。 |
| Interface font；Code font | 各有 **Font family / Font style**；**System default** 和本机可用字体，条件状态 Loading / 不可读 / 字体缺失；浏览器使用可访问的字体机制，不能假定与桌面字体清单相同。 |
| Click the tray icon to | **Open the quick panel / Open the main window**；桌面。 |
| Quick panel shortcut | **Record shortcut / Type shortcut / Clear**；桌面，有快捷键冲突/系统不支持说明。 |
| Bar icon | **Off / On**；Omarchy bar 集成可用时。 |
| Provider in model names | **Off / Not on names I set / On**；控制 agent 模型显示名称的 provider 后缀，非路由切换。 |
| Open at login | **Off / On**；桌面，macOS 有系统登录项许可/管理提示。 |
| Gateway | **On / Paused**；桌面控制，暂停会断开已连接 agent 并恢复其原设置，不等于退出 app。 |
| Ask before quitting；Put agents back when quitting | 各 **Off / On**；桌面的退出确认、退出时恢复 agent 设置。 |
| Show in Dock | **Hide / With window / Show**；仅 macOS。 |
| Lightweight mode | **Off / On**；桌面关闭窗口后释放 WebView，gateway/任务继续。 |
| Prevent sleep | **Off / On / Screen on too**；保持计算机或连屏幕一起唤醒。 |
| Detect agents in WSL | **Off / On**；仅检测到 WSL 支持的 Windows 环境，本机 macOS 不显示。 |
| Session terminal | **System default (名称)**、发现的终端 app、固定当前默认项；失效选项显示 **Unavailable app**。桌面有可用终端时才显示。 |

证据：[app.js:19490][S14]、[appearance.js][S15]、[navpages.js][S2]、[Sessions 的设置模块][S16]、[provider 后缀][S17]。

### 2.2 Allowances

| 原文项目 | 可见选项与含义/条件 |
| --- | --- |
| Allowances in the menu bar | **Off**、各 provider 当前 **Account in use**、单个账户、**Tokens and cost today / Tokens and cost, last 7 days**，可多选。非 Mac 将 menu bar 文案换成 tray。 |
| Menu bar windows | 为已选订阅选择其窗口，例如 5-hour/weekly；**All windows** 或具体窗口，随 provider 返回。 |
| Menu bar refresh | **1 / 3 / 5 / 10 / 30 min**。 |
| Menu bar logos；Menu bar magpie icon；Menu bar pace；Menu bar cost | 各 **Off / On**；菜单栏相关项随平台/所选卡片显示。Pace 是相对于均匀使用进度的偏差，不是剩余额度。 |
| Menu bar Claude logo | **Claude / Anthropic**；仅 Mac、启用 logos 且所选卡中有 Claude 时。 |
| Tray icon number | **Off / On**；适用桌面平台，将首个额度数值作为托盘图标。 |
| Allowance display | **Used / Left**；影响额度显示方向。 |
| Allowance reads | **Automatic / When I ask**；后者只在显式打开/刷新额度等情况下重新读取，其他地方用上次结果。 |
| Currency | **$ USD / ¥ CNY / By provider**；余额自身币种不因此变成另一种。 |
| Totals in | **$ USD / ¥ CNY**；Currency=By provider 时显示。 |
| Day starts at | **0:00–6:00**，逐小时。 |
| Number units | **K / M / B / 万 / 亿**；简中或繁中界面条件显示。 |
| Advanced → Menu bar currency | **Same as totals / $ USD / ¥ CNY**。 |
| Allowance alert | **Off / On** + 已用比例输入 **1–100%**。 |
| Low balance alert | **Off / On** + 正数阈值；使用该余额自己的币种或 credits。 |
| Reset reminder | **Off / 12 h before / 24 h before / 48 h before**；已有自定义值也会显示。 |
| Task done alert | **Off / 1 min / 3 min / 10 min**；任务至少持续该时长才通知，已有自定义秒数亦保留。 |
| Bark | **Server / Device key / Save / Test / Remove**；将通知转发到该服务。 |
| Bark daily summary | **Off / On** + **Time of day**；配置 Bark 后条件出现。 |

provider 的 warm-up/check-in 已移到对应 provider 编辑器，agent 的专属设置在 Agents 页；这里的入口可跳转，不能误当作全部全局选项。菜单栏/托盘行取决于平台；gateway mode 隐藏部分通知行。[额度与告警][S18]、[traywindows.js][S19]、[币种][S20]、[Bark][S21]。

### 2.3 Network and sharing

| 节/项目原文 | 可见选项与含义/条件 |
| --- | --- |
| Proxy | **Auto / Off / Custom**；有保存的代理时还可选保存项。Custom 展开 **Proxy address / Username (optional) / Password (optional) / Save**，有连接检测/诊断结果。 |
| Plugin downloads；App updates | 各 **Same as above / Direct / Custom**，可使用已保存代理；分别控制插件/npm/GitHub 下载及 app 更新，不改变所有模型路由。 |
| Proxies | **Add proxy**；**Proxy / SSH**；**Name / Proxy address 或 SSH server / User 或 Username / Password**；SSH **Advanced → Private key / Host key / Trust a new key**；保存、编辑、移除、连接状态。 |
| GitHub → GitHub token | 可填/保存/移除个人 token，帮助读取公共资源/避免限流；不是 GitHub sync 的独立凭据字段。 |
| Gateway → Gateway port | 数字 **1024–65535 / Apply**，默认示例 3425；`MAGPIE_ADDR` 覆盖时改叫 **Gateway address**，字段只读并说明覆盖来源。会迁移 Magpie 自己连接过的 agent。 |
| Model ids without the provider | **Off / On / Only**；控制模型清单是否另外/仅列裸 ID，可能影响同名模型的解析。 |
| Local network → Share on local network | **Off / On**；显示 **Address** 和 **OpenAI / Anthropic** 连接片段，其他计算机需 gateway key。 |
| Join with a password；Join link | **Password / New password / Set / Turn off joining**；启用后显示加入链接。其他计算机使用链接和密码取得自己的 gateway key 及 agent 设置，不是浏览器管理授权。 |
| Allowed addresses | IP/CIDR 输入、**Add / Remove**；共享/网络环境或环境变量设置时显示；环境变量覆盖时只读。 |
| Require a client certificate | **Off / On**；网络入口的 mTLS；**Client certificates / Device name / Issue / Revoke**，带有效期；不是普通 API key。 |
| HTTPS | **Off / On**；共享或已启用时显示；**Certificate / Import… / Remove**，自有证书或 Magpie CA；**magpie’s CA / Save**、下载/信任指引。 |
| Web pages → Web pages that may call magpie | **Web page origin / Add / Remove**；按 origin 允许浏览器脚本调用 gateway，不能当作“打开管理网页”。 |
| Browser access → Open magpie in a browser | **Off / This computer / Local network**；展开 **Link**（复制/重建 key）和 **Port / Apply**；HTTP 局域网有 **Not encrypted** 提示。管理网页端口与模型 gateway 端口不同。 |
| Another magpie | **Address / Key / Open / Forget**；连接另一台 Magpie 管理页面的入口，按它的地址/key 检查；不是在此编辑另一台的本地配置。 |
| Advanced → Name | 自定义当前 Magpie 在浏览器 tab 中的名称。 |

证据：[代理与 GitHub][S22]、[保存代理][S23]、[gateway 网络设置][S24]、[实例名][S25]；机制旁证：[官方 Remote](https://usemagpie.ai/docs/remote)。本表仅说明控件，不包含用户实际地址、key 或证书。

### 2.4 Models

| 节/项目原文 | 可见选项与含义/条件 |
| --- | --- |
| Images → Image recognition | **Automatic / Off / 支持图像的模型列表**；无法看图的当前模型由其转述图像；Off 时相关图像请求可被拒绝，非静默忽略。 |
| Image generation | **Automatic / Off / 可生成图像的模型列表**；**Give agents Magpie Image…** 为 Library 分配入口，**MCP server** 有可复制地址。 |
| Video generation | **Automatic / 可生成视频的模型列表**；条件出现；Image generation=Off 时一并停用该工具。 |
| Image resolution | **Automatic / 1K / 2K / 4K**，模型不能达到时按其自身能力。 |
| Image generation timeout | **5 / 10 / 15 / 30 / 60 min**；已有自定义值也显示。 |
| Web search → Searches for other models | **Automatic / Off / provider 的原生搜索或指定模型**；模型选择器可带推理强度。 |
| If it fails | 按序添加/移除指定搜索 provider/model，限制失败后的接替名单。 |
| Search APIs | **Search API / API key / Base URL 或 Address / Get a key ↗ / Add**；保存后逐项启停、移除、拖动排序；多 key 有 **Show / Copy / Add / Remove**、启停和 **In turn / In order**。可选厂商来自该版服务端目录/插件，不读取用户 key。 |
| Search first with | **Model search / Search APIs**；两者都配置时出现。 |
| Models that search by themselves | **Their own / magpie’s**；Magpie 没有搜索源时不能选其代搜。 |
| Results per search | **3 / 6 / 10 / 15 / 20**（并显示已有自定义值）。 |
| MCP server | 搜索的 Streamable HTTP 地址、复制及 **Give agents Magpie Web Search…** 入口。 |
| Advanced → Ask the search APIs | **In order / All at once**；至少两个已启用搜索 API 时出现，后者合并去重。 |
| Quick check → Test all | 为所列辅助模型逐个做真实调用；不是纯连通性检查，也不是不消耗额度的按钮。 |
| Replies → Model name in replies | **The model asked for / The member that answered / The vendor’s own name**；选择返回 metadata 的名称口径，不能据此改变模型身份或能力。 |
| Stop looping replies | **Off / On**；识别循环文本后以可重试错误结束。 |
| Routing → Ask again after a refusal | **Never ask again / 1 / 2 / 3 / All**；已有自定义次数保留。 |
| Longest wait an agent is told | **1 / 5 / 15 min / No limit**；已有自定义值保留；改变告诉 agent 的等待，不改变账户实际休息时长。 |
| Intent classifier timeout | **8 / 15 / 30 / 60 s**，默认15秒；合法自定义值可能另列。 |
| Busy models last | **Off / Over 50% / Over 70% / Over 80% / Over 90% / Custom…**；自定义 1–9999%；依赖插件报告模型负载。 |
| Longest context | token 大小输入或 **None**；作用于 **Models without their own / Every model**。 |
| Disabled models → Disable a model | 模型选择器逐项禁用、恢复；已有项不等于 provider 已被删除。 |

证据：[图像与回复][S26]、[搜索设置][S27]、[视频与分辨率][S28]、[busy/context][S24]；机制旁证：[官方 Intent routing](https://usemagpie.ai/docs/intent)。

### 2.5 Privacy

| 节/项目原文 | 可见选项与含义/条件 |
| --- | --- |
| How it’s found → Find with a local model | **Off / On**，模型 **AstrLink Guard / Privacy Filter**（可用性依系统而异）；下载/启动/运行/失败状态，**Cancel / Delete model**；模型目录选择/移动入口。 |
| Confidence threshold | **Default** 及 **0.5 / 0.6 / 0.7 / 0.8 / 0.85 / 0.9 / 0.95**；高阈值通常少脱敏、少误报。 |
| Rules | **Always on / Off** 状态行；规则识别与本地模型识别是两个来源。 |
| What to mask → Mask secrets；Mask personal data | 各 **Off / On**；分别处理秘密与个人信息。 |
| Keep a key’s form | **Off / On**；Mask secrets 开时出现，用相同外形的替代值而非普通占位符。 |
| 个人信息细类 | Mask personal data 开时逐项 **Off / On**：**Social Security numbers / Passport numbers / IBANs / Birthdays / MAC addresses / Serial numbers / User name in home folders / User and computer names / Public IP addresses / Cloud storage buckets**。基础邮箱/电话/身份证/银行卡也由总开关管理。 |
| Masked words；Never mask | 逐词编辑、添加/删除，支持 **Import… / Copy** 和多词粘贴；前者强制脱敏，后者保留原值。 |
| Masked words in any case；Whole words only | 各 **Off / On**，控制自定词的大小写与词边界匹配。 |
| Masking rules | 类别/占位符名（提示 **API_KEY**）、**Prefix / Regex**、匹配式、**Add / Edit / Remove / Import… / Copy**；为内置规则不认识的值补规则。 |
| Instead of masking, send to | **Off / 被明确允许接收未脱敏请求的模型列表**；这会把原值交给所选模型，不等同于增强脱敏。 |
| Sent unmasked | 列出已被单独允许未脱敏请求的 provider；点击去其编辑器修改。 |
| When a value is found | 各类 **Mask / Warn / Block**；有 **Show all kinds / Show fewer**。类别包括 API key/private key/token/password/secret、邮箱/电话/姓名/地址/账号/身份号等；只有检测到并启用相应类才有作用。 |
| Try it | 输入样例，显示 **What the vendor would get**、发现项及 Masked/Sent as written/Held back；只在本机预览，不是发送模型请求。 |
| Masking alert | **Off / On**；插件动态补入的脱敏通知选项。 |
| Sharing → Hide accounts | **Off / On**；只是界面账号名/邮箱模糊，适合截图，不改变发给厂商的请求。 |
| Turn off telemetry for all agents | **Off / On**；覆盖 agent 各自的 Telemetry 开关，下次 agent 启动生效。 |
| Count me as a user | **Off / On**；Magpie 自身的匿名使用计数。 |
| Share the agents, providers, models and plugins I use | **Off / On**；Count me as a user 开时出现，附加所用公开 ID/数量等，不是开放 prompt/密钥。 |
| Agents’ sign-ins → Subscription accounts | **Off / On**；是否读取本机 agent 的登录文件/Keychain 并提供订阅；关掉会影响订阅源，API-key provider 保留。环境变量可强制本次关闭。 |
| Sign-in pages → Open sign-in pages in the browser | **Off / On**；关掉仅给登录链接，用户自己选择浏览器。 |
| Agents’ session history | **Agents found later** 和每个发现的 agent 各 **Off / On**；与订阅登录读取分开。Gateway mode 不读取这里的本机历史。 |

证据：[Privacy 核心][S29]、[动态词表/路由/提醒][S30]、[原生历史读取][S16]、[模型目录][S31]；旁证：[官方隐私](https://usemagpie.ai/docs/privacy)、[官方 masking](https://usemagpie.ai/docs/masking)。三种“隐私开关”必须分清：**隐藏显示、改变请求、读取本机资料**。

### 2.6 Observability

三节：**Collector connection / Export scope / Trace content**。[S32]

| 原文项目 | 可见选项与含义/条件 |
| --- | --- |
| OTLP export | **Off / On**；启用向用户选择的 collector 导出。 |
| Collector | **OTLP / Langfuse**。 |
| OTLP endpoint；OTLP headers | endpoint 地址、逗号分隔 header 字段；选择通用 OTLP 时。 |
| Langfuse host | **Cloud EU / Cloud US / Self-hosted** + 自托管地址。 |
| API keys | **Public key / Secret key**；Langfuse 分支。 |
| Export metrics；Trace agent conversations | 各 **Off / On**。后者可读取原生会话（包括未经 Magpie 的调用），与只导出 gateway metadata 范围不同。 |
| Request and response content | **Metadata only / Up to 256 KB / Full content**；带脱敏，不代表完整内容一定被 collector 接受。环境变量覆盖时界面提示。 |

### 2.7 Sync and backup

主行根据状态叫 **WebDAV, S3 or GitHub sync / WebDAV sync / S3 sync / GitHub sync**，支持 **Set up / Edit / Sync now**。以下是展开后的实际字段及附属行。[S33][S34][S35]

| 项目/分支 | 可见字段与选项 |
| --- | --- |
| Sync to | **WebDAV / S3 / GitHub**；**Passphrase**；已有服务配置可保留并切换。 |
| WebDAV | **Address / User / Password**。 |
| S3 | **Endpoint / Bucket / Prefix / Region / Access key / Secret**；**Path-style: the bucket in the path, not the host name**。 |
| GitHub | **Repository / Branch / Folder / GitHub token**；该 token 与通用 GitHub 下载 token 分开。 |
| What syncs | **Providers / With their API keys / Settings / Agents’ models / Library… / Memory…**；未勾选部分在各机保留自身状态。 |
| Advanced | **Profiles / Usage: this computer’s calls… / Sign-ins: subscription accounts and plugin sign-ins / Not synced**（选择不共享登录的订阅）。共享 sign-ins 明显扩大备份/同步内容，默认不等于只同步界面偏好。 |
| 表单动作 | **Turn on / Save / Move sync to… / Turn off / Cancel / Copy setup / Preview**。 |
| Sync by itself | **Off / 3 min / 15 min / 30 min / 1 hour**。 |
| This computer | **Both ways / Follows the server**。 |
| 条件行 | **Kept on this computer / Follow the others**；**Upload this computer’s setup / Upload…**；**Restore from the server / Restore…**；**Preview a sync / Preview…**；**Undo the last sync / Undo… / Undo anyway**。 |
| Export | passphrase 输入两遍；可选 **With the providers’ API keys / With the library… / With memory… / With the usage history / With the sign-ins…**，**Export / Cancel**。 |
| Import | **File / Choose… / Passphrase**；**Set the agents’ models too / Bring in the library too / Bring in memory too / Bring in the usage history too / Bring in the sign-ins too**；**Import / Cancel**。 |
| Back up by itself | **Off / 1 hour / 6 hours / 1 day / 1 week**。 |
| Versions kept | **3 / 7 / 14 / 30**。 |
| Sign-ins in backups | **Off / On** + passphrase；不打开时不能假定含账户登录。 |
| Backup folder；Versions；Data folder | 选择/打开/移动目录；**Back up now**、版本查看/恢复/删除及恢复确认等；状态含备份中、无变化、成功、失败、尚无备份。 |

### 2.8 Plugins

Settings → Plugins 是第三方插件 **settings slot** 的入口，不是重复的插件市场；没有提供该面板的插件时整节隐藏。表单选项来自当前安装插件的 schema，随插件而变，**仅靠公共源码不能列出用户本机尚未读取的插件自定义字段**；本次不进入其账户/配置去补猜。插件的安装/启停在一级 Plugins 页。[index.html:502](https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/index.html#L502)、[pluginpages.js][S36]

Built-in 的完整固定功能名为：**Gateway page / Key limits / Routing groups / Library / JS gateway plugins / Observability / Privacy masking / Routing strategies / Routing / Web search / Sessions / Plugin tools / Usage / Warm-up and check-in**。主要是 **Off / On**；In use 时禁止关闭。Gateway 页自己的 **Recent calls at a time = 10 / 20 / 50 / 100**。这些状态页关闭不一概等于核心 gateway 停止；例如 Usage 页关闭，gateway 仍计数。证据：[内置插件定义][S37]、[Built-in 表单][S38]。

### 2.9 About

| 原文项目 | 可见操作/选项 |
| --- | --- |
| Version | 当前版本、检查/下载/安装/重启更新状态；已是最新版、下载中、失败等分开呈现。 |
| What’s new | **Open**；正式语义版本发布才有相应记录入口。 |
| Update button | **Off / On**；暂时 **Hidden for 3 days / Show again**。 |
| Automatic updates | **Off / On**。 |
| Update check interval | **30 min / 1 h / 6 h / 24 h**；自动更新关时保留但置灰。 |
| Update channel | **Every version / Daily / Stable**；是更新频率/渠道选择，不是模型稳定性。 |
| Download updates automatically；Restart automatically | 各 **Off / On**；重启需等待不会截断 agent 请求的时机。 |
| Download source | 下载源说明及 **Use a mirror… / Change / Remove mirror / How mirrors work**。 |
| Update source | **Automatic / usemagpie.ai only / GitHub only**；镜像下载仍核对校验和/签名。 |
| Config folder；Log | 路径显示、复制、**Open**；Log 仅该服务提供本地日志路径时。本文不写用户实际路径。 |
| Command line | 检查 shell，安装/移除命令入口；`claude-magpie` 相关启动器随本版支持。 |
| Gateway URL；Public address | 地址复制；Public address 在声明该公共地址时条件出现。 |
| Status line on another computer | 命令复制；浏览器服务界面条件出现。 |
| Website；Open-source licenses；Community；Report a problem | **Open / View / Join Discord / GitHub**；问题反馈先复制诊断事实，再打开外部入口。 |
| Uninstall magpie | **Uninstall…** + 确认/恢复 agent 配置；只在桌面显示，远程浏览器不提供卸载服务宿主的操作。 |

证据：[About 的实际生成][S39]、[更新源][S40]、[更新信任提示][S41]。

## 3. 不在全局 Settings 的专属设置

这些很容易漏掉：它们可能通过设置搜索找到，但实际编辑位置是 **Agents/Providers/模型右键/组编辑器**。不应把它们复制成圆桌的通用偏好。

| 位置 | 本版实际字段/选项与边界 |
| --- | --- |
| Agent → 专属设置 | 通用 **Telemetry**、按该 agent 返回的字段与 **Advanced → Not set / 其原生选项**。Codex：**Codex subagents on any model / Codex subagent model / Open Codex with**（Automatic/Codex app/Terminal）、**Codex service tier**（As Codex asks/Standard/Fast/Ultrafast）、**Codex client**（Codex CLI/Codex Desktop）、**Long conversations**（Compact at 大小/Full window）、**Codex background compaction**（Off/On + 比例）、**Codex thread titles / thread descriptions / composer predictions / prompt suggestions / auto-review model / memories model**（其自身选择/同会话/指定模型/关闭，依该项支持）。[S42] |
| Claude 与其他 agent → 专属设置 | **Long conversations**、适用 agent 的 **Context window**；Claude **Prompt cache · main conversation / Prompt cache · subagents**（Claude Code’s default/5 min/1 hour）、**Commit signature (Co-Authored-By)**（On/Off，已有自定文本显示 Your own text）、原生许可等字段。模型速度有 **Usual / Fast / Ultrafast**（模型与 provider 支持时），不是所有席位共有。[S43] |
| 订阅 provider → warm-up、reset、check-in | ChatGPT/Claude **Warm up on reset**（Off/Weekly/Weekly and 5-hour）、**Daily warm-up**（Off/On + 时刻，可多个）、**Warm up now**；ChatGPT 每账户 **Auto-use resets**：**when its week runs out / before one expires** 两种场景独立 Off/On，**How early before one expires** 预设 **3/5/10/15/30/60/120/180/360/720/1440 min**，**Use a reset** 确认；账户自己的 **Same / Own / Off** 时间。适用 provider **Daily check-in**（Off/On、时间、每账户、立即签到）。这些会真实调用服务或消耗 reset，非无成本 UI 演示。[S44] |
| Claude 订阅 provider | **Short Claude system prompt / Spend extra usage** 各 Off/On；后者有账单意义，前者有请求外形/账户风险说明，均只留 Magpie 管理。[S26] |
| Provider 编辑器 → 基础 | **Name / ID / Region / Account(s) 或 API key / Endpoint(s) / Base URL / Server address / Models / Routing / Fallback**；订阅选择账户、API provider 选择 keys。Custom 可有多种 API endpoint、Models URL、Catalog、Icon。Vertex 等特例还有 **Project ID / Location / Credentials file / Service account**；其他厂商按 preset 出现 Workspace/Team org/Team project 等字段，不能泛化给全部 provider。[S45] |
| Provider → Advanced / Model settings | **Context window / Max output / Compact at / Compaction**、Headers、Extra body、Reply headers、Request headers to pass、Proxy、Web search、Key header（Both/x-api-key/Authorization: Bearer）、User-Agent、Certificate/TLS、HTTP version、Rests、Errors、Images、Account balance / Balance URL / Balance field；**Send requests unmasked** 只在适用本机/局域网 provider。模型可调名称/裸ID映射/价格/推理 levels、Accepts images、Makes 图像/视频、Images per request，动态能力决定控件。[S45] |
| Provider/Group → 路由策略 | Provider 可有 **Smart / In order / Until used up / In turn / Least used first / Use before expiry / By weight / Free first / Speed first**；组的对应额度优先项显示 **Quota first**，还可有 **Cheapest first / Free quota by expiry / Small context first / Manual** 与插件策略。**Stays = Auto / Session / Within a turn / Off / Strict**；**Rate limited = Keeps its place / Goes to the back**。[S46] |
| Routing group 编辑器 | **Name / Note / In agents’ lists / Models / Accounts / Gateway keys / Masking / Patterns / Model lists / Routing / Rate limited / Slow to start / Every member busy / Context / Compact at / Stays**；规则可组合 intent、token长度、图像、推理、agent 等条件，选 classifier、目标模型/effort，调整优先顺序。是路由条件，不是多模型会谈成员表。[S5] |
| Gateway key 编辑器 | **Name / Models 与账户范围 / Gateway key**；菜单 **Enable/Disable key / Make read-only 或 Give full access / MCP servers / Model names / Keep accounts out / Rotate key / Remove**；**Advanced → Management API / Magpie Memory**；concurrency **1/2/3/5/10/No limit/Other**（最多1000）；service tier **As the request asks / Standard / Fast / Ultrafast**；masking **Follow Settings / On / Off**；token/cost限额与周期、查看/重置使用。允许范围与预算是 key 的权限，不是圆桌编辑文件权限。[S47] |
| Library → MCP router / 项目资源 | MCP 是独立命令或远程 URL，字段包括 name/transport/command/args/env/headers/OAuth，按 agent/项目分配；router 把多个 MCP 合成单入口，支持共享与工具选择。Library 子代理模型是原生 agent 配置，**与圆桌自己的 children 记录不是同一个系统**。[S4]；[官方 MCP router](https://usemagpie.ai/docs/mcp-router)。 |

## 4. 状态与呈现手法：可以学什么

- **主行先说当前值**：名称左、值/分段选择在右；自定义内容才展开字段。连接、账号发现、缺模型等用就地说明，错误不伪装成成功；控制台错误不等于用户已看到可理解反馈。
- **渐进展示**：Advanced 折叠、模型/账户列表按需打开、长会话和工具结果折叠、详情页返回原位置；主操作和当前状态常显。小字解释能转换成提示，不能直接全部省掉。
- **可核对的来源**：Usage/路由展示是请求、账户、模型和时间的数据，不是“AI 已完成”装饰。Context、Masking 的概览都能下钻到请求级细节；未知、估算和读取失败单独标识。
- **平台差异**：Mac Dock/menu bar、Windows WSL、Omarchy bar、桌面快捷键/终端与浏览器服务不是同一套可用功能。网页访问远程 Magpie 时，“本机”一般指运行服务的计算机；当前浏览器的导航布局则留在浏览器。
- **视觉基底**：`app.css:756` 卡片细边框/12px圆角，`:762` 紧凑 flex 行，`:764` 行间分隔，`:770/772` 主值/弱说明，`:3903` 分段控件，`:5479` Advanced；`settingshints.js` 控制长说明的按需呈现。移植交互关系，不把本机小字号或密度直接当圆桌通用字号。[S48]

## 5. 圆桌迁移边界

**适合迁移到圆桌**：清楚的主导航、席位模型选择器、紧凑且可展开的连接设置、真实连接检查结果、会话列表/聊天时间线、主 agent 与私有子任务分层、可下钻事件/文件 diff、取消与失败/重试状态、导出、主题/字号/减少动画等圆桌自身偏好。每项只说明圆桌真实支持的行为；保留“请求模型/实际返回标识/传输路径”的区别。

**只由 Magpie 管理**：账户登录/Keychain、订阅额度与 credits/resets/warm-up/check-in、provider/key凭据、多账户轮转与fallback、gateway监听/共享/IP/证书/浏览器授权、厂商价格与真实路由、脱敏模型/例外、MCP与Library向原生agent配置的分发、OTLP、Magpie同步/备份/更新/卸载。圆桌只需显示连接 Magpie 的方式、选定模型和可得的诊断；不要复制另一套账号、路由、额度或密钥管理，也不要为了“学完整UI”自动打开这些高影响操作。

**本次圆桌已采用的设计选择**（实现范围，非用户测试结论）：

- 群聊按时间排列，两位主 agent 的头像旁显示名称与当次型号。子代理报告和文件差异分别在右侧面板阅读。正文和发送操作获得主要空间，必要的过程证据仍可找到。这是对 [NN/g：Aesthetic and Minimalist Design](https://www.nngroup.com/articles/aesthetic-minimalist-design/) 的应用：减少与当前任务争夺注意力的内容，同时保留完成任务所需信息。
- 连接来源使用三条紧凑设置行，当前检测结果常显；地址、CLI 路径、模型选择和诊断细节在各行展开，超时留在“协作”折叠项。展开控件说明其内容，靠近被展开的设置，主要状态不随折叠丢失；依据 [Apple HIG：Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)。这是借用披露层级原则，不声称网页控件就是原生 macOS 控件。
- 新建任务时项目选择放在任务旁，运行输入附近放收件人；较少改变的连接/协作偏好留在设置。设置入口固定在左侧栏底部。本机 CLI 清单只显示安装情况，各席的模型可以从目录选择或手动输入。将任务选项留在其上下文、减少全局设置数量，依据 [Apple HIG：Settings](https://developer.apple.com/design/human-interface-guidelines/settings)。

文件改动采用聊天旁的按文件审阅面板，行数显示增删方向，文档还可以按字或词查看。[Codex 代码审阅](https://learn.chatgpt.com/docs/code-review?surface=app)

**核对范围**包括固定提交的窗口、导航、内置页面、设置和动态模块。同一提交的浏览器实测留下 44 张状态截图，覆盖十个业务一级页、八个实际可见设置节、Library 十二标签，以及 provider 编辑/Advanced、网络展开、搜索、Gateway Connect 和端口占用状态。它使用临时测试数据、拦截网络；**不是本机 Wails 桌面、真实账户或模型服务验证**。无插件时 Settings → Plugins 本来就隐藏，没有把其回退到 General 的截图算作验证。渲染佐证布局与分支显示，不能证明账户连接、通知、文件分发或模型调用成功。

参考界面使用独立测试数据。用户实际启用的第三方插件、服务端动态模型/账户/终端清单及真实通知效果尚未逐项操作；本文不宣称已读取其私人数据或验证每个运行结果。

## 源码索引（全部固定在同一提交）

上文链接均指向以下固定版本文件；官网机制说明和设计规范则明确使用其当前公开页面。

[S0]: https://github.com/yetone/magpie/tree/4716a77ff9f8e6bd7ff64780f81674de0fee805e
[S1]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/index.html#L42
[S2]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/navpages.js#L1
[S3]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/sessions/client.js#L630
[S4]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/library/client.js#L1007
[S5]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/routing/client.js#L19
[S6]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/gateway/client.js#L889
[S7]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/usage/client.js#L14
[S8]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/usage/page.js#L4207
[S9]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/context.js#L1
[S10]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/redact/page.js#L1
[S11]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins.js#L938
[S12]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/index.html#L179
[S13]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20131
[S14]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L19490
[S15]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/appearance.js#L1
[S16]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/sessions/settings.js#L1
[S17]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20675
[S18]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20755
[S19]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/traywindows.js#L1
[S20]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/currencyprefs.js#L1
[S21]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/bark.js#L1
[S22]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20917
[S23]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/proxies.js#L1
[S24]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/gateway/settings.js#L1
[S25]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/instancename.js#L1
[S26]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L21635
[S27]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/search/settings.js#L1
[S28]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/videogen.js#L1
[S29]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L21962
[S30]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/redact/settings.js#L1
[S31]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/pmfolder.js#L1
[S32]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/otel/page.js#L85
[S33]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20435
[S34]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/syncfiles.js#L1
[S35]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/autobackup.js#L1
[S36]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/pluginpages.js#L1
[S37]: https://github.com/yetone/magpie/tree/4716a77ff9f8e6bd7ff64780f81674de0fee805e/plugins
[S38]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L23474
[S39]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L20264
[S40]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/updatesource.js#L1
[S41]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/updatetrust.js#L1
[S42]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L21293
[S43]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/agentcompact.js#L1
[S44]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/autoresetown.js#L1
[S45]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L9493
[S46]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.js#L12479
[S47]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/plugins/gateway/keys.js#L327
[S48]: https://github.com/yetone/magpie/blob/4716a77ff9f8e6bd7ff64780f81674de0fee805e/internal/gui/assets/app.css#L756
