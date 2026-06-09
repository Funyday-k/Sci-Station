# 打包指南

## 目标

为 beta/RC/stable 构建可追踪的 macOS App 包。本文只描述流程，实际签名、notarization 和上传命令需由发布者确认后执行。

## 打包前置

- 工作区干净或只有本次发布相关改动。
- `MARKETING_VERSION` 正确。
- `CURRENT_PROJECT_VERSION` 已递增。
- 自动化和手动回归已记录。
- `CHANGELOG.md` 和 `releases/<version>.md` 已更新。

## 构建配置

测试阶段默认使用 Debug 验证，正式外发包应使用 Release/Archive 流程，并确认 sandbox、entitlements、签名和 notarization 状态。

## 产物记录

每个构建包必须记录：

- App version。
- Build number。
- Git commit。
- Git tag。
- 构建时间。
- 构建机器/环境摘要。
- 是否签名。
- 是否 notarized。
- 已知问题。

## 诊断反馈要求

测试用户反馈问题时，应要求提供：

- App version/build。
- macOS 版本。
- 复现步骤。
- 诊断包。
- 是否新 workspace 或旧 workspace。
- 是否涉及 AI provider / API key / network。

## 禁止提交

- `.app`、`.dmg`、`.zip` 构建产物。
- DerivedData。
- 私人 Research Root。
- 签名证书、notary credentials、API key。
