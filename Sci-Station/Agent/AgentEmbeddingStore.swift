import CryptoKit
import Foundation

public nonisolated enum AgentEmbeddingIndexStatus: String, Codable, Hashable, Sendable {
    case disabled
    case ready
    case indexing
    case stale
    case fallback
    case error
    case migrationRequired = "migration_required"

    public nonisolated var uiStatus: AgentEmbeddingIndexStatus {
        self == .migrationRequired ? .stale : self
    }
}


public nonisolated enum AgentEmbeddingSourceHashStatus: String, Codable, Hashable, Sendable {
    case fresh
    case stale
    case missing
}

public nonisolated enum AgentEmbeddingLocationType: String, Codable, Hashable, Sendable {
    case markdownLine = "markdown_line"
    case pdfPage = "pdf_page"
    case materialFile = "material_file"
}

public nonisolated struct AgentEmbeddingModelIdentity: Codable, Hashable, Sendable {
    public var provider: String
    public var modelID: String
    public var modelVersion: String?
    public var dimension: Int

    public nonisolated init(
        provider: String = "swift-proxy",
        modelID: String = "deterministic-fallback-v1",
        modelVersion: String? = "v1",
        dimension: Int = 32
    ) {
        self.provider = provider
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.dimension = dimension
    }
}

public nonisolated struct AgentEmbeddingChunk: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourcePath: String
    public var sourceType: String
    public var sourceID: String?
    public var sourceHash: String
    public var chunkIndex: Int
    public var textHash: String
    public var text: String
    public var lineStart: Int
    public var lineEnd: Int
    public var headingPath: [String]
    public var pdfPageStart: Int?
    public var pdfPageEnd: Int?
    public var embeddingProvider: String
    public var embeddingModelID: String
    public var embeddingModelVersion: String?
    public var embeddingDimension: Int
    public var embeddingCreatedAt: Date
    public var chunkSchemaVersion: Int
    public var metadata: [String: String]

    public nonisolated init(
        id: String,
        sourcePath: String,
        sourceType: String,
        sourceID: String? = nil,
        sourceHash: String,
        chunkIndex: Int,
        textHash: String,
        text: String,
        lineStart: Int,
        lineEnd: Int,
        headingPath: [String] = [],
        pdfPageStart: Int? = nil,
        pdfPageEnd: Int? = nil,
        model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity(),
        embeddingCreatedAt: Date = Date(),
        chunkSchemaVersion: Int = AgentEmbeddingChunker.chunkSchemaVersion,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.sourceHash = sourceHash
        self.chunkIndex = chunkIndex
        self.textHash = textHash
        self.text = text
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.headingPath = headingPath
        self.pdfPageStart = pdfPageStart
        self.pdfPageEnd = pdfPageEnd
        self.embeddingProvider = model.provider
        self.embeddingModelID = model.modelID
        self.embeddingModelVersion = model.modelVersion
        self.embeddingDimension = model.dimension
        self.embeddingCreatedAt = embeddingCreatedAt
        self.chunkSchemaVersion = chunkSchemaVersion
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourcePath = "source_path"
        case sourceType = "source_type"
        case sourceID = "source_id"
        case sourceHash = "source_hash"
        case chunkIndex = "chunk_index"
        case textHash = "text_hash"
        case text
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case headingPath = "heading_path"
        case pdfPageStart = "pdf_page_start"
        case pdfPageEnd = "pdf_page_end"
        case embeddingProvider = "embedding_provider"
        case embeddingModelID = "embedding_model_id"
        case embeddingModelVersion = "embedding_model_version"
        case embeddingDimension = "embedding_dimension"
        case embeddingCreatedAt = "embedding_created_at"
        case chunkSchemaVersion = "chunk_schema_version"
        case metadata
    }
}

