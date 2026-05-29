# MT13：ProjectSpace Shell / P43 手动测试

更新时间：2026-05-08
适用任务书：`docs/development/Proposal43.md`

## 前置条件

- 已运行 `swift run SciStationCoreTestRunner`。
- 已运行 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`。
- 使用 Standard / Literature Review workspace，至少包含 1 个 active project。
- Settings → Modules 可用于启用 / 禁用 `code`、`citation-graph`、`wiki` 等模块。

## 测试用例

| ID | 标题 | 步骤 | 期望 |
|---|---|---|---|
| MT13-P43-01 | 顶层 sidebar 6 项固定 | 打开 workspace，观察 sidebar | 只显示 Home / Projects / Library / Calendar / AI Lab / Settings；Materials / Wiki / Tasks 不再作为顶层入口出现 |
| MT13-P43-02 | ProjectSpace tabs | 点击 Projects，双击/打开任意 project | 进入 ProjectSpace；默认可见 Overview / Papers / Wiki / Tasks / Calendar / AI Workflows；Overview 在最左侧 |
| MT13-P43-03 | `code` 模块 gating | Settings → Modules 启用 `code` 及依赖，返回 ProjectSpace；再禁用 `code` | Code tab 出现；禁用后消失；当前停在 Code 时回到 Overview，无 crash |
| MT13-P43-04 | `citation-graph` placeholder | 启用 `citation-graph` 及依赖，打开 Graph tab | Graph tab 出现；内容显示 `Graph data not built yet, see P44-P46.` |
| MT13-P43-05 | ProjectSpace tab 重排 | 拖拽 Wiki / Papers / Tasks tab 改变顺序，重启 App | Overview 仍 leftmost；其余顺序保留 |
| MT13-P43-06 | Route restore | 停在 ProjectSpace.Wiki，关闭并重开 App | 自动恢复到 Projects → 同一 project → Wiki tab |
| MT13-P43-07 | 禁用模块 fallback | 停在 Wiki tab，关闭 App；编辑/通过 Settings 禁用 wiki；重开 | 回到 ProjectSpace.Overview；`.sci-station/debug/app_events.jsonl` 记录 `route.persist.fallback` |
| MT13-P43-08 | 切换 project | 从 Projects 列表打开 Project A，再打开 Project B | Tab strip 重新计算；`project_space.tab_change` payload 含当前 project/tab/available_tabs，不含论文/wiki 正文 |
| MT13-P43-09 | 顶层 Calendar / AI Lab | 点击 Calendar、AI Lab；再从 ProjectSpace 打开 Calendar / AI Workflows | 顶层 Calendar/AI Lab 是 workspace-wide；ProjectSpace 内 tab 绑定当前 project |
| MT13-P43-10 | Top sidebar 重排 | 拖拽 Home / Library / Calendar 改变顺序，重启 App | 顺序保留；Settings 仍在顶层集合内，不会丢失 |

## Debug 检查

打开 `.sci-station/debug/app_events.jsonl`，确认存在以下事件且 payload 不含 paper title、wiki path 正文、todo title、绝对路径或 secret：

```text
sidebar.render
project_space.tab_change
project_space.builder_warn
route.persist
route.persist.fallback
```

## 阻塞判定

```text
S0: 导航操作造成 App crash、workspace_preferences.yaml 写坏、或 debug payload 泄漏正文/secret
S1: 顶层 sidebar 不是 6 项、ProjectSpace 无法打开、模块禁用后 tab 不隐藏、route restore 失效
```