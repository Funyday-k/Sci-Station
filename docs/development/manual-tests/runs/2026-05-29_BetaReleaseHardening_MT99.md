# Beta Release Hardening — MT99 Release Regression 记录

日期：2026-05-29
执行人：自动化基线 + 签名/分发就绪度核查（GUI 手动用例仍需人工执行）
关联：`docs/development/manual-tests/MT99_ReleaseRegression.md`、Beta 发布收口计划

## 自动化 / 构建基线

```text
swift run --quiet SciStationCoreTestRunner
结果：通过（All SciStation core checks passed）

.venv/bin/python -m pytest AgentRuntime/tests/ -q
结果：通过（75 passed）

xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
结果：BUILD SUCCEEDED

xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Release -destination 'platform=macOS' build
结果：BUILD SUCCEEDED

git diff --check
结果：无空白/冲突标记问题
```

MT99-P49C-01 / MT99-P49C-02（Recommendation Core 自动化 + App target 编译）由上述 Core runner 与 Debug/Release build 覆盖，通过。

## 签名 / 分发就绪度（本轮新增核查）

本轮为沙盒 Beta 补齐了 entitlements，并验证签名链：

```text
codesign -d --entitlements :- <Sci-Station.app>
embedded entitlements:
  com.apple.security.app-sandbox                       = true
  com.apple.security.files.user-selected.read-write    = true
  com.apple.security.files.bookmarks.app-scope         = true   # 本轮新增，修复重启后 workspace 恢复
  com.apple.security.files.downloads.read-write        = true
  com.apple.security.network.client                    = true
  com.apple.security.personal-information.calendars     = true

ENABLE_HARDENED_RUNTIME = YES（Runtime Version 已嵌入）
```

- 修复点：此前工程仅靠 `ENABLE_*` 构建设置生成 entitlements，缺少 `com.apple.security.files.bookmarks.app-scope`；而 `WorkspaceBookmarkStore` 用 `.withSecurityScope` 持久化并在重启时解析。沙盒下缺该 entitlement 会导致 Research Root 重启恢复失败（对应 MT99-02 / MT99-12 / MT99-13）。
- 新增 `Sci-Station/Sci-Station.entitlements` 并在 Debug/Release 设 `CODE_SIGN_ENTITLEMENTS`；与既有构建设置合并为并集，已用 codesign 验证。

```text
spctl -a -vvv <Release Sci-Station.app>
结果：rejected，origin=Apple Development
```

- 结论：当前仅有 "Apple Development" 证书，Gatekeeper 在他机拒绝。Beta 发给同行前需 "Developer ID Application" 证书；packaging 流程见 `Tools/scripts/package-beta.sh`。notarization 按 Beta 目标后置。

## 手动 GUI 用例状态（MT99-01 ~ MT99-14）

以下用例需在 macOS App 中人工执行，尚未在本轮覆盖：

| ID | 状态 | 备注 |
|---|---|---|
| MT99-01 创建新 workspace | Pending | 需 GUI |
| MT99-02 打开旧 workspace | Pending | 需 GUI；重点验证 entitlements 修复后 bookmark 恢复 |
| MT99-03 导入 PDF | Pending | 需 GUI |
| MT99-04 打开 PDF Reader | Pending | 需 GUI |
| MT99-05 保存 annotations.md | Pending | 需 GUI |
| MT99-06 新建 Wiki + Cmd+S | Pending | 需 GUI |
| MT99-07 新建 todo | Pending | 需 GUI |
| MT99-08 Materials 预览 | Pending | 需 GUI |
| MT99-09 打开 Projects | Pending | 需 GUI |
| MT99-10 打开 AI Lab | Pending | 需 GUI |
| MT99-11 打开 Settings | Pending | 需 GUI |
| MT99-12 重启 App 恢复 | Pending | 需 GUI；重点验证 bookmark 恢复 |
| MT99-13 bookmark 失效不崩溃 | Pending | 需 GUI |
| MT99-14 Research Root 敏感文件审计 | 见隐私审计 | 由 `bad-data` / `privacy-audit` 工作项补充自动化证据 |

P44–P50 与 BugBash gate 段（MT99-P47/P48/P49C/BB0517*）：自动化部分由 Core runner 覆盖；GUI 行为段落仍标记 Pending，待人工 spot check。

## 备注

- 本记录用于 Beta 收口挂接：自动化基线、签名/分发就绪度已绿；GUI 手动回归仍需在正式 Beta 切版前由人工跑一轮（English + 简体中文 + compact/narrow）。
- 阻塞项（须人工/外部解决）：Developer ID Application 证书 + 第二台 Mac 冒烟。
