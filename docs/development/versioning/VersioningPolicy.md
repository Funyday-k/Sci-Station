# 版本号策略

Sci-Station 从 `0.1.0` beta 开始采用 SemVer 风格版本管理。

## App 版本

```text
MAJOR.MINOR.PATCH
```

当前阶段仍处于 `0.x` beta：

- `0.1.x`：当前 beta 的稳定性修复、文档重构、测试流程补齐。
- `0.2.0`：下一轮产品化 beta，可包含较完整的新功能和 polish。
- `1.0.0`：稳定版本，需具备明确数据兼容承诺和完整发布流程。

## Build Number

Xcode `CURRENT_PROJECT_VERSION` 必须单调递增。每次发给测试用户的新构建都要递增，即使 App version 不变。

示例：

```text
0.1.0 (1)
0.1.1 (2)
0.1.1 (3)
0.2.0 (10)
```

## 版本递增规则

### Patch

用于：

- 崩溃修复。
- 数据保存/恢复修复。
- UI 回归修复。
- 性能修复。
- 文档、测试和发布流程补齐。

### Minor

用于：

- 用户可见新功能。
- 新 workflow 或 project tab。
- 新持久化路径。
- 较大 UI 信息架构变化。

### Major

用于：

- 正式稳定承诺。
- 明确 workspace/schema 兼容政策。
- 完整发布、回滚和用户支持流程。

## 版本之外的 schema

不要把所有兼容性都塞进 App version。必须分别管理：

- Workspace schema。
- Feature schema。
- Agent/sidecar protocol。
- Recommendation/Queue/Reading Plan 等子系统 schema。

## Tag 格式

```text
v0.1.1-beta.1
v0.1.1-rc.1
v0.1.1
```

发布记录必须写清：

- Version。
- Build number。
- Tag。
- Commit。
- Date。
- Validation。
