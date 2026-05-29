# 推荐论文专用任务书：Paper Recommender V2

更新时间：2026-05-26
状态：R2.1 / R2.2 已落地；R2.3 / R2.4 / R2.5 核心闭环已部分落地；R2.6 暂缓
优先级：S1：Recommendation / Queue / Reading Plan 工作流打磨
承接：P49 `Recommendation Engine V1`、P48 `Research Queue`、P50 `Reading Plan`
目标：把现有 Recommendation 从“可解释候选重排 + arXiv 手动刷新”升级为“面向论文阅读决策的专用推荐器”。

---

## 0. 审阅结论

用户给出的方案方向正确，但不能按“全新推荐系统”直接落地。当前仓库已经有一套 P49 推荐核心：`RecommendationCandidate`、`RecommendationScorer`、`RecommendationPipeline`、arXiv client、AI evaluation、history snapshot、Queue 推送和 ProjectSpace UI。V2 应该在这些既有能力上增量演进。

### 0.1 直接采纳

- **arXiv 领域硬边界**：领域选择必须成为候选过滤条件，而不是只参与 arXiv query 或 soft score。
- **关键词软边界**：关键词不应硬过滤，应进入加权相关性评分。
- **种子论文软边界**：用户选择的参考论文应成为最强兴趣锚点。
- **项目上下文**：来自 project brief / linked papers / wiki 的上下文应进入推荐，但需要先做最小可控版本。
- **AI 作为评审器**：AI 不直接决定排序，而是输出结构化评价、风险与短评。
- **Like / Dislike 反馈**：反馈应本地持久化，逐步影响排序。
- **多样性重排**：Top-K 需要避免全是同一类论文，适合引入 MMR。

### 0.2 需要调整

- **Embedding 不是 V2 第一前提**：仓库已有 deterministic `RecommendationTextSimilarity` 和 agent embedding 相关能力，但推荐 V2 第一阶段应先用可测试的本地 token / cosine 语义近似；embedding backend 作为可插拔增强，不阻塞 MVP。
- **质量分先用弱信号**：引用数、作者影响力、代码链接等数据源并不总是可用，V2 先做摘要完整度、标题具体性、类别命中、AI method soundness 等弱信号。
- **AI prompt 必须隐私降级**：当前代码已经会把用户 query、参考论文标题/摘要、候选标题/摘要发给 provider。V2 必须继续明确 opt-in、截断、错误降级，不把 API key、绝对路径、全文 PDF、debug payload 写出。
- **结构化 AI 评价需向后兼容**：现有 `RecommendationAIEvaluation` 只有 `overall` 和 per-score comment。V2 可增加结构化 review，但旧 snapshot 仍要能读取。

### 0.3 不建议纳入本轮

- **后台常驻每日推荐 daemon**：与当前 local-first / foreground-only 策略冲突，先保留手动刷新与前台 scheduler。
- **Crossref / Semantic Scholar / INSPIRE 全量接入**：候选来源可设计接口，但本轮先把 arXiv 专线做好。
- **PDF 全文抓取或全文上传 AI**：不符合当前隐私边界。
- **复杂 bandit / 多臂老虎机**：反馈样本量不足，先做可解释的正负样本相似度与权重调整。

---

## 1. 当前代码基线

### 1.1 已有能力

- **Core model**：`Sci-Station/Recommendation/RecommendationModels.swift`
  - `RecommendationConfig`
  - `RecommendationWeights`
  - `RecommendationCandidate`
  - `RecommendationContext`
  - `RecommendationFeatureBreakdown`
  - `RecommendationScore`
  - `RecommendationRunResult`
- **Scoring**：`Sci-Station/Recommendation/RecommendationScorer.swift`
  - `citedByCore`
  - `libraryInterestSimilarity`
  - `recency`
  - `openGapCoverage`
  - `authorOverlapWithCore`
  - `queuePressurePenalty`
- **Pipeline**：`Sci-Station/Recommendation/RecommendationPipeline.swift`
  - candidate gather
  - top-K
  - snapshot JSON
  - history
  - `recommendation_note` / `queue_candidates` payload
