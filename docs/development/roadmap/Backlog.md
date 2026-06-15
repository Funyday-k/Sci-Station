# Backlog

本文件记录不进入当前 patch 版本的后续方向。进入实施前必须创建新的 Proposal。

## Release Hardening

- 自动化版本号检查脚本。
- 发布包签名和 notarization 文档。
- 更完整的 diagnostics bundle。
- beta feedback 模板。

## Product Polish

- 中文/localization 全面检查。
- Recommendation → Library / reading Todo 闭环继续打磨。
- Home/Project Dashboard 空态、onboarding polish、widget SVG 审阅稿到 SwiftUI 截图的视觉 QA。
- Settings 信息架构整理。
- 色彩系统加深：建立语义色板、数据色、状态色和 Liquid Glass tint 使用规范，避免整体过淡。

## Performance

- AppViewModel 领域 store 拆分。
- Sidebar/Home/AILab 高频状态隔离。
- 大列表 row model 和缓存继续收敛。

## AI / Agent

- Agent tool 权限 preset 审计。
- Sidecar protocol version 真实 App version 注入。
- UI smoke 覆盖更多主路径。
- AI 对话面板升级：thread/context/sidebar、工具调用卡、审批卡、证据栏、写回 Brief/Wiki/Tasks。
- App Intents、Spotlight semantic index、Foundation Models / Language Model protocol 预留集成边界。

## Plugin Interface

- 内部插件 manifest、route/widget/tool/artifact/command contribution 协议。
- 插件权限、版本兼容、禁用/降级、审计日志和 crash isolation。
- 第一批内部插件候选：Zotero/论文库、AI 审核、项目模板、图谱扩展。

## Documentation

- 用户教程截图。
- 英文文档同步。
- Release notes 自动生成辅助脚本。
