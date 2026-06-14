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
- macOS 27 / Liquid Glass 适配时，优先使用系统 `NavigationSplitView`、toolbar、search、sheet、inspector 行为；不要用自绘 opaque 背景覆盖系统 sidebar 或 toolbar。
- Toolbar 分组使用系统 API 表达：相关按钮成组，低频动作进入 more/menu，主要动作单独强调；图标 tint 只表达语义状态。
- Search 若作用于整个 workspace，应挂在 split view 或 shell 级别；不要为每个页面手写独立搜索按钮造成行为分裂。

## Liquid Glass 审核点

- 清理旧 toolbar/sidebar/sheet 上的额外背景、边框、暗色 scrim 和自定义 blur，再判断新系统材质效果。
- 自定义浮动控件才使用 `glassEffect`，相关控件必须共享 `GlassEffectContainer`。
- 避免 glass-on-glass：玻璃 surface 内部的按钮用 fill、vibrancy 或标准 control。
- 对滚动内容和 pinned header 使用系统 scroll edge effect；不要用硬分割线模拟。
- 检查 Reduced Transparency、Increase Contrast、Reduced Motion。
- 参考资料：[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)、[Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)。

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