- **arXiv**：`Sci-Station/Recommendation/ArxivRecommendationClient.swift`
  - category query
  - max results clamp
  - Atom parser
  - abstract / publishedAt / categories
- **App integration**：`Sci-Station/App/AppViewModel.swift`
  - `refreshArxivRecommendations`
  - AI search strategy planning
  - AI evaluation
  - recommendation history
  - add to Reading Queue
- **UI**：`Sci-Station/UI/Recommendation/RecommendationView.swift`
  - field selector sheet
  - keyword query
  - topK
  - AI model selection
  - seed/reference paper sheet
  - result/history panels

### 1.2 当前缺口

- **硬边界不足**：arXiv query 使用 category，但 fetch 后没有独立的 category boundary pass；AI search strategy 还可能引入近邻 category。
- **关键词表达粗糙**：当前 query 被 token 化进入 `openGapKeywords`，没有 `WeightedKeyword`、短语匹配和标题/摘要分层权重。
- **种子论文信号混在 library similarity**：参考论文作为 `interestPapers` 参与相似度，但没有单独的 `seedSimilarity` 分量与解释。
- **项目上下文弱**：当前 prompt 用 project name/description，scorer 不直接使用 project context feature。
- **recency 粗粒度**：当前按 published year 分段；arXiv 候选已有 `publishedAt`，应支持日级指数衰减。
- **新颖性/重复度不足**：Queue suppression 存在，但与 library/history 的 near-duplicate suppression 不足。
- **AI 评价非结构化**：当前只返回 overall + comment，没有 relevance / novelty / methodSoundness / usefulness / risk。
- **反馈闭环缺失**：没有本地 like/dislike store，也没有把用户行为反馈进入下一轮排序。
- **多样性缺失**：Top-K 直接按总分排序，容易出现同主题重复。

---

## 2. V2 目标

### 2.1 产品目标

让用户在 ProjectSpace Recommendation 页面完成以下路径：

```text
选择 arXiv 领域（硬边界）
  -> 输入关键词（软边界，可为空）
  -> 选择参考论文（软边界，可为空）
  -> 获取 arXiv 候选
  -> 本地可解释打分
  -> 可选 AI 结构化评审
  -> 多样性重排
  -> like/dislike 或加入 Queue
  -> 后续生成 Reading Plan
```

### 2.2 工程目标

- **不重写 P49**：复用 `RecommendationPipeline`、`RecommendationScorer`、`RecommendationRunResult`。
- **向后兼容 snapshot**：旧 `.sci-station/recommendations/notes/*.json` 仍可加载。
- **local-first**：规则、相似度、反馈与日志默认本地；AI 与 arXiv 网络请求必须可降级。
- **可测试**：每个新增 scoring component 都有 core test。
- **可解释**：UI 与 snapshot 均能说明推荐理由与主要贡献分。

---

## 3. 数据模型设计

### 3.1 推荐请求

新增或扩展为内部请求模型：

```text
PaperRecommendationRequest
- arxivCategories: [String]
- includeCrossList: Bool
- keywords: [WeightedKeyword]
- seedPaperIDs: [Paper.ID]
- projectID: String?
- limit: Int
- timeRange: PaperTimeRange?
- aiModel: String?
```

落点建议：

- `Sci-Station/Recommendation/RecommendationModels.swift`
- 或新文件 `Sci-Station/Recommendation/PaperRecommendationRequest.swift`

### 3.2 加权关键词

```text
WeightedKeyword
- text: String
- weight: Double
```

约束：

- `text` trim 后不能为空。
- `weight` clamp 到 `0.0...2.0`。
- UI 可以先只暴露普通关键词输入，内部默认 `weight = 1.0`。
- 后续再做多关键词权重编辑器。

### 3.3 类别硬边界

候选必须经过：

```text
passesCategoryBoundary(candidate, selectedCategories, includeCrossList)
```

规则：

