import Foundation

public nonisolated struct ArxivRecommendationRequest: Hashable, Sendable {
    public var query: String
    public var categories: [String]
    public var maxResults: Int
    public var submittedAfter: Date?
    public var submittedBefore: Date?

    public init(query: String = "", categories: [String] = [], maxResults: Int = 50, submittedAfter: Date? = nil, submittedBefore: Date? = nil) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categories = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.maxResults = min(max(maxResults, 1), 100)
        self.submittedAfter = submittedAfter
        self.submittedBefore = submittedBefore
    }
}

public actor ArxivRecommendationClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ request: ArxivRecommendationRequest) async throws -> [RecommendationCandidate] {
        let url = try Self.url(for: request)
        let (data, _) = try await session.data(from: url)
        let contents = String(decoding: data, as: UTF8.self)
        return ArxivRecommendationParser.parseAtom(contents)
    }

    public nonisolated static func url(for request: ArxivRecommendationRequest) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "export.arxiv.org"
        components.path = "/api/query"
        components.queryItems = [
            URLQueryItem(name: "search_query", value: searchQuery(for: request)),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: String(request.maxResults)),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending")
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private nonisolated static func searchQuery(for request: ArxivRecommendationRequest) -> String {
        var clauses: [String] = []
        if !request.categories.isEmpty {
            clauses.append(request.categories.map { "cat:\($0)" }.joined(separator: " OR "))
        }
        if !request.query.isEmpty {
            let escapedQuery = request.query.replacingOccurrences(of: "\"", with: " ")
            clauses.append("all:\"\(escapedQuery)\"")
        }
        if let submittedAfter = request.submittedAfter, let submittedBefore = request.submittedBefore {
            clauses.append("submittedDate:[\(arxivDate(submittedAfter)) TO \(arxivDate(submittedBefore))]")
        }
        return clauses.isEmpty ? "cat:cs.AI OR cat:cs.CL OR cat:cs.CV OR cat:cs.LG" : clauses.joined(separator: " AND ")
    }

    private nonisolated static func arxivDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }
}

public nonisolated enum ArxivRecommendationParser {
    public static func parseAtom(_ contents: String) -> [RecommendationCandidate] {
        entryBlocks(in: contents).compactMap(candidate(from:))
    }

    private static func candidate(from block: String) -> RecommendationCandidate? {
        guard let title = text(for: "title", in: block)?.singleSpaced, !title.isEmpty else {
            return nil
        }
        let rawArxivID = text(for: "id", in: block)
        let normalizedArxivID = PaperIdentityGenerator.normalizedArxiv(rawArxivID)
        let externalKey = normalizedArxivID.map { "arxiv:\($0)" }
        let sourceURL = normalizedArxivID.map { "https://arxiv.org/abs/\($0)" } ?? rawArxivID
        let pdfURL = normalizedArxivID.map { "https://arxiv.org/pdf/\($0).pdf" }
        let categories = categoryTerms(in: block)
        let publishedRaw = text(for: "published", in: block) ?? text(for: "updated", in: block)
        let publishedAt = date(from: publishedRaw)
        let publishedYear = year(from: publishedRaw)
        let canonicalID = RecommendationCandidateGatherer.canonicalID(
            paperID: nil,
            externalKey: externalKey,
            fallback: title
        )
        return RecommendationCandidate(
            canonicalID: canonicalID,
            paperID: nil,
            externalKey: externalKey,
            displayTitle: title,
            authors: authorNames(in: block),
            publishedYear: publishedYear,
            sourceTags: [.dailyFeed],
            sourceName: "arXiv",
            sourceURL: sourceURL,
            pdfURL: pdfURL,
            categories: categories,
            abstractText: text(for: "summary", in: block)?.singleSpaced,
            publishedAt: publishedAt
        )
    }

    private static func entryBlocks(in contents: String) -> [String] {
        var blocks: [String] = []
        var searchStart = contents.startIndex
        while let openRange = contents.range(of: "<entry", range: searchStart..<contents.endIndex),
              let openEnd = contents[openRange.upperBound...].firstIndex(of: ">"),
              let closeRange = contents.range(of: "</entry>", range: openEnd..<contents.endIndex) {
            let blockStart = contents.index(after: openEnd)
            blocks.append(String(contents[blockStart..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }
        return blocks
    }

    private static func authorNames(in block: String) -> [String] {
        elementBlocks(named: "author", in: block)
            .compactMap { text(for: "name", in: $0)?.singleSpaced }
            .filter { !$0.isEmpty }
    }

    private static func categoryTerms(in block: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<category\b[^>]*\bterm=[\"']([^\"']+)[\"'][^>]*/?>"#, options: []) else {
            return []
        }
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        let matches = regex.matches(in: block, options: [], range: range)
        return matches.compactMap { match in
            guard let termRange = Range(match.range(at: 1), in: block) else { return nil }
            return xmlDecoded(String(block[termRange])).singleSpaced
        }
        .filter { !$0.isEmpty }
        .uniquedStable()
    }

    private static func elementBlocks(named name: String, in contents: String) -> [String] {
        var blocks: [String] = []
        var searchStart = contents.startIndex
        while let openRange = contents.range(of: "<\(name)", range: searchStart..<contents.endIndex),
              let openEnd = contents[openRange.upperBound...].firstIndex(of: ">"),
              let closeRange = contents.range(of: "</\(name)>", range: openEnd..<contents.endIndex) {
            let blockStart = contents.index(after: openEnd)
            blocks.append(String(contents[blockStart..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }
        return blocks
    }

    private static func text(for tag: String, in contents: String) -> String? {
        guard let block = elementBlocks(named: tag, in: contents).first else {
            return nil
        }
        return xmlDecoded(stripTags(block)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func year(from raw: String?) -> Int? {
        guard let raw, raw.count >= 4 else {
            return nil
        }
        return Int(raw.prefix(4))
    }

    private static func date(from raw: String?) -> Date? {
        guard let raw else {
            return nil
        }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func xmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

private extension String {
    nonisolated var singleSpaced: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Array where Element: Hashable {
    nonisolated func uniquedStable() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
