import Foundation

public nonisolated enum RecommendationCandidateSource: String, Codable, Hashable, Sendable, CaseIterable {
    case graphOneHop = "graph_one_hop"
    case libraryInterest = "library_interest"
    case libraryRecent = "library_recent"
    case dailyFeed = "daily_feed"
}

/// Workspace-or-project target for recommendation actions: library import,
/// reading-todo creation, and feedback attribution.
public nonisolated enum RecommendationTarget: Hashable, Sendable {
    case workspace
    case project(String)

    public var identifier: String {
        switch self {
        case .workspace:
            return "workspace"
        case .project(let projectID):
            return "project:\(projectID)"
        }
    }

    public var projectID: String? {
        if case .project(let id) = self {
            return id
        }
        return nil
    }

    /// Project id used when attributing recommendation feedback.
    public var projectIDForRecommendationFeedback: String? {
        projectID
    }

    public init?(identifier: String) {
        if identifier == "workspace" {
            self = .workspace
            return
        }
        if identifier.hasPrefix("project:") {
            let projectID = String(identifier.dropFirst("project:".count))
            guard !projectID.isEmpty else {
                return nil
            }
            self = .project(projectID)
            return
        }
        return nil
    }
}

public nonisolated enum RecommendationDailySourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case arxiv
    case biorxiv
    case medrxiv
}

public nonisolated enum RecommendationCadence: String, Codable, Hashable, Sendable, CaseIterable {
    case off
    case daily
    case weekly
}

public nonisolated enum RecommendationScope: String, Codable, Hashable, Sendable, CaseIterable {
    case activeProjectOnly = "active_project_only"
    case allProjects = "all_projects"
    case workspace
}

public nonisolated enum RecommendationLocale: String, Codable, Hashable, Sendable {
    case en
    case zh
}

public nonisolated enum RecommendationTriggerReason: String, Codable, Hashable, Sendable {
    case manual
    case scheduled
    case agentTool = "agent_tool"
}

