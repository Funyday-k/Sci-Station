# 任务书 39.9：AI Lab 论文阅读、工具契约与写入工作流产品化

更新时间：2026-05-07

完成状态：Completed implementation；自动化验证通过，live provider / GUI 手测待用户以真实工作区和 API key 复核。

> P39.6/P39.7 已把“第一篇文章的蒸发率公式是什么？”作为关键回归，但目前可靠性主要靠 prompt 约束和少量 fixture。要让 AI Lab 真正可用，需要把论文阅读、检索、引用、草稿写入、审批恢复变成可验证工具契约，而不是每次寄希望于模型刚好按提示调用正确工具。

## 1. 背景

代码和任务书反复暴露的核心问题：

```text
1. Chat mode 与 Assistant mode 的工具路径不同，导致“助理能读、聊天不能读”的真实反馈。
2. 工具输出是自由文本 message，UI 和模型很难稳定区分 title、paper_id、path、section、formula、source excerpt。
3. 论文正文读取依赖 list/search/read 的模型自觉顺序；缺少 deterministic preflight 和 missing-content 解释。
4. 写 wiki / todo / artifact 的流程仍偏“计划 + 审批 + 执行”，没有形成用户可读草稿、diff、目标路径确认、执行后结果校验的完整产品路径。
5. 当前 fallback 会总结最后工具结果，但不能证明回答真正引用了工具结果或覆盖了用户问题。
6. P39.7 原计划要求真实模型下 Chat 与 Assistant 对同一论文阅读问题能力一致，并保存公式答案质量快照；该部分并入本任务书。
```

P39.9 的重点是让 AI Lab 对研究工作“有用”：能稳定列论文、读正文、找公式、生成带来源答案，并在写入前展示草稿和目标。

## 2. 本轮目标

1. 建立 paper QA deterministic routing：论文内容类问题先解析目标 paper，再检索/读取，再回答。
2. 将工具输出升级为结构化 payload + 用户可读摘要，模型与 UI 都能消费同一份证据。
3. 统一 Chat / Assistant 对 paper tools 的能力边界：同题不能出现 Chat 低于 Assistant 的断裂。
4. 写入 workflow 产品化：先展示草稿和 diff/target，再审批，执行后回显结果与 rollback hint。
5. 增加 AI answer quality evaluator，覆盖来源、公式、未命中解释、语言和段落结构。
6. 形成标准研究场景回归集，而不只测“你好”和单个公式问题。
7. 吸收 P39.7：真实 provider 下 paper formula prompt 必须记录工具序列、最终输出和 Chat/Assistant parity 结论。

## 3. 实施任务

- [x] [P39.9.1] Paper intent router。
  - 在 Swift loop 前增加轻量 deterministic classifier：paper listing、paper body QA、formula/equation、section summary、citation/source lookup、writeback。
  - 对 ordinal paper（第一篇/first paper）先解析 paper id；解析失败必须显示可选候选，而不是让模型猜。
  - 对 metadata-only context 明确提示需要读取正文，避免直接编造答案。

- [x] [P39.9.2] Structured tool result contract。
  - 为 `list_papers`、`search_papers`、`read_paper`、`read_paper_section` 定义稳定 JSON payload 字段。
  - `AgentToolResult.message` 保留人类可读摘要，但 run directory 保存 full structured payload。
  - UI timeline 默认显示 compact summary，展开后可看 paper id、path、section、matched lines。

- [x] [P39.9.3] Evidence-grounded final answer。
  - 最终回答生成前检查是否有足够 tool evidence；没有 evidence 时返回“我没有读取到正文/公式”的可操作说明。
  - 公式问题必须包含公式块、符号解释、source title/id/path、使用过的查询或章节。
  - 回答不得只复述工具过程；必须有 direct answer。

- [x] [P39.9.4] Chat / Assistant tool parity。
  - Conversation mode 的 native tool calls 与 Assistant planner 的 planned tool calls 使用同一组 tool definitions、permission rules、paper routing hints。
  - 对同一 paper QA prompt，Chat 和 Assistant 至少都能给出同等级 evidence 或同等级失败原因。
  - 如果 Assistant 仍不执行工具，必须把“需要切到 Chat/工具循环”作为明确产品文案，而不是静默降级。
  - 吸收 P39.7 live feedback：同一问题不能出现“助理能读、聊天不能读”的分裂体验。

