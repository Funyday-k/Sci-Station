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
            recency: recency(candidate, context: context),
            openGapCoverage: openGapCoverage(candidate, context: context),
            authorOverlapWithCore: authorOverlapWithCore(candidate, context: context),
            queuePressurePenalty: queuePressurePenalty(candidate, context: context)
        )
        let total = weightedTotal(features)
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
        let candidateText = [candidate.displayTitle, candidate.abstractText ?? "", candidate.categories.joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    public nonisolated func recency(_ candidate: RecommendationCandidate, context: RecommendationContext) -> Double {
        guard let year = candidate.publishedYear else {
            if candidate.sourceTags.contains(.dailyFeed) {
                return 1
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

    private func weightedTotal(_ features: RecommendationFeatureBreakdown) -> Double {
        let w = config.weights
        let raw =
            features.citedByCore * w.citedByCore
            + features.libraryInterestSimilarity * w.libraryInterestSimilarity
            + features.recency * w.recency
            + features.openGapCoverage * w.openGapCoverage
            + features.authorOverlapWithCore * w.authorOverlapWithCore
            - features.queuePressurePenalty * w.queuePressurePenalty
        return RecommendationTextSimilarity.clamp(raw)
    }

    private nonisolated func normalizedAuthor(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "\n", with: " ")
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
            ("recency", score.features.recency * weights.recency),
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
        case ("recency", .en):
            return "new or recently published"
        case ("recency", .zh):
            return "新近发布"
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
