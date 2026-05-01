# 任务书 21：Library Table V2 与 GitHub Copilot SDK 接口适配

更新时间：2026-05-01

## 1. 本轮结论

任务书 20 已完成 AI Lab Thread 管理与计划复用 V1：thread 重命名、归档/隐藏、空 pending draft 丢弃、历史 orphan run 手动归并、thread-level prompt draft 持久化、历史 prompt 复制到 New Chat，以及未来 Auto Run Loop 的权限矩阵与停止条件说明均已落地。

下一阶段应回到任务书 17 顺延下来的 Library Table V2。Library 是 Sci-Station 的核心入口，V1 已经切换到 SwiftUI `Table` 并完成排序、多选和 BibTeX 复制/导出，但列顺序/列宽持久化、选择集批量编辑和 Quick Look 仍未收口。

同时，本轮需要按 `DOC/Github Copilot` 接入手册为 AI Lab 增加 GitHub Copilot SDK 接口适配方案：现有 Copilot Bridge 仍保留为 prompt/manifest 文件导出，但新的接口边界应面向 GitHub OAuth / GitHub App user token、每用户独立 Copilot SDK client、token 生命周期管理和组织访问校验。由于 Sci-Station 是 macOS 桌面应用，本轮不得把 GitHub OAuth client secret 或用户 token 写入普通 workspace 配置；如需 token exchange，应通过安全后端、GitHub App flow 或后续明确的 OAuth relay 完成。

因此任务书 21 的主线是：完成 Library Table V2 的高频生产力能力，并为 AI Lab 引入 GitHub Copilot SDK 适配接口的本地抽象、配置边界和安全文档，不急于替换现有 LLM provider 或启用自动连续执行。

## 2. 当前代码基线

- `LibraryPaperTableView` 已使用 SwiftUI `Table` 渲染 `appModel.filteredPapers`。
- `LibraryColumn` 已包含 title、authors、year、projects、coreProjects、collection、publication、itemType、doi、arxiv、wiki、tags、status、priority、rating、updated。
- `workspace_preferences.yaml` 已保存 `libraryVisibleColumns` 和 `librarySortState`。
- SwiftUI `TableColumnBuilder` 当前不适合按任意 workspace 列顺序动态生成完整列集合，任务书 17 暂停了列拖拽和任意列顺序恢复。
- `selectedLibraryPaperIDs` 已支持多选；Inspector 多选摘要、Copy Citation、Copy BibTeX 和选择集 BibTeX 导出已落地。
- 单篇论文右键菜单保留 Read in App、Open PDF、Export BibTeX、项目关系菜单和 Delete Paper。
- `PDFOpeningService`、内置 Reader 和 `PDFReaderViewModel` 已存在，可为 Quick Look / Space 预览提供入口。
- `AgentCopilotBridgeExporter` 当前只导出 `.sci-station/agent/copilot-bridge/*.prompt.md` 和 manifest，不直接调用 Copilot SDK。
- `LLMProvider` 当前只有 OpenAI-compatible provider；LLM API key 通过 Keychain 保存，`settings.yaml` 不写入 API key。
- AI Lab 已有 plan-only、逐项 tool approval、thread timeline、prompt draft 持久化和 Copilot Bridge export。

## 3. 执行任务

### 3.1 Library 列布局 V2

1. 重新评估 SwiftUI `Table` 在当前 macOS target 下对列宽、列顺序和列显示状态的支持：
   - 优先继续使用 SwiftUI `Table`。
   - 若任意列顺序/列宽持久化仍受阻，应记录明确阻塞，并只实现可稳定维护的替代方案。
   - 只有 SwiftUI `Table` 无法满足 V2 核心需求时，才评估局部 `NSTableView` wrapper。
2. 扩展 workspace preferences 的 Library 列布局状态：
   - 保留旧 `libraryVisibleColumns` 兼容读取。
   - 新增可选 column order / width 状态时必须有默认值。
   - 旧 preferences 缺少新字段时仍能读取。
3. 提供用户可理解的列管理入口：
   - Show / Hide column。
   - Reset Columns。
   - 如不能支持拖拽列顺序，则提供 Move Earlier / Move Later 的菜单或设置入口。
4. 默认列不应突变；用户已有可见列偏好应继续生效。

### 3.2 Library 选择集批量编辑

