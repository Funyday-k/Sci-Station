import Foundation

public nonisolated enum RecommendationConfigStoreError: Error, Sendable, Equatable {
    case invalidTopK(String)
    case invalidMaxDailyCandidates(String)
}

public nonisolated struct RecommendationConfigStore {
    public static let relativePath = ".sci-station/recommendations/config.yaml"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in workspace: ResearchWorkspace) throws -> RecommendationConfig {
        let url = workspace.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return RecommendationConfig()
        }
        return try Self.decode(String(contentsOf: url, encoding: .utf8))
    }

    public func save(_ config: RecommendationConfig, in workspace: ResearchWorkspace) throws {
        let url = workspace.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(config).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func encode(_ config: RecommendationConfig) -> String {
        var lines: [String] = []
        lines.append("schema_version: \(config.schemaVersion)")
        lines.append("cadence: \(config.cadence.rawValue)")
        lines.append("scope: \(config.scope.rawValue)")
        lines.append("top_k: \(config.topK)")
        lines.append("external_network_enabled: \(config.externalNetworkEnabled)")
        lines.append("max_daily_candidates: \(config.maxDailyCandidates)")
        lines.append("library_recent_days: \(config.libraryRecentDays)")
        lines.append("weights:")
        lines.append("  cited_by_core: \(format(config.weights.citedByCore))")
        lines.append("  library_interest_similarity: \(format(config.weights.libraryInterestSimilarity))")
        lines.append("  keyword_relevance: \(format(config.weights.keywordRelevance))")
        lines.append("  seed_similarity: \(format(config.weights.seedSimilarity))")
        lines.append("  project_context_similarity: \(format(config.weights.projectContextSimilarity))")
        lines.append("  recency: \(format(config.weights.recency))")
        lines.append("  novelty: \(format(config.weights.novelty))")
        lines.append("  quality: \(format(config.weights.quality))")
        lines.append("  ai_score: \(format(config.weights.aiScore))")
        lines.append("  feedback: \(format(config.weights.feedback))")
        lines.append("  open_gap_coverage: \(format(config.weights.openGapCoverage))")
        lines.append("  author_overlap_with_core: \(format(config.weights.authorOverlapWithCore))")
        lines.append("  queue_pressure_penalty: \(format(config.weights.queuePressurePenalty))")
        lines.append("  duplicate_penalty: \(format(config.weights.duplicatePenalty))")
        lines.append("daily_sources:")
        if config.dailySources.isEmpty {
            lines.append("  []")
        } else {
            for source in config.dailySources {
                lines.append("  - kind: \(source.kind.rawValue)")
                lines.append("    enabled: \(source.enabled)")
                lines.append("    categories: \(inlineArray(source.categories))")
                lines.append("    include_cross_list: \(source.includeCrossList)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func decode(_ yaml: String) throws -> RecommendationConfig {
        var config = RecommendationConfig()
        let lines = yaml.components(separatedBy: .newlines)
        var index = 0
        var dailySources: [RecommendationDailySourceConfig] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            if trimmed.hasPrefix("schema_version:") {
                config.schemaVersion = Int(value(after: "schema_version:", in: trimmed)) ?? RecommendationConfig.currentSchemaVersion
            } else if trimmed.hasPrefix("cadence:") {
                config.cadence = RecommendationCadence(rawValue: value(after: "cadence:", in: trimmed)) ?? .off
            } else if trimmed.hasPrefix("scope:") {
                config.scope = RecommendationScope(rawValue: value(after: "scope:", in: trimmed)) ?? .activeProjectOnly
            } else if trimmed.hasPrefix("top_k:") {
                let raw = value(after: "top_k:", in: trimmed)
                guard let topK = Int(raw) else { throw RecommendationConfigStoreError.invalidTopK(raw) }
                config.topK = min(max(topK, 1), 100)
            } else if trimmed.hasPrefix("external_network_enabled:") {
                config.externalNetworkEnabled = bool(value(after: "external_network_enabled:", in: trimmed))
            } else if trimmed.hasPrefix("max_daily_candidates:") {
                let raw = value(after: "max_daily_candidates:", in: trimmed)
                guard let count = Int(raw) else { throw RecommendationConfigStoreError.invalidMaxDailyCandidates(raw) }
                config.maxDailyCandidates = min(max(count, 1), 500)
            } else if trimmed.hasPrefix("library_recent_days:") {
                config.libraryRecentDays = max(Int(value(after: "library_recent_days:", in: trimmed)) ?? config.libraryRecentDays, 1)
            } else if trimmed == "weights:" {
                let result = parseWeights(lines, start: index + 1, current: config.weights)
                config.weights = result.weights
                index = result.nextIndex - 1
            } else if trimmed == "daily_sources:" {
                let result = parseDailySources(lines, start: index + 1)
                dailySources = result.sources
                index = result.nextIndex - 1
            }
            index += 1
        }

        if !dailySources.isEmpty {
            config.dailySources = dailySources
        }
        return config
    }

    private static func parseWeights(_ lines: [String], start: Int, current: RecommendationWeights) -> (weights: RecommendationWeights, nextIndex: Int) {
        var weights = current
        var index = start
        while index < lines.count {
            let raw = lines[index]
            let indent = indentation(of: raw)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard indent > 0, !trimmed.hasPrefix("-") else {
                break
            }
            let pair = keyValue(trimmed)
            if let number = Double(pair.value) {
                switch pair.key {
                case "cited_by_core": weights.citedByCore = number
                case "library_interest_similarity": weights.libraryInterestSimilarity = number
                case "keyword_relevance": weights.keywordRelevance = number
                case "seed_similarity": weights.seedSimilarity = number
                case "project_context_similarity": weights.projectContextSimilarity = number
                case "recency": weights.recency = number
                case "novelty": weights.novelty = number
                case "quality": weights.quality = number
                case "ai_score": weights.aiScore = number
                case "feedback": weights.feedback = number
                case "open_gap_coverage": weights.openGapCoverage = number
                case "author_overlap_with_core": weights.authorOverlapWithCore = number
                case "queue_pressure_penalty": weights.queuePressurePenalty = number
                case "duplicate_penalty": weights.duplicatePenalty = number
                default: break
                }
            }
            index += 1
        }
        return (weights, index)
    }

    private static func parseDailySources(_ lines: [String], start: Int) -> (sources: [RecommendationDailySourceConfig], nextIndex: Int) {
        var sources: [RecommendationDailySourceConfig] = []
        var current: RecommendationDailySourceConfig?
        var index = start

        func commit() {
            if let current {
                sources.append(current)
            }
        }

        while index < lines.count {
            let raw = lines[index]
            let indent = indentation(of: raw)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard indent > 0 else {
                break
            }
            if trimmed == "[]" {
                index += 1
                continue
            }
            if trimmed.hasPrefix("- kind:") {
                commit()
                let kindRaw = value(after: "- kind:", in: trimmed)
                current = RecommendationDailySourceKind(rawValue: kindRaw).map { RecommendationDailySourceConfig(kind: $0) }
            } else if trimmed.hasPrefix("enabled:") {
                current?.enabled = bool(value(after: "enabled:", in: trimmed))
            } else if trimmed.hasPrefix("categories:") {
                current?.categories = parseInlineArray(value(after: "categories:", in: trimmed))
            } else if trimmed.hasPrefix("include_cross_list:") {
                current?.includeCrossList = bool(value(after: "include_cross_list:", in: trimmed))
            }
            index += 1
        }
        commit()
        return (sources, index)
    }

    private static func value(after prefix: String, in line: String) -> String {
        unquoted(line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces))
    }

    private static func keyValue(_ line: String) -> (key: String, value: String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        return (key, unquoted(value))
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func bool(_ raw: String) -> Bool {
        ["true", "yes", "1", "on"].contains(raw.lowercased())
    }

    private static func inlineArray(_ values: [String]) -> String {
        guard !values.isEmpty else {
            return "[]"
        }
        return "[" + values.map(quoted(_:)).joined(separator: ", ") + "]"
    }

    private static func parseInlineArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return trimmed.isEmpty ? [] : [unquoted(trimmed)]
        }
        let body = trimmed.dropFirst().dropLast()
        return body
            .split(separator: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let inner = value.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func format(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.4f", value)
    }
}
