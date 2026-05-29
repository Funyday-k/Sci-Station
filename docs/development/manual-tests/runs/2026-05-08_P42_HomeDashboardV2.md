# P42 Home / Project Dashboard V2 手动测试报告

日期：2026-05-08
任务书：docs/development/Proposal42.md

## 状态

```text
自动化验证：通过 `swift run SciStationCoreTestRunner`
Xcode build：通过 `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`
GUI spot check：pending（本轮先完成代码、文档与自动化覆盖；原生 macOS GUI 交互需在 Xcode 运行后执行）
```

## 已覆盖

- 新增 Home / Project Dashboard 聚合核心测试入口。
- 新增 MT12 Home 手动测试协议。
- 新增 MT99-P42 partial regression gate。

## 待手动执行

```text
MT12-P42-01
MT12-P42-02
MT12-P42-03
MT12-P42-04
MT12-P42-05
MT12-P42-06
MT12-P42-07
MT12-P42-08
MT12-P42-09
MT12-P42-10
```

## 记录

```text
执行人：
环境：macOS / Xcode 本地运行
结果：
阻塞问题：
备注：Draft Inbox 尚未有独立 store，P42 UI 使用现有 AgentRun / AgentToolResult / retrieval index 状态做降级展示。
```