public nonisolated struct WeightedKeyword: Codable, Hashable, Sendable, Identifiable {
    public var id: String { text.lowercased() }
    public var text: String
    public var weight: Double

    public init(text: String, weight: Double = 1.0) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.weight = RecommendationTextSimilarity.clamp(weight, lower: 0, upper: 2)
    }

    public static func parse(_ query: String) -> [WeightedKeyword] {
        let parts = query
            .components(separatedBy: CharacterSet(charactersIn: ",;|\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolved = parts.isEmpty ? [query.trimmingCharacters(in: .whitespacesAndNewlines)] : parts
        return resolved
            .map { WeightedKeyword(text: $0) }
            .filter { !$0.text.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case weight
    }
}

public nonisolated struct PaperTimeRange: Codable, Hashable, Sendable {
    public var submittedAfter: Date?
    public var submittedBefore: Date?

    public init(submittedAfter: Date? = nil, submittedBefore: Date? = nil) {
        self.submittedAfter = submittedAfter
        self.submittedBefore = submittedBefore
    }

    private enum CodingKeys: String, CodingKey {
        case submittedAfter = "submitted_after"
        case submittedBefore = "submitted_before"
    }
}

public nonisolated struct PaperRecommendationRequest: Codable, Hashable, Sendable {
    public var arxivCategories: [String]
    public var includeCrossList: Bool
    public var keywords: [WeightedKeyword]
    public var seedPaperIDs: [Paper.ID]
    public var projectID: String?
    public var limit: Int
    public var timeRange: PaperTimeRange?
    public var aiModel: String?

    public init(
        arxivCategories: [String] = [],
        includeCrossList: Bool = true,
        keywords: [WeightedKeyword] = [],
        seedPaperIDs: [Paper.ID] = [],
        projectID: String? = nil,
        limit: Int = 10,
        timeRange: PaperTimeRange? = nil,
        aiModel: String? = nil
    ) {
        self.arxivCategories = arxivCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.includeCrossList = includeCrossList
        self.keywords = keywords.filter { !$0.text.isEmpty && $0.weight > 0 }
        self.seedPaperIDs = seedPaperIDs
        self.projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecommendation
        self.limit = min(max(limit, 1), 100)
        self.timeRange = timeRange
        self.aiModel = aiModel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecommendation
    }

    private enum CodingKeys: String, CodingKey {
        case arxivCategories = "arxiv_categories"
        case includeCrossList = "include_cross_list"
        case keywords
        case seedPaperIDs = "seed_paper_ids"
        case projectID = "project_id"
        case limit
        case timeRange = "time_range"
        case aiModel = "ai_model"
    }
}

public nonisolated struct RecommendationDailySourceConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: RecommendationDailySourceKind
    public var enabled: Bool
    public var categories: [String]
    public var includeCrossList: Bool

    public init(
        kind: RecommendationDailySourceKind,
        enabled: Bool = false,
        categories: [String] = [],
        includeCrossList: Bool = false
    ) {
        self.kind = kind
        self.enabled = enabled
        self.categories = categories
        self.includeCrossList = includeCrossList
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case enabled
        case categories
        case includeCrossList = "include_cross_list"
    }
}

public nonisolated struct RecommendationWeights: Codable, Hashable, Sendable {
    public var citedByCore: Double
    public var libraryInterestSimilarity: Double
    public var keywordRelevance: Double
    public var seedSimilarity: Double
    public var projectContextSimilarity: Double
    public var recency: Double
    public var novelty: Double
    public var quality: Double
    public var aiScore: Double
    public var feedback: Double
    public var openGapCoverage: Double
    public var authorOverlapWithCore: Double
    public var duplicatePenalty: Double

    public init(
        citedByCore: Double = 0.20,
        libraryInterestSimilarity: Double = 0.40,
        keywordRelevance: Double = 0.15,
        seedSimilarity: Double = 0.25,
        projectContextSimilarity: Double = 0.15,
        recency: Double = 0.10,
        novelty: Double = 0.10,
        quality: Double = 0.10,
        aiScore: Double = 0.10,
        feedback: Double = 0.05,
        openGapCoverage: Double = 0.10,
        authorOverlapWithCore: Double = 0.10,
        duplicatePenalty: Double = 0.65
    ) {
        self.citedByCore = citedByCore
        self.libraryInterestSimilarity = libraryInterestSimilarity
        self.keywordRelevance = keywordRelevance
        self.seedSimilarity = seedSimilarity
        self.projectContextSimilarity = projectContextSimilarity
        self.recency = recency
        self.novelty = novelty
        self.quality = quality
        self.aiScore = aiScore
        self.feedback = feedback
        self.openGapCoverage = openGapCoverage
        self.authorOverlapWithCore = authorOverlapWithCore
        self.duplicatePenalty = duplicatePenalty
    }

    private enum CodingKeys: String, CodingKey {
        case citedByCore = "cited_by_core"
        case libraryInterestSimilarity = "library_interest_similarity"
        case keywordRelevance = "keyword_relevance"
        case seedSimilarity = "seed_similarity"
        case projectContextSimilarity = "project_context_similarity"
        case recency
        case novelty
        case quality
        case aiScore = "ai_score"
        case feedback
        case openGapCoverage = "open_gap_coverage"
        case authorOverlapWithCore = "author_overlap_with_core"
        case duplicatePenalty = "duplicate_penalty"
    }

    public init(from decoder: Decoder) throws {
        let defaults = RecommendationWeights()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        citedByCore = try container.decodeIfPresent(Double.self, forKey: .citedByCore) ?? defaults.citedByCore
        libraryInterestSimilarity = try container.decodeIfPresent(Double.self, forKey: .libraryInterestSimilarity) ?? defaults.libraryInterestSimilarity
        keywordRelevance = try container.decodeIfPresent(Double.self, forKey: .keywordRelevance) ?? defaults.keywordRelevance
        seedSimilarity = try container.decodeIfPresent(Double.self, forKey: .seedSimilarity) ?? defaults.seedSimilarity
        projectContextSimilarity = try container.decodeIfPresent(Double.self, forKey: .projectContextSimilarity) ?? defaults.projectContextSimilarity
        recency = try container.decodeIfPresent(Double.self, forKey: .recency) ?? defaults.recency
        novelty = try container.decodeIfPresent(Double.self, forKey: .novelty) ?? defaults.novelty
        quality = try container.decodeIfPresent(Double.self, forKey: .quality) ?? defaults.quality
        aiScore = try container.decodeIfPresent(Double.self, forKey: .aiScore) ?? defaults.aiScore
        feedback = try container.decodeIfPresent(Double.self, forKey: .feedback) ?? defaults.feedback
        openGapCoverage = try container.decodeIfPresent(Double.self, forKey: .openGapCoverage) ?? defaults.openGapCoverage
        authorOverlapWithCore = try container.decodeIfPresent(Double.self, forKey: .authorOverlapWithCore) ?? defaults.authorOverlapWithCore
        duplicatePenalty = try container.decodeIfPresent(Double.self, forKey: .duplicatePenalty) ?? defaults.duplicatePenalty
    }
}

public nonisolated struct RecommendationConfig: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var cadence: RecommendationCadence
    public var scope: RecommendationScope
    public var topK: Int
    public var externalNetworkEnabled: Bool
    public var maxDailyCandidates: Int
    public var libraryRecentDays: Int
    public var weights: RecommendationWeights
    public var dailySources: [RecommendationDailySourceConfig]

    public init(
        schemaVersion: Int = RecommendationConfig.currentSchemaVersion,
        cadence: RecommendationCadence = .off,
        scope: RecommendationScope = .activeProjectOnly,
        topK: Int = 10,
        externalNetworkEnabled: Bool = false,
        maxDailyCandidates: Int = 100,
        libraryRecentDays: Int = 60,
        weights: RecommendationWeights = RecommendationWeights(),
        dailySources: [RecommendationDailySourceConfig] = [
            RecommendationDailySourceConfig(kind: .arxiv, enabled: false, categories: ["cs.AI", "cs.CL", "cs.CV", "cs.LG"]),
            RecommendationDailySourceConfig(kind: .biorxiv, enabled: false),
            RecommendationDailySourceConfig(kind: .medrxiv, enabled: false)
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.cadence = cadence
        self.scope = scope
        self.topK = min(max(topK, 1), 100)
        self.externalNetworkEnabled = externalNetworkEnabled
        self.maxDailyCandidates = min(max(maxDailyCandidates, 1), 500)
        self.libraryRecentDays = max(libraryRecentDays, 1)
        self.weights = weights
        self.dailySources = dailySources
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case cadence
        case scope
        case topK = "top_k"
        case externalNetworkEnabled = "external_network_enabled"
        case maxDailyCandidates = "max_daily_candidates"
        case libraryRecentDays = "library_recent_days"
        case weights
        case dailySources = "daily_sources"
    }
}

public nonisolated struct RecommendationCandidate: Codable, Hashable, Sendable, Identifiable {
    public var id: String { canonicalID }
    public var canonicalID: String
    public var paperID: String?
    public var externalKey: String?
    public var displayTitle: String
    public var authors: [String]
    public var publishedYear: Int?
    public var sourceTags: Set<RecommendationCandidateSource>
    public var sourceName: String?
    public var sourceURL: String?
    public var pdfURL: String?
    public var categories: [String]
    public var primaryCategory: String?
    public var addedToLibraryAt: Date?
    public var citedByCorePaperIDs: Set<String>
    public var abstractText: String?
    public var publishedAt: Date?

    public init(
        canonicalID: String,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        authors: [String] = [],
        publishedYear: Int? = nil,
        sourceTags: Set<RecommendationCandidateSource> = [],
        sourceName: String? = nil,
        sourceURL: String? = nil,
        pdfURL: String? = nil,
        categories: [String] = [],
        primaryCategory: String? = nil,
        addedToLibraryAt: Date? = nil,
        citedByCorePaperIDs: Set<String> = [],
        abstractText: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.canonicalID = canonicalID
        self.paperID = paperID
        self.externalKey = externalKey
        self.displayTitle = displayTitle
        self.authors = authors
        self.publishedYear = publishedYear
        self.sourceTags = sourceTags
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.pdfURL = pdfURL
        self.categories = categories
        self.primaryCategory = primaryCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecommendation ?? categories.first
        self.addedToLibraryAt = addedToLibraryAt
        self.citedByCorePaperIDs = citedByCorePaperIDs
        self.abstractText = abstractText
        self.publishedAt = publishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalID = "canonical_id"
        case paperID = "paper_id"
        case externalKey = "external_key"
        case displayTitle = "display_title"
        case authors
        case publishedYear = "published_year"
        case sourceTags = "source_tags"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case pdfURL = "pdf_url"
        case categories
        case primaryCategory = "primary_category"
        case addedToLibraryAt = "added_to_library_at"
        case citedByCorePaperIDs = "cited_by_core_paper_ids"
        case abstractText = "abstract_text"
        case publishedAt = "published_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalID = try container.decode(String.self, forKey: .canonicalID)
        paperID = try container.decodeIfPresent(String.self, forKey: .paperID)
        externalKey = try container.decodeIfPresent(String.self, forKey: .externalKey)
        displayTitle = try container.decode(String.self, forKey: .displayTitle)
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        publishedYear = try container.decodeIfPresent(Int.self, forKey: .publishedYear)
        sourceTags = Set(try container.decodeIfPresent([RecommendationCandidateSource].self, forKey: .sourceTags) ?? [])
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        pdfURL = try container.decodeIfPresent(String.self, forKey: .pdfURL)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        primaryCategory = try container.decodeIfPresent(String.self, forKey: .primaryCategory) ?? categories.first
        addedToLibraryAt = try container.decodeIfPresent(Date.self, forKey: .addedToLibraryAt)
        citedByCorePaperIDs = Set(try container.decodeIfPresent([String].self, forKey: .citedByCorePaperIDs) ?? [])
        abstractText = try container.decodeIfPresent(String.self, forKey: .abstractText)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalID, forKey: .canonicalID)
        try container.encodeIfPresent(paperID, forKey: .paperID)
        try container.encodeIfPresent(externalKey, forKey: .externalKey)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(authors, forKey: .authors)
        try container.encodeIfPresent(publishedYear, forKey: .publishedYear)
        try container.encode(sourceTags.sorted { $0.rawValue < $1.rawValue }, forKey: .sourceTags)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(pdfURL, forKey: .pdfURL)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(primaryCategory, forKey: .primaryCategory)
        try container.encodeIfPresent(addedToLibraryAt, forKey: .addedToLibraryAt)
        try container.encode(citedByCorePaperIDs.sorted(), forKey: .citedByCorePaperIDs)
        try container.encodeIfPresent(abstractText, forKey: .abstractText)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
    }
}

