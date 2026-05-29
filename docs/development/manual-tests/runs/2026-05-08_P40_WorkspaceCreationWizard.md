# 2026-05-08 P40 Workspace Creation Wizard 手动测试记录

## 范围

任务书：`docs/development/Proposal40.md`

本轮实现 Workspace Creation Wizard V1：空状态 / Settings 入口、模板选择、模块与目录预览、privacy / AI setup confirmation、确定性 `settings/workspace_modules.yaml` 生成、目标路径安全校验。

## 自动化验证

```text
swift run SciStationCoreTestRunner：PASS
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build：PASS
get_errors（P40 编辑 Swift 文件）：PASS
```

新增自动化覆盖：

```text
workspaceCreationWizardPreviewValidationAndSafety
- Minimal preview uses schema_version 1 and template enabled modules.
- Minimal preview exposes AI Lab and hides Library.
- Wildcard project directories are preview-only and not created directly.
- Safe directory resolver filters wildcard, YAML files, and unsafe relative paths.
- Target validation allows new/empty/legacy roots and blocks files / unknown non-empty folders.
- Existing Research Root opened through create path does not overwrite workspace_modules.yaml.
- Generated template/module/AI settings files do not contain api_key/provider_raw_config/prompt/response plaintext markers.
```

## MT10-P40

| ID | 状态 | 记录 |
|---|---|---|
| MT10-P40-01 | GUI pending | 需要本机 App 点击 Empty Workspace → Create Workspace；代码入口已接到 `AppViewModel.beginWorkspaceCreation` |
| MT10-P40-02 | GUI pending | 需要本机 App 点击 Settings → Workspace → Create Root；Settings scene / main content 均挂载同一 sheet |
| MT10-P40-03 | Automated pass / GUI pending | Minimal preview/config/safe dirs 已由 CoreTestRunner 覆盖；仍需 UI 目视核对 |
| MT10-P40-04 | Automated pass / GUI pending | Literature Review config generation 由既有 template test 覆盖；仍需 UI 目视核对 |
| MT10-P40-05 | Automated pass / GUI pending | Code / Theory / Writing template options 为 coming later 且不可选择；仍需 UI 目视核对 |
| MT10-P40-06 | Automated pass | 非空未知目录 blocked；existing Research Root 不覆盖 `workspace_modules.yaml` |
| MT10-P40-07 | Automated pass / GUI pending | `canCompleteWorkspaceCreation` 要求 privacy acknowledgement；仍需 UI 目视核对 disabled state |
| MT10-P40-08 | Automated pass / GUI pending | Wizard privacy notes 明确 AI Lab route/workflow 不等于 credentials/sidecar/run ready；仍需 UI 文案目视核对 |

## MT99 P40 Partial Regression

| ID | 状态 | 记录 |
|---|---|---|
| MT99-P40-01 | GUI pending | Empty Workspace wizard 打开/取消需 App UI 补测 |
| MT99-P40-02 | GUI pending | Settings wizard 打开需 App UI 补测 |
| MT99-P40-03 | Automated pass / GUI pending | preview resolver 已覆盖；UI 即时更新需 App UI 补测 |
| MT99-P40-04 | Automated pass / GUI pending | privacy boundary 与 keyword scan 已覆盖；UI disabled state 需 App UI 补测 |
| MT99-P40-05 | Automated pass | target validation 与 existing-root preservation 已覆盖 |
| MT99-P40-06 | GUI pending | 创建后 sidebar / Settings / Library / AI Lab New Chat entry 需 App UI 补测 |

## 已知问题 / 后续补测

```text
当前环境未驱动真实 macOS App GUI；release/演示前需补跑 MT10-P40-01..08 与 MT99-P40-01..06 的 UI spot check。
Xcode build 仍报告既有 ChatMarkdownWebView / MarkdownPreviewView WebKit actor-isolation warnings；P40 未修改该路径。
P39.5 GUI-only spot check 仍需补跑。
```

## 结论

P40 代码实现和自动化验证完成。GUI-only 手测项已记录为 pending，不阻塞当前代码交付，但应在 release/对外演示前完成。