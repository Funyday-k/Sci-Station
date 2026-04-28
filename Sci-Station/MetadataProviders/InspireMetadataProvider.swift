import Foundation

public actor InspireMetadataProvider {
    private let session: URLSession
    private let mapper: InspireMetadataMapper

    public init(session: URLSession = .shared, mapper: InspireMetadataMapper = InspireMetadataMapper()) {
        self.session = session
        self.mapper = mapper
    }

    public func fetchMetadata(for recordID: String) async throws -> PaperMetadataDraft {
        let url = URL(string: "https://inspirehep.net/api/literature/\(recordID)")!
        let (data, _) = try await session.data(from: url)
        var draft = try mapper.map(data: data, recordID: recordID)
        draft.bibtex = try? await fetchBibTeX(for: recordID)
        return draft
    }

    public func fetchBibTeX(for recordID: String) async throws -> String {
        var components = URLComponents(string: "https://inspirehep.net/api/literature/\(recordID)")!
        components.queryItems = [URLQueryItem(name: "format", value: "bibtex")]
        let url = components.url!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let bibtex = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}