public nonisolated struct RecommendationContext: Sendable, Hashable {
    public var projectID: String?
    public var corePaperIDs: Set<String>
    public var openGapKeywords: [String]
    public var weightedKeywords: [WeightedKeyword]
    public var interestPapers: [Paper]
    public var seedPapers: [Paper]
    public var projectContextTexts: [String]
    public var noveltyReferenceTexts: [String]
    public var duplicateCandidateKeys: Set<String>
    public var feedbackProfile: RecommendationFeedbackProfile
    public var aiReviewsByScoreID: [String: RecommendationAIReview]
    public var evaluatedAt: Date

    public init(
        projectID: String? = nil,
        corePaperIDs: Set<String> = [],
        openGapKeywords: [String] = [],
        weightedKeywords: [WeightedKeyword] = [],
        interestPapers: [Paper] = [],
        seedPapers: [Paper] = [],
        projectContextTexts: [String] = [],
        noveltyReferenceTexts: [String] = [],
        duplicateCandidateKeys: Set<String> = [],
        feedbackProfile: RecommendationFeedbackProfile = RecommendationFeedbackProfile(),
        aiReviewsByScoreID: [String: RecommendationAIReview] = [:],
        evaluatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.corePaperIDs = corePaperIDs
        self.openGapKeywords = openGapKeywords
        self.weightedKeywords = weightedKeywords
        self.interestPapers = interestPapers
        self.seedPapers = seedPapers
        self.projectContextTexts = projectContextTexts
        self.noveltyReferenceTexts = noveltyReferenceTexts
        self.duplicateCandidateKeys = duplicateCandidateKeys
        self.feedbackProfile = feedbackProfile
        self.aiReviewsByScoreID = aiReviewsByScoreID
        self.evaluatedAt = evaluatedAt
    }
}

public nonisolated struct RecommendationFeatureBreakdown: Codable, Hashable, Sendable {
    public var citedByCore: Double
    public var libraryInterestSimilarity: Double
    public var keywordRelevance: Double
    public var seedSimilarity: Double
    public var projectContextSimilarity: Double
    public var recency: Double
    public var novelty: Double
    public var quality: Double
    public var aiScore: Double
    public var feedback: Double
    public var openGapCoverage: Double
    public var authorOverlapWithCore: Double
    public var duplicatePenalty: Double

    public init(
        citedByCore: Double = 0,
        libraryInterestSimilarity: Double = 0,
        keywordRelevance: Double = 0,
        seedSimilarity: Double = 0,
        projectContextSimilarity: Double = 0,
        recency: Double = 0,
        novelty: Double = 0,
        quality: Double = 0,
        aiScore: Double = 0,
        feedback: Double = 0,
        openGapCoverage: Double = 0,
        authorOverlapWithCore: Double = 0,
        duplicatePenalty: Double = 0
    ) {
        self.citedByCore = citedByCore
        self.libraryInterestSimilarity = libraryInterestSimilarity
        self.keywordRelevance = keywordRelevance
        self.seedSimilarity = seedSimilarity
        self.projectContextSimilarity = projectContextSimilarity
        self.recency = recency
        self.novelty = novelty
        self.quality = quality
        self.aiScore = aiScore
        self.feedback = feedback
        self.openGapCoverage = openGapCoverage
        self.authorOverlapWithCore = authorOverlapWithCore
        self.duplicatePenalty = duplicatePenalty
    }

    private enum CodingKeys: String, CodingKey {
        case citedByCore = "cited_by_core"
        case libraryInterestSimilarity = "library_interest_similarity"
        case keywordRelevance = "keyword_relevance"
        case seedSimilarity = "seed_similarity"
        case projectContextSimilarity = "project_context_similarity"
        case recency
        case novelty
        case quality
        case aiScore = "ai_score"
        case feedback
        case openGapCoverage = "open_gap_coverage"
        case authorOverlapWithCore = "author_overlap_with_core"
        case duplicatePenalty = "duplicate_penalty"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        citedByCore = try container.decodeIfPresent(Double.self, forKey: .citedByCore) ?? 0
        libraryInterestSimilarity = try container.decodeIfPresent(Double.self, forKey: .libraryInterestSimilarity) ?? 0
        keywordRelevance = try container.decodeIfPresent(Double.self, forKey: .keywordRelevance) ?? 0
        seedSimilarity = try container.decodeIfPresent(Double.self, forKey: .seedSimilarity) ?? 0
        projectContextSimilarity = try container.decodeIfPresent(Double.self, forKey: .projectContextSimilarity) ?? 0
        recency = try container.decodeIfPresent(Double.self, forKey: .recency) ?? 0
        novelty = try container.decodeIfPresent(Double.self, forKey: .novelty) ?? 0
        quality = try container.decodeIfPresent(Double.self, forKey: .quality) ?? 0
        aiScore = try container.decodeIfPresent(Double.self, forKey: .aiScore) ?? 0
        feedback = try container.decodeIfPresent(Double.self, forKey: .feedback) ?? 0
        openGapCoverage = try container.decodeIfPresent(Double.self, forKey: .openGapCoverage) ?? 0
        authorOverlapWithCore = try container.decodeIfPresent(Double.self, forKey: .authorOverlapWithCore) ?? 0
        duplicatePenalty = try container.decodeIfPresent(Double.self, forKey: .duplicatePenalty) ?? 0
    }
}