- `selectedCategories` 为空时允许默认 category set，但 UI 不应让用户误以为“无限制”。
- 如果 `includeCrossList = true`，`candidate.categories` 包含任一选中 category 即通过。
- 如果 `includeCrossList = false`，只允许 primary category 命中。
- 当前 `RecommendationCandidate` 只有 `categories`，V2 需要增加 `primaryCategory` 或在 arXiv parser 中约定第一个 category 为 primary fallback。

### 3.4 V2 feature breakdown

在不破坏旧字段的前提下扩展：

```text
RecommendationFeatureBreakdown
- keywordRelevance
- seedSimilarity
- projectContextSimilarity
- recency
- novelty
- quality
- aiScore
- feedback
- queuePressurePenalty
```

兼容策略：

- 旧字段可保留；新增字段 decode 默认 `0`。
- `RecommendationWeights` schema 可升级到 v2，decode 缺失时填默认。
- `RecommendationRunResult` 增加 request metadata 时必须 `decodeIfPresent`。

### 3.5 AI review

新增结构化评价模型：

```text
RecommendationAIReview
- relevance: Double
- novelty: Double
- methodSoundness: Double
- usefulness: Double
- risk: Double
- summary: String
- recommendationComment: String
- suitableFor: [String]
- possibleWeaknesses: [String]
```

存储方式：

- 可以先挂在 `RecommendationAIEvaluation` 下：`reviewsByScoreID: [String: RecommendationAIReview]`。
- 旧 `commentsByScoreID` 保留，用于 UI fallback。

### 3.6 用户反馈

新增本地反馈 store：

```text
RecommendationFeedbackRecord
- paperKey: String
- externalKey: String?
- projectID: String?
- feedbackType: like | dislike | save | addToQueue | openPDF | ignore
- recommendationRunID: String
- createdAt: Date
```

持久化路径：

```text
.sci-station/recommendations/feedback.jsonl
```

设计约束：

- 只记录 paper key、行为类型、project scope、run id、时间。
- 不写 abstract、prompt、API key、绝对路径。
- 可从 `addRecommendationToReadingList` 自动记录 `addToQueue`。

---

## 4. 排序算法

### 4.1 候选获取

第一阶段只做 arXiv：

```text
manual query strategy
AI-generated search strategy（可选，有 API key 时）
category-only fallback
```

每个 strategy 的结果统一进入 candidate map，然后执行：

```text
canonical dedup
category hard boundary
history / queue / library duplicate annotation
score
MMR rerank
topK
```

### 4.2 硬边界过滤

`ArxivRecommendationClient` 的 search query 仍保留 category clause，但不能只依赖它。

新增测试必须证明：

```text
selectedCategories = ["cs.CL"]
includeCrossList = false
candidate.categories = ["cs.AI", "cs.CL"]
primaryCategory = "cs.AI"
=> filtered out

selectedCategories = ["cs.CL"]
includeCrossList = true
candidate.categories = ["cs.AI", "cs.CL"]
=> accepted
```

### 4.3 关键词分

V2 先实现可测试的 deterministic score：

```text
S_keyword = 0.5 * titlePhraseMatch
          + 0.3 * abstractPhraseMatch
          + 0.2 * tokenCosine
```

多关键词按权重加权平均。

空关键词默认：

```text
S_keyword = nil
```

权重归一化时跳过 nil feature，而不是给固定 0.5，避免空关键词产生假信号。

### 4.4 种子论文相似度

候选文本：

```text
title + abstract + categories
```

种子文本：

```text
title + abstract + tags + categories + notes excerpt（若已有安全来源）
```

得分：

```text
S_seed = 0.7 * max(sim(candidate, seeds)) + 0.3 * mean(sim(candidate, seeds))
```

无种子论文时：

```text
S_seed = nil
```

### 4.5 项目上下文分

第一阶段上下文只取低风险字段：

```text
project.name
project.description
project linked paper titles/tags/categories
```

后续再考虑 wiki / shared_research excerpts。

无项目时：

```text
S_project = nil
```

### 4.6 时效性分

优先使用 `candidate.publishedAt`：

```text
S_recency = exp(-lambda * ageDays)
lambda = 0.01
```

