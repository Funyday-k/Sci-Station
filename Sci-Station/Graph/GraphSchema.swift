import CryptoKit
import Foundation

/// Schema version exposed by graph snapshots and manifests. SQLite storage
/// migrations are applied by `GraphRepository` through `PRAGMA user_version`.
public nonisolated let graphSchemaVersion: Int = 2

public enum GraphNodeKind: String, Codable, Hashable, Sendable, CaseIterable {
    case paper
    case project
    case concept
    case method
    case dataset
    case claim
    case evidence
    case task
    case artifact
    case calendarEvent = "calendar_event"
    case run
    case approval
}

public enum GraphEdgeKind: String, Codable, Hashable, Sendable, CaseIterable {
    case cites
    case mentions
    case supports
    case contradicts
    case extends
    case uses
    case belongsTo = "belongs_to"
    case relatedTo = "related_to"
    case generatedBy = "generated_by"
    case approvedBy = "approved_by"
    case scheduledFor = "scheduled_for"
}

/// A graph node. `id` is namespaced as `<kind>:<stable-id>`, but the stable
/// portion may contain additional colons, so callers should treat it as opaque.
public nonisolated struct GraphNode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: GraphNodeKind
    public let displayName: String
    public let payload: JSONValue
    public let createdAt: Date
    public let updatedAt: Date
    public let sourceHash: String?
    public let lastIndexedAt: Date

    public nonisolated init(
        id: String,
        kind: GraphNodeKind,
        displayName: String,
        payload: JSONValue = .object([:]),
        createdAt: Date,
        updatedAt: Date,
        sourceHash: String?,
        lastIndexedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceHash = sourceHash
        self.lastIndexedAt = lastIndexedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName = "display_name"
        case payload
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sourceHash = "source_hash"
        case lastIndexedAt = "last_indexed_at"
    }
}

/// A graph edge. `id` is `<from>|<kind>|<to>` and is derived deterministically
/// by `GraphEdge.computeID` so upserts are idempotent.
public nonisolated struct GraphEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: GraphEdgeKind
    public let from: String
    public let to: String
    public let weight: Double
    public let payload: JSONValue
    public let createdAt: Date
    public let updatedAt: Date
    public let sourceHash: String?
    public let lastIndexedAt: Date

    public nonisolated init(
        id: String? = nil,
        kind: GraphEdgeKind,
        from: String,
        to: String,
        weight: Double = 1.0,
        payload: JSONValue = .object([:]),
        createdAt: Date,
        updatedAt: Date,
        sourceHash: String?,
        lastIndexedAt: Date
    ) {
        self.id = id ?? Self.computeID(from: from, kind: kind, to: to)
        self.kind = kind
        self.from = from
        self.to = to
        self.weight = weight
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceHash = sourceHash
        self.lastIndexedAt = lastIndexedAt
    }

    public static func computeID(from: String, kind: GraphEdgeKind, to: String) -> String {
        "\(from)|\(kind.rawValue)|\(to)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case from
        case to
        case weight
        case payload
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sourceHash = "source_hash"
        case lastIndexedAt = "last_indexed_at"
    }
}

/// Legacy JSONL deletion record retained for migration compatibility. Current
/// SQLite graph writes delete rows directly and do not append tombstones.
public nonisolated struct GraphTombstone: Codable, Hashable, Sendable {
    public enum Target: String, Codable, Hashable, Sendable {
        case node
        case edge
    }

    public let id: String
    public let target: Target
    public let createdAt: Date
    public let reason: String?

    public nonisolated init(id: String, target: Target, createdAt: Date = Date(), reason: String? = nil) {
        self.id = id
        self.target = target
        self.createdAt = createdAt
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case target
        case createdAt = "created_at"
        case reason
    }
}

/// Read-only snapshot of the in-memory graph, suitable for passing across
/// actor boundaries. Exposes lookup helpers used by the indexer.
public nonisolated struct GraphSnapshot: Sendable {
    public let schemaVersion: Int
    public let nodes: [String: GraphNode]
    public let edges: [String: GraphEdge]
    public let citationOccurrences: [String: GraphCitationOccurrence]
    public let sourceAnchors: [String: GraphSourceAnchor]

    public nonisolated init(
        schemaVersion: Int,
        nodes: [String: GraphNode],
        edges: [String: GraphEdge],
        citationOccurrences: [String: GraphCitationOccurrence] = [:],
        sourceAnchors: [String: GraphSourceAnchor] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes
        self.edges = edges
        self.citationOccurrences = citationOccurrences
        self.sourceAnchors = sourceAnchors
    }

    public nonisolated func node(id: String) -> GraphNode? { nodes[id] }
    public nonisolated func edge(id: String) -> GraphEdge? { edges[id] }
}

