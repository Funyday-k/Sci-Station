import CryptoKit
import Foundation

public actor RecommendationPipeline {
    public static let notesRelativeDirectory = ".sci-station/recommendations/notes"
    public static let archivedNotesRelativeDirectory = ".sci-station/recommendations/archived"
    public static let historyRelativePath = ".sci-station/recommendations/history.jsonl"

    private let gatherer: RecommendationCandidateGatherer
    private let scorer: RecommendationScorer
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date
    private var lastCandidateHash: String?
    private var lastRunAt: Date?

    public init(
        gatherer: RecommendationCandidateGatherer = RecommendationCandidateGatherer(),
        scorer: RecommendationScorer = RecommendationScorer(),
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gatherer = gatherer
        self.scorer = scorer
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public func run(
        workspace: ResearchWorkspace,
        papers: [Paper],
        queueEntries: [ResearchQueueEntry] = [],
        dailyFeedCandidates: [RecommendationCandidate] = [],
        graph: GraphReadModel? = nil,
        context: RecommendationContext,
        config: RecommendationConfig = RecommendationConfig(),
        trigger: RecommendationTriggerReason = .manual,
        locale: RecommendationLocale = .en,
        persistSnapshot: Bool = true,
        force: Bool = false,
        query: String = "",
        categories: [String] = [],
        referencePaperIDs: [String] = [],
        sourceDate: Date? = nil,
        sourceNote: String? = nil
    ) async throws -> RecommendationRunResult? {
        await scorer.updateConfig(config)
        var resolvedContext = context
        resolvedContext.evaluatedAt = context.evaluatedAt
        let candidates = await gatherer.gather(
            papers: papers,
            queueEntries: queueEntries,
            dailyFeedCandidates: dailyFeedCandidates,
            graph: graph,
            context: resolvedContext,
            config: config
        )
        let hash = Self.candidateHash(candidates)
        let now = dateProvider()
        if !force,
           let lastCandidateHash,
           let lastRunAt,
           lastCandidateHash == hash,
           now.timeIntervalSince(lastRunAt) < 30 * 60 {
            return nil
        }

        let scores = await scorer.score(candidates, context: resolvedContext, locale: locale)
        let topK = Array(scores.prefix(config.topK))
        let snapshotID = Self.snapshotID(date: now, hash: hash)
        let result = RecommendationRunResult(
            id: snapshotID,
            trigger: trigger,
            contextProjectID: context.projectID,
            generatedAt: now,
            candidateCount: candidates.count,
            scores: topK,
            query: query,
            categories: categories,
            sourceDate: sourceDate,
            sourceNote: sourceNote,
            referencePaperIDs: referencePaperIDs
        )

        if persistSnapshot {
            try persist(result, candidateHash: hash, workspace: workspace)
        }
        lastCandidateHash = hash
        lastRunAt = now
        return result
    }

    public nonisolated static func recommendationNotePayload(
        for result: RecommendationRunResult,
        queueScope: QueueScope
    ) -> JSONValue {
        .object([
            "schema_version": .number("1"),
            "kind": .string("recommendation_note"),
            "artifact_kind": .string("recommendation_note"),
            "queue_scope": .string(queueScope.identifier),
            "snapshot_id": .string(result.id),
            "trigger": .string(result.trigger.rawValue),
            "queue_candidates": .array(result.scores.map { score in
                var object: [String: JSONValue] = [
                    "canonical_id": .string(score.id),
                    "display_title": .string(score.candidate.displayTitle),
                    "rank": .number(String(score.rank)),
                    "total": .number(String(format: "%.6f", score.total)),
                    "reason": .string(score.reason)
                ]
                if let paperID = score.candidate.paperID {
                    object["paper_id"] = .string(paperID)
                }
                if let externalKey = score.candidate.externalKey {
                    object["external_key"] = .string(externalKey)
                }
                return .object(object)
            })
        ])
    }

    public nonisolated static func candidateHash(_ candidates: [RecommendationCandidate]) -> String {
        let canonical = candidates
            .map { candidate in
                [
                    candidate.canonicalID,
                    candidate.displayTitle,
                    candidate.sourceTags.map(\.rawValue).sorted().joined(separator: ",")
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated static func snapshotID(date: Date, hash: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let datePart = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return "rec-\(datePart)-\(hash.prefix(8))"
    }

    public func loadHistory(workspace: ResearchWorkspace, limit: Int = 20) throws -> [RecommendationRunResult] {
        let notesDirectory = workspace.fileURL(for: Self.notesRelativeDirectory)
        guard fileManager.fileExists(atPath: notesDirectory.path) else {
            return []
        }
        let urls = try fileManager.contentsOfDirectory(at: notesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try urls.compactMap { url in
            let data = try Data(contentsOf: url)
            return try? decoder.decode(RecommendationRunResult.self, from: data)
        }
        .sorted { lhs, rhs in
            lhs.generatedAt > rhs.generatedAt
        }
        .prefix(max(limit, 1))
        .map { $0 }
    }

    public func recommendedCandidateKeys(workspace: ResearchWorkspace) throws -> Set<String> {
        let history = try loadHistory(workspace: workspace, limit: 200)
        return Set(history.flatMap { result in
            result.scores.flatMap { score in
                [
                    score.id,
                    score.candidate.canonicalID,
                    score.candidate.externalKey
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            }
        })
    }

    public func persistSnapshot(_ result: RecommendationRunResult, workspace: ResearchWorkspace) throws {
        let notesDirectory = workspace.fileURL(for: Self.notesRelativeDirectory)
        try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let snapshotURL = notesDirectory.appendingPathComponent("\(result.id).json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: snapshotURL, options: .atomic)
    }

    public func archiveSnapshot(id: String, workspace: ResearchWorkspace) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return
        }
        let notesDirectory = workspace.fileURL(for: Self.notesRelativeDirectory)
        let archivedDirectory = workspace.fileURL(for: Self.archivedNotesRelativeDirectory)
        let sourceURL = notesDirectory.appendingPathComponent("\(trimmedID).json", isDirectory: false)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        try fileManager.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)
        let destinationURL = archivedDirectory.appendingPathComponent("\(trimmedID).json", isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func persist(_ result: RecommendationRunResult, candidateHash: String, workspace: ResearchWorkspace) throws {
        try persistSnapshot(result, workspace: workspace)

        let historyURL = workspace.fileURL(for: Self.historyRelativePath)
        try fileManager.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let historyRecord: JSONValue = .object([
            "schema_version": .number("1"),
            "snapshot_id": .string(result.id),
            "candidate_hash": .string(candidateHash),
            "generated_at": .string(ISO8601DateFormatter().string(from: result.generatedAt)),
            "top_k": .number(String(result.scores.count)),
            "candidate_count": .number(String(result.candidateCount)),
            "trigger": .string(result.trigger.rawValue)
        ])
        let line = historyRecord.canonicalJSON + "\n"
        if fileManager.fileExists(atPath: historyURL.path) {
            let handle = try FileHandle(forWritingTo: historyURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: historyURL, atomically: true, encoding: .utf8)
        }
    }
}
