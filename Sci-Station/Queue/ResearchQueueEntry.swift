import Foundation

/// One row in a research reading queue. P48 Layer A is built directly out of
/// these rows; Layer B (P49 recommendation ingest) feeds the same shape so
/// that the queue file format stays stable across implementations. See
/// `docs/development/Proposal48.md` §5.1.
public nonisolated struct ResearchQueueEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var paperID: String?
    public var externalKey: String?
    public var displayTitle: String
    public var scope: QueueScope
    public var status: QueueStatus
    public var source: QueueSource
    public var order: Int
    public var addedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var lastTouchedAt: Date
    public var noteSummary: String?
    public var sourceRefs: [String]

    public nonisolated init(
        id: String,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        scope: QueueScope,
        status: QueueStatus = .queued,
        source: QueueSource = .manual,
        order: Int,
        addedAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        lastTouchedAt: Date,
        noteSummary: String? = nil,
        sourceRefs: [String] = []
    ) {
        self.id = id
        self.paperID = paperID
        self.externalKey = externalKey
        self.displayTitle = displayTitle
        self.scope = scope
        self.status = status
        self.source = source
        self.order = order
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.lastTouchedAt = lastTouchedAt
        self.noteSummary = noteSummary
        self.sourceRefs = sourceRefs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case paperID = "paper_id"
        case externalKey = "external_key"
        case displayTitle = "display_title"
        case scope
        case status
        case source
        case order
        case addedAt = "added_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case lastTouchedAt = "last_touched_at"
        case noteSummary = "note_summary"
        case sourceRefs = "source_refs"
    }
}

/// Queue files live either at the workspace level (`library/queue.yaml`) or at
/// the project level (`projects/<id>/queue.yaml`). Both share the same row
/// schema; only the relative path differs. `identifier` is used as the
/// deterministic key in YAML (`workspace` or `project:<id>`) so that round-
/// trips stay byte-stable.
public nonisolated enum QueueScope: Hashable, Sendable, Codable {
    case workspace
    case project(String)

    public var identifier: String {
        switch self {
        case .workspace:
            return "workspace"
        case .project(let projectID):
            return "project:\(projectID)"
        }
    }

    public var fileRelativePath: String {
        switch self {
        case .workspace:
            return "library/queue.yaml"
        case .project(let projectID):
            return "projects/\(projectID)/queue.yaml"
        }
    }

    public var projectID: String? {
        if case .project(let id) = self {
            return id
        }
        return nil
    }

    /// Round-trips `identifier` strings such as `workspace` or `project:p1`.
    public init?(identifier: String) {
        if identifier == "workspace" {
            self = .workspace
            return
        }
        if identifier.hasPrefix("project:") {
            let projectID = String(identifier.dropFirst("project:".count))
            guard !projectID.isEmpty else {
                return nil
            }
            self = .project(projectID)
            return
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let scope = QueueScope(identifier: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown queue scope identifier: \(raw)"
            )
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}

/// Status machine — `queued → reading → finished` is the happy path; the rest
/// captures defer / dismiss / abandoned cases. See `docs/development/Proposal48.md` §3.3.
public nonisolated enum QueueStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case queued
    case reading
    case finished
    case deferred
    case dismissed
}

/// Why a queue entry exists. `manual` is direct user action; `recommendation`
/// arrives via the P49 ingestor (Layer B); `graphTool` is reserved for the P47
/// graph workflow path; `paperStatus` is set when a queue row is auto-flipped
/// by `Paper.status` transitions (§4.10). Raw values stay snake_case so the
/// YAML file is human-readable.
public nonisolated enum QueueSource: String, Codable, Hashable, Sendable, CaseIterable {
    case manual
    case recommendation
    case graphTool = "graph_tool"
    case paperStatus = "paper_status"
}

/// Streamed change events. Subscribers (UI / aggregator) pull the latest store
/// snapshot when they receive any event; the event itself only describes what
/// kind of mutation happened, never the entry contents.
public nonisolated enum QueueChange: Hashable, Sendable {
    case appended(id: String, scope: QueueScope)
    case appendedBatch(scope: QueueScope, count: Int)
    case statusChanged(id: String, scope: QueueScope, from: QueueStatus, to: QueueStatus)
    case reordered(scope: QueueScope, count: Int)
    case removed(id: String, scope: QueueScope)
    case bulkReloaded(scope: QueueScope, count: Int)
}

/// Lightweight projection used by `HomeSnapshot` / `ProjectDashboardSnapshot`
/// so that UI layers do not transitively depend on the actor's full row type.
/// The aggregator builds these from `ResearchQueueStore` snapshots; UI views
/// then render them. Sensitive long-text (`noteSummary`) is included as-is for
/// the UI but never written to debug events.
public nonisolated struct ReadingQueueEntrySummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var paperID: String?
    public var externalKey: String?
    public var displayTitle: String
    public var status: QueueStatus
    public var source: QueueSource
    public var order: Int
    public var scopeIdentifier: String
    public var lastTouchedAt: Date
    public var noteSummary: String?

    public nonisolated init(
        id: String,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        status: QueueStatus,
        source: QueueSource,
        order: Int,
        scopeIdentifier: String,
        lastTouchedAt: Date,
        noteSummary: String? = nil
    ) {
        self.id = id
        self.paperID = paperID
        self.externalKey = externalKey
        self.displayTitle = displayTitle
        self.status = status
        self.source = source
        self.order = order
        self.scopeIdentifier = scopeIdentifier
        self.lastTouchedAt = lastTouchedAt
        self.noteSummary = noteSummary
    }

    public nonisolated init(entry: ResearchQueueEntry) {
        self.init(
            id: entry.id,
            paperID: entry.paperID,
            externalKey: entry.externalKey,
            displayTitle: entry.displayTitle,
            status: entry.status,
            source: entry.source,
            order: entry.order,
            scopeIdentifier: entry.scope.identifier,
            lastTouchedAt: entry.lastTouchedAt,
            noteSummary: entry.noteSummary
        )
    }
}
