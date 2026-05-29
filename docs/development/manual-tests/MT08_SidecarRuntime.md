# MT08：Sidecar Runtime 手动测试

更新时间：2026-05-05

## 目标

验证 runtime selector、sidecar health、fallback、restart、run directory、debug bundle 和 crash/replay 行为。

## 适用触发点

- P36 必须执行完整 MT08。
- 修改 sidecar supervisor、LangGraphAgentRuntime、AI Lab runtime panel、debug bundle 时执行。

## 前置条件

- 已运行自动化基线，或报告中明确标记基线失败。
- Standard Workspace 可打开。
- Python sidecar 可启动；如果不可启动，必须记录 fallback 验证。

## 测试用例

| ID | 标题 | 步骤摘要 | 期望 |
|---|---|---|---|
| MT08-01 | 选择 Swift Loop 后发起新 run | selector 设为 Swift Loop，发起 AI Lab run | 新 run runtime 为 Swift loop，sidecar 不被强制使用 |
| MT08-02 | 选择 LangGraph Sidecar 后发起新 run | selector 设为 LangGraph Sidecar | 新 run 走 sidecar；失败时显示 fallback reason |
| MT08-03 | 选择 Auto fallback 后发起新 run | sidecar ready / not ready 各测一次 | ready 时走 sidecar；not ready 时走 Swift fallback |
| MT08-04 | sidecar 不可用时显示 fallback reason | 断开或禁用 sidecar | UI 显示可理解原因，不崩溃 |
| MT08-05 | Restart sidecar | 点击 Restart sidecar | health 状态更新，失败有错误提示 |
| MT08-06 | Open run directory | 对已完成 run 打开目录 | 打开真实 run directory |
| MT08-07 | Disable sidecar for workspace | 禁用后发起新 run | 新 run 不使用 sidecar，设置持久化 |
| MT08-08 | sidecar crash 后显示 last checkpoint | 注入或模拟 crash | UI 显示 last checkpoint 和 replay/fallback 选项 |
| MT08-09 | replay 已完成 run 不受 selector 改变影响 | 改 selector 后打开旧 run | replay 使用原 run metadata |
| MT08-10 | Export debug bundle | 导出已完成 run bundle | 生成真实 zip 和 manifest |
| MT08-11 | 检查 zip 隐私清单 | 解包或预览 zip 清单 | 不含 API key、`.env`、Keychain、private path inventory |

## 记录要求

每个 run 记录：

```text
runtime selector:
actual runtime:
run_id:
fallback reason:
sidecar health:
debug bundle path:
```

## 允许跳过

```text
MT08-08: 仅在无法稳定注入 crash 时允许 skipped，必须记录替代验证。
```

## 阻塞问题

```text
S0: debug bundle 泄漏 secret；sidecar 直接写 workspace；App crash
S1: runtime selector 不影响新 run；health panel 无真实状态；debug bundle 无法生成
```
