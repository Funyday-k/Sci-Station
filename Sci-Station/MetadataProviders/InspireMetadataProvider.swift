import Foundation

public actor InspireMetadataProvider {
    private let session: URLSession
    private let mapper: InspireMetadataMapper
    private let summaryFields = [
        "control_number",
        "titles",
        "authors",
        "abstracts",
        "arxiv_eprints",
        "dois",
        "publication_info",
        "inspire_categories",
        "citation_count",
        "reference_count"
    ]
    private let graphFields = [
        "control_number",
        "titles",
        "authors",
        "abstracts",
        "arxiv_eprints",
        "dois",
        "publication_info",
        "inspire_categories",
        "citation_count",
        "reference_count",
        "references"
    ]

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

    public func resolveRecordID(doi: String?, arxiv: String?) async throws -> String? {
        if let arxiv = PaperIdentityGenerator.normalizedArxiv(arxiv),
           let id = try await firstRecordID(matching: "arxiv:\(arxiv)") {
            return id
        }

        if let doi = PaperIdentityGenerator.normalizedDOI(doi),
           let id = try await firstRecordID(matching: "doi:\(doi)") {
            return id
        }

        return nil
    }

    public func fetchCitationGraph(for recordID: String, limit: Int = 25) async throws -> InspireCitationGraph {
        let normalizedID = Self.normalizedRecordID(recordID)
        let recordData = try await fetchLiteratureRecordData(for: normalizedID, fields: graphFields)
        let center = try? mapper.mapCitationPaper(data: recordData, fallbackRecordID: normalizedID)

        let referenceIDs = try mapper.referenceRecordIDs(data: recordData)
        var references: [InspireCitationPaper] = []
        for referenceID in referenceIDs.prefix(max(0, limit)) {
            if let paper = try? await fetchCitationPaper(for: referenceID) {
                references.append(paper)
            }
        }

        let citedBy = try await searchCitationPapers(query: "refersto:recid:\(normalizedID)", limit: limit)
        return InspireCitationGraph(center: center, references: references, citedBy: citedBy)
    }

    public func fetchCitationPaper(for recordID: String) async throws -> InspireCitationPaper {
        let normalizedID = Self.normalizedRecordID(recordID)
        let data = try await fetchLiteratureRecordData(for: normalizedID, fields: summaryFields)
        return try mapper.mapCitationPaper(data: data, fallbackRecordID: normalizedID)
    }

    private func firstRecordID(matching query: String) async throws -> String? {
        var components = URLComponents(string: "https://inspirehep.net/api/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "size", value: "1"),
            URLQueryItem(name: "fields", value: "control_number")
        ]
        let data = try await fetchData(from: components.url!)
        return try mapper.mapCitationSearch(data: data).first?.inspireID
    }

    private func searchCitationPapers(query: String, limit: Int) async throws -> [InspireCitationPaper] {
        guard limit > 0 else { return [] }
        var components = URLComponents(string: "https://inspirehep.net/api/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "size", value: String(limit)),
            URLQueryItem(name: "sort", value: "mostrecent"),
            URLQueryItem(name: "fields", value: summaryFields.joined(separator: ","))
        ]
        let data = try await fetchData(from: components.url!)
        return try mapper.mapCitationSearch(data: data)
    }

    private func fetchLiteratureRecordData(for recordID: String, fields: [String]) async throws -> Data {
        var components = URLComponents(string: "https://inspirehep.net/api/literature/\(recordID)")!
        components.queryItems = [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
        return try await fetchData(from: components.url!)
    }

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    private nonisolated static func normalizedRecordID(_ recordID: String) -> String {
        PaperIdentityGenerator.normalizedInspire(recordID) ?? recordID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}