# 测试运行记录

每次 release、RC、重要 bug bash 或专项验证都应在本目录新增记录。

## 命名

```text
YYYY-MM-DD_<version>_<scope>.md
```

示例：

```text
2026-06-08_0.1.1_release-regression.md
```

## 内容

使用 `../../templates/ManualTestReportTemplate.md`。

必须包含：

- App version/build。
- commit。
- 测试环境。
- workspace 类型。
- 通过/失败项。
- blocker。
- known issues。
- 诊断或日志附件说明。