fallback：

- 有 `publishedYear` 时按 year bucket。
- arXiv daily feed 无日期时给 `0.8`，但记录 reason key 为 `recency_fallback`。

### 4.7 新颖性 / 重复度

比较对象：

- 本地论文库。
- Recommendation history。
- Queue entries。

分段函数：

```text
sim >= 0.95 -> novelty = 0.05
0.80...0.95 -> novelty = 0.65
0.55...0.80 -> novelty = 1.0
0.35...0.55 -> novelty = 0.75
< 0.35 -> novelty = 0.4
```

重复论文不得只靠 novelty 降权；如果 canonical key 已在 library / finished queue / recent history 中出现，需要额外 `duplicatePenalty` 或直接标注为 suppressed。

### 4.8 质量分

V2 弱质量信号：

```text
abstract completeness
specific title length / non-marketing title
has authors
has arXiv id / source url
AI methodSoundness（如果可用）
```

无 AI 时仍可给 heuristic quality。

### 4.9 AI 分

AI 分只在结构化 review 可用时参与：

```text
S_ai = 0.35 * relevance
     + 0.20 * novelty
     + 0.20 * methodSoundness
     + 0.20 * usefulness
     - 0.15 * risk
```

然后 clamp 到 `0...1`。

约束：

- AI 分默认权重不超过 `0.10`。
- AI 失败不影响基础推荐。
- AI 评论必须显示“AI evaluation unavailable”或中文降级说明。

### 4.10 反馈分

第一阶段：

```text
S_feedback = 0.7 * similarity(candidate, positiveFeedbackPapers)
           - 0.5 * maxSimilarity(candidate, negativeFeedbackPapers)
```

正反馈：

```text
like, save, addToQueue, openPDF
```

负反馈：

```text
dislike, ignore
```

无反馈时：

```text
S_feedback = nil
```

### 4.11 动态权重

基础权重：

```text
keyword: 0.15
seedSimilarity: 0.25
projectContext: 0.15
recency: 0.10
novelty: 0.10
quality: 0.10
aiScore: 0.10
feedback: 0.05
```

归一化规则：

- 缺失的 optional feature 不计入分母。
- `queuePressurePenalty`、`duplicatePenalty` 独立从总分扣除。
- 最终分 clamp 到 `0...1`。

特殊情况：

```text
无关键词 -> keyword 权重释放给 seed/project/recency
无种子 -> seed 权重释放给 keyword/project/novelty
无关键词且无种子 -> 以 project/recency/novelty/quality 为主
```

### 4.12 多样性重排

对 score 排名前 `min(50, candidateCount)` 执行 MMR：

```text
MMR(p) = lambda * finalScore(p)
       - (1 - lambda) * maxSimilarity(p, selected)

lambda = 0.75
```

相似度使用当前 deterministic text similarity，后续可切换 embedding。

---

## 5. AI Prompt 设计

### 5.1 Search planning prompt

现有 search planning 可保留，但需要新增硬边界要求：

```text
- You may propose adjacent search keywords.
- Do not broaden categories beyond the user selected hard boundary unless explicitly allowed.
- The app will filter candidates by the selected category boundary after fetch.
```

### 5.2 Structured review prompt

替换或扩展当前 `recommendationAIEvaluationPrompt`：

```text
Return strict JSON only:
{
  "overall": "short overall evaluation",
  "reviews": [
    {
      "id": "score id",
      "relevance": 0.0,
      "novelty": 0.0,
      "method_soundness": 0.0,
      "usefulness": 0.0,
      "risk": 0.0,
      "summary": "",
      "recommendation_comment": "",
      "suitable_for": [],
      "possible_weaknesses": []
    }
  ]
}
```

安全要求：

- 限制候选数量：默认 Top 20。
- 限制每篇摘要长度：沿用 `limitedRecommendationText`。
- 不发送 PDF full text。
- 不写入 debug payload。
- 解析失败时保留原始 short comment fallback，但不阻塞推荐。

---

## 6. UI 工作

### 6.1 RecommendationView 控件

