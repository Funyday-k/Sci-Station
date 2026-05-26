import Foundation

public nonisolated enum DailyFeedCandidateImporterError: Error, Sendable, Equatable {
    case invalidJSON
}

public nonisolated struct DailyFeedCandidateImporter {
    public init() {}

    public func parseJSONLines(_ contents: String) throws -> [RecommendationCandidate] {
        var candidates: [RecommendationCandidate] = []
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            let value = try JSONValue.parse(line)
            guard let candidate = candidate(from: value) else {
                throw DailyFeedCandidateImporterError.invalidJSON
            }
            candidates.append(candidate)
        }
        return candidates
    }

    public func parseJSONArray(_ contents: String) throws -> [RecommendationCandidate] {
        let value = try JSONValue.parse(contents)
        guard let array = value.arrayValue else {
            throw DailyFeedCandidateImporterError.invalidJSON
        }
        return try array.map { value in
            guard let candidate = candidate(from: value) else {
                throw DailyFeedCandidateImporterError.invalidJSON
            }
            return candidate
        }
    }

    public func candidate(from value: JSONValue) -> RecommendationCandidate? {
        guard let object = value.objectValue else {
            return nil
        }
        let title = object["title"]?.stringValue
            ?? object["display_title"]?.stringValue
            ?? object["displayTitle"]?.stringValue
        guard let displayTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines), !displayTitle.isEmpty else {
            return nil
        }

        let source = object["source"]?.stringValue?.lowercased() ?? "daily"
        let arxivID = normalizedArxiv(object["arxiv"]?.stringValue ?? object["arxiv_id"]?.stringValue ?? object["id"]?.stringValue)
        let doi = PaperIdentityGenerator.normalizedDOI(object["doi"]?.stringValue)
        let externalKey = object["external_key"]?.stringValue
            ?? arxivID.map { "arxiv:\($0)" }
            ?? doi.map { "doi:\($0)" }
            ?? object["url"]?.stringValue
            ?? object["source_url"]?.stringValue
        let canonicalID = RecommendationCandidateGatherer.canonicalID(
            paperID: object["paper_id"]?.stringValue,
            externalKey: externalKey,
            fallback: displayTitle
        )
        let categories = stringArray(object["categories"]) + stringArray(object["category"])
        let primaryCategory = object["primary_category"]?.stringValue
            ?? object["primaryCategory"]?.stringValue
            ?? categories.first
        let publishedYear = object["published_year"]?.stringValue.flatMap(Int.init)
            ?? object["year"]?.stringValue.flatMap(Int.init)
            ?? year(from: object["published"]?.stringValue ?? object["published_date"]?.stringValue)
        return RecommendationCandidate(
            canonicalID: canonicalID,
            paperID: object["paper_id"]?.stringValue,
            externalKey: externalKey,
            displayTitle: displayTitle,
            authors: stringArray(object["authors"]),
            publishedYear: publishedYear,
            sourceTags: [.dailyFeed],
            sourceName: source,
            sourceURL: object["url"]?.stringValue ?? object["source_url"]?.stringValue,
            pdfURL: object["pdf_url"]?.stringValue,
            categories: Array(Set(categories)).sorted(),
            primaryCategory: primaryCategory,
            abstractText: object["abstract"]?.stringValue ?? object["summary"]?.stringValue
        )
    }

    private func normalizedArxiv(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        if let normalized = PaperIdentityGenerator.normalizedArxiv(raw),
           raw.lowercased().contains("arxiv") || raw.range(of: #"^\d{4}\.\d{4,5}"#, options: .regularExpression) != nil {
            return normalized
        }
        return nil
    }

    private func stringArray(_ value: JSONValue?) -> [String] {
        if let string = value?.stringValue {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return value?.arrayValue?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }

    private func year(from raw: String?) -> Int? {
        guard let raw, raw.count >= 4 else {
            return nil
        }
        return Int(raw.prefix(4))
    }
}
