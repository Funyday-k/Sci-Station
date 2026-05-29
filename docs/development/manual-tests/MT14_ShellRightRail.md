# MT14：Shell 右栏 / 全局 AI 侧栏 / P43.5 手动测试

更新时间：2026-05-08
适用任务书：`docs/development/Proposal43.5.md`

## 前置条件

- 已运行 `swift run SciStationCoreTestRunner`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 使用包含至少 1 个 active project、1 篇 paper、1 个 wiki page 的 workspace。
- Settings → AI Lab 已配置可用模型；未配置模型时仅验证 UI shell 与 context crumb。

## 测试用例

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT14-P43.5-01 | Home 打开 | 打开 workspace 后点击 Home | 右栏默认为折叠窄栏；不显示 workspace 统计卡片；点击 AI 后右栏展开为 AI panel，顶部 context 显示 Home |
| MT14-P43.5-02 | Library 打开 | 点击 Library，选中任意 paper | `Import PDF` / `Add by Identifier` 出现在 toolbar；右栏显示 Paper Inspector；AI panel context 显示所选 paper 标题 |
| MT14-P43.5-03 | Calendar 打开 | 点击 Calendar，再打开 AI panel | toolbar 不显示论文导入按钮；AI context 含 Calendar；Debug 记录 `shell.ai_panel.context_update` |
| MT14-P43.5-04 | ProjectSpace.Papers 打开 | 在 Projects 打开 project，切到 Papers tab | toolbar 显示论文导入动作；AI context 含 project + `papers` tab；右栏显示 Paper Inspector |
| MT14-P43.5-05 | AI Lab 打开 | 点击 AI Lab，展开/折叠左侧 Chats，搜索、New Chat、切换 thread、归档 thread | 左侧 thread 管理稳定存在；选中 thread 后 timeline 更新；归档需确认且不改变 run history 数据结构 |
| MT14-P43.5-06 | 折叠右栏重启 | 在 Library 手动隐藏右栏，重启 App；再打开 Home/Library | 偏好写入 `settings/workspace_preferences.yaml`；Home 默认折叠；Library 可自动建议 Paper Inspector 或通过 Inspector 按钮恢复 |
| MT14-P43.5-07 | Project tree 删除当前 project | 在 sidebar Projects → Project Tree 中对当前 project 执行 Delete... | 弹出确认，说明本轮只归档且保留 workspace files；确认后 project 从 active list 隐藏，route 回 Projects list |
| MT14-P43.5-08 | 中文界面 | Settings 切到中文偏好，重启并重复 Home/Library/AI Lab 基础路径 | 新增 Shell/toolbar 文案不 crash；核心流程可用；后续全量中文化留 P43.8 |

## Debug 检查

打开 `.sci-station/debug/app_events.jsonl`，确认存在以下事件，且 payload 只包含 id、路径、标题或布尔摘要，不含论文正文、wiki 正文、选区全文或 secret：

```text
shell.right_rail.change
shell.ai_panel.open
shell.ai_panel.context_update
shell.toolbar.policy
sidebar.project_tree.toggle
project.delete.requested
project.delete.confirmed
```

## 阻塞判定

```text
S0: 右栏/AI panel/Project delete 造成 App crash、workspace_preferences.yaml 写坏、或 debug payload 泄漏正文/secret
S1: Library/Papers 导入动作在 Home/Calendar 泄漏、AI Lab thread 无法切换、Project delete 不回 Projects list
S2: Project Tree 搜索/Pin/Recent 显示异常但不影响导航
```