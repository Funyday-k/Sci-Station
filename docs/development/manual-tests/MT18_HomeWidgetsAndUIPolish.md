# MT18：Home Widgets 与 UI Polish 手动测试

更新时间：2026-05-11
任务书：P43.9
状态：Ready / Automated baseline passed

## 0. 自动化基线

已执行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

结果：PASS。

## 1. 测试范围

覆盖 P43.9 新增能力：

1. Home widget registry / layout / grid / gallery。
2. Edit Layout：按钮排序、基础拖拽、尺寸切换、显示/隐藏、Reset Default。
3. Workspace preferences schema v4 与 `home_widget_layout` 持久化。
4. 响应式 shell policy：Home columns、右栏隐藏、项目树折叠、toolbar overflow。
5. P43.5-P43.8 UI 主路径：Home、Library、ProjectSpace、AI Lab、PDF、Wiki、Settings。

## 2. 用例

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT18-P43.9-01 | Home 默认布局 | 打开标准 workspace，进入 Home | 显示 Today / Active Projects / AI Review / Calendar / Recent Papers / Reading Plan / Project Health / Quick Actions，无大面积空洞 |
| MT18-P43.9-02 | Edit Layout 排序 | 点击 Edit Layout，使用上移/下移按钮移动 widget | 顺序改变，按钮可键盘聚焦，重启后顺序保留 |
| MT18-P43.9-03 | Edit Layout 拖拽 | 拖动一个 widget 到另一个 widget 前 | 位置重排，debug log 记录 `home.widget.move` |
| MT18-P43.9-04 | Resize widget | 打开 widget 尺寸菜单，选择支持尺寸 | 尺寸改变；不支持尺寸不出现；布局自动 repack 且不重叠 |
| MT18-P43.9-05 | 隐藏与恢复 | 点击 eye-slash 隐藏 widget，再从 Widget Gallery 打开 | Home 中隐藏/恢复即时生效，偏好落盘 |
| MT18-P43.9-06 | Reset Default | 修改布局后点击 Reset Default | 默认 widgets 全部启用并恢复默认顺序 |
| MT18-P43.9-07 | 模块禁用 | Settings → Modules 关闭 Calendar 或 AI Lab，再回 Home | 对应 widget 从 grid 消失；gallery 显示 required modules 原因 |
| MT18-P43.9-08 | 窄窗口 | 将窗口调到 1300 / 900 / 720 pt 左右 | Home 分别为 3 / 2 / 1 columns；右栏在 compact/narrow 隐藏；page toolbar actions 进入 overflow |
| MT18-P43.9-09 | 中文界面 | Settings 切换简体中文，进入 Home 编辑模式 | widget 标题、按钮、gallery、empty state 无明显截断或英文残留 |
| MT18-P43.9-10 | 英文界面 | Settings 切换 English，重复 Home 主路径 | 中文残留不出现在 Home widget 主路径 |
| MT18-P43.9-11 | AI Review widget | 准备 pending draft / unsupported claim / stale evidence，进入 Home | 只显示需要审核的摘要；点击后进入 Inbox 或 AI Lab |
| MT18-P43.9-12 | 深浅色模式 | 切换系统外观 | hairline、灰色辅助文字、按钮、empty state 在两种模式均可读 |
| MT18-P43.9-13 | Release UI spot check | 依次打开 Library / ProjectSpace / AI Lab / PDF / Wiki / Settings | toolbar 与右栏策略稳定，不出现 crash、空白页或明显错位 |

## 3. 验收记录模板

```text
测试日期：
测试人：
Git commit：
macOS / Xcode：
Workspace：Empty / Standard / Broken / Custom
自动化基线：PASS / FAIL

MT18-P43.9-01：PASS / FAIL / N/A
MT18-P43.9-02：PASS / FAIL / N/A
MT18-P43.9-03：PASS / FAIL / N/A
MT18-P43.9-04：PASS / FAIL / N/A
MT18-P43.9-05：PASS / FAIL / N/A
MT18-P43.9-06：PASS / FAIL / N/A
MT18-P43.9-07：PASS / FAIL / N/A
MT18-P43.9-08：PASS / FAIL / N/A
MT18-P43.9-09：PASS / FAIL / N/A
MT18-P43.9-10：PASS / FAIL / N/A
MT18-P43.9-11：PASS / FAIL / N/A
MT18-P43.9-12：PASS / FAIL / N/A
MT18-P43.9-13：PASS / FAIL / N/A

结论：PASS / CONDITIONAL PASS / BLOCKED / INCOMPLETE
阻塞问题：
后续问题：
```

## 4. P43.9 当前执行摘要

本轮已完成自动化与构建基线；由于当前环境没有可交互 macOS GUI 驱动，本文件作为 release/manual pass 的执行模板与验收清单。代码层已覆盖 layout persistence、invalid fallback、grid repack、responsive policy 与 toolbar overflow。