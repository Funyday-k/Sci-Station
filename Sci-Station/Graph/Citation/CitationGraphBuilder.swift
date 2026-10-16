import Foundation

/// Compatibility API for callers that update citations one source paper at a
/// time. It derives a complete expected graph from one repository snapshot and
/// commits the replacement through a single atomic reconciliation.
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

    /// Replaces all citation evidence for one source paper atomically. Multiple
    /// references to the same target share one semantic edge while retaining a
    /// distinct occurrence (and source anchor, when available) for each item.
    public func updateCitations(
        for sourcePaperGraphNodeID: String,
        references: [ResolvedReference],
        in root: ResearchRoot
    ) async throws {
        let sourceNodeID = "paper:\(sourcePaperGraphNodeID)"
        let indexedAt = Date()
        let previous = await repository.snapshot()
        var nodes = previous.nodes
        var edges = previous.edges
        var occurrences = previous.citationOccurrences
        var anchors = previous.sourceAnchors

        let replacedEdges = previous.edges.values.filter {
            $0.kind == .cites && $0.from == sourceNodeID
        }
        let replacedEdgeIDs = Set(replacedEdges.map(\.id))
        let removedAnchorIDs: Set<String> = Set(occurrences.values.compactMap { occurrence in
            guard replacedEdgeIDs.contains(occurrence.edgeID) else { return nil }
            return occurrence.anchorID
        })

        for edgeID in replacedEdgeIDs { edges.removeValue(forKey: edgeID) }
        occurrences = occurrences.filter { !replacedEdgeIDs.contains($0.value.edgeID) }
        let retainedAnchorIDs = Set(occurrences.values.compactMap(\.anchorID))
        for anchorID in removedAnchorIDs where !retainedAnchorIDs.contains(anchorID) {
            anchors.removeValue(forKey: anchorID)
        }

        var edgeOccurrences: [String: [GraphCitationOccurrence]] = [:]
        var externalReferences: [String: (reference: CitationReference, source: ExternalSource)] = [:]
        var duplicateCounts: [String: Int] = [:]
        var unresolved: [(reference: CitationReference, reason: String)] = []

        for resolved in references {
            let targetID: String
            switch resolved.outcome {
            case .matchedLocal(let paperGraphNodeID):
                targetID = "paper:\(paperGraphNodeID)"
            case .matchedExternal(let externalNodeID, let source):
                targetID = externalNodeID
                if shouldPreferExternal(resolved.reference, over: externalReferences[externalNodeID]?.reference) {
                    externalReferences[externalNodeID] = (resolved.reference, source)
                }
            case .unresolved(let reason):
                unresolved.append((resolved.reference, reason))
                continue
            }

            let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .cites, to: targetID)
            let referenceHash = resolved.reference.computeHash()
            let duplicateKey = GraphIdentifier.sourceHash(from: [edgeID, referenceHash])
            let duplicateIndex = duplicateCounts[duplicateKey, default: 0]
            duplicateCounts[duplicateKey] = duplicateIndex + 1
            let occurrenceHashComponents = duplicateIndex == 0
                ? [edgeID, referenceHash]
                : [edgeID, referenceHash, "duplicate:\(duplicateIndex)"]
            let occurrenceID = "citation_occurrence:\(GraphIdentifier.sourceHash(from: occurrenceHashComponents))"
            let anchorID = resolved.reference.sourceRelativePath.map { relativePath -> String in
                let anchorHashComponents = [
                    sourceNodeID,
                    relativePath,
                    resolved.reference.locator ?? ""
                ]
                return "source_anchor:\(GraphIdentifier.sourceHash(from: anchorHashComponents))"
            }
            if let relativePath = resolved.reference.sourceRelativePath, let anchorID {
                anchors[anchorID] = GraphSourceAnchor(
                    id: anchorID,
                    sourceNodeID: sourceNodeID,
                    relativePath: relativePath,
                    locator: resolved.reference.locator ?? "unknown",
                    excerpt: String(resolved.reference.rawText.prefix(500)),
                    sourceHash: referenceHash
                )
            }
            let occurrence = GraphCitationOccurrence(
                id: occurrenceID,
                edgeID: edgeID,
                sourceNodeID: sourceNodeID,
                targetNodeID: targetID,
                evidenceSource: resolved.reference.evidenceSource.rawValue,
                bibtexKey: resolved.reference.bibtexKey,
                rawText: String(resolved.reference.rawText.prefix(2_000)),
                ordinal: resolved.reference.occurrenceIndex,
                sourceHash: referenceHash,
                anchorID: anchorID
            )
            occurrences[occurrence.id] = occurrence
            edgeOccurrences[edgeID, default: []].append(occurrence)
        }

        for (externalID, item) in externalReferences {
            nodes[externalID] = externalNode(
                id: externalID,
                source: item.source,
                reference: item.reference,
                previous: previous.node(id: externalID),
                indexedAt: indexedAt
            )
        }

        for (edgeID, items) in edgeOccurrences {
            guard let first = items.first else { continue }
            let sorted = items.sorted { $0.id < $1.id }
            let sourceHash = GraphIdentifier.canonicalHash(
                of: JSONValue.array(sorted.map { .string($0.sourceHash) })
            )
            let previousEdge = previous.edge(id: edgeID)
            edges[edgeID] = GraphEdge(
                id: edgeID,
                kind: .cites,
                from: first.sourceNodeID,
                to: first.targetNodeID,
                payload: .object([
                    "occurrence_count": .number(String(sorted.count)),
                    "evidence_sources": .array(
                        Array(Set(sorted.map(\.evidenceSource))).sorted().map(JSONValue.string)
                    )
                ]),
                createdAt: previousEdge?.createdAt ?? indexedAt,
                updatedAt: indexedAt,
                sourceHash: sourceHash,
                lastIndexedAt: previousEdge?.sourceHash == sourceHash
                    ? previousEdge?.lastIndexedAt ?? indexedAt
                    : indexedAt
            )
        }

        let referencedNodeIDs = Set(edges.values.flatMap { [$0.from, $0.to] })
        for nodeID in Set(replacedEdges.map(\.to)) where
            previous.node(id: nodeID).map(isExternalNode) == true &&
            !referencedNodeIDs.contains(nodeID) {
            nodes.removeValue(forKey: nodeID)
        }

        _ = try await repository.reconcile(GraphExpectedState(
            nodes: nodes,
            edges: edges,
            citationOccurrences: occurrences,
            sourceAnchors: anchors
        ))

        for item in unresolved {
            let warning = CitationResolutionWarning(
                sourcePaperID: item.reference.sourcePaperID,
                rawText: String(item.reference.rawText.prefix(200)),
                reason: item.reason,
                lastSeenAt: indexedAt
            )
            do {
                try await warningStore.append(warning, in: root)
            } catch {
                await emit(
                    "citation.warning_store_failed",
                    payload: .object(["error": .string(String(describing: error))]),
                    in: root
                )
            }
            await emit(
                "citation.resolve_unmatched",
                payload: .object([
                    "source_paper_id": .string(item.reference.sourcePaperID),
                    "reason": .string(item.reason),
                    "has_doi": .bool(item.reference.doi != nil),
                    "has_arxiv": .bool(item.reference.arxivID != nil),
                    "has_title": .bool(item.reference.normalizedTitle != nil)
                ]),
                in: root
            )
        }

        for edge in edgeOccurrences.values.compactMap(\.first) {
            await emit(
                "citation.edge_upsert",
                payload: .object([
                    "edge_id": .string(edge.edgeID),
                    "from": .string(edge.sourceNodeID),
                    "to": .string(edge.targetNodeID)
                ]),
                in: root
            )
        }
        let currentEdgeIDs = Set(edgeOccurrences.keys)
        for edge in replacedEdges where !currentEdgeIDs.contains(edge.id) {
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

    private func externalNode(
        id: String,
        source: ExternalSource,
        reference: CitationReference,
        previous: GraphNode?,
        indexedAt: Date
    ) -> GraphNode {
        let displayName: String
        switch source {
        case .doi:
            displayName = reference.doi ?? "External (DOI)"
        case .arxiv:
            displayName = reference.arxivID ?? "External (arXiv)"
        case .titleHash:
            displayName = reference.normalizedTitle ?? "External Paper"
        }

        let payload: JSONValue = .object([
            "is_external": .bool(true),
            "source": .string(source.rawValue),
            "doi": reference.doi.map(JSONValue.string) ?? .null,
            "arxiv": reference.arxivID.map(JSONValue.string) ?? .null,
            "title": reference.normalizedTitle.map(JSONValue.string) ?? .null,
            "first_author": reference.firstAuthorLastName.map(JSONValue.string) ?? .null,
            "year": reference.year.map { .number(String($0)) } ?? .null
        ])
        let sourceHash = GraphIdentifier.canonicalHash(of: JSONValue.object([
            "id": .string(id),
            "source": .string(source.rawValue),
            "doi": reference.doi.map(JSONValue.string) ?? .null,
            "arxiv": reference.arxivID.map(JSONValue.string) ?? .null,
            "title": reference.normalizedTitle.map(JSONValue.string) ?? .null,
            "first_author": reference.firstAuthorLastName.map(JSONValue.string) ?? .null,
            "year": reference.year.map { .number(String($0)) } ?? .null
        ]))
        return GraphNode(
            id: id,
            kind: .paper,
            displayName: displayName,
            payload: payload,
            createdAt: previous?.createdAt ?? indexedAt,
            updatedAt: indexedAt,
            sourceHash: sourceHash,
            lastIndexedAt: previous?.sourceHash == sourceHash
                ? previous?.lastIndexedAt ?? indexedAt
                : indexedAt
        )
    }

    private func shouldPreferExternal(
        _ candidate: CitationReference,
        over current: CitationReference?
    ) -> Bool {
        guard let current else { return true }
        let candidateScore = [
            candidate.doi,
            candidate.arxivID,
            candidate.normalizedTitle,
            candidate.firstAuthorLastName,
            candidate.year.map(String.init)
        ].compactMap { $0 }.count
        let currentScore = [
            current.doi,
            current.arxivID,
            current.normalizedTitle,
            current.firstAuthorLastName,
            current.year.map(String.init)
        ].compactMap { $0 }.count
        if candidateScore != currentScore { return candidateScore > currentScore }
        return candidate.computeHash() < current.computeHash()
    }

    private func isExternalNode(_ node: GraphNode) -> Bool {
        node.kind == .paper && node.payload.objectValue?["is_external"] == .bool(true)
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