当前 UI 已有：

- query field
- category selector
- topK
- AI model
- reference paper selector

V2 增量：

- **领域硬边界说明**：在 field selector summary 下显示“只推荐这些 arXiv 领域内的论文”。
- **include cross-list toggle**：默认开启，说明 cross-list 含义。
- **关键词 chips**：第一阶段从 query 自动切分；后续再做权重编辑。
- **参考论文权重说明**：显示 “N 篇参考论文将作为兴趣锚点”。
- **AI 降级状态**：AI 失败时不使用红色阻断，而用 info/warning banner。

### 6.2 结果卡片

每篇推荐至少显示：

- title / authors / source / date / categories
- final score
- top reason keys
- keyword / seed / recency / novelty / AI / feedback 小分
- AI short comment（如果可用）
- risk chip（如果可用）
- Like / Dislike
- Add to Queue

### 6.3 历史与反馈

- 历史 run 详情应能回看 request：categories、keywords、reference paper count、includeCrossList、AI model。
- like/dislike 后当前列表即时更新 chip 状态，不需要立即重排；下一次 refresh 生效即可。
- Add to Queue 自动记录 `addToQueue` feedback。

---

## 7. 文件落点

### 7.1 Core

- `Sci-Station/Recommendation/RecommendationModels.swift`
  - request / weighted keyword / AI review / new feature fields
- `Sci-Station/Recommendation/RecommendationScorer.swift`
  - V2 feature calculation
  - dynamic weight normalization
- `Sci-Station/Recommendation/RecommendationTextSimilarity.swift`
  - phrase match helpers
  - max / mean similarity helpers
- `Sci-Station/Recommendation/RecommendationPipeline.swift`
  - category boundary filter
  - MMR rerank
  - request metadata persistence
- `Sci-Station/Recommendation/ArxivRecommendationClient.swift`
  - primary category parse or fallback
  - category post-filter support remains outside client
- 新增 `Sci-Station/Recommendation/RecommendationFeedbackStore.swift`
  - JSONL read/write
  - positive / negative profile extraction

### 7.2 App / UI

- `Sci-Station/App/AppViewModel.swift`
  - build `PaperRecommendationRequest`
  - load feedback
  - record feedback
  - parse structured AI review
  - keep current AI degradation behavior
- `Sci-Station/UI/Recommendation/RecommendationView.swift`
  - include cross-list toggle
  - score breakdown UI
  - feedback buttons
  - structured AI review display

### 7.3 Tests / Docs

- `Tools/SciStationCoreTestRunner/main.swift`
  - V2 scorer tests
  - category hard boundary tests
  - feedback store tests
  - MMR diversity tests
  - AI review parser tests
- `docs/development/manual-tests/MT20_Recommendation.md`
  - update to V2 UI/manual cases
- `docs/development/manual-tests/MT99_ReleaseRegression.md`
  - add Recommendation V2 regression gate after implementation

---

## 8. 分阶段工作计划

### R2.1：硬边界与请求模型（S1）

目标：先让“领域 = 硬过滤”成为可靠 invariant。

实现状态：已完成。核心模型、arXiv parser fallback、pipeline/app fetch category boundary、AI search planning hard-boundary prompt、UI cross-list toggle 均已接入，并补充核心测试。

任务：

1. 增加 `PaperRecommendationRequest` / `WeightedKeyword` / `includeCrossList`。
2. 增加 `RecommendationCandidate.primaryCategory` 或 parser fallback。
3. 在 pipeline 或 app fetch 后执行 category boundary filter。
4. 更新 AI search planning prompt，禁止越过用户 category 硬边界。
5. UI 增加 include cross-list toggle 与说明文案。

验收：

- `cs.CL` hard boundary 不会显示纯 `cs.AI` 候选。
- cross-list 开启/关闭结果可解释。
- 旧 snapshot 可加载。

### R2.2：Deterministic Scoring V2（S1）

目标：不用 AI 也能给出更合理的论文排序。

实现状态：已完成。已加入 weighted keyword、seed similarity、project context、publishedAt 日级 recency、novelty / duplicate suppression、V2 reason keys 与 score breakdown UI，并补充核心测试。

