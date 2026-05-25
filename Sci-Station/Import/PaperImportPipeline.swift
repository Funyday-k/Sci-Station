import Foundation

public nonisolated enum PaperImportInputKind: String, Codable, CaseIterable, Hashable, Sendable {
    case fileURL = "file_url"
    case remoteURL = "remote_url"
    case doi
    case arxiv
    case isbn
    case freeText = "free_text"
}

public nonisolated struct PaperImportInput: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: PaperImportInputKind
    public var value: String
    public var collectionPath: String?
    public var tags: [String]

    public nonisolated init(id: String = UUID().uuidString, kind: PaperImportInputKind, value: String, collectionPath: String? = nil, tags: [String] = []) {
        self.id = id
        self.kind = kind
        self.value = value
        self.collectionPath = collectionPath
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case value
        case collectionPath = "collection_path"
        case tags
    }
}

public nonisolated struct MetadataLookupQuery: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var identifierKind: String
    public var value: String

    public nonisolated init(id: String = UUID().uuidString, identifierKind: String, value: String) {
        self.id = id
        self.identifierKind = identifierKind
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case identifierKind = "identifier_kind"
        case value
    }
}

public nonisolated struct PaperMetadataCandidate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var draft: PaperMetadataDraft
    public var providerID: String
    public var confidence: Double

    public nonisolated init(id: String = UUID().uuidString, draft: PaperMetadataDraft, providerID: String, confidence: Double = 1.0) {
        self.id = id
        self.draft = draft
        self.providerID = providerID
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case draft
        case providerID = "provider_id"
        case confidence
    }
}

public nonisolated struct PaperImportResult: Codable, Hashable, Sendable {
    public var paperID: String?
    public var metadata: PaperMetadataDraft?
    public var assetPaths: [String]
    public var messages: [String]

    public nonisolated init(paperID: String? = nil, metadata: PaperMetadataDraft? = nil, assetPaths: [String] = [], messages: [String] = []) {
        self.paperID = paperID
        self.metadata = metadata
        self.assetPaths = assetPaths
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case metadata
        case assetPaths = "asset_paths"
        case messages
    }
}

public protocol PaperImporter: Sendable {
    var contribution: ImporterContribution { get }
    func canHandle(_ input: PaperImportInput) -> Bool
    func importPaper(_ input: PaperImportInput, context: PluginContext) async throws -> PaperImportResult
}

public protocol PaperMetadataProviderPlugin: Sendable {
    var contribution: MetadataProviderContribution { get }
    func lookup(_ query: MetadataLookupQuery, context: PluginContext) async throws -> [PaperMetadataCandidate]
}

public nonisolated enum PaperImportPipelineError: LocalizedError, Sendable {
    case noImporter(PaperImportInputKind)

    public var errorDescription: String? {
        switch self {
        case let .noImporter(kind):
            return "No paper importer is registered for input kind '\(kind.rawValue)'."
        }
    }
}

public actor PaperImportPipeline {
    private var importers: [any PaperImporter]
    private var metadataProviders: [any PaperMetadataProviderPlugin]

    public init(importers: [any PaperImporter] = [], metadataProviders: [any PaperMetadataProviderPlugin] = []) {
        self.importers = importers
        self.metadataProviders = metadataProviders
    }

    public func registerImporter(_ importer: any PaperImporter) {
        importers.append(importer)
    }

    public func registerMetadataProvider(_ provider: any PaperMetadataProviderPlugin) {
        metadataProviders.append(provider)
    }

    public func importerContributions() -> [ImporterContribution] {
        importers.map(\.contribution).sorted { $0.id < $1.id }
    }

    public func metadataProviderContributions() -> [MetadataProviderContribution] {
        metadataProviders.map(\.contribution).sorted { $0.id < $1.id }
    }

    public func importPaper(_ input: PaperImportInput, context: PluginContext) async throws -> PaperImportResult {
        guard let importer = importers.first(where: { $0.canHandle(input) }) else {
            throw PaperImportPipelineError.noImporter(input.kind)
        }
        return try await importer.importPaper(input, context: context)
    }

    public func lookupMetadata(_ query: MetadataLookupQuery, context: PluginContext) async throws -> [PaperMetadataCandidate] {
        var candidates: [PaperMetadataCandidate] = []
        for provider in metadataProviders {
            candidates.append(contentsOf: try await provider.lookup(query, context: context))
        }
        return candidates.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.providerID < rhs.providerID
            }
            return lhs.confidence > rhs.confidence
        }
    }
}
