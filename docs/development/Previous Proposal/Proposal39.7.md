# 任务书 39.7：AI Lab 真实模型回归、Provider 诊断与可重试体验收口

更新时间：2026-05-07

完成状态：Superseded before implementation；本任务书未单独实施，内容已拆分并并入 P39.8-P39.11。

> 2026-05-07 更新：P39.7 原计划作为单个 live provider release gate，但范围同时包含 runtime 回归、provider 诊断、retry、论文公式质量、Markdown/LaTeX 渲染、Permission Dock 生命周期和最终发布门禁。为避免继续形成“大桶任务”，P39.7 不再单独实施：
>
> - P39.7.3 / P39.7.4 并入 `docs/development/Proposal39.8.md`：provider failure diagnostics、retry、recovery、Permission Dock pending lifecycle。
> - P39.7.1 的 paper parity 与 P39.7.5 并入 `docs/development/Proposal39.9.md`：Chat/Assistant paper tool parity、公式答案质量、真实工具读取路径。
> - P39.7.5 的渲染部分与 P39.7.6 并入 `docs/development/Proposal39.10.md`：Markdown/LaTeX、回答排版、Permission Dock timeline card、GUI polish。
> - P39.7.1/P39.7.2/P39.7.7 并入 `docs/development/Proposal39.11.md`：live provider/runtime matrix、diagnostics/privacy、release gate record。

> P39.6 已完成实现层修复与自动化验证：provider schema normalization、planner readable fallback、SwiftLoop 工具后空回复 fallback、论文公式 prompt/tool-loop 强化、LangGraph fixture parity、工具事件显示清理均已落地并通过 SwiftPM / pytest / Xcode build。P39.7 不再扩大功能范围，专门补齐 P39.6 未能在非交互环境完成的真实 GUI/provider 回归，并把 provider 失败与 retry 体验打磨到可发布状态。

## 1. 背景

P39.6 解决了阻塞 AI Lab 主路径的代码问题，但仍有三类风险需要用真实 App session 收口：

```text
1. 真实 DeepSeek/OpenAI-compatible 模型是否按新 prompt 稳定调用 list/search/read 并生成最终回答。
2. LangGraph Sidecar 在真实进程 ready / unavailable / crash 场景下的 UI 表现是否与 fixture 一致。
3. provider empty response / HTTP error 的用户可重试体验是否足够清楚，尤其是 runtime/provider/model 信息与最后工具摘要。
```

2026-05-07 真实 GUI 反馈新增 release-blocking 问题：

```text
1. Chat / 聊天模式仍不能稳定正常阅读论文；同一问题在 Assistant / 助理模式下可得到回答，说明需要做 Chat 与 Assistant 的真实工具读取路径对齐。
2. 论文公式回答在 AI 气泡中渲染很差：LaTeX/Markdown math 容易以原始转义文本或拥挤长段落出现，公式、符号解释和来源不易阅读。
3. 真实模型输出倾向于不分行，AI 回复可读性差；需要在 prompt、后处理或 UI 渲染层强制短段落、空行、列表和 display math。
4. Permission Dock 不应固定在输入框上方，也不应在 run 结束后继续滞留；审批应作为当前对话中的 pending interaction 出现在对话栏/时间线尾部，并在审批执行完成、失败落入时间线或切换对话后消失。
```

P39.7 的目标是做小而硬的 release-candidate 验证，不进入 P40 Workspace Creation Wizard，也不引入新 provider。

## 2. 本轮目标

1. 用真实 macOS App 和配置好的 provider 跑完 AI Lab Chat / Assistant / SwiftLoop / LangGraph / Auto fallback 矩阵。
2. 为 provider 失败、空回复、sidecar fallback 增强用户可读诊断：runtime、provider/model、失败原因、可重试上下文。
3. 让“重试上一条消息”或等价 retry 入口在失败 run 后足够明确，不依赖 toast。
4. 将真实模型的论文公式回答质量、公式渲染质量和分行可读性固化为手动记录、必要 prompt 微调和 UI 渲染修复。
5. 修正 Permission Dock 的显示位置和生命周期：它属于对话 pending interaction，不属于固定 composer 区域。
6. 补齐截图、session event、run JSONL 检查，形成进入 P40 前的 AI Lab release gate。

## 3. 实施任务

- [ ] [P39.7.1] Live provider smoke matrix。
  - SwiftLoop / Chat：`你好`、`你能做什么`、`项目里都有什么文章？列一下`。
  - SwiftLoop / paper：`第一篇文章的蒸发率公式是什么？`。
  - 对比 Chat / 聊天 与 Assistant / 助理：同一论文阅读问题不能出现“助理能读、聊天不能读”的分裂体验。
  - Assistant / Plan：可读非 JSON 回复不显示结构化失败。
  - 记录 provider、model、runtime、工具序列、最终输出。

- [ ] [P39.7.2] LangGraph and Auto live parity。
  - sidecar ready 时同题输出 final response。
  - sidecar unavailable 时 Auto 快速 fallback SwiftLoop。
  - sidecar crash / timeout 时 timeline 不丢 user message、pending approval 或 fallback reason。

- [ ] [P39.7.3] Provider failure diagnostics UX。
  - 确认 provider empty response、HTTP 400/401/429、malformed response 都有 inline failure。
  - failure 文案包含 runtime、provider/model、失败原因、已使用工具和最后工具摘要。
  - 错误 run 在 `.sci-station/agent` 中可复查，不暴露 API key 或敏感 headers。