任务：

1. 实现 keyword phrase/title/abstract/token score。
2. 实现 seed similarity max/mean 混合。
3. 实现 project context similarity 的最小版本。
4. recency 改为优先使用 `publishedAt` 的日级指数衰减。
5. 实现 novelty / duplicate suppression。
6. 扩展 reason builder，输出更贴近论文推荐的中文解释。

验收：

- 关键词命中标题的论文排名高于只命中摘要的论文。
- 种子论文相似候选在无关键词时仍能排前。
- 已在 library/queue/history 的近重复论文被降权或标注。

### R2.3：多样性重排与反馈闭环（S1/S2）

目标：Top-K 不重复，用户反馈可影响下一轮。

实现状态：核心已完成。已新增本地 JSONL feedback store、like/dislike UI、Add to Queue 自动 feedback、feedback score、MMR rerank，并补充核心测试。后续可继续做更强的即时反馈解释与更细粒度权重编辑。

任务：

1. 新增 `RecommendationFeedbackStore`。
2. UI 增加 like/dislike。
3. Add to Queue 自动写入 `addToQueue` feedback。
4. 实现 feedback score。
5. 实现 MMR rerank。

验收：

- dislike 后相似论文下一轮被降权。
- like 后相似论文下一轮加权。
- Top 10 不应全是高度相似标题/摘要的候选。

### R2.4：结构化 AI 评审（S2）

目标：AI 从“短评生成器”升级为“审稿维度解释器”，但仍不主导排序。

实现状态：基础闭环已完成。已新增 `RecommendationAIReview`、strict JSON reviews prompt、parser fallback、optional AI score 字段、UI risk/relevance/novelty/method/usefulness 展示。后续可继续补专门 parser 单测与更严格 schema diagnostics。

任务：

1. 新增 `RecommendationAIReview`。
2. 更新 prompt 输出 strict JSON reviews。
3. 增加 parser 与 fallback。
4. 将 AI score 作为 optional feature。
5. UI 显示 relevance / novelty / method soundness / usefulness / risk。

验收：

- 无 API key 时推荐仍可用。
- AI JSON 解析失败时不丢失基础结果。
- AI risk 高的论文在 UI 上明确提示，而不是被静默隐藏。

### R2.5：Recommendation -> Queue -> Reading Plan 体验闭环（S2）

目标：推荐结果能自然进入阅读计划。

实现状态：部分完成。推荐结果显示 Queue 状态，Add to Queue 会写 feedback，并提供进入 Reading/Plan 相关页面的 CTA；历史 run 保留 request metadata。MT20 / P-AT 场景仍需后续补充。

任务：

1. 推荐结果卡片清楚显示是否已在 Queue。
2. Add to Queue 后给出下一步 CTA：打开 Queue / 生成 Reading Plan。
3. 历史 run 可回看哪些论文已加入 Queue。
4. MT20 增加 Recommendation V2 手测用例。
5. P-AT 增加 recommendation refresh scenario skeleton。

验收：

- 用户能从一次推荐 run 完成“加入 Queue -> 生成 Reading Plan”。
- scope 是 workspace/project 时，Queue 目标一致且可解释。

### R2.6：Settings / Scheduler 后续化（S3）

目标：不阻塞 V2 核心，但为后续产品化留接口。

任务：

1. Settings 中暴露 default categories、topK、includeCrossList、AI model、weights preset。
2. Foreground-only daily scheduler。
3. 外部数据源扩展接口：Crossref / Semantic Scholar / INSPIRE。

暂缓：

- 后台 daemon。
- email digest。
- bandit 主动学习。
- PDF full-text retrieval。

---

## 9. 自动化测试清单

建议新增测试名：

```text
recommendationCategoryBoundaryFiltersPrimaryOnly
recommendationCategoryBoundaryAllowsCrossListedCandidate
recommendationKeywordScoreWeightsTitleAboveAbstract
recommendationSeedSimilarityUsesMaxAndMean
recommendationRecencyUsesPublishedAtDayDecay
recommendationNoveltySuppressesLibraryDuplicates
recommendationFeedbackStoreRoundTripsJSONL
recommendationFeedbackScoreRewardsLikesAndPenalizesDislikes
recommendationMMRRerankerDiversifiesTopResults
recommendationStructuredAIReviewParserFallsBackGracefully
recommendationRunResultDecodesLegacySnapshots
```

保留既有测试：

```text
recommendationConfigYAMLRoundTripsDailySourceSettings
dailyFeedCandidateImporterMapsExternalArxivCandidates
recommendationCandidateGathererDedupsDailyFeedAndQueueTail
recommendationScorerRanksByLibraryInterestAndSuppressesFinished
recommendationPipelineWritesSnapshotAndQueuePayload
```

---

## 10. 手动测试清单

更新 `MT20_Recommendation.md` 后至少覆盖：

| ID | 标题 | 期望 |
|---|---|---|
| MT20-R2-01 | category hard boundary | 只显示选中 arXiv 领域或允许的 cross-list |
| MT20-R2-02 | keyword soft scoring | 关键词更相关的候选排前，但非精确匹配不被硬过滤 |
| MT20-R2-03 | seed paper scoring | 选择参考论文后推荐结果明显围绕该方向变化 |
| MT20-R2-04 | AI unavailable fallback | 无 API key / AI 失败时基础推荐可用 |
| MT20-R2-05 | structured AI review | 显示短评、风险、相关性、新颖性等维度 |
| MT20-R2-06 | like/dislike | 反馈写入本地并在下一轮影响排序 |
| MT20-R2-07 | MMR diversity | Top-K 不被同一主题刷屏 |
| MT20-R2-08 | Add to Queue | 推荐论文进入正确 workspace/project queue |
| MT20-R2-09 | history replay | 历史 run 可回看请求、结果、AI review 与 queue 状态 |
| MT20-R2-10 | privacy/debug audit | debug event 不包含 abstract、prompt、API key、绝对路径 |

---

## 11. 隐私、安全与审计边界

### 11.1 必须坚持

- API key 只走 Keychain / provider config，不写 workspace。
- arXiv 网络请求必须是用户触发或显式开启。
- AI evaluation 失败必须降级，不阻断基础推荐。
- Debug payload 只写 count、scope、phase、reason code，不写 paper abstract / prompt / path。
- Add to Queue 不绕过现有 Research Queue store 与 source refs。

### 11.2 AI 发送内容上限

默认上限：

```text
reference papers <= 8
candidate papers <= 20
abstract <= 900 chars each
project context <= name + description in R2.1/R2.2
```

后续若加入 wiki/shared_research，必须单独加 opt-in 或明确 UI 说明。

---

## 12. Definition of Done

R2 完成时必须满足：

- **算法**：category hard boundary、keyword、seed、project、recency、novelty、feedback、AI optional score 可解释。
- **UI**：用户知道“为什么推荐、为什么被降权、是否经过 AI、能否加入 Queue”。
- **持久化**：snapshot/history/feedback 均在 `.sci-station/recommendations/` 下，旧数据可读。
- **闭环**：推荐结果可进入 Queue，并能继续生成 Reading Plan。
- **测试**：CoreTestRunner 通过，MT20 更新，关键边界有回归测试。
- **隐私**：网络、AI、debug payload 符合 local-first 审计边界。

验证命令：

```text
swift run --quiet SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build
git diff --check
```

---

## 13. 建议优先实施切片

最小可交付切片：

```text
R2.1 category hard boundary
+ R2.2 keyword / seed / recency scoring
+ result score breakdown UI
+ legacy snapshot compatibility tests
```

第二切片：

```text
feedback store
+ like/dislike UI
+ MMR rerank
+ Add to Queue feedback
```

第三切片：

```text
structured AI review
+ risk / usefulness display
+ AI score optional feature
```

这能避免一次性改动过大，同时先解决推荐质量最核心的问题：领域误入、关键词和种子论文信号不足、重复结果过多、解释不清。