public nonisolated struct AgentEmbeddingSearchResult: Codable, Hashable, Sendable {
    public var chunk: AgentEmbeddingChunk
    public var score: Double
    public var rank: Int
    public var sourceHashStatus: AgentEmbeddingSourceHashStatus
    public var locationType: AgentEmbeddingLocationType
    public var snippet: String

    public nonisolated init(
        chunk: AgentEmbeddingChunk,
        score: Double,
        rank: Int,
        sourceHashStatus: AgentEmbeddingSourceHashStatus = .fresh,
        locationType: AgentEmbeddingLocationType = .markdownLine,
        snippet: String = ""
    ) {
        self.chunk = chunk
        self.score = score
        self.rank = rank
        self.sourceHashStatus = sourceHashStatus
        self.locationType = locationType
        self.snippet = snippet
    }
}

public nonisolated struct AgentEmbeddingStoreStats: Codable, Hashable, Sendable {
    public var store: String
    public var status: AgentEmbeddingIndexStatus
    public var chunkCount: Int
    public var staleCount: Int
    public var fallbackReason: String?
    public var lastIndexedAt: Date?

    public nonisolated init(
        store: String,
        status: AgentEmbeddingIndexStatus,
        chunkCount: Int,
        staleCount: Int = 0,
        fallbackReason: String? = nil,
        lastIndexedAt: Date? = nil
    ) {
        self.store = store
        self.status = status
        self.chunkCount = chunkCount
        self.staleCount = staleCount
        self.fallbackReason = fallbackReason
        self.lastIndexedAt = lastIndexedAt
    }
}

