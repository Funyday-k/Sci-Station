# 测试策略

## 测试金字塔

1. Core tests：领域模型、codec、store、aggregator、策略和兼容性。
2. App build：SwiftUI 类型检查、target 集成、entitlements 基础检查。
3. Python tests：AgentRuntime、UI test runner、scenario loader。
4. UI smoke：真实 App + bridge/probe + 最小场景。
5. Manual regression：发布前主路径人工确认。

## 何时补测试

- 新持久化格式：必须补 round trip 和旧数据兼容测试。
- 新 module/tab/workflow：必须补 registry/catalog/gating 测试。
- 新 debug event：必须补 allowlist 或事件约束测试。
- 新 AI 工具：必须补参数验证、权限和错误分类测试。
- 修复回归：必须补能抓住该回归的测试或手动门禁。

## 测试失败处理

- 优先判断是否真实产品回归。
- 环境/权限问题要在 release record 中说明。
- 不允许用删除测试代替修复。
- 如果暂时跳过，必须写 follow-up 和恢复条件。
