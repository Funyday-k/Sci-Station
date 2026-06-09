# Shell、启动与导航

## 范围

负责 App 启动、主窗口、侧边栏、ProjectSpace tabs、toolbar、右栏、路由恢复和响应式布局。

## 关键代码入口

- `Sci-Station/Sci_StationApp.swift`
- `Sci-Station/ContentView.swift`
- `Sci-Station/App/SciStationLaunchCoordinator.swift`
- `Sci-Station/UI/Shell/`
- `Sci-Station/App/AppViewModel.swift`

## 不变量

- 启动动画期间不要让主 ContentView 提前参与高频状态刷新。
- 主窗口尺寸和 restoration 行为必须稳定，不能在启动后被 root view 反向撑大。
- 右栏模式应保持用户意图，不因路由变化意外自动展开或关闭。
- ProjectSpace tab 的显示必须由 workspace module / catalog 决定，不应硬编码绕过 gating。
- Toolbar action 应有稳定 command id，便于测试和扩展。

## 发布前检查

- 新建 workspace 后首次进入 Home 不崩溃。
- 重启后恢复最近 sidebar / project / tab。
- 缩窄窗口后主要动作仍可通过 toolbar overflow 或页面按钮触达。
- 中英文界面下 tab、toolbar、空态无明显截断。

## 常用验证

```bash
swift run --quiet SciStationCoreTestRunner
```

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
```
