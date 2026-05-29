# MT00：Test Workspace Setup

更新时间：2026-05-05

## 目标

为所有手动测试提供一致的 Empty、Standard、Broken 三类 Research Root，并规范报告保存位置。

## Workspace 类型

### A. Empty Workspace

用于测试首次创建、空状态、目录补齐、默认 settings 写入。

建议命名：

```text
ManualTestWorkspace_Empty/
```

最低要求：

```text
空文件夹或只含系统隐藏文件
没有 library/projects/wiki/settings 等 Sci-Station 目录
```

### B. Standard Workspace

用于常规主路径和轻量回归。

建议命名：

```text
ManualTestWorkspace_Standard/
```

最低内容：

```text
3 篇 paper
1 个 project
project_overview.md
core_papers.md
existing todos
a wiki page
annotations.md
materials 文件
code 文件
图片
PDF
```

### C. Broken Workspace

用于错误恢复、权限、stale source 和降级状态。

建议命名：

```text
ManualTestWorkspace_Broken/
```

建议包含：

```text
缺失 meta.yaml
损坏 paper_index.yaml
缺失 paper.md
缺失 PDF
损坏 todos.yaml
缺失 settings/
移动过的 workspace
source_hash 变化的 evidence
```

## 执行前检查

- [ ] 已记录 Git commit
- [ ] 已记录 macOS / Xcode 版本
- [ ] 已确认是否 clean build
- [ ] 已确认 AI / sidecar / embedding 开关状态
- [ ] 已备份会被破坏性测试影响的 workspace

## 报告路径

```text
docs/development/manual-tests/runs/YYYY-MM-DD_Pxx_ModuleName.md
```

## 清理规则

- 不把测试 workspace 放进仓库根目录。
- 不把 API key、Keychain 导出、`.env`、private path inventory 写入测试报告。
- Broken Workspace 可以保留用于复测，但必须在报告中说明其人工损坏项。
