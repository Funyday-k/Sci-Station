# 任务书 40：Workspace Creation Wizard V1 与模板到模块配置生成

更新时间：2026-05-06

> 本任务书承接 P39。P39 已建立 Workspace Module Registry V1、`settings/workspace_modules.yaml` 持久化、route/project tab/workflow gating、artifact kind descriptor 和 Permission Dock module scope 解释。P40 的目标是把这些能力接入创建工作区的可视化流程，让新建 Research Root 时可以选择模板、预览目录、理解隐私/AI 设置边界，并生成确定性的 module config。

## 1. 背景

当前 Sci-Station 已能通过内置模板创建 workspace，并由 P39 写出完整 module registry 配置。但创建入口仍是简单菜单，用户无法在创建前理解：

```text
template -> enabled modules -> directories -> routes/project tabs -> workflows -> settings files
```

P40 要把这个链路变成一个清晰、可审计、local-first 的 Workspace Creation Wizard。它不做完整 P41 module settings page，也不引入第三方插件，只负责“创建前选择与预览”。

## 2. 本轮目标

1. 提供 Workspace Creation Wizard V1，可从 Settings / Empty Workspace 进入。
2. 支持选择内置模板：Minimal、Literature Review，以及为后续 Code/Theory/Writing 模板预留禁用或实验入口。
3. 根据模板和 P39 registry 生成确定性的 enabled module set 与 `workspace_modules.yaml`。
4. 创建前预览目录结构、settings 文件、默认 routes/project tabs/workflows。
5. 展示 privacy / AI setup 边界：不写 API key，不写 provider raw config，不写 prompt/response 明文。
6. 创建后打开 workspace，并保持 legacy-safe 行为。
7. 保持 P40 范围有限：不做完整模块启用/禁用设置页，不做插件市场，不做目录 repair UI。

## 3. 实施任务

- [ ] [P40.1] Creation Wizard view model。
  - 定义 wizard draft：目标路径、模板、enabled module ids、workspace name、privacy acknowledgement。
  - 支持从 `WorkspaceTemplateRegistry` 和 `WorkspaceModuleRegistry` 派生预览。
  - 校验目标路径是否可创建、是否为空或可兼容打开。

- [ ] [P40.2] Creation Wizard UI。
  - Empty Workspace 和 Settings -> Workspace 都可打开 wizard。
  - 用模板列表、模块摘要、目录预览和隐私边界确认组成单一可完成流程。
  - UI 保持工作型、紧凑、可扫描，不做营销式 landing 页面。

- [ ] [P40.3] Template -> module config generation。
  - 创建时根据模板写出 `settings/workspace_modules.yaml` schema_version 1。
  - 预览和实际写入使用同一 registry resolver，避免 UI 与文件不一致。
  - Future/experimental 模块可展示为 disabled/coming later，不默认启用。

- [ ] [P40.4] Directory preview and creation safety。
  - 显示 required / optional / repairable 目录。
  - 创建时只创建安全相对路径；忽略 wildcard preview 路径中的具体项目实例。
  - 不删除目标路径已有用户文件。

- [ ] [P40.5] Privacy / AI setup page。
  - 明确创建流程不会写入 API key、Keychain、provider raw config、prompt/response 明文。
  - AI Lab 模块启用只表示 route/workflow 可见，不表示模型凭证已配置。
  - 若需要 API key，引导用户后续去 AI Lab settings，而不是写入 workspace module config。

- [ ] [P40.6] Tests and delivery record。
  - Swift CoreTestRunner 覆盖 wizard draft validation、template preview、module config generation、safe directory filtering。
  - Xcode build 必须通过。
  - 更新 MT10 / MT99 手动测试报告。

## 4. 非目标

```text
不做 P41 完整 Module Settings enable/disable UX
不做第三方插件市场或动态代码加载
不做目录 repair UI
不做 Graph/Recommendation/Writing/Theory 模块完整功能
不在 workspace 文件中保存 API key 或 provider raw config
不迁移或删除用户已有目录内容
```

## 5. 验收标准

1. 用户可从空状态或 Settings 打开创建向导。
2. 向导可选择模板并预览 enabled modules、directories、routes/project tabs/workflows。
3. 创建出的 workspace 包含 deterministic `settings/workspace_modules.yaml` schema_version 1。
4. 创建流程不写入 API key、Keychain、provider raw config、prompt/response 明文。
5. Existing/legacy workspace 路径不会被删除或覆盖用户资料。
6. SwiftPM CoreTestRunner、Xcode build 通过，或交付记录明确环境阻塞。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

建议补充：

```text
get_errors for edited SwiftUI/App files
manual creation of Minimal and Literature Review roots
manual inspection of generated settings/workspace_modules.yaml
privacy keyword scan for generated settings files
```

## 7. 手动测试计划

```text
MT10-P40-01: Empty Workspace opens Creation Wizard
MT10-P40-02: Settings -> Workspace opens Creation Wizard
MT10-P40-03: Minimal template preview matches generated directories/module config
MT10-P40-04: Literature Review template preview matches generated directories/module config
MT10-P40-05: Future/experimental modules are visible as disabled/coming later, not enabled by default
MT10-P40-06: Existing target path is not destructively overwritten
MT10-P40-07: Privacy page confirms no API key/provider raw config/prompt-response plaintext is written
MT99 partial regression: workspace open, create root, sidebar, Settings, Library, AI Lab
```

## 8. 交付记录

完成实现后补充：

```text
完成日期：
Git commit：
自动化测试结果：
手动测试报告：DOC/manual-tests/runs/YYYY-MM-DD_P40_WorkspaceCreationWizard.md
已知问题：
推迟到 P41 的事项：Module settings page、enable/disable UX、pin to sidebar、directory repair UI
```

## 9. Questions

1. P40 是否优先做单窗口 wizard，而不是多页面独立设置中心？当前建议为是。
2. P40 是否只允许选择内置模板，不允许自定义任意模块组合？当前建议为是，完整自定义留给 P41。
3. Future/experimental 模板是否可展示但默认不可选或带明确 experimental 标记？当前建议为是。
4. 创建向导是否必须包含 privacy / AI setup confirmation？当前建议为是。
5. P40 是否继续使用 P39 的 `WorkspaceTemplateRegistry` 和 `WorkspaceModuleRegistry` 作为唯一生成源？当前建议为是。