public nonisolated struct RecommendationScore: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var candidate: RecommendationCandidate
    public var features: RecommendationFeatureBreakdown
    public var total: Double
    public var rank: Int
    public var reason: String
    public var reasonKeys: [String]
    public var evaluatedAt: Date

    public init(
        id: String,
        candidate: RecommendationCandidate,
        features: RecommendationFeatureBreakdown,
        total: Double,
        rank: Int = 0,
        reason: String = "",
        reasonKeys: [String] = [],
        evaluatedAt: Date
    ) {
        self.id = id
        self.candidate = candidate
        self.features = features
        self.total = total
        self.rank = rank
        self.reason = reason
        self.reasonKeys = reasonKeys
        self.evaluatedAt = evaluatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case candidate
        case features
        case total
        case rank
        case reason
        case reasonKeys = "reason_keys"
        case evaluatedAt = "evaluated_at"
    }
}

public nonisolated struct RecommendationAIEvaluation: Codable, Hashable, Sendable {
    public var model: String
    public var overall: String
    public var commentsByScoreID: [String: String]
    public var reviewsByScoreID: [String: RecommendationAIReview]
    public var generatedAt: Date

    public init(
        model: String,
        overall: String,
        commentsByScoreID: [String: String],
        reviewsByScoreID: [String: RecommendationAIReview] = [:],
        generatedAt: Date
    ) {
        self.model = model
        self.overall = overall
        self.commentsByScoreID = commentsByScoreID
        self.reviewsByScoreID = reviewsByScoreID
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case overall
        case commentsByScoreID = "comments_by_score_id"
        case reviewsByScoreID = "reviews_by_score_id"
        case generatedAt = "generated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        overall = try container.decode(String.self, forKey: .overall)
        commentsByScoreID = try container.decodeIfPresent([String: String].self, forKey: .commentsByScoreID) ?? [:]
        reviewsByScoreID = try container.decodeIfPresent([String: RecommendationAIReview].self, forKey: .reviewsByScoreID) ?? [:]
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }
}

