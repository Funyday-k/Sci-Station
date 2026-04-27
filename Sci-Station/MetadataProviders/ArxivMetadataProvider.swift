import Foundation

public actor ArxivMetadataProvider {
    private let session: URLSession
    private let parser: ArxivEntryParser

    public init(session: URLSession = .shared, parser: ArxivEntryParser = ArxivEntryParser()) {
        self.session = session
        self.parser = parser
    }

    public func fetchMetadata(for arxivID: String) async throws -> PaperMetadataDraft {
        let query = arxivID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? arxivID
        let url = URL(string: "https://export.arxiv.org/api/query?search_query=id:\(query)&start=0&max_results=1")!
        let (data, _) = try await session.data(from: url)
        return try parser.parse(data)
    }
}