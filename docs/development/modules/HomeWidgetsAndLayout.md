# Home Widgets 与布局系统

## 范围

负责首页 Home widgets、项目概览 Project widgets、组件尺寸体系、编辑布局、拖拽重排、组件库、Home/Project 视觉统一，以及后续可扩展的 widget provider 接口。

## 关键代码入口

- `Sci-Station/Workspace/HomeWidgetLayout.swift`
- `Sci-Station/UI/Home/Widgets/HomeWidgetDashboardView.swift`
- `Sci-Station/UI/ProjectOverviewView.swift`
- `Sci-Station/UI/Shell/ResponsiveShellPolicy.swift`
- `Sci-Station/Workspace/WorkspacePreferences.swift`
- `Sci-Station/Workspace/WorkspacePreferencesRepository.swift`
- `Tools/SciStationCoreTestRunner/main.swift`

## 尺寸契约

所有 Home widget 和 Project widget 都必须支持同一组单位尺寸，尺寸命名按 `高×宽` 解释：

| 尺寸 | 单位 | 用途 |
| --- | --- | --- |
| `small` | `1×1` | 小，圆角正方形，只显示主指标或一个代表性条目。 |
| `wide` | `1×2` | 宽，横向摘要，适合两项指标、短状态、两个快捷动作。 |
| `tall` | `2×1` | 竖向，适合三到四条列表、待办、论文、材料。 |
| `medium` | `2×2` | 中，默认工作尺寸，可显示指标组和短列表。 |
| `large` | `3×3` | 大，承载完整日历、长列表、文档预览或多段摘要。 |

禁止重新引入 `4×4` 作为普通 widget 尺寸。四列指的是页面网格最大列数，不是单个 widget 的最大尺寸。

## 四列单位网格

- Home 与 Project 页面共用同一套 `HomeWidgetLayout` 数据模型。
- 桌面普通与展开宽度使用 4 列单位网格；紧凑宽度降到 2 列；窄宽度降到 1 列。
- 不再使用 3 列分割，避免首页和项目页在中等宽度下形成三张大卡片的旧视觉。
- `1×1` 的单位格必须按列宽生成等高圆角正方形。`1×2`、`2×1`、`2×2`、`3×3` 通过单位格跨度组合得到。
- 单位宽度由当前 grid container 提交给视图计算；初始渲染可使用 fallback unit，测量完成后以实际列宽重排。

## Gravity/Skyline 堆叠算法

布局 planner 使用 skyline packing，行为类似“重力堆叠”：

1. 保留用户在 `items` 中的顺序，拖拽、resize、toggle 只改变这个顺序或尺寸。
2. 对每个启用 widget，计算其 `columnSpan` 和 `rowSpan`。
3. 在所有可容纳该宽度的连续列组中，找到当前最高度最低的一组。
4. widget 落到该列组的最低可承载 row；若多个列组高度相同，选择最左列组。
5. 更新被覆盖列的 skyline 高度。
6. 禁用 widget 放在启用 widget 之后，不参与可见网格。

这与旧的逐格 row-major 搜索不同：新算法允许保留由高组件留下的空洞，但不会让组件“悬空”，也不会因为回填空洞导致拖拽后的视觉顺序跳动。

## Home 与 Project 视觉统一

- Home 是全局“今天该做什么”，Project Overview 是当前项目“现在在哪里”。
- 两处 widget 使用同样的尺寸、圆角、单位网格、拖拽语义和组件库入口。
- 首页不展示模块启用、工作流就绪等系统状态；这些应进入 Settings、diagnostics 或项目健康/模块设置。
- 项目页使用首页更成熟的卡片语言：icon chip、标题、主指标、短操作行、低噪声边框和一致的玻璃 tint。
- 每个尺寸必须有特定信息密度，不允许只是把同一内容等比拉伸。

## macOS 27 / Liquid Glass 适配约束

参考 Apple 的 Liquid Glass 与新设计系统资料：

- [Apple introduces a delightful and elegant new software design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)

执行规则：

- Liquid Glass 只用于导航层、控制层和 app-specific floating surfaces；内容层不要继续叠玻璃。
- 避免 glass-on-glass。widget 内部的小按钮优先用 fill、vibrancy 或标准 control，而不是再套一层重玻璃。
- 相关自定义玻璃元素必须放入同一个 `GlassEffectContainer`。
- Toolbar、sidebar、search 先使用系统结构和标准控件，再考虑自定义玻璃。
- 图标 tint 只表达语义，不用颜色做装饰性噪声。
- macOS 的紧凑桌面控件仍优先使用圆角矩形；胶囊形态只用于更突出的主操作或更宽松的空间。
- 嵌套容器要保持 concentric radius：外层、内层和 padding 的圆角关系必须统一，避免卡片内元素显得“夹角”或过度圆化。
- 必须检查 Reduce Transparency、Increase Contrast、Reduce Motion 下的可读性。

## SVG 审阅稿

当前 SVG 草图放在：

- `docs/assets/design/home-widget-size-matrix.svg`
- `docs/assets/design/home-widget-component-drafts.svg`
- `docs/assets/design/home-widget-gravity-layout.svg`

SVG 用于审阅尺寸、视觉层次和功能说明，不直接等同最终 SwiftUI 实现。进入实现前，应以这些 SVG 为基准核对实际截图。

## 发布前检查

- `small/wide/tall/medium/large` 的 `rowSpan` 与 `columnSpan` 不能改变，除非同步更新本文件、测试和迁移说明。
- 所有默认 Home widgets 支持全部五种尺寸。
- 首页和项目页都使用四列最大网格，不回退到三列。
- 拖拽重排后，前后方向都能落到目标 widget 的位置。
- Resize 后 layout 无 overlap，且 skyline packing 不产生悬空组件。
- 中英文尺寸菜单与实际尺寸一致。

## 常用验证

```bash
swift run --quiet SciStationCoreTestRunner
```

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
```
