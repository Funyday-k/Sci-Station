# 发布流程

## 发布分支

从 `main` 或当前稳定开发点创建：

```bash
git switch -c release/<version>
```

发布分支只接受：

- 当前版本 Proposal 中列明的任务。
- S0/S1 blocker 修复。
- 文档、测试、打包修复。

## 发布前检查

1. 确认 `MARKETING_VERSION`。
2. 递增 `CURRENT_PROJECT_VERSION`。
3. 更新 `CHANGELOG.md`。
4. 更新 `releases/<version>.md`。
5. 完成 release checklist。
6. 运行自动化验证。
7. 完成手动回归。
8. 创建 tag。
9. 归档构建包和 release notes。

## 必跑验证

```bash
swift run --quiet SciStationCoreTestRunner
```

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
```

如涉及 AgentRuntime 或 UI test runner：

```bash
.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q
```

## Release Candidate 规则

进入 RC 后只允许：

- 崩溃修复。
- 数据损坏修复。
- 安装/启动/签名修复。
- 明确的 S0/S1 release blocker 修复。
- 文档和 release notes 修正。

## Blocker 分级

- S0：可能造成用户数据丢失、secret 泄漏、App 无法启动。
- S1：核心主路径不可用、旧 workspace 无法打开、测试版无法有效反馈。
- S2：明显体验问题，但有 workaround。
- S3：文案、布局、小问题。

## 发布产物命名

```text
Sci-Station-<version>-<build>.zip
Sci-Station-<version>-<build>.dmg
Sci-Station-<version>-release-notes.md
```

## 发布后

- 将 `CHANGELOG.md` 的 Unreleased 内容移动到版本条目。
- 在 `releases/<version>.md` 记录最终 tag、commit、构建号。
- 在 `roadmap/Current.md` 切换到下一个版本。
- 对未完成任务创建 backlog 条目。
