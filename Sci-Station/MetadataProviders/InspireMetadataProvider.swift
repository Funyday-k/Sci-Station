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
        return try mapper.map(data: data, recordID: recordID)
    }
}