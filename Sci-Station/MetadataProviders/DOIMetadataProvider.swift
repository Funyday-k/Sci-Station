import Foundation

public enum DOIMetadataProviderError: LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Failed to fetch DOI metadata from Crossref."
        }
    }
}

public actor DOIMetadataProvider {
    private let session: URLSession
    private let mapper: DOIMetadataMapper

    public init(session: URLSession = .shared, mapper: DOIMetadataMapper = DOIMetadataMapper()) {
        self.session = session
        self.mapper = mapper
    }

    public func fetchMetadata(for doi: String) async throws -> PaperMetadataDraft {
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        let url = URL(string: "https://api.crossref.org/works/\(encodedDOI)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DOIMetadataProviderError.invalidResponse
        }

        return try mapper.map(data: data, doi: doi)
    }
}