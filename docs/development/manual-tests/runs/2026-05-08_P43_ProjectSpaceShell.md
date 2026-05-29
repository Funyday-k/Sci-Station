# P43 ProjectSpace Shell 手动测试记录

日期：2026-05-08
执行人：未执行 GUI spot check（本轮由自动化与 Xcode build 覆盖）

## 自动化 / 构建

```text
swift run SciStationCoreTestRunner
结果：通过

xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
结果：通过
```

## 手动用例状态

| ID | 状态 | 备注 |
|---|---|---|
| MT13-P43-01 | Pending | 需 GUI spot check |
| MT13-P43-02 | Pending | 需 GUI spot check |
| MT13-P43-03 | Pending | 需 GUI spot check |
| MT13-P43-04 | Pending | 需 GUI spot check |
| MT13-P43-05 | Pending | 需 GUI spot check |
| MT13-P43-06 | Pending | 需 GUI spot check |
| MT13-P43-07 | Pending | 需 GUI spot check |
| MT13-P43-08 | Pending | 需 GUI spot check |
| MT13-P43-09 | Pending | 需 GUI spot check |
| MT13-P43-10 | Pending | 需 GUI spot check |

## 备注

- 本记录用于 P43 交付挂接；正式发布前需要在 macOS App 中执行完整 MT13。
- 自动化已覆盖 builder、pin order、route persistence、schema v2 backward compatibility、module-disabled fallback。