1. 在多选 Inspector 或右键菜单中增加低风险批量操作：
   - Set Status。
   - Set Priority。
   - Set Rating。
   - Move to Folder / Collection。
   - Add Tags。
   - Remove Tags。
2. 批量项目关系操作进入本轮可选项：
   - Add to Project。
   - Remove from Project。
   - Mark as Core in Project。
   - Unmark Core in Project。
3. 批量写入必须复用现有 repository/service：
   - Paper metadata 字段仍由 `PaperRepository` 管理。
   - 项目关系仍优先写入 `ProjectPaperLinkRepository`。
4. 批量操作前显示 selection count 和操作摘要；删除仍使用现有确认，不做批量物理删除的第一版。
5. 批量操作完成后保持 selection set，除非用户主动 Clear Selection。

### 3.3 Quick Look / Space 预览

1. 为 Library 表格增加 Space 预览入口：
   - 单选且有 PDF 时，Space 打开 Quick Look 或轻量预览面板。
   - 无 PDF 时显示非阻塞说明，不切换选择。
   - 多选时优先预览当前 focus row；若无法稳定获得 focus row，则预览 selection 中第一篇有 PDF 的论文。
2. 右键菜单增加 Quick Look / Preview。
3. Quick Look 不替代 Read in App；双击仍进入内置 Reader。
4. 若 `QLPreviewPanel` 集成风险较高，可先用现有 `PDFOpeningService` 或内置 Reader 做 Space fallback，并在完成记录中说明。

### 3.4 GitHub Copilot SDK 接口适配

1. 按 `DOC/Github Copilot` 接入手册建立 Copilot provider/adapter 边界：
   - 面向 GitHub OAuth App 或 GitHub App user token。
   - 每个 GitHub 用户独立 Copilot client/session。
   - `useLoggedInUser` 语义必须等价于 false，不回退到本机 CLI 登录。
   - 支持模型配置，默认先记录为 `gpt-4.1` 或由设置显式选择。
2. 新增本地抽象，不直接把 AI Lab 绑死在某个 SDK 实现：
   - 建议新增 `CopilotSDKProvider` / `CopilotSessionProvider` 协议。
   - 建议新增 `GitHubCopilotConfiguration`，保存 client id、callback URL、required org、model、enabled flag 等非敏感配置。
   - 用户 token、refresh token 和 OAuth state/nonce 只允许进入 Keychain 或后续安全后端，不写入 `settings.yaml`、`workspace_preferences.yaml` 或 `.sci-station/agent` 日志。
3. 明确 OAuth token exchange 责任边界：
   - 桌面端不得内置 GitHub OAuth client secret。
   - 如采用 OAuth App server-side code exchange，必须通过后端 relay 完成。
   - 如后续采用 GitHub App 或支持 PKCE 的 flow，应在实现前单独确认。
4. 预留组织/企业访问校验：
   - 支持 required GitHub org 配置。
   - 通过 GitHub `/user/orgs` 或后续后端校验组织成员身份。
   - Enterprise Managed Users 不需要特殊 SDK 配置，但要保留错误提示。
5. 支持 token 类型约束：
   - 接受 `gho_` OAuth user token。
   - 接受 `ghu_` GitHub App user token。
   - 接受 `github_pat_` fine-grained PAT 作为开发/调试可选入口。
   - 不鼓励 `ghp_` classic PAT，UI 中应标记为不推荐或禁用。
6. 保留现有 Copilot Bridge export：
   - 在真正 SDK 调用稳定前，Export Copilot Bridge 继续写 prompt/manifest。
   - 新的 Copilot SDK adapter 可作为 Settings 中的 experimental provider，不影响现有 DeepSeek/OpenAI-compatible provider。
   - SDK 调用不得绕过 plan-only 和逐项 tool approval 安全边界。

### 3.5 AI Lab Provider 设置入口

1. Settings 中增加 GitHub Copilot 区域草案：
   - Enabled / Disabled。
   - Client ID。
   - Callback URL。
   - Required Organization。
   - Model。
   - Connect GitHub / Disconnect。
   - Connection status。
2. 在 AI Lab 中显示当前 agent provider：
   - OpenAI-compatible / DeepSeek。
   - GitHub Copilot SDK experimental。
   - Copilot Bridge file export。
3. 若未连接 GitHub 或用户无 Copilot subscription，生成计划前应给出明确错误，不进入半执行状态。
4. Copilot subscription、rate limit、token refresh 失败等错误必须以用户可读方式展示。

