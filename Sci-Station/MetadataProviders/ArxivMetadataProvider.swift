import Foundation

public enum ArxivMetadataProviderError: LocalizedError {
    case invalidIdentifier(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(identifier):
            return "Invalid arXiv metadata request: \(identifier)."
        case .invalidResponse:
            return "Failed to fetch arXiv metadata."
        }
    }
}

public actor ArxivMetadataProvider {
    private let session: URLSession
    private let parser: ArxivEntryParser

    public init(session: URLSession = .shared, parser: ArxivEntryParser = ArxivEntryParser()) {
        self.session = session
        self.parser = parser
    }

    public func fetchMetadata(for arxivID: String) async throws -> PaperMetadataDraft {
        let url = try Self.apiURL(for: arxivID)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ArxivMetadataProviderError.invalidResponse
        }

        return try parser.parse(data)
    }

    public nonisolated static func apiURL(for arxivID: String) throws -> URL {
        let normalizedID = arxivID.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "export.arxiv.org"
        components.path = "/api/query"
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "id:\(normalizedID)"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: "1")
        ]

        guard let url = components.url else {
            throw ArxivMetadataProviderError.invalidIdentifier(arxivID)
        }

        return url
    }
}