/// One concrete appearance of a citation. Citation edges describe the
/// semantic relationship; occurrences preserve every piece of evidence that
/// established it, including repeated references to the same target.
public nonisolated struct GraphCitationOccurrence: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let edgeID: String
    public let sourceNodeID: String
    public let targetNodeID: String
    public let evidenceSource: String
    public let bibtexKey: String?
    public let rawText: String
    public let ordinal: Int
    public let sourceHash: String
    public let anchorID: String?

    public nonisolated init(
        id: String,
        edgeID: String,
        sourceNodeID: String,
        targetNodeID: String,
        evidenceSource: String,
        bibtexKey: String? = nil,
        rawText: String,
        ordinal: Int,
        sourceHash: String,
        anchorID: String? = nil
    ) {
        self.id = id
        self.edgeID = edgeID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.evidenceSource = evidenceSource
        self.bibtexKey = bibtexKey
        self.rawText = rawText
        self.ordinal = ordinal
        self.sourceHash = sourceHash
        self.anchorID = anchorID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case edgeID = "edge_id"
        case sourceNodeID = "source_node_id"
        case targetNodeID = "target_node_id"
        case evidenceSource = "evidence_source"
        case bibtexKey = "bibtex_key"
        case rawText = "raw_text"
        case ordinal
        case sourceHash = "source_hash"
        case anchorID = "anchor_id"
    }
}

/// Stable pointer back to source material that produced a graph fact.
public nonisolated struct GraphSourceAnchor: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let sourceNodeID: String
    public let relativePath: String
    public let locator: String
    public let excerpt: String?
    public let sourceHash: String

    public nonisolated init(
        id: String,
        sourceNodeID: String,
        relativePath: String,
        locator: String,
        excerpt: String? = nil,
        sourceHash: String
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.relativePath = relativePath
        self.locator = locator
        self.excerpt = excerpt
        self.sourceHash = sourceHash
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceNodeID = "source_node_id"
        case relativePath = "relative_path"
        case locator
        case excerpt
        case sourceHash = "source_hash"
    }
}

/// Complete authoritative graph produced by one deterministic indexing pass.
/// Reconciliation treats the listed kinds as managed and leaves future/manual
/// graph kinds alone.
public nonisolated struct GraphExpectedState: Sendable {
    public let nodes: [String: GraphNode]
    public let edges: [String: GraphEdge]
    public let citationOccurrences: [String: GraphCitationOccurrence]
    public let sourceAnchors: [String: GraphSourceAnchor]
    public let managedNodeKinds: Set<GraphNodeKind>
    public let managedEdgeKinds: Set<GraphEdgeKind>

    public nonisolated init(
        nodes: [String: GraphNode],
        edges: [String: GraphEdge],
        citationOccurrences: [String: GraphCitationOccurrence] = [:],
        sourceAnchors: [String: GraphSourceAnchor] = [:],
        managedNodeKinds: Set<GraphNodeKind> = [.paper, .project, .concept, .method, .task],
        managedEdgeKinds: Set<GraphEdgeKind> = [.cites, .mentions, .belongsTo]
    ) {
        self.nodes = nodes
        self.edges = edges
        self.citationOccurrences = citationOccurrences
        self.sourceAnchors = sourceAnchors
        self.managedNodeKinds = managedNodeKinds
        self.managedEdgeKinds = managedEdgeKinds
    }
}

public nonisolated struct GraphReconciliationResult: Hashable, Sendable {
    public let insertedOrUpdatedNodes: Int
    public let insertedOrUpdatedEdges: Int
    public let deletedNodes: Int
    public let deletedEdges: Int
    public let citationOccurrences: Int
    public let sourceAnchors: Int

    public nonisolated init(
        insertedOrUpdatedNodes: Int,
        insertedOrUpdatedEdges: Int,
        deletedNodes: Int,
        deletedEdges: Int,
        citationOccurrences: Int,
        sourceAnchors: Int
    ) {
        self.insertedOrUpdatedNodes = insertedOrUpdatedNodes
        self.insertedOrUpdatedEdges = insertedOrUpdatedEdges
        self.deletedNodes = deletedNodes
        self.deletedEdges = deletedEdges
        self.citationOccurrences = citationOccurrences
        self.sourceAnchors = sourceAnchors
    }
}

