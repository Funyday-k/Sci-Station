# Workspace 与模块系统

## 范围

负责 Research Root 创建/打开/恢复、workspace templates、module settings、插件贡献、route/tab/workflow/artifact 注册。

## 关键代码入口

- `Sci-Station/Workspace/`
- `Sci-Station/PluginKit/`
- `Sci-Station/UI/ModuleSettings/`
- `Sci-Station/UI/SettingsViews.swift`
- `Sci-Station/App/AppViewModel.swift`

## 数据路径

- `settings/workspace_preferences.yaml`
- `.sci-station/`
- `projects/*/project.yaml`
- 模块声明、project tabs、workflow requirements、artifact descriptors。

## 不变量

- 不把源码仓库当作 Research Root。
- 打开旧 workspace 时必须安全降级或迁移。
- module enable/disable 后 sidebar、ProjectSpace tab、workflow gating 必须同步更新。
- Project override 不得影响其它 project。
- Repair 操作必须明确确认，不能静默创建或删除用户文件。

## Proposal 要求

涉及 workspace/module 的 Proposal 必须写清：

- 新增或修改的 module id。
- 受影响的 route、project tab、workflow、artifact kind。
- 新增 write path。
- disabled/missing dependency 的 UI 行为。
- 旧 workspace 兼容行为。