public nonisolated struct RecommendationAIReview: Codable, Hashable, Sendable {
    public var relevance: Double
    public var novelty: Double
    public var methodSoundness: Double
    public var usefulness: Double
    public var risk: Double
    public var summary: String
    public var recommendationComment: String
    public var suitableFor: [String]
    public var possibleWeaknesses: [String]

    public init(
        relevance: Double = 0,
        novelty: Double = 0,
        methodSoundness: Double = 0,
        usefulness: Double = 0,
        risk: Double = 0,
        summary: String = "",
        recommendationComment: String = "",
        suitableFor: [String] = [],
        possibleWeaknesses: [String] = []
    ) {
        self.relevance = RecommendationTextSimilarity.clamp(relevance)
        self.novelty = RecommendationTextSimilarity.clamp(novelty)
        self.methodSoundness = RecommendationTextSimilarity.clamp(methodSoundness)
        self.usefulness = RecommendationTextSimilarity.clamp(usefulness)
        self.risk = RecommendationTextSimilarity.clamp(risk)
        self.summary = summary
        self.recommendationComment = recommendationComment
        self.suitableFor = suitableFor
        self.possibleWeaknesses = possibleWeaknesses
    }

    public var compositeScore: Double {
        RecommendationTextSimilarity.clamp(
            0.35 * relevance
            + 0.20 * novelty
            + 0.20 * methodSoundness
            + 0.20 * usefulness
            - 0.15 * risk
        )
    }

    private enum CodingKeys: String, CodingKey {
        case relevance
        case novelty
        case methodSoundness = "method_soundness"
        case usefulness
        case risk
        case summary
        case recommendationComment = "recommendation_comment"
        case suitableFor = "suitable_for"
        case possibleWeaknesses = "possible_weaknesses"
    }
}