### 3.6 测试与验证

1. 增加 workspace preferences 兼容验证：
   - 旧 preferences 缺少 column order / width 字段仍可读取。
   - 可见列、顺序和宽度状态不会丢失。
2. 增加 Library 批量编辑核心验证：
   - 批量 status / priority / rating 更新目标 papers。
   - 批量 tag add/remove 不制造重复 tag。
   - 批量 folder 移动保持 paper id 不变。
   - 如实现项目关系批量编辑，应验证只写 `ProjectPaperLinkRepository`。
3. 增加 Quick Look / Space 入口的可测试边界：
   - 有 PDF 时能解析预览目标。
   - 无 PDF 时不崩溃并返回说明。
4. 增加 Copilot SDK adapter 的纯逻辑验证：
   - token prefix classification。
   - sensitive fields 不写入 settings/workspace preferences。
   - required org 配置可序列化但 token 不可序列化。
   - 未连接状态会阻止 SDK provider 生成计划。
5. 更新 README 的 Library V2 与 AI Lab provider 说明。
6. 更新 `DOC/Next-Step-Task-Book.md`。
7. 运行 `swift run SciStationCoreTestRunner`。
8. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。

## 4. 非目标

- 不在本轮启用 Auto Run Loop。
- 不放宽 workspace 写入工具逐项审批。
- 不让 Copilot SDK provider 自动执行 tools。
- 不把 GitHub OAuth client secret 写入 macOS app、workspace 配置或仓库文件。
- 不把 GitHub user token、refresh token 或 Copilot session 内容写入 `.sci-station/agent` 明文日志。
- 不强制替换现有 OpenAI-compatible / DeepSeek provider。
- 不实现跨 thread plan diff 或 merge。
- 不处理项目归档、项目排序或项目物理删除。

## 5. 验收标准

1. Library 列显示设置继续兼容旧 workspace preferences。
2. 用户可以管理 Library 列布局；若 SwiftUI `Table` 无法支持完整列顺序/列宽，任务书完成记录必须说明阻塞和替代行为。
3. 用户可以对多选论文批量设置 status、priority、rating。
4. 用户可以对多选论文批量移动 folder，并批量 add/remove tags。
5. 若实现项目关系批量编辑，写入路径必须是 `ProjectPaperLinkRepository`，不回退到旧 metadata 主写入。
6. Space 或右键 Preview 能对有 PDF 的论文打开预览入口；无 PDF 时给出非阻塞说明。
7. AI Lab 保留现有 Copilot Bridge prompt/manifest 导出。
8. 新增 GitHub Copilot SDK 接口适配抽象，能表达 OAuth/GitHub App user token、每用户 client、model、required org 和未连接状态。
9. GitHub OAuth client secret 和用户 token 不写入 settings、workspace preferences、agent run log、thread log、drafts 或 Copilot Bridge manifest。
10. `gho_`、`ghu_`、`github_pat_`、`ghp_` token 类型被明确分类，`ghp_` 不作为推荐路径。
11. 未连接 GitHub、token 过期或缺少 Copilot subscription 时，AI Lab 给出明确状态，不执行 plan/tool。
12. SwiftPM Core Test Runner 通过。
13. Xcode macOS build 通过。

## 6. Question

1. Library Table V2 是否优先保持 SwiftUI `Table`，只有明确阻塞时再局部引入 `NSTableView` wrapper？建议是。
2. 批量项目关系编辑是否纳入本轮，还是先只做 paper metadata 批量编辑？建议纳入可选项，若风险过高先完成 status/priority/rating/folder/tags。
3. Quick Look 是否必须使用 `QLPreviewPanel`，还是允许先用现有内置 Reader / PDF opening 作为 Space fallback？建议允许 fallback，先保证 Space 入口可用。
4. GitHub Copilot SDK 接口本轮是否只做安全 adapter 边界和设置草案，不真正替换现有 provider？建议是。
5. GitHub OAuth token exchange 是否必须通过后端 relay，而不是桌面端保存 client secret？建议必须通过后端 relay 或后续明确的 GitHub App/PKCE 方案。

## 7. 完成记录

完成时间：2026-04-29

本轮按任务书 21 完成 Library Table V2 与 GitHub Copilot SDK 接口适配第一版：

- Library 表格继续使用 SwiftUI `Table`，但列渲染改为尊重 workspace preference 中的可见列顺序；Columns 菜单新增 Move Earlier / Move Later，保留 Show / Hide 与 Reset Columns。
- 多选论文在 Inspector 和右键菜单中新增批量 status、priority、rating、folder、add tags、remove tags 操作；批量编辑复用 `PaperRepository` 与 `MovePaperToCollectionService`，并在完成后保留 selection set。
- Space / Preview PDF 使用现有外部 PDF opening 作为 Quick Look fallback；单选、多选右键和 Paper 菜单均可进入预览，未选中 PDF 时显示非阻塞状态。
- 新增 `LibraryBulkEditService`，核心验证覆盖批量 status/priority/rating/tag add/remove。
- 新增 GitHub Copilot SDK experimental 配置、token 分类、adapter 协议和 settings store；配置只保存 client id、callback URL、required org、model、enabled 等非敏感字段。
- GitHub Copilot Settings 增加 Connect GitHub：直接打开 `https://github.com/login/oauth/authorize`，授权后回到 `sci-station://github-copilot/callback`。
- Connect GitHub 不再静默失败：未打开 workspace 时显示说明，未填写 Client ID 时会打开 GitHub OAuth App 创建页，授权页打开失败时会显示可复制 URL。
- 新增 token exchange relay URL 配置；桌面端只接收 OAuth callback code/state，不内置 client secret，code-to-token 交换通过 relay/backend 完成。
- GitHub user token 通过 Keychain account 保存；`settings/github_copilot.yaml` 不写 client secret、access token 或 refresh token。
- Settings 增加 GitHub Copilot SDK Experimental 区域，可配置 Client ID、Callback URL、Required Org、Model、Token、保存/检查 adapter/断开连接。
- AI Lab header 显示当前 provider summary；GitHub Copilot SDK provider 目前保持 experimental，不替换现有 OpenAI-compatible / DeepSeek provider，也不绕过 plan-only 和 tool approval。
- README 与 `DOC/Next-Step-Task-Book.md` 已同步 Library V2 与 Copilot SDK adapter 状态。
- 核心验证增加 GitHub Copilot token prefix 分类和非敏感配置往返测试。
- 核心验证增加 GitHub authorize URL 构造、callback code/state 解析和 token exchange request 不含 client secret。

验证：

- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。

## 8. 追加修订：转入 Agent Platform 预设化迁移

追加时间：2026-05-01

任务书 21 已完成 Library Table V2 与 GitHub Copilot SDK adapter 的第一版后，后续计划调整为吸收 OpenCode 与 Claude Code 的 agent 平台设计：OpenCode 作为运行时、session、tool registry、permission、MCP 和 provider 抽象参考，Claude Code 插件作为 hooks、skills、commands、MCP preset、settings 与安全治理参考。

本次已按该计划先完成当前工作区的轻量预设落地：

- 新增 `.claude/settings.json`，启用 `SessionStart` 与 `PreToolUse` hooks。
- 新增 `.claude/hooks/session_start.py`，在 Claude Code 会话开始时注入 Sci-Station 架构、安全与验证上下文。
- 新增 `.claude/hooks/sci_station_guard.py`，对危险 shell、敏感路径写入和疑似 secret 内容做确定性拦截或人工确认。
- 新增 `.claude/skills/sci-station-agent-platform/`，沉淀 AI Lab、OpenCode/Claude Code 迁移、provider/tool/session、MCP、hooks、skills 和安全 preset 的默认指导。
- 新增 `.claude/skills/sci-station-research-workflow/`，沉淀科研 workflow、proposal、论文库、文献综述和代码/数据复核的默认指导。
- 新增 `.mcp.json`，提供受限到当前仓库的 filesystem MCP 入口。

这些文件是产品化迁移的原型，不等同于最终 Sci-Station App 内置 agent 平台。任务书 22 将把这组预设上升为 Swift-native Agent Platform V1 的正式实施路线：核心模型、权限层、hook engine、plugin/skill/command schema、MCP 配置边界、session event log、provider V2 和 AI Lab UI 演进。

追加验证：

- `python3 -m py_compile .claude/hooks/session_start.py .claude/hooks/sci_station_guard.py` 通过。
- `python3 -m json.tool .claude/settings.json` 通过。
- `python3 -m json.tool .mcp.json` 通过。