/// Manifest persisted at `.sci-station/graph/manifest.json`. Holds the schema
/// version plus counters used for compact scheduling and debug events.
public nonisolated struct GraphManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var lastCompactAt: Date?
    public var lastIndexedAt: Date?
    public var countNodes: Int
    public var countEdges: Int
    public var countTombstones: Int
    public var appVersion: String?

    public nonisolated init(
        schemaVersion: Int = graphSchemaVersion,
        generatedAt: Date = Date(),
        lastCompactAt: Date? = nil,
        lastIndexedAt: Date? = nil,
        countNodes: Int = 0,
        countEdges: Int = 0,
        countTombstones: Int = 0,
        appVersion: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.lastCompactAt = lastCompactAt
        self.lastIndexedAt = lastIndexedAt
        self.countNodes = countNodes
        self.countEdges = countEdges
        self.countTombstones = countTombstones
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case lastCompactAt = "last_compact_at"
        case lastIndexedAt = "last_indexed_at"
        case countNodes = "count_nodes"
        case countEdges = "count_edges"
        case countTombstones = "count_tombstones"
        case appVersion = "app_version"
    }
}

/// Changes published by `GraphRepository` to subscribers.
public enum GraphChange: Sendable {
    case upsertNode(GraphNode)
    case upsertEdge(GraphEdge)
    case deleteNode(String)
    case deleteEdge(String)
    case bulkReloaded
}

/// Subgraph result returned by `GraphReadModel.subgraph(...)`.
public nonisolated struct GraphSubgraph: Sendable {
    public let center: String
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]

    public nonisolated init(center: String, nodes: [GraphNode], edges: [GraphEdge]) {
        self.center = center
        self.nodes = nodes
        self.edges = edges
    }
}

public nonisolated struct GraphCompactResult: Sendable {
    public let snapshotURL: URL?
    public let beforeLines: Int
    public let afterLines: Int
    public let durationMilliseconds: Double

    public nonisolated init(snapshotURL: URL?, beforeLines: Int, afterLines: Int, durationMilliseconds: Double) {
        self.snapshotURL = snapshotURL
        self.beforeLines = beforeLines
        self.afterLines = afterLines
        self.durationMilliseconds = durationMilliseconds
    }
}

/// Utility for normalising a name into a slug suitable for concept/method ids.
/// This matches `WikiLink.normalizePageKey` but collapses whitespace to `-`
/// (ids cannot contain spaces).
public enum GraphIdentifier {
    public nonisolated static func slug(from value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let filteredScalars = normalized.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
    }

    /// Produces a deterministic source hash from a stable representation of
    /// any codable value. Used by the indexer to decide whether to skip an
    /// unchanged entity.
    public nonisolated static func sourceHash(from components: [String]) -> String {
        let joined = components.joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes a Codable value using sorted-key JSON and ISO-8601 dates. This is
    /// the canonical hashing primitive for graph records and source entities.
    public nonisolated static func canonicalHash<T: Encodable>(of value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            assertionFailure("Graph canonical hash encoding failed for \(T.self)")
            return sourceHash(from: [String(describing: value)])
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Produces a readable, workspace/project-scoped identifier while using a
    /// SHA-256 suffix to avoid the punctuation collisions caused by slugs.
    public nonisolated static func scopedEntityID(kind: GraphNodeKind, name: String, scope: String) -> String {
        let canonicalName = name.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let canonicalScope = scope.precomposedStringWithCanonicalMapping.lowercased()
        let nameDigest = sourceHash(from: [canonicalName])
        let scopeDigest = sourceHash(from: [canonicalScope])
        let readable = slug(from: name).prefix(48)
        let label = readable.isEmpty ? "entity" : String(readable)
        return "\(kind.rawValue):\(scopeDigest.prefix(16)):\(label)-\(nameDigest.prefix(16))"
    }

    /// Asserts (debug-only) that `id` does not contain `|` which is the edge
    /// ID separator. Colons are allowed since node IDs use the format
    /// `<kind>:<stable-id>` where stable-id may itself contain colons
    /// (e.g. `arxiv:2602.15113`). Edge IDs use `|` to avoid ambiguity.
    /// In release builds this is a no-op.
    public nonisolated static func assertStableIDIsClean(_ stableID: String) {
        assert(!stableID.contains("|"), "Graph node stable-id should not contain '|' (found in '\(stableID)')")
    }
}