public nonisolated struct AgentEmbeddingIndexStatusSnapshot: Codable, Hashable, Sendable {
    public var status: AgentEmbeddingIndexStatus
    public var store: String
    public var provider: String
    public var modelID: String
    public var modelVersion: String?
    public var dimension: Int
    public var chunkCount: Int
    public var staleCount: Int
    public var fallbackReason: String?
    public var errorMessage: String?
    public var indexRelativePath: String
    public var lastIndexedAt: Date?

    public nonisolated init(
        status: AgentEmbeddingIndexStatus,
        store: String = "fts_only",
        model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity(),
        chunkCount: Int = 0,
        staleCount: Int = 0,
        fallbackReason: String? = nil,
        errorMessage: String? = nil,
        indexRelativePath: String = AgentEmbeddingIndexController.indexRelativePath,
        lastIndexedAt: Date? = nil
    ) {
        self.status = status
        self.store = store
        self.provider = model.provider
        self.modelID = model.modelID
        self.modelVersion = model.modelVersion
        self.dimension = model.dimension
        self.chunkCount = chunkCount
        self.staleCount = staleCount
        self.fallbackReason = fallbackReason
        self.errorMessage = errorMessage
        self.indexRelativePath = indexRelativePath
        self.lastIndexedAt = lastIndexedAt
    }

    public nonisolated static func disabled() -> AgentEmbeddingIndexStatusSnapshot {
        AgentEmbeddingIndexStatusSnapshot(status: .disabled, store: "fts_only", fallbackReason: "Embedding is disabled; workflows use FTS-only retrieval.")
    }

    public nonisolated var explanation: String {
        switch status.uiStatus {
        case .ready:
            return "Ready"
        case .fallback:
            return "Fallback deterministic retrieval"
        case .error:
            if errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
                return "Error not indexable"
            }
            return "Error"
        case .disabled:
            return "Disabled FTS-only"
        case .indexing:
            return "Indexing"
        case .stale, .migrationRequired:
            return "Stale"
        }
    }

    public nonisolated var zeroChunkGuidance: String? {
        guard status.uiStatus != .indexing, chunkCount == 0 else {
            return nil
        }
        if status.uiStatus == .disabled {
            return "Embedding index disabled; FTS-only retrieval is active."
        }
        if errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
            return "chunks=0; selected source is not indexable. Use paper.md, annotations.md, wiki/material paths, or migrate legacy raw/papers if preferred."
        }
        return "chunks=0; confirm paper.md exists, is non-empty, and run Rebuild Source. Check paper.md quality if PDFKit fallback was used."
    }

    public nonisolated var diagnosticText: String {
        [
            "status=\(status.uiStatus.rawValue)",
            "explanation=\(explanation)",
            "store=\(store)",
            "provider=\(provider)",
            "model_id=\(modelID)",
            "dimension=\(dimension)",
            "chunks=\(chunkCount)",
            "stale=\(staleCount)",
            zeroChunkGuidance.map { "guidance=\($0)" },
            fallbackReason.map { "fallback_reason=\($0)" },
            errorMessage.map { "error=\($0)" },
            "index=\(indexRelativePath)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

public nonisolated protocol AgentEmbeddingStore: Sendable {
    func open() async throws
    func close() async
    func healthCheck(model: AgentEmbeddingModelIdentity, schemaVersion: Int) async -> AgentEmbeddingStoreStats
    func beginTransaction() async throws
    func commitTransaction() async throws
    func rollbackTransaction() async
    func upsertChunks(_ chunks: [AgentEmbeddingChunk]) async throws
    func deleteBySource(_ sourcePath: String) async throws
    func markStale(currentSourceHashes: [String: String]) async -> [String]
    func query(_ query: String, limit: Int, currentSourceHashes: [String: String]) async -> [AgentEmbeddingSearchResult]
    func stats(currentSourceHashes: [String: String]) async -> AgentEmbeddingStoreStats
    func compact() async throws
}

public actor AgentDeterministicEmbeddingStore: AgentEmbeddingStore {
    private nonisolated struct Snapshot: Codable {
        var schemaVersion: Int
        var store: String
        var fallbackReason: String
        var chunks: [AgentEmbeddingChunk]
        var updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case store
            case fallbackReason = "fallback_reason"
            case chunks
            case updatedAt = "updated_at"
        }
    }

    private let indexDirectoryURL: URL
    private let fallbackReason: String
    private var rows: [String: AgentEmbeddingChunk] = [:]
    private var transactionBackup: [String: AgentEmbeddingChunk]?
    private var lastIndexedAt: Date?

    public init(indexDirectoryURL: URL, fallbackReason: String = "sqlite-vec unavailable; using deterministic fallback") {
        self.indexDirectoryURL = indexDirectoryURL
        self.fallbackReason = fallbackReason
    }

    public func open() async throws {
        try FileManager.default.createDirectory(at: indexDirectoryURL, withIntermediateDirectories: true)
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            rows = [:]
            return
        }
        let snapshot = try Self.decoder.decode(Snapshot.self, from: Data(contentsOf: url))
        rows = Dictionary(uniqueKeysWithValues: snapshot.chunks.map { ($0.id, $0) })
        lastIndexedAt = snapshot.updatedAt
    }

    public func close() async {
        try? persist()
    }

    public func healthCheck(model: AgentEmbeddingModelIdentity, schemaVersion: Int = AgentEmbeddingChunker.chunkSchemaVersion) async -> AgentEmbeddingStoreStats {
        let stale = rows.values.filter { chunk in
            chunk.embeddingModelID != model.modelID
                || chunk.embeddingDimension != model.dimension
                || chunk.chunkSchemaVersion != schemaVersion
        }.count
        return AgentEmbeddingStoreStats(
            store: "deterministic_fallback",
            status: stale > 0 ? .migrationRequired : .fallback,
            chunkCount: rows.count,
            staleCount: stale,
            fallbackReason: fallbackReason,
            lastIndexedAt: lastIndexedAt
        )
    }

    public func beginTransaction() async throws {
        transactionBackup = rows
    }

    public func commitTransaction() async throws {
        try persist()
        transactionBackup = nil
    }

    public func rollbackTransaction() async {
        if let transactionBackup {
            rows = transactionBackup
        }
        transactionBackup = nil
    }

    public func upsertChunks(_ chunks: [AgentEmbeddingChunk]) async throws {
        for chunk in chunks {
            rows[chunk.id] = chunk
        }
    }

    public func deleteBySource(_ sourcePath: String) async throws {
        rows = rows.filter { $0.value.sourcePath != sourcePath }
    }

    public func markStale(currentSourceHashes: [String: String]) async -> [String] {
        rows.values.compactMap { chunk in
            guard let current = currentSourceHashes[chunk.sourcePath], current != chunk.sourceHash else {
                return nil
            }
            return chunk.id
        }
    }

    public func query(_ query: String, limit: Int = 10, currentSourceHashes: [String: String] = [:]) async -> [AgentEmbeddingSearchResult] {
        let scored = rows.values.map { chunk -> (Double, AgentEmbeddingChunk) in
            let lexical = Self.lexicalScore(query: query, text: chunk.text)
            let semantic = Self.cosineSimilarity(Self.deterministicEmbedding(query, dimension: chunk.embeddingDimension), Self.deterministicEmbedding(chunk.text, dimension: chunk.embeddingDimension))
            return ((0.55 * lexical) + (0.45 * semantic), chunk)
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(max(limit, 0)).enumerated().map { index, item in
            let currentHash = currentSourceHashes[item.1.sourcePath]
            let sourceStatus: AgentEmbeddingSourceHashStatus
            if let currentHash {
                sourceStatus = currentHash == item.1.sourceHash ? .fresh : .stale
            } else {
                sourceStatus = currentSourceHashes.isEmpty ? .fresh : .missing
            }
            let locationType: AgentEmbeddingLocationType = item.1.pdfPageStart == nil
                ? (item.1.sourceType == "material" ? .materialFile : .markdownLine)
                : .pdfPage
            return AgentEmbeddingSearchResult(
                chunk: item.1,
                score: (item.0 * 1_000_000).rounded() / 1_000_000,
                rank: index + 1,
                sourceHashStatus: sourceStatus,
                locationType: locationType,
                snippet: String(item.1.text.prefix(240))
            )
        }
    }

    public func stats(currentSourceHashes: [String: String] = [:]) async -> AgentEmbeddingStoreStats {
        let staleIDs = await markStale(currentSourceHashes: currentSourceHashes)
        let stale = staleIDs.count
        return AgentEmbeddingStoreStats(
            store: "deterministic_fallback",
            status: stale > 0 ? .stale : .fallback,
            chunkCount: rows.count,
            staleCount: stale,
            fallbackReason: fallbackReason,
            lastIndexedAt: lastIndexedAt
        )
    }

    public func compact() async throws {
        try persist()
    }

    private var snapshotURL: URL {
        indexDirectoryURL.appendingPathComponent("deterministic_fallback_chunks.json", isDirectory: false)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: indexDirectoryURL, withIntermediateDirectories: true)
        let now = Date()
        let snapshot = Snapshot(
            schemaVersion: AgentEmbeddingChunker.chunkSchemaVersion,
            store: "deterministic_fallback",
            fallbackReason: fallbackReason,
            chunks: rows.values.sorted { $0.id < $1.id },
            updatedAt: now
        )
        try Self.encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        lastIndexedAt = now
    }

    private nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public nonisolated static func deterministicEmbedding(_ text: String, dimension: Int = 32) -> [Double] {
        var values = Array(repeating: 0.0, count: max(dimension, 1))
        let tokens = AgentEmbeddingHashing.normalizedText(text).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for token in tokens.isEmpty ? [AgentEmbeddingHashing.normalizedText(text)] : tokens {
            let digest = SHA256.hash(data: Data(token.utf8))
            let bytes = Array(digest)
            let bucket = Int(bytes[0]) % values.count
            values[bucket] += bytes[1].isMultiple(of: 2) ? 1 : -1
        }
        let norm = sqrt(values.reduce(0.0) { $0 + ($1 * $1) })
        guard norm > 0 else { return values }
        return values.map { (($0 / norm) * 100_000_000).rounded() / 100_000_000 }
    }

    private nonisolated static func lexicalScore(query: String, text: String) -> Double {
        let queryTerms = Set(AgentEmbeddingHashing.normalizedText(query).lowercased().split { !$0.isLetter && !$0.isNumber })
        let textTerms = Set(AgentEmbeddingHashing.normalizedText(text).lowercased().split { !$0.isLetter && !$0.isNumber })
        guard !queryTerms.isEmpty, !textTerms.isEmpty else { return 0 }
        return Double(queryTerms.intersection(textTerms).count) / Double(queryTerms.count)
    }

    private nonisolated static func cosineSimilarity(_ first: [Double], _ second: [Double]) -> Double {
        guard !first.isEmpty, first.count == second.count else { return 0 }
        let dot = zip(first, second).reduce(0.0) { $0 + ($1.0 * $1.1) }
        let firstNorm = sqrt(first.reduce(0.0) { $0 + ($1 * $1) })
        let secondNorm = sqrt(second.reduce(0.0) { $0 + ($1 * $1) })
        guard firstNorm > 0, secondNorm > 0 else { return 0 }
        return dot / (firstNorm * secondNorm)
    }
}

