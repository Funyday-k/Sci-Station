# 任务书 23.5：AI Lab Dialog-First UI Refinement

更新时间：2026-05-01

## 1. 本轮结论

任务书 23 已完成 AI Lab Agent Platform Runtime UI V1：session event timeline、Permission Dock、Hook Activity、MCP Server 状态、Preset Manager 和 Provider V2 wrapper skeleton 已进入 AI Lab。

本轮插入 23.5，用于在任务书 24 的项目生命周期控制之前，先把 AI Lab 的主交互从“面板集合”整理为更接近 opencode-dev 的对话式体验：主区域优先呈现 thread timeline，底部提供 composer dock，权限/待处理交互靠近输入区，runtime details 放入侧向 rail。

本轮只借鉴 opencode-dev 的 UI 模式，不把 OpenCode runtime 或前端代码作为生产依赖。Agent 安全边界保持不变：plan-only、逐项 tool approval、hook/MCP 可审计和 Auto Run Loop disabled 继续保留。

## 2. 参考模式

- opencode-dev session 主体验由 `MessageTimeline` 和底部 `SessionComposerRegion` 组成。
- composer 上方可弹出 Permission / Question / Todo / Revert dock，用户在当前对话上下文中处理阻塞项。
- review、context、files 等细节进入侧向 panel，而不是挤在主对话流里。
- prompt input 底部 tray 展示 agent、model、variant 等当前运行参数和次级操作。

## 3. 当前代码基线

- `Sci-Station/UI/AILabWorkspaceView.swift` 已包含 AI Lab compact header、thread strip、prompt editor、action buttons、timeline 和 Agent Panel Details。
- 当前 UI 仍以 `GroupBox` 和多层 `DisclosureGroup` 为主，prompt 在 timeline 上方，Permission Dock 在 details 折叠区内。
- `AppViewModel` 已提供当前 thread、run、timeline item、permission dock item、hook/MCP/preset summary 和 agent 操作方法。
- 本轮可在 SwiftUI 视图层完成，不需要变更 agent core model 或 provider 行为。

## 4. 执行任务

### 4.1 Dialog-First Layout

1. 将 AI Lab 主屏改为垂直 session panel：顶部 compact context bar，中部 thread timeline，底部 composer dock。
2. 主 timeline 不再被 Agent Panel Details 打断；details 移到侧向 runtime rail。
3. 线程选择保留在主对话上方，支持 draft、rename、archive 和 current thread 状态。
4. 空状态直接出现在 timeline 区域，并引导用户从 composer 发起对话。

### 4.2 Composer Dock

1. 将 prompt editor 视觉上改成 dock shell：输入区、发送按钮和底部 tray 一体化。
2. tray 展示当前 project、model、provider，并放置 New Chat、Refresh Context、Export Copilot Bridge 和 disabled Auto Run Loop 等次级动作。
3. `Cmd+Return` 继续生成 plan。
4. Composer 不改变现有 draft 保存、plan generation 或 execution 方法。

### 4.3 Pending Interaction Dock

1. 将当前 run 的 Permission Dock 从 details 中前置到 composer 上方。
2. 保留 allow once、deny、correction feedback、session-scoped approval draft。
3. 没有 tool call 时不占用主对话空间。
4. 工具执行按钮靠近 pending permission，避免用户在 details 中寻找下一步。

### 4.4 Runtime Rail

1. 将 Agent Platform、Preset Manager、Hook Activity、MCP Servers、Context、Current Plan、Conversation History 和 Copilot Bridge 放入侧向 rail。
2. Runtime rail 默认不抢主对话空间，用户可按需展开各节。
3. Context / Plan / History 等信息保持只读展示，不改变原有状态来源。

### 4.5 Message Rendering Polish

1. user message 采用靠右对话气泡。
2. assistant / reasoning summary 采用靠左对话块。
3. permission、tool、hook 等 runtime event 采用紧凑系统事件行。
4. run fallback card 也按 user / agent turn 展示，避免回退到旧面板感。

### 4.6 测试与验证

1. 运行 SwiftUI edited file diagnostics。
2. 运行 `swift run SciStationCoreTestRunner`。
3. 运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build`。
4. 检查 git diff，确认未修改 OpenCode 或 agent core 安全边界。

## 5. 非目标

- 不启用 Auto Run Loop。
- 不改变 tool approval、permission rule、hook、MCP 或 provider 的核心语义。
- 不把 OpenCode runtime、Solid UI 或 npm package 引入 Sci-Station app。
- 不重写 `AppViewModel` agent 状态流。
- 不实现真实 MCP server 启动或 Copilot SDK provider 切换。

## 6. 验收标准

1. AI Lab 首屏呈现 dialog-first session：context bar、thread strip、timeline、composer dock。
2. Prompt composer 位于对话底部，并保留 `Cmd+Return` plan generation。
3. Pending Permission Dock 出现在 composer 上方，能直接 allow once / deny / 填写 correction feedback。
4. Run Approved Tools 操作靠近 pending permissions。
5. Runtime details 进入侧向 rail，不打断主 timeline。
6. User / assistant / runtime event 的视觉层级清晰，消息文本不会被按钮或状态条遮挡。
7. Existing thread、history、Copilot Bridge、Hook Activity、MCP、Preset Manager 功能仍可访问。
8. `swift run SciStationCoreTestRunner` 通过。
9. Xcode macOS build 通过。

## 7. Question

1. 23.5 是否应保持纯 SwiftUI 视图层改造，不新增 agent core 状态？建议是。
2. Permission Dock 是否应前置到 composer 上方，并在 details rail 中避免重复展示？建议是。
3. Runtime rail 是否暂时保持右侧展开式详情，而不是做可拖拽 split panel？建议是。
4. Auto Run Loop 是否继续只显示 disabled 入口和安全说明？建议是。

## 8. 完成记录

已完成。

- AI Lab 主屏已改为 dialog-first session：顶部 context bar、thread strip、中部 timeline、底部 composer dock。
- Prompt composer 已改为 dock shell + tray 结构，保留 `Cmd+Return` plan generation，并在 tray 中展示 project、model、provider、New Chat、Refresh、Export 和 disabled Auto Run。
- Permission Dock 已从 runtime details 前置到 composer 上方，并保留 allow once、deny、correction feedback 和 session-scoped approval draft；Run Approved Tools 已靠近 pending permissions。
- Agent Platform、Preset Manager、Hook Activity、MCP Servers、Context、Current Plan、Conversation History 和 Copilot Bridge 已进入右侧 runtime rail。
- Timeline 已区分 user bubble、assistant bubble 和 compact runtime event row；旧 run fallback 也按 user / agent turn 展示。
- 本轮未改动 agent core、provider、permission、hook、MCP 或 Auto Run Loop 安全语义。

验证：

- SwiftUI edited file diagnostics 通过。
- `swift run SciStationCoreTestRunner` 通过。
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' -derivedDataPath .derivedData build` 通过。