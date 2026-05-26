import Foundation

public actor RecommendationScorer {
    private var config: RecommendationConfig

    public init(config: RecommendationConfig = RecommendationConfig()) {
        self.config = config
    }

    public func updateConfig(_ config: RecommendationConfig) {
        self.config = config
    }

    public func score(
        _ candidates: [RecommendationCandidate],
        context: RecommendationContext,
        locale: RecommendationLocale = .en
    ) async -> [RecommendationScore] {
        let reasonBuilder = ReasonBuilder(locale: locale, weights: config.weights)
        let unranked = candidates.map { candidate in
            scoreOne(candidate, context: context)
        }
        return unranked
            .sorted { lhs, rhs in
                if lhs.total != rhs.total {
                    return lhs.total > rhs.total
                }
                return lhs.candidate.displayTitle.localizedStandardCompare(rhs.candidate.displayTitle) == .orderedAscending
            }
            .enumerated()
            .map { index, score in
                var ranked = score
                ranked.rank = index + 1
                let rendered = reasonBuilder.render(score)
                ranked.reason = rendered.text
                ranked.reasonKeys = rendered.keys
                return ranked
            }
    }

    public func scoreOne(
        _ candidate: RecommendationCandidate,
        context: RecommendationContext
    ) -> RecommendationScore {
        let features = RecommendationFeatureBreakdown(
            citedByCore: citedByCore(candidate, context: context),
            libraryInterestSimilarity: libraryInterestSimilarity(candidate, context: context),
            keywordRelevance: keywordRelevance(candidate, context: context),
            seedSimilarity: seedSimilarity(candidate, context: context),
            projectContextSimilarity: projectContextSimilarity(candidate, context: context),
            recency: recency(candidate, context: context),
            novelty: novelty(candidate, context: context),
            quality: quality(candidate),
            aiScore: aiScore(candidate, context: context),
            feedback: feedback(candidate, context: context),
            openGapCoverage: openGapCoverage(candidate, context: context),
            authorOverlapWithCore: authorOverlapWithCore(candidate, context: context),
            queuePressurePenalty: queuePressurePenalty(candidate, context: context),
            duplicatePenalty: duplicatePenalty(candidate, context: context)
        )
        let total = weightedTotal(features, candidate: candidate, context: context)
        return RecommendationScore(
            id: candidate.canonicalID,
            candidate: candidate,
            features: features,
            total: total,
            evaluatedAt: context.evaluatedAt
        )
    }

    public nonisolated func citedByCore(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        guard !context.corePaperIDs.isEmpty else {
            return candidate.sourceTags.contains(.graphOneHop) ? 0.35 : 0
        }
        if !candidate.citedByCorePaperIDs.isEmpty {
            return RecommendationTextSimilarity.clamp(Double(candidate.citedByCorePaperIDs.count) / Double(context.corePaperIDs.count))
        }
        return candidate.sourceTags.contains(.graphOneHop) ? 0.35 : 0
    }

    public nonisolated func libraryInterestSimilarity(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let candidateText = Self.candidateText(candidate)
        let corpus = context.interestPapers
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastReadAt ?? lhs.updatedAt
                let rhsDate = rhs.lastReadAt ?? rhs.updatedAt
                return lhsDate > rhsDate
            }
            .map { paper in
                [paper.title, paper.abstract ?? "", paper.tags.joined(separator: " "), paper.categories.joined(separator: " ")]
                    .joined(separator: " ")
            }
        return RecommendationTextSimilarity.score(candidateText: candidateText, corpusTexts: corpus)
    }

    public nonisolated func keywordRelevance(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let keywords = context.weightedKeywords.isEmpty
            ? context.openGapKeywords.map { WeightedKeyword(text: $0) }
            : context.weightedKeywords
        return RecommendationTextSimilarity.weightedKeywordScore(
            title: candidate.displayTitle,
            abstract: candidate.abstractText ?? "",
            keywords: keywords
        ) ?? 0
    }

    public nonisolated func seedSimilarity(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let seeds = context.seedPapers.isEmpty ? context.interestPapers.filter { context.corePaperIDs.contains($0.id) } : context.seedPapers
        let seedTexts = seeds.map(Self.paperText(_:)).filter { !$0.isEmpty }
        guard !seedTexts.isEmpty else {
            return 0
        }
        let candidateText = Self.candidateText(candidate)
        let maxScore = RecommendationTextSimilarity.maxSimilarity(candidateText, corpusTexts: seedTexts)
        let meanScore = RecommendationTextSimilarity.meanSimilarity(candidateText, corpusTexts: seedTexts)
        return RecommendationTextSimilarity.clamp(0.7 * maxScore + 0.3 * meanScore)
    }

    public nonisolated func projectContextSimilarity(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let texts = context.projectContextTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !texts.isEmpty else {
            return 0
        }
        return RecommendationTextSimilarity.score(candidateText: Self.candidateText(candidate), corpusTexts: texts)
    }

    public nonisolated func recency(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        if let publishedAt = candidate.publishedAt {
            let ageDays = max(context.evaluatedAt.timeIntervalSince(publishedAt) / 86_400, 0)
            return RecommendationTextSimilarity.clamp(exp(-0.01 * ageDays))
        }
        guard let year = candidate.publishedYear else {
            if candidate.sourceTags.contains(.dailyFeed) {
                return 0.8
            }
            return 0
        }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: context.evaluatedAt)
        let delta = max(currentYear - year, 0)
        switch delta {
        case 0...1: return 1.0
        case 2...3: return 0.8
        case 4...5: return 0.5
        case 6...10: return 0.2
        default: return 0.05
        }
    }

    public nonisolated func novelty(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let references = context.noveltyReferenceTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !references.isEmpty else {
            return 0.7
        }
        let similarity = RecommendationTextSimilarity.maxSimilarity(Self.candidateText(candidate), corpusTexts: references)
        switch similarity {
        case 0.95...:
            return 0.05
        case 0.80..<0.95:
            return 0.65
        case 0.55..<0.80:
            return 1.0
        case 0.35..<0.55:
            return 0.75
        default:
            return 0.4
        }
    }

    public nonisolated func quality(_ candidate: RecommendationCandidate) -> Double {
        var components: [Double] = []
        let abstractLength = candidate.abstractText?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        components.append(abstractLength >= 500 ? 1.0 : abstractLength >= 180 ? 0.75 : abstractLength > 0 ? 0.35 : 0)
        let titleLength = RecommendationTextSimilarity.tokens(candidate.displayTitle).count
        components.append((4...22).contains(titleLength) ? 1.0 : titleLength >= 3 ? 0.65 : 0.2)
        components.append(candidate.authors.isEmpty ? 0 : 1)
        components.append((candidate.externalKey != nil || candidate.sourceURL != nil) ? 1 : 0)
        return RecommendationTextSimilarity.clamp(components.reduce(0, +) / Double(max(components.count, 1)))
    }

    public nonisolated func aiScore(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        context.aiReviewsByScoreID[candidate.canonicalID]?.compositeScore ?? 0
    }

    public nonisolated func feedback(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let candidateText = Self.candidateText(candidate)
        let positive = RecommendationTextSimilarity.meanSimilarity(candidateText, corpusTexts: context.feedbackProfile.positiveTexts)
        let negative = RecommendationTextSimilarity.maxSimilarity(candidateText, corpusTexts: context.feedbackProfile.negativeTexts)
        guard positive > 0 || negative > 0 else {
            return 0
        }
        return RecommendationTextSimilarity.clamp(0.5 + 0.7 * positive - 0.5 * negative)
    }

    public nonisolated func openGapCoverage(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let keywords = Set(context.openGapKeywords.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !keywords.isEmpty else {
            return 0
        }
        let candidateTokens = Set(RecommendationTextSimilarity.tokens([candidate.displayTitle, candidate.abstractText ?? "", candidate.categories.joined(separator: " ")].joined(separator: " ")))
        guard !candidateTokens.isEmpty else {
            return 0
        }
        let overlap = keywords.filter { keyword in
            candidateTokens.contains(keyword) || candidateTokens.contains(where: { $0.contains(keyword) })
        }.count
        return RecommendationTextSimilarity.clamp(Double(overlap) / Double(keywords.count))
    }

    public nonisolated func authorOverlapWithCore(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let candidateAuthors = Set(candidate.authors.map(normalizedAuthor(_:)).filter { !$0.isEmpty })
        guard !candidateAuthors.isEmpty else {
            return 0
        }
        let corePapers = context.interestPapers.filter { context.corePaperIDs.contains($0.id) }
        guard !corePapers.isEmpty else {
            return 0
        }
        let overlapCount = corePapers.filter { paper in
            let authors = Set(paper.authors.map(normalizedAuthor(_:)).filter { !$0.isEmpty })
            return !authors.isDisjoint(with: candidateAuthors)
        }.count
        return RecommendationTextSimilarity.clamp(Double(overlapCount) / Double(corePapers.count))
    }

    public nonisolated func queuePressurePenalty(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let keys = [candidate.paperID, candidate.externalKey, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let status = keys.compactMap { key in
            context.queueStatusByID[key] ?? context.queueStatusByID["external:\(key)"] ?? context.queueStatusByID["paper:\(key)"]
        }.first
        switch status {
        case .reading:
            return 0.6
        case .queued:
            return 0.4
        case .deferred:
            return 0.2
        case .finished, .dismissed:
            return 0.95
        case .none:
            return 0
        }
    }

    public nonisolated func duplicatePenalty(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let keys = RecommendationFeedbackStore.candidateKeys(candidate)
        if !keys.isDisjoint(with: context.duplicateCandidateKeys) {
            return 1
        }
        if queuePressurePenalty(candidate, context: context) >= 0.95 {
            return 1
        }
        return 0
    }

    private func weightedTotal(_ features: RecommendationFeatureBreakdown, candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        let w = config.weights
        var weighted = 0.0
        var totalWeight = 0.0

        func add(_ value: Double, _ weight: Double, available: Bool = true) {
            guard available, weight > 0 else {
                return
            }
            weighted += value * weight
            totalWeight += weight
        }

        add(features.citedByCore, w.citedByCore, available: !context.corePaperIDs.isEmpty || candidate.sourceTags.contains(.graphOneHop))
        add(features.libraryInterestSimilarity, w.libraryInterestSimilarity, available: !context.interestPapers.isEmpty)
        add(features.keywordRelevance, w.keywordRelevance, available: !context.weightedKeywords.isEmpty || !context.openGapKeywords.isEmpty)
        add(features.seedSimilarity, w.seedSimilarity, available: !context.seedPapers.isEmpty || !context.corePaperIDs.isEmpty)
        add(features.projectContextSimilarity, w.projectContextSimilarity, available: !context.projectContextTexts.isEmpty)
        add(features.recency, w.recency, available: features.recency > 0)
        add(features.novelty, w.novelty, available: !context.noveltyReferenceTexts.isEmpty)
        add(features.quality, w.quality)
        add(features.aiScore, w.aiScore, available: context.aiReviewsByScoreID[candidate.canonicalID] != nil)
        add(features.feedback, w.feedback, available: !context.feedbackProfile.positiveTexts.isEmpty || !context.feedbackProfile.negativeTexts.isEmpty)
        add(features.openGapCoverage, w.openGapCoverage, available: !context.openGapKeywords.isEmpty)
        add(features.authorOverlapWithCore, w.authorOverlapWithCore, available: !context.corePaperIDs.isEmpty)

        let base = totalWeight > 0 ? weighted / totalWeight : 0
        let raw = base
            - features.queuePressurePenalty * w.queuePressurePenalty
            - features.duplicatePenalty * w.duplicatePenalty
        return RecommendationTextSimilarity.clamp(raw)
    }

    private nonisolated func normalizedAuthor(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public nonisolated static func candidateText(_ candidate: RecommendationCandidate) -> String {
        [candidate.displayTitle, candidate.abstractText ?? "", candidate.categories.joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public nonisolated static func paperText(_ paper: Paper) -> String {
        [paper.title, paper.abstract ?? "", paper.tags.joined(separator: " "), paper.categories.joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public nonisolated struct ReasonBuilder: Sendable {
    public struct RenderedReason: Hashable, Sendable {
        public var text: String
        public var keys: [String]
    }

    public var locale: RecommendationLocale
    public var weights: RecommendationWeights
    public var threshold: Double

    public init(locale: RecommendationLocale = .en, weights: RecommendationWeights = RecommendationWeights(), threshold: Double = 0.20) {
        self.locale = locale
        self.weights = weights
        self.threshold = threshold
    }

    public func render(_ score: RecommendationScore) -> RenderedReason {
        let contributions: [(String, Double)] = [
            ("cited_by_core", score.features.citedByCore * weights.citedByCore),
            ("library_interest_similarity", score.features.libraryInterestSimilarity * weights.libraryInterestSimilarity),
            ("keyword_relevance", score.features.keywordRelevance * weights.keywordRelevance),
            ("seed_similarity", score.features.seedSimilarity * weights.seedSimilarity),
            ("project_context_similarity", score.features.projectContextSimilarity * weights.projectContextSimilarity),
            ("recency", score.features.recency * weights.recency),
            ("novelty", score.features.novelty * weights.novelty),
            ("quality", score.features.quality * weights.quality),
            ("ai_score", score.features.aiScore * weights.aiScore),
            ("feedback", score.features.feedback * weights.feedback),
            ("open_gap_coverage", score.features.openGapCoverage * weights.openGapCoverage),
            ("author_overlap_with_core", score.features.authorOverlapWithCore * weights.authorOverlapWithCore)
        ]
        let selected = contributions
            .filter { $0.1 >= threshold * 0.25 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }
            .prefix(2)
        guard !selected.isEmpty else {
            return RenderedReason(
                text: locale == .en ? "Weak but nonzero local recommendation signals." : "本地推荐信号较弱但非零。",
                keys: ["weak_signals"]
            )
        }
        let keys = selected.map(\.0)
        let separator = locale == .en ? "; " : "；"
        return RenderedReason(text: keys.map(template(for:)).joined(separator: separator), keys: keys)
    }

    private func template(for key: String) -> String {
        switch (key, locale) {
        case ("cited_by_core", .en):
            return "linked to your core papers"
        case ("cited_by_core", .zh):
            return "与核心论文相连"
        case ("library_interest_similarity", .en):
            return "matches recent library interests"
        case ("library_interest_similarity", .zh):
            return "匹配近期文献兴趣"
        case ("keyword_relevance", .en):
            return "matches your keywords"
        case ("keyword_relevance", .zh):
            return "关键词高度相关"
        case ("seed_similarity", .en):
            return "close to selected reference papers"
        case ("seed_similarity", .zh):
            return "贴近参考论文"
        case ("project_context_similarity", .en):
            return "fits the project context"
        case ("project_context_similarity", .zh):
            return "符合项目上下文"
        case ("recency", .en):
            return "new or recently published"
        case ("recency", .zh):
            return "新近发布"
        case ("novelty", .en):
            return "adds a distinct angle"
        case ("novelty", .zh):
            return "提供新颖角度"
        case ("quality", .en):
            return "has complete paper metadata"
        case ("quality", .zh):
            return "论文元数据较完整"
        case ("ai_score", .en):
            return "AI review is favorable"
        case ("ai_score", .zh):
            return "AI 评审信号较好"
        case ("feedback", .en):
            return "matches prior feedback"
        case ("feedback", .zh):
            return "符合历史反馈偏好"
        case ("open_gap_coverage", .en):
            return "touches open research gaps"
        case ("open_gap_coverage", .zh):
            return "覆盖当前研究空缺"
        case ("author_overlap_with_core", .en):
            return "shares authors with core papers"
        case ("author_overlap_with_core", .zh):
            return "与核心论文作者重叠"
        default:
            return locale == .en ? "local relevance signal" : "本地相关性信号"
        }
    }
}
