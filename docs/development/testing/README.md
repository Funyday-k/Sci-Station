# 测试文档中心

本目录替代旧的分散手动测试任务书。测试文档按策略、发布回归、UI automation 和运行记录组织。

## 文件

- `TestStrategy.md`：整体测试策略。
- `ReleaseRegression.md`：发布前回归清单。
- `UIAutomation.md`：UI test runner 和 smoke 场景说明。
- `runs/README.md`：测试运行记录存放规则。

## 基线命令

```bash
swift run --quiet SciStationCoreTestRunner
```

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
```

```bash
.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q
```

## 记录规则

每次 release、RC 或重要 bug bash 都应在 `runs/` 增加一份运行记录，模板见 `../templates/ManualTestReportTemplate.md`。
