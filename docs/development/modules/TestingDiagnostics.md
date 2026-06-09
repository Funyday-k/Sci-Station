# 测试、诊断与调试事件

## 范围

负责核心测试、手动回归、UI smoke、debug events、diagnostics export 和发布证据。

## 关键代码入口

- `Tools/SciStationCoreTestRunner/`
- `Tools/SciStationUIProbe/`
- `AgentRuntime/sci_station_agent/uitest/`
- `Sci-Station/Agent/AppDebugEventName.swift`
- `Sci-Station/App/AppViewModel.swift`
- `docs/development/testing/`

## 测试层级

- Core tests：模型、YAML/JSON、聚合器、策略、兼容性。
- Xcode build：App target 编译和 SwiftUI 类型检查。
- Python tests：AgentRuntime 和 UI test runner。
- UI smoke：真实 App + bridge + probe。
- Manual regression：发布前人工主路径验证。

## Debug event 规则

- event name 必须稳定。
- payload 不得包含 secret、绝对路径、论文正文、wiki 正文。
- 新 event 要进入 allowlist 和测试。
- UI test bridge 可强制 debug logging；普通 Debug 使用不得引入高频写入。

## Diagnostics 规则

诊断包应包含：

- app version 和 build number。
- OS、语言、runtime 选择。
- workspace 是否打开。
- 模块状态摘要。
- 最近脱敏 debug events。

诊断包不得包含：

- home 绝对路径。
- API key 或 token。
- 私有论文全文。
- 未脱敏 provider 原始响应。