public nonisolated struct RecommendationRunResult: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var trigger: RecommendationTriggerReason
    public var contextProjectID: String?
    public var generatedAt: Date
    public var candidateCount: Int
    public var scores: [RecommendationScore]
    public var query: String
    public var categories: [String]
    public var sourceDate: Date?
    public var sourceNote: String?
    public var referencePaperIDs: [String]
    public var keywords: [WeightedKeyword]
    public var includeCrossList: Bool
    public var aiModel: String?
    public var aiEvaluation: RecommendationAIEvaluation?

    public init(
        id: String,
        trigger: RecommendationTriggerReason,
        contextProjectID: String?,
        generatedAt: Date,
        candidateCount: Int,
        scores: [RecommendationScore],
        query: String = "",
        categories: [String] = [],
        sourceDate: Date? = nil,
        sourceNote: String? = nil,
        referencePaperIDs: [String] = [],
        keywords: [WeightedKeyword] = [],
        includeCrossList: Bool = true,
        aiModel: String? = nil,
        aiEvaluation: RecommendationAIEvaluation? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.contextProjectID = contextProjectID
        self.generatedAt = generatedAt
        self.candidateCount = candidateCount
        self.scores = scores
        self.query = query
        self.categories = categories
        self.sourceDate = sourceDate
        self.sourceNote = sourceNote
        self.referencePaperIDs = referencePaperIDs
        self.keywords = keywords
        self.includeCrossList = includeCrossList
        self.aiModel = aiModel
        self.aiEvaluation = aiEvaluation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case trigger
        case contextProjectID = "context_project_id"
        case generatedAt = "generated_at"
        case candidateCount = "candidate_count"
        case scores
        case query
        case categories
        case sourceDate = "source_date"
        case sourceNote = "source_note"
        case referencePaperIDs = "reference_paper_ids"
        case keywords
        case includeCrossList = "include_cross_list"
        case aiModel = "ai_model"
        case aiEvaluation = "ai_evaluation"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trigger = try container.decode(RecommendationTriggerReason.self, forKey: .trigger)
        contextProjectID = try container.decodeIfPresent(String.self, forKey: .contextProjectID)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        candidateCount = try container.decode(Int.self, forKey: .candidateCount)
        scores = try container.decode([RecommendationScore].self, forKey: .scores)
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        sourceDate = try container.decodeIfPresent(Date.self, forKey: .sourceDate)
        sourceNote = try container.decodeIfPresent(String.self, forKey: .sourceNote)
        referencePaperIDs = try container.decodeIfPresent([String].self, forKey: .referencePaperIDs) ?? []
        keywords = try container.decodeIfPresent([WeightedKeyword].self, forKey: .keywords) ?? WeightedKeyword.parse(query)
        includeCrossList = try container.decodeIfPresent(Bool.self, forKey: .includeCrossList) ?? true
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel)
        aiEvaluation = try container.decodeIfPresent(RecommendationAIEvaluation.self, forKey: .aiEvaluation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trigger, forKey: .trigger)
        try container.encodeIfPresent(contextProjectID, forKey: .contextProjectID)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(candidateCount, forKey: .candidateCount)
        try container.encode(scores, forKey: .scores)
        try container.encode(query, forKey: .query)
        try container.encode(categories, forKey: .categories)
        try container.encodeIfPresent(sourceDate, forKey: .sourceDate)
        try container.encodeIfPresent(sourceNote, forKey: .sourceNote)
        try container.encode(referencePaperIDs, forKey: .referencePaperIDs)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(includeCrossList, forKey: .includeCrossList)
        try container.encodeIfPresent(aiModel, forKey: .aiModel)
        try container.encodeIfPresent(aiEvaluation, forKey: .aiEvaluation)
    }
}

private extension String {
    nonisolated var nilIfEmptyRecommendation: String? {
        isEmpty ? nil : self
    }
}