- [x] [P39.9.5] Write workflow as draft-first UX。
  - “总结第一篇文章并写入 wiki”必须先生成 wiki 草稿消息和目标路径。
  - Permission Dock 展示目标文件、写入模式、摘要 diff、rollback hint。
  - Approve 后执行写入并在 timeline 显示成功路径；失败时显示可重试和保留草稿。

- [x] [P39.9.6] Tool error taxonomy。
  - 区分 paper not found、markdown not converted、section not found、empty search、permission denied、write failed、provider failed。
  - 每种错误给用户下一步建议：导入/转换 Markdown、选择论文、缩小关键词、重试模型、审批写入。

- [x] [P39.9.7] Quality evaluator and fixture suite。
  - 增加无网络 provider fixture，模拟 list/search/read/final answer。
  - 增加 answer quality checks：has direct answer、has source、has display math when formula、has missing-content explanation。
  - AgentRuntime pytest 增加 paper reading workflow parity。

## 4. 非目标

```text
不引入新的向量数据库或云端 RAG 服务。
不要求所有论文 PDF 自动 OCR；缺 Markdown 时必须清楚说明。
不取消用户写入审批。
不做 UI 视觉系统重构；P39.10 负责。
不进入 P40 Workspace Creation Wizard。
```

## 5. 验收标准

1. `项目里都有什么文章？列一下` 稳定列出当前 context 下论文，并带可定位 id/path。
2. `第一篇文章的蒸发率公式是什么？` 稳定读取正文或明确说明缺 Markdown/未命中路径。
3. Chat 与 Assistant 对同一 paper QA 不出现一个能读、一个静默失败。
4. 公式答案包含 display math、符号解释和来源。
5. 写 wiki/todo/artifact 类 prompt 先展示草稿/目标，再审批，再执行；失败不丢草稿。
6. 工具错误可分类、可理解、可重试。
7. 自动化质量检查能抓住“只有工具过程、没有最终回答”的回归。

## 6. Tests

必须运行：

```bash
swift run SciStationCoreTestRunner
/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

新增手测：

```text
MT07-P39.9-01: Chat / 列论文 -> id/title/path 可见
MT07-P39.9-02: Assistant / 列论文 -> 与 Chat parity
MT07-P39.9-03: Chat / 第一篇公式 -> direct answer + source
MT07-P39.9-04: Assistant / 第一篇公式 -> 与 Chat parity 或明确模式限制
MT07-P39.9-05: 缺 Markdown 论文 -> 不编造，提示转换/导入
MT07-P39.9-06: 总结并写入 wiki -> 草稿 -> 审批 -> 写入路径 -> 成功回显
MT07-P39.9-07: 拒绝写入 -> 保留草稿，timeline 可解释
MT07-P39.9-08: section not found -> 展示搜索路径和候选
```

## 7. 交付记录

完成实现后补充：

```text
完成日期：2026-05-07
Git commit：未提交
自动化测试结果：
  - swift run SciStationCoreTestRunner：通过
  - /Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests：28 passed
  - xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build：BUILD SUCCEEDED
手动测试报告：docs/development/manual-tests/runs/2026-05-07_P39.9_AILabResearchWorkflows.md
剩余风险：
  - live provider thinking-mode 已通过 reasoning_content 回传修复和 request payload 回归覆盖，但仍需用用户实际 DeepSeek/Qwen thinking 模型跑一次真实工具循环确认。
  - GUI 手测未在本轮自动执行；需用户在真实工作区确认 Chat/Assistant parity、审批卡文案、写入成功/拒绝路径。
  - P39.10 仍需处理 Markdown/LaTeX 渲染、bubble layout、Permission Dock 视觉整合。
是否允许进入 P39.10：允许；P39.10 开始前建议先用本报告的 MT07-P39.9-01~08 做一次 live smoke。
```
