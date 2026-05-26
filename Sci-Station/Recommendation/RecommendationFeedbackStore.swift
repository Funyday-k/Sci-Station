import Foundation

public nonisolated enum RecommendationFeedbackType: String, Codable, Hashable, Sendable, CaseIterable {
    case like
    case dislike
    case save
    case addToQueue = "add_to_queue"
    case openPDF = "open_pdf"
    case ignore

    public var isPositive: Bool {
        switch self {
        case .like, .save, .addToQueue, .openPDF:
            return true
        case .dislike, .ignore:
            return false
        }
    }
}

public nonisolated struct RecommendationFeedbackRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(recommendationRunID)|\(paperKey)|\(feedbackType.rawValue)|\(createdAt.timeIntervalSince1970)" }
    public var paperKey: String
    public var externalKey: String?
    public var projectID: String?
    public var feedbackType: RecommendationFeedbackType
    public var recommendationRunID: String
    public var createdAt: Date

    public init(
        paperKey: String,
        externalKey: String? = nil,
        projectID: String? = nil,
        feedbackType: RecommendationFeedbackType,
        recommendationRunID: String,
        createdAt: Date = Date()
    ) {
        self.paperKey = paperKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.externalKey = externalKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmptyRecommendationFeedback
        self.projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyRecommendationFeedback
        self.feedbackType = feedbackType
        self.recommendationRunID = recommendationRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case paperKey = "paper_key"
        case externalKey = "external_key"
        case projectID = "project_id"
        case feedbackType = "feedback_type"
        case recommendationRunID = "recommendation_run_id"
        case createdAt = "created_at"
    }
}

public nonisolated struct RecommendationFeedbackProfile: Codable, Hashable, Sendable {
    public var positiveTexts: [String]
    public var negativeTexts: [String]
    public var feedbackByPaperKey: [String: RecommendationFeedbackType]

    public init(
        positiveTexts: [String] = [],
        negativeTexts: [String] = [],
        feedbackByPaperKey: [String: RecommendationFeedbackType] = [:]
    ) {
        self.positiveTexts = positiveTexts
        self.negativeTexts = negativeTexts
        self.feedbackByPaperKey = feedbackByPaperKey
    }
}

public actor RecommendationFeedbackStore {
    public static let relativePath = ".sci-station/recommendations/feedback.jsonl"

    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date

    public init(fileManager: FileManager = .default, dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public func load(in workspace: ResearchWorkspace) throws -> [RecommendationFeedbackRecord] {
        let url = workspace.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let contents = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, let data = line.data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(RecommendationFeedbackRecord.self, from: data)
            }
    }

    public func append(_ record: RecommendationFeedbackRecord, in workspace: ResearchWorkspace) throws {
        let url = workspace.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let line = String(decoding: data, as: UTF8.self) + "\n"
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func record(
        candidate: RecommendationCandidate,
        type: RecommendationFeedbackType,
        projectID: String?,
        recommendationRunID: String,
        in workspace: ResearchWorkspace
    ) throws {
        let key = Self.paperKey(for: candidate)
        guard !key.isEmpty else {
            return
        }
        try append(
            RecommendationFeedbackRecord(
                paperKey: key,
                externalKey: candidate.externalKey,
                projectID: projectID,
                feedbackType: type,
                recommendationRunID: recommendationRunID,
                createdAt: dateProvider()
            ),
            in: workspace
        )
    }

    public nonisolated static func paperKey(for candidate: RecommendationCandidate) -> String {
        (candidate.externalKey ?? candidate.paperID ?? candidate.canonicalID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public nonisolated static func profile(records: [RecommendationFeedbackRecord], scores: [RecommendationScore], projectID: String?) -> RecommendationFeedbackProfile {
        var scoreByKey: [String: RecommendationScore] = [:]
        for score in scores {
            for key in candidateKeys(score.candidate) where scoreByKey[key] == nil {
                scoreByKey[key] = score
            }
        }
        var positiveTexts: [String] = []
        var negativeTexts: [String] = []
        var feedbackByPaperKey: [String: RecommendationFeedbackType] = [:]
        for record in records where record.projectID == nil || projectID == nil || record.projectID == projectID {
            feedbackByPaperKey[record.paperKey] = record.feedbackType
            let text = scoreByKey[record.paperKey].map { candidateText($0.candidate) } ?? record.paperKey
            if record.feedbackType.isPositive {
                positiveTexts.append(text)
            } else {
                negativeTexts.append(text)
            }
        }
        return RecommendationFeedbackProfile(
            positiveTexts: positiveTexts,
            negativeTexts: negativeTexts,
            feedbackByPaperKey: feedbackByPaperKey
        )
    }

    public nonisolated static func candidateKeys(_ candidate: RecommendationCandidate) -> Set<String> {
        Set([candidate.paperID, candidate.externalKey, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { key in [key, "external:\(key)", "paper:\(key)"] })
    }

    public nonisolated static func candidateText(_ candidate: RecommendationCandidate) -> String {
        [candidate.displayTitle, candidate.abstractText ?? "", candidate.categories.joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    nonisolated var nilIfEmptyRecommendationFeedback: String? {
        isEmpty ? nil : self
    }
}
