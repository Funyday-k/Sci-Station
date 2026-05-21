import Foundation

public nonisolated enum RecommendationCandidateSource: String, Codable, Hashable, Sendable, CaseIterable {
    case graphOneHop = "graph_one_hop"
    case libraryInterest = "library_interest"
    case libraryRecent = "library_recent"
    case queueTail = "queue_tail"
    case dailyFeed = "daily_feed"
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
    public var recency: Double
    public var openGapCoverage: Double
    public var authorOverlapWithCore: Double
    public var queuePressurePenalty: Double

    public init(
        citedByCore: Double = 0.20,
        libraryInterestSimilarity: Double = 0.40,
        recency: Double = 0.15,
        openGapCoverage: Double = 0.10,
        authorOverlapWithCore: Double = 0.10,
        queuePressurePenalty: Double = 0.45
    ) {
        self.citedByCore = citedByCore
        self.libraryInterestSimilarity = libraryInterestSimilarity
        self.recency = recency
        self.openGapCoverage = openGapCoverage
        self.authorOverlapWithCore = authorOverlapWithCore
        self.queuePressurePenalty = queuePressurePenalty
    }

    private enum CodingKeys: String, CodingKey {
        case citedByCore = "cited_by_core"
        case libraryInterestSimilarity = "library_interest_similarity"
        case recency
        case openGapCoverage = "open_gap_coverage"
        case authorOverlapWithCore = "author_overlap_with_core"
        case queuePressurePenalty = "queue_pressure_penalty"
    }
}

public nonisolated struct RecommendationConfig: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

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
        try container.encodeIfPresent(addedToLibraryAt, forKey: .addedToLibraryAt)
        try container.encode(citedByCorePaperIDs.sorted(), forKey: .citedByCorePaperIDs)
        try container.encodeIfPresent(abstractText, forKey: .abstractText)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
    }
}

public nonisolated struct RecommendationContext: Sendable, Hashable {
    public var projectID: String?
    public var corePaperIDs: Set<String>
    public var queueStatusByID: [String: QueueStatus]
    public var openGapKeywords: [String]
    public var interestPapers: [Paper]
    public var evaluatedAt: Date

    public init(
        projectID: String? = nil,
        corePaperIDs: Set<String> = [],
        queueStatusByID: [String: QueueStatus] = [:],
        openGapKeywords: [String] = [],
        interestPapers: [Paper] = [],
        evaluatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.corePaperIDs = corePaperIDs
        self.queueStatusByID = queueStatusByID
        self.openGapKeywords = openGapKeywords
        self.interestPapers = interestPapers
        self.evaluatedAt = evaluatedAt
    }
}

public nonisolated struct RecommendationFeatureBreakdown: Codable, Hashable, Sendable {
    public var citedByCore: Double
    public var libraryInterestSimilarity: Double
    public var recency: Double
    public var openGapCoverage: Double
    public var authorOverlapWithCore: Double
    public var queuePressurePenalty: Double

    public init(
        citedByCore: Double = 0,
        libraryInterestSimilarity: Double = 0,
        recency: Double = 0,
        openGapCoverage: Double = 0,
        authorOverlapWithCore: Double = 0,
        queuePressurePenalty: Double = 0
    ) {
        self.citedByCore = citedByCore
        self.libraryInterestSimilarity = libraryInterestSimilarity
        self.recency = recency
        self.openGapCoverage = openGapCoverage
        self.authorOverlapWithCore = authorOverlapWithCore
        self.queuePressurePenalty = queuePressurePenalty
    }

    private enum CodingKeys: String, CodingKey {
        case citedByCore = "cited_by_core"
        case libraryInterestSimilarity = "library_interest_similarity"
        case recency
        case openGapCoverage = "open_gap_coverage"
        case authorOverlapWithCore = "author_overlap_with_core"
        case queuePressurePenalty = "queue_pressure_penalty"
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
    public var generatedAt: Date

    public init(model: String, overall: String, commentsByScoreID: [String: String], generatedAt: Date) {
        self.model = model
        self.overall = overall
        self.commentsByScoreID = commentsByScoreID
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case overall
        case commentsByScoreID = "comments_by_score_id"
        case generatedAt = "generated_at"
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
        try container.encodeIfPresent(aiEvaluation, forKey: .aiEvaluation)
    }
}
