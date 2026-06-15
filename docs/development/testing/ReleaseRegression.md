# Release Regression

发布前必须执行与版本类型匹配的回归。

## Patch beta 回归

适用于 `0.1.x` patch：

- [ ] 新建 workspace。
- [ ] 打开旧 workspace。
- [ ] Library 导入或至少打开已有论文。
- [ ] Wiki 新建/保存/重启恢复。
- [ ] Settings 打开，diagnostics export 可用。
- [ ] 当前版本改动涉及的模块专项验证。
- [ ] 检查 diagnostics/debug events 不泄漏 secret、绝对路径、正文。

## Minor beta 回归

Patch beta 项目之外，还应验证：

- [ ] 新功能完整 happy path。
- [ ] 新功能空态、失败态、无配置降级。
- [ ] 旧 workspace 兼容。
- [ ] 中英文关键文案。
- [ ] 数据文件 round trip。

## RC 回归

RC 阶段执行更完整主路径：

- [ ] Create/Open workspace。
- [ ] Library/PDF/Wiki。
- [ ] Recommendation / reading Todo。
- [ ] AI Lab 无 key/有 key基础状态。
- [ ] Settings/Diagnostics。
- [ ] 重启恢复。
- [ ] 打包产物启动。

## Blocker 判定

- S0：数据丢失、secret 泄漏、App 无法启动。
- S1：核心主路径不可用、旧 workspace 打不开、测试反馈链路断裂。
- S2：明显体验问题但有 workaround。
- S3：低风险文案或布局问题。
