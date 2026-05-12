import Foundation

/// Writes `cites` edges and external paper nodes into the `GraphRepository`
/// based on resolved references. Also manages tombstoning of edges that no
/// longer exist after a re-index.
public actor CitationGraphBuilder {
    private let repository: GraphRepository
    private let warningStore: CitationResolutionStore
    private let debug: AppDebugEventLogger?

    public init(
        repository: GraphRepository,
        warningStore: CitationResolutionStore = CitationResolutionStore(),
        debug: AppDebugEventLogger? = nil
    ) {
        self.repository = repository
        self.warningStore = warningStore
        self.debug = debug
    }

    /// Updates all `cites` edges for a given source paper. Edges that existed
    /// before but are no longer present in `references` are tombstoned.
    public func updateCitations(
        for sourcePaperGraphNodeID: String,
        references: [ResolvedReference],
        in root: ResearchRoot
    ) async throws {
        let sourceNodeID = "paper:\(sourcePaperGraphNodeID)"
        let existingEdges = await repository.outgoingEdges(of: sourceNodeID)
            .filter { $0.kind == .cites }
        var keepEdgeIDs: Set<String> = []

        for resolved in references {
            let targetID: String
            switch resolved.outcome {
            case .matchedLocal(let paperGraphNodeID):
                targetID = "paper:\(paperGraphNodeID)"
            case .matchedExternal(let externalNodeID, let source):
                targetID = externalNodeID
                try await ensureExternalNode(
                    id: externalNodeID,
                    source: source,
                    reference: resolved.reference
                )
            case .unresolved(let reason):
                try await warningStore.append(
                    CitationResolutionWarning(
                        sourcePaperID: resolved.reference.sourcePaperID,
                        rawText: String(resolved.reference.rawText.prefix(200)),
                        reason: reason,
                        lastSeenAt: Date()
                    ),
                    in: root
                )
                await emit(
                    "citation.resolve_unmatched",
                    payload: .object([
                        "source_paper_id": .string(resolved.reference.sourcePaperID),
                        "reason": .string(reason),
                        "has_doi": .bool(resolved.reference.doi != nil),
                        "has_arxiv": .bool(resolved.reference.arxivID != nil),
                        "has_title": .bool(resolved.reference.normalizedTitle != nil)
                    ]),
                    in: root
                )
                continue
            }

            let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .cites, to: targetID)
            keepEdgeIDs.insert(edgeID)

            try await repository.upsertEdge(GraphEdge(
                id: edgeID,
                kind: .cites,
                from: sourceNodeID,
                to: targetID,
                weight: 1.0,
                payload: .object([
                    "evidence_source": .string(resolved.reference.evidenceSource.rawValue),
                    "bibtex_key": resolved.reference.bibtexKey.map { .string($0) } ?? .null,
                    "raw_text": .string(String(resolved.reference.rawText.prefix(200)))
                ]),
                createdAt: Date(),
                updatedAt: Date(),
                sourceHash: resolved.reference.computeHash(),
                lastIndexedAt: Date()
            ))

            await emit(
                "citation.edge_upsert",
                payload: .object([
                    "edge_id": .string(edgeID),
                    "from": .string(sourceNodeID),
                    "to": .string(targetID),
                    "evidence_source": .string(resolved.reference.evidenceSource.rawValue)
                ]),
                in: root
            )
        }

        // Tombstone edges that no longer exist.
        for edge in existingEdges where !keepEdgeIDs.contains(edge.id) {
            try await repository.deleteEdge(id: edge.id, reason: "reference_removed")
            await emit(
                "citation.edge_tombstone",
                payload: .object([
                    "edge_id": .string(edge.id),
                    "reason": .string("reference_removed")
                ]),
                in: root
            )
        }
    }

    private func ensureExternalNode(
        id: String,
        source: ExternalSource,
        reference: CitationReference
    ) async throws {
        // Only create if it doesn't already exist.
        if await repository.node(id: id) != nil { return }

        let displayName: String
        switch source {
        case .doi:
            displayName = reference.doi ?? "External (DOI)"
        case .arxiv:
            displayName = reference.arxivID ?? "External (arXiv)"
        case .titleHash:
            displayName = reference.normalizedTitle ?? "External Paper"
        }

        try await repository.upsertNode(GraphNode(
            id: id,
            kind: .paper,
            displayName: displayName,
            payload: .object([
                "is_external": .bool(true),
                "source": .string(source.rawValue),
                "doi": reference.doi.map { .string($0) } ?? .null,
                "arxiv": reference.arxivID.map { .string($0) } ?? .null,
                "title": reference.normalizedTitle.map { .string($0) } ?? .null,
                "first_author": reference.firstAuthorLastName.map { .string($0) } ?? .null,
                "year": reference.year.map { .number(String($0)) } ?? .null
            ]),
            createdAt: Date(),
            updatedAt: Date(),
            sourceHash: nil,
            lastIndexedAt: Date()
        ))
    }

    private func emit(_ event: String, payload: JSONValue, in root: ResearchRoot) async {
        guard let debug else { return }
        try? await debug.append(AppDebugEvent(event: event, payload: payload), in: root)
    }
}

// MARK: - Citation Resolution Store

public nonisolated struct CitationResolutionWarning: Codable, Hashable, Sendable {
    public var sourcePaperID: String
    public var rawText: String
    public var reason: String
    public var lastSeenAt: Date

    public nonisolated init(sourcePaperID: String, rawText: String, reason: String, lastSeenAt: Date) {
        self.sourcePaperID = sourcePaperID
        self.rawText = rawText
        self.reason = reason
        self.lastSeenAt = lastSeenAt
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePaperID = "source_paper_id"
        case rawText = "raw_text"
        case reason
        case lastSeenAt = "last_seen_at"
    }
}

/// Persists unresolved citation warnings to `.sci-station/graph/citation_warnings.jsonl`.
public actor CitationResolutionStore {
    public static let relativePath = ".sci-station/graph/citation_warnings.jsonl"

    private let writerRegistry: JSONLWriterRegistry

    public init(writerRegistry: JSONLWriterRegistry = .shared) {
        self.writerRegistry = writerRegistry
    }

    public func append(_ warning: CitationResolutionWarning, in root: ResearchRoot) async throws {
        let url = root.fileURL(for: Self.relativePath)
        let writer = await writerRegistry.writer(for: url)
        try await writer.append(warning, encoder: JSONLWriter.defaultEncoder())
    }

    public func warnings(in root: ResearchRoot) throws -> [CitationResolutionWarning] {
        let url = root.fileURL(for: Self.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { try? decoder.decode(CitationResolutionWarning.self, from: Data($0.utf8)) }
    }
}