- [ ] [P39.7.4] Retry and recovery polish。
  - 失败 run 后用户能明确重试上一条消息，或 composer 自动保留可重试文本。
  - Stop / sidecar fallback / provider failure 不丢 user message。
  - retry 后新 run 与旧 failed run 都能在 thread timeline 中区分。

- [ ] [P39.7.5] Paper formula answer quality snapshot。
  - 对真实模型输出检查：公式、符号上下文、source title/id/path、未命中时的搜索路径。
  - 若模型仍跳过 read tool，微调 prompt 或 tool descriptions，但不引入复杂 planner。
  - 修复或规避公式渲染问题：LaTeX math 不应以拥挤转义串、反斜杠垃圾或代码样式长段落展示。
  - 强化回答排版：中文回答应有短段落、空行、列表和 display math；不能把公式、解释和来源塞成一个巨段。
  - 保存截图或摘录到 manual-test record。

- [ ] [P39.7.6] GUI polish spot checks。
  - `运行范围` / `全工作区` 文案视觉确认。
  - AI 回复复制按钮在气泡底部，复制 Markdown/plain text。
  - read-only 工具只显示“已使用工具：...”，不出现默认审批完成噪音。
  - 写 workspace 仍进入 Permission Dock，但 Permission Dock 必须显示在对话栏/时间线尾部，不能固定贴在输入框上方。
  - run 结束、审批执行完成或失败落入 inline failure 后，Permission Dock 不再滞留；历史 run 只保留时间线记录。

- [ ] [P39.7.7] Release gate record。
  - 新增 `docs/development/manual-tests/runs/YYYY-MM-DD_P39.7_AILabLiveProvider.md`。
  - 更新 P39.7 交付记录、已知风险和是否允许进入 P40 的结论。
  - 重新运行 SwiftPM、AgentRuntime pytest、Xcode build。

## 4. 非目标

```text
不做 P40 Workspace Creation Wizard。
不新增 provider 或重写凭证管理。
不把 LangGraph 设为唯一 runtime；SwiftLoop 仍是最小可用 fallback。
不取消写入审批。
不做 AI Lab 大型信息架构重设计。
不引入 OpenCode/Claude Code 作为生产依赖。
```

## 5. 验收标准

1. 真实 Chat / SwiftLoop 普通问候和论文列表有自然语言回答，无 schema HTTP 400。
2. 真实 Chat / SwiftLoop 与 Assistant 对同一论文阅读问题的能力一致：Chat 不能低于 Assistant；如果 Chat 失败，必须有明确工具调用路径、失败原因和 retry 入口。
3. 真实“第一篇文章的蒸发率公式是什么？”给出公式/上下文/来源，或明确说明搜索路径与未命中原因。
4. 公式在 AI 气泡中可读：inline math、display math、符号解释和来源分区清楚；即使暂未接入完整 TeX renderer，也不能显示为难读的一整坨转义文本。
5. AI 回复默认有可扫描结构：短段落、空行、列表或小标题；中文长回答不能是单段墙。
6. LangGraph ready 与 Auto fallback 在 UI timeline 中都有可见 final/fallback，不只停在工具过程。
7. provider empty/error run 保留 user message、runtime/provider/model、失败原因、最后工具摘要和可重试路径。
8. read-only 工具不显示审批噪音；写 workspace 仍默认 ask 并可 approve/resume。
9. Permission Dock 显示在对话时间线内，不固定占用输入框上方空间；审批完成或 run 结束后不滞留。
10. P39.7 manual-test record 有截图或输出摘录，能支撑是否进入 P40 的判断。
11. SwiftPM CoreTestRunner、AgentRuntime pytest、Xcode build 通过，或交付记录明确环境阻塞。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

必须手动执行：

```text
MT07-P39.7-01: SwiftLoop / Chat / “你好”
MT07-P39.7-02: SwiftLoop / Chat / “项目里都有什么文章？列一下”
MT07-P39.7-03: SwiftLoop / Chat / “第一篇文章的蒸发率公式是什么？”
MT07-P39.7-04: Assistant / readable non-JSON fallback
MT07-P39.7-05: LangGraph ready / final response
MT07-P39.7-06: Auto fallback while sidecar unavailable
MT07-P39.7-07: provider empty response or simulated failure / inline retry path
MT07-P39.7-08: read-only tool timeline display
MT07-P39.7-09: write tool Permission Dock approval/resume
MT07-P39.7-10: copy button and run-scope wording visual spot check
MT07-P39.7-11: Chat vs Assistant / same paper-reading question parity
MT07-P39.7-12: formula rendering / display math / no escaped long blob
MT07-P39.7-13: assistant answer readability / short paragraphs and blank-line breaks
MT07-P39.7-14: Permission Dock appears in conversation timeline, not fixed above composer; disappears after completion
```

## 7. Questions

1. P39.7 是否作为进入 P40 前的唯一 release gate？当前建议：是。
2. 如果真实模型仍偶发跳过 read tool，但 App 能给出可见失败和搜索路径，是否允许进入 P40？当前建议：允许，但保留 S2 quality issue。
3. 是否需要在 P39.7 中加入显式“重试上一条”按钮，而不是仅依赖 composer 保留文本？当前建议：先以 GUI 手测结果决定。
4. LangGraph sidecar 若真实环境不稳定，是否继续默认 Auto fallback 到 SwiftLoop？当前建议：是。
5. 公式渲染优先级如何取舍：先做轻量 Markdown/LaTeX 规范化保证可读，还是直接接入原生 TeX 渲染组件？当前建议：先轻量规范化与 display math 分块，P40 后再评估完整 TeX renderer。
