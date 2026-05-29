# P43 UI Bug Bash

更新时间：2026-05-11
范围：P43.5-P43.9 Shell / Home / Toolbar / Localization / Project lifecycle / PDF-Wiki-AI 主路径
结论：Automated pass；manual GUI spot check 需按 MT18 执行

## 1. 已修复 / 已覆盖

| Area | Severity | 状态 | 处理 |
|---|---|---|---|
| Home 固定面板不可编辑 | S1 | Fixed | Home 改为 widget dashboard，支持 Edit Layout、gallery、resize、hide/show、reset |
| Home layout 无持久化 | S1 | Fixed | `WorkspacePreferences` schema v4 增加 `home_widget_layout`，YAML encode/decode roundtrip |
| Home grid 冲突/窄屏重叠风险 | S1 | Fixed | `HomeWidgetGridPlanner` 自动 repack，1/2/3/4 columns 测试覆盖 |
| Home 编辑只能拖拽 | S2 | Fixed | 增加键盘可达的上移/下移按钮，拖拽作为增强 |
| 模块禁用后 Home widget 误显示 | S2 | Fixed | registry 按 `WorkspaceModuleConfiguration.enabledModuleIDs` 过滤，gallery 显示 required modules |
| 窄窗口右栏占位过宽 | S2 | Fixed | `ResponsiveShellPolicy` 在 compact/narrow 隐藏 right rail |
| 窄窗口 toolbar page actions 挤压 | S2 | Fixed | page actions 在 `<760` 进入 overflow menu |
| 项目树紧凑窗口默认展开 | S3 | Fixed | compact/narrow 下项目树默认折叠 |
| Home 主路径新增文案未入 L10n | S2 | Fixed | 新增 Home widget / gallery / responsive 相关 `L10nKey`，本轮未新增 `localized(zh,en)` 调用 |
| P43.8 deferred 主路径无状态 | S3 | Fixed | Home / toolbar / Settings / ProjectSpace 主路径继续使用 key；PDF/Wiki/Markdown/AI/Library 深层仍登记为非阻断 polish/backlog |

## 2. 需手动复核

| Area | Severity | 状态 | 复核方式 |
|---|---|---|---|
| Home widget drag/drop 手感 | S3 | Manual pending | MT18-P43.9-03 |
| 中文长文案在 720pt 窗口是否截断 | S3 | Manual pending | MT18-P43.9-09 |
| 深浅色 hairline 与 secondary text 对比度 | S3 | Manual pending | MT18-P43.9-12 |
| PDF annotation list / Wiki file list / AI timeline 视觉一致性 | S3 | Manual pending | MT18-P43.9-13 |
| VoiceOver label 覆盖度 | S3 | Manual pending | MT18-P43.9-02 / 08 / 13 |

## 3. 已知非阻断风险

| Area | Severity | 状态 | 说明 |
|---|---|---|---|
| WebKit MainActor warning | S3 | Backlog | Xcode build 仍提示既有 `AppViewModel`/WebKit 相关 Swift 6 warning；不阻断本轮构建 |
| Project hard delete | S4 | Backlog | P43.8 保持 recoverable archive/trash 语义；P43.9 未新增危险删除入口 |
| Full masonry row-span | S4 | Backlog | SwiftUI 第一版以 column span + 高度表达 widget size；core planner 保留 rowSpan，可为后续 custom grid 使用 |

## 4. 验证

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

结果：PASS。