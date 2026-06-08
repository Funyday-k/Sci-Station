# 性能与启动稳定性

## 范围

负责 SwiftUI 渲染性能、AppViewModel 发布风暴、Home/Library/AI Lab 高频刷新、启动动画、窗口尺寸和滚动性能。

## 常见风险

- 单一 `AppViewModel` 的大量 `@Published` 触发全局 invalidation。
- SwiftUI body 中重复过滤、排序、map 大数组。
- 高频 agent streaming / event polling 牵动 Home 或 Sidebar。
- 嵌套 ScrollView、无限高度 frame、复杂 glass/geometry 动画。
- 启动期间恢复 workspace 导致 visible SwiftUI tree 重算。

## 优化原则

- 深层 view 尽量接收轻量 props 和 closure，不直接读整个 app model。
- 高频数据用 revision token 或局部 store 隔离。
- 列表行使用预计算 row model。
- Home/Project Dashboard 使用 debounce 和轻量 summary。
- 启动动画期间避免构建主窗口复杂内容。

## 发布前检查

- App 冷启动没有明显卡顿或窗口尺寸异常。
- Home、Library、Recommendation、Queue、Reading Plan 首次进入没有长时间白屏。
- AI streaming 不应导致 Home/Sidebar 明显掉帧。
- Debug-only instrumentation 不应在普通 Debug workspace 中持续轮询或写日志。

## 验证方式

- `swift run --quiet SciStationCoreTestRunner`
- Xcode Debug build。
- 必要时使用 Instruments / ETTrace / OSLog Performance 事件做前后对比。