public nonisolated enum AgentEmbeddingHashing {
    public static func normalizedText(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimmingTrailingWhitespace(String($0)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sha256(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedText(content).utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func trimmingTrailingWhitespace(_ line: String) -> String {
        var endIndex = line.endIndex
        while endIndex > line.startIndex {
            let previousIndex = line.index(before: endIndex)
            let scalarView = line[previousIndex].unicodeScalars
            guard scalarView.allSatisfy({ CharacterSet.whitespaces.contains($0) }) else {
                break
            }
            endIndex = previousIndex
        }
        return String(line[..<endIndex])
    }
}

public nonisolated enum AgentEmbeddingChunker {
    public static let chunkSchemaVersion = 1

    public static func chunks(
        from snapshot: IndexableDocumentSnapshot,
        content: String,
        model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity(),
        maxLines: Int = 80
    ) -> [AgentEmbeddingChunk] {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        var chunks: [AgentEmbeddingChunk] = []
        var buffer: [String] = []
        var startLine = 1
        var headingPath: [String] = []
        var currentHeading = ""

        func appendChunk(endLine: Int) {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let index = chunks.count
            chunks.append(AgentEmbeddingChunk(
                id: "\(snapshot.resourceID):\(startLine)-\(endLine)",
                sourcePath: snapshot.relativePath,
                sourceType: snapshot.sourceType,
                sourceID: snapshot.sourceID,
                sourceHash: snapshot.contentHash,
                chunkIndex: index,
                textHash: AgentEmbeddingHashing.sha256(text),
                text: text,
                lineStart: startLine,
                lineEnd: endLine,
                headingPath: headingPath.isEmpty && !currentHeading.isEmpty ? [currentHeading] : headingPath,
                model: model,
                chunkSchemaVersion: chunkSchemaVersion
            ))
        }

        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            if line.hasPrefix("#") {
                if !buffer.isEmpty {
                    appendChunk(endLine: max(lineNumber - 1, startLine))
                    buffer.removeAll()
                }
                let level = line.prefix { $0 == "#" }.count
                currentHeading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !currentHeading.isEmpty {
                    headingPath = Array(headingPath.prefix(max(level - 1, 0))) + [currentHeading]
                }
                startLine = lineNumber
            }
            buffer.append(line)
            if buffer.count >= maxLines {
                appendChunk(endLine: lineNumber)
                buffer.removeAll()
                startLine = lineNumber + 1
            }
        }
        if !buffer.isEmpty {
            appendChunk(endLine: lines.count)
        }
        return chunks
    }
}

public actor AgentEmbeddingIndexController {
    public nonisolated static let indexRelativePath = ".sci-station/index/embeddings"

    private let resourceProvider: AgentAuthorizedResourceProvider

    public init(resourceProvider: AgentAuthorizedResourceProvider = AgentAuthorizedResourceProvider()) {
        self.resourceProvider = resourceProvider
    }

    public func status(in root: ResearchRoot, model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity()) async -> AgentEmbeddingIndexStatusSnapshot {
        let store = AgentDeterministicEmbeddingStore(indexDirectoryURL: root.directoryURL(for: Self.indexRelativePath))
        do {
            try await store.open()
            let stats = await store.healthCheck(model: model, schemaVersion: AgentEmbeddingChunker.chunkSchemaVersion)
            return AgentEmbeddingIndexStatusSnapshot(
                status: stats.status,
                store: stats.store,
                model: model,
                chunkCount: stats.chunkCount,
                staleCount: stats.staleCount,
                fallbackReason: stats.fallbackReason,
                lastIndexedAt: stats.lastIndexedAt
            )
        } catch {
            return AgentEmbeddingIndexStatusSnapshot(status: .error, model: model, errorMessage: error.localizedDescription)
        }
    }

    public func rebuildCurrentProject(in root: ResearchRoot, projectID: String?, model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity()) async -> AgentEmbeddingIndexStatusSnapshot {
        do {
            let allDocuments = try await resourceProvider.listIndexableDocuments(in: root)
            let documents = allDocuments.filter { snapshot in
                guard let projectID else { return true }
                return snapshot.relativePath.hasPrefix("projects/\(projectID)/") || snapshot.sourceID == projectID
            }
            return try await rebuild(documents: documents, in: root, model: model)
        } catch {
            return AgentEmbeddingIndexStatusSnapshot(status: .error, model: model, errorMessage: error.localizedDescription)
        }
    }

    public func rebuildSelectedSource(_ relativePath: String, in root: ResearchRoot, model: AgentEmbeddingModelIdentity = AgentEmbeddingModelIdentity()) async -> AgentEmbeddingIndexStatusSnapshot {
        do {
            let allDocuments = try await resourceProvider.listIndexableDocuments(in: root)
            let documents = allDocuments.filter { $0.relativePath == relativePath }
            guard !documents.isEmpty else {
                return AgentEmbeddingIndexStatusSnapshot(status: .error, model: model, errorMessage: "Selected source is not indexable: \(relativePath)")
            }
            return try await rebuild(documents: documents, in: root, model: model)
        } catch {
            return AgentEmbeddingIndexStatusSnapshot(status: .error, model: model, errorMessage: error.localizedDescription)
        }
    }

    private func rebuild(documents: [IndexableDocumentSnapshot], in root: ResearchRoot, model: AgentEmbeddingModelIdentity) async throws -> AgentEmbeddingIndexStatusSnapshot {
        let store = AgentDeterministicEmbeddingStore(indexDirectoryURL: root.directoryURL(for: Self.indexRelativePath))
        try await store.open()
        try await store.beginTransaction()
        do {
            var chunks: [AgentEmbeddingChunk] = []
            for document in documents {
                let response = try await resourceProvider.read(
                    AuthorizedResourceReadRequest(resourceID: document.resourceID, maxBytes: 2_000_000, maxCharacters: 2_000_000),
                    in: root
                )
                try await store.deleteBySource(document.relativePath)
                chunks.append(contentsOf: AgentEmbeddingChunker.chunks(from: document, content: response.content, model: model))
            }
            try await store.upsertChunks(chunks)
            try await store.commitTransaction()
            let stats = await store.stats(currentSourceHashes: Dictionary(uniqueKeysWithValues: documents.map { ($0.relativePath, $0.contentHash) }))
            return AgentEmbeddingIndexStatusSnapshot(
                status: stats.status,
                store: stats.store,
                model: model,
                chunkCount: stats.chunkCount,
                staleCount: stats.staleCount,
                fallbackReason: stats.fallbackReason,
                lastIndexedAt: stats.lastIndexedAt
            )
        } catch {
            await store.rollbackTransaction()
            throw error
        }
    }
}

public nonisolated struct SidecarEmbeddingRequest: Codable, Hashable, Sendable {
    public var operation: String
    public var texts: [String]
    public var modelRequestID: String?
    public var modelOptions: [String: JSONValue]

    public nonisolated init(operation: String = "embed", texts: [String], modelRequestID: String? = nil, modelOptions: [String: JSONValue] = [:]) {
        self.operation = operation
        self.texts = texts
        self.modelRequestID = modelRequestID
        self.modelOptions = modelOptions
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "embed"
        self.texts = try container.decode([String].self, forKey: .texts)
        self.modelRequestID = try container.decodeIfPresent(String.self, forKey: .modelRequestID)
        self.modelOptions = try container.decodeIfPresent([String: JSONValue].self, forKey: .modelOptions) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case texts
        case modelRequestID = "model_request_id"
        case modelOptions = "model_options"
    }
}

public nonisolated struct SidecarEmbeddingResponse: Codable, Hashable, Sendable {
    public var vectors: [[Double]]
    public var redactedMetadata: [String: String]
    public var modelID: String
    public var tokenCount: Int
    public var latencyMilliseconds: Int
    public var providerErrorCode: String?

    private enum CodingKeys: String, CodingKey {
        case vectors
        case redactedMetadata = "redacted_metadata"
        case modelID = "model_id"
        case tokenCount = "token_count"
        case latencyMilliseconds = "latency_ms"
        case providerErrorCode = "provider_error_code"
    }
}

public nonisolated struct SidecarEmbeddingProxy: Sendable {
    public nonisolated init() {}

    public func embed(params: JSONValue?, runtimeRequest: AgentRuntimeRequest) async throws -> JSONValue {
        try validateNoSensitiveKeys(params)
        let request = try SidecarJSONCodec.decode(SidecarEmbeddingRequest.self, from: params)
        try validateNoSensitiveKeys(.object(request.modelOptions))
        guard request.operation == "embed" || request.operation == "respond" else {
            throw SidecarJSONRPCError(code: -32602, message: "Unsupported embedding operation: \(request.operation)")
        }
        let startedAt = Date()
        let model = AgentEmbeddingModelIdentity()
        let vectors = request.texts.map { AgentDeterministicEmbeddingStore.deterministicEmbedding($0, dimension: model.dimension) }
        let tokenCount = request.texts.reduce(0) { count, text in
            count + text.split { $0.isWhitespace || $0.isNewline }.count
        }
        let response = SidecarEmbeddingResponse(
            vectors: vectors,
            redactedMetadata: [
                "redacted": "true",
                "text_count": String(request.texts.count),
                "request_id": request.modelRequestID ?? ""
            ],
            modelID: model.modelID,
            tokenCount: tokenCount,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
            providerErrorCode: nil
        )
        _ = runtimeRequest.runID
        return try SidecarJSONCodec.jsonValue(from: response)
    }

    private func validateNoSensitiveKeys(_ value: JSONValue?) throws {
        guard let value else { return }
        let sensitiveFragments = ["api", "key", "token", "credential", "secret", "env", "provider_config"]
        func walk(_ value: JSONValue) throws {
            switch value {
            case let .object(object):
                for (key, item) in object {
                    let lowered = key.lowercased()
                    if sensitiveFragments.contains(where: { lowered.contains($0) }) {
                        throw SidecarJSONRPCError(code: -32602, message: "Embedding request contains a sensitive key: \(key)")
                    }
                    try walk(item)
                }
            case let .array(array):
                for item in array { try walk(item) }
            default:
                return
            }
        }
        try walk(value)
    }
}