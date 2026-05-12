import CryptoKit
import Foundation

/// Schema version for the on-disk research graph. Increment on every breaking
/// change and update `GraphMigrationRunner` accordingly. See Proposal44 §4.7.
public nonisolated let graphSchemaVersion: Int = 1

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

/// A graph node. `id` is `<kind>:<stable-id>` where `<stable-id>` never
/// contains `:` (so `id` can be decomposed by the first colon).
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

/// A graph edge. `id` is `<from>:<kind>:<to>` and is derived deterministically
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

/// Tombstone record written to `tombstones.jsonl` when a node or edge is
/// deleted. The replay logic uses tombstones to suppress prior upserts that
/// are no longer valid.
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

    public nonisolated init(schemaVersion: Int, nodes: [String: GraphNode], edges: [String: GraphEdge]) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes
        self.edges = edges
    }

    public nonisolated func node(id: String) -> GraphNode? { nodes[id] }
    public nonisolated func edge(id: String) -> GraphEdge? { edges[id] }
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

/// Changes published by `GraphRepository` to subscribers (P46 UI / P47 tools).
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

    /// Asserts (debug-only) that `id` does not contain `|` which is the edge
    /// ID separator. Colons are allowed since node IDs use the format
    /// `<kind>:<stable-id>` where stable-id may itself contain colons
    /// (e.g. `arxiv:2602.15113`). Edge IDs use `|` to avoid ambiguity.
    /// In release builds this is a no-op.
    public nonisolated static func assertStableIDIsClean(_ stableID: String) {
        assert(!stableID.contains("|"), "Graph node stable-id should not contain '|' (found in '\(stableID)')")
    }
}
