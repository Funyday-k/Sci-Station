# UI Automation

Sci-Station 的 UI smoke 由 `AgentRuntime/sci_station_agent/uitest/` 编排，配合 `Tools/SciStationUIProbe` 和 Debug-only app bridge。

## 入口

- Runner：`AgentRuntime/sci_station_agent/uitest/`
- Probe：`Tools/SciStationUIProbe/`
- Scenarios：`AgentRuntime/sci_station_agent/uitest/scenarios/`
- App bridge：Debug-only bridge in AppViewModel

## 常用命令

```bash
.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q
```

真实 App smoke 需要先确认 Accessibility 权限和当前构建路径。若涉及 click/type/drag，`SciStationUIProbe` 需要 macOS Accessibility trust。

## 场景要求

每个 UI smoke scenario 应包含：

- 明确的 workspace setup。
- UI action steps。
- 至少一个事件、文件或视觉断言。
- 失败时可读的错误信息。

## 已知环境风险

- macOS Accessibility 未授权会导致 click/type/drag 失败。
- 已运行的旧 App 实例可能复用旧启动参数。
- App Sandbox 对 bridge socket 和临时 workspace 路径有限制。
- lsregister 可能解析到旧 `.app` 副本。

这些问题属于测试环境风险，应在 release record 中注明，不应误判为产品回归。
