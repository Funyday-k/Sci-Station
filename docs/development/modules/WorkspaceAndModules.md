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

## 插件接口可行性

可以提供插件接口，但必须先把内部模块规范收紧为可声明、可审计、可禁用的贡献模型。

### 内部协议草案

- `PluginManifest`：id、display name、version、minimum app version、author、description、permissions。
- `RouteContribution`：顶层 route、ProjectSpace tab、toolbar command、settings pane。
- `WidgetContribution`：Home/Project widget descriptor、支持尺寸、默认尺寸、数据 provider、空态。
- `AIToolContribution`：工具名称、输入 schema、输出 schema、权限等级、审计字段。
- `ArtifactContribution`：产物 kind、默认路径、viewer/editor、导出动作。
- `CommandContribution`：command id、菜单/toolbar 可见性、keyboard shortcut。

### 插件边界

- 插件不得直接写 Research Root；必须通过 workspace service 或受限 repository。
- 插件不得直接读取 Keychain；凭据必须走 host app 的 provider 配置。
- 插件声明的 widgets 必须支持 `small/wide/tall/medium/large` 全尺寸，或在 manifest 中声明不可用原因并由 host 隐藏对应入口。
- AI tools 必须声明读写权限和可审计日志字段，默认需要用户确认。
- 初期只开放内部插件；第三方插件需要签名、沙箱、版本兼容和 crash isolation 方案后再开放。

## Proposal 要求

涉及 workspace/module 的 Proposal 必须写清：

- 新增或修改的 module id。
- 受影响的 route、project tab、workflow、artifact kind。
- 新增 write path。
- disabled/missing dependency 的 UI 行为。
- 旧 workspace 兼容行为。
