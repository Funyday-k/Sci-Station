import Foundation

public enum DOIMetadataProviderError: LocalizedError {
    case invalidDOI(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidDOI(doi):
            return "Invalid DOI metadata request: \(doi)."
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
        let url = try Self.crossrefWorksURL(for: doi)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DOIMetadataProviderError.invalidResponse
        }

        return try mapper.map(data: data, doi: doi)
    }

    public nonisolated static func crossrefWorksURL(for doi: String) throws -> URL {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")

        let trimmedDOI = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encodedDOI = trimmedDOI.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let url = URL(string: "https://api.crossref.org/works/\(encodedDOI)") else {
            throw DOIMetadataProviderError.invalidDOI(doi)
        }

        return url
    }
}