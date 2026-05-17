import Foundation

/// View kinds for the graph UI. Each kind determines the center node
/// selection strategy and default edge filter.
public nonisolated enum GraphViewKind: String, Codable, CaseIterable, Hashable, Sendable {
    case paperNeighborhood = "paper_neighborhood"
    case projectCitation = "project_citation"
    case themeCluster = "theme_cluster"
    case evidenceSupport = "evidence_support"
    case artifactLineage = "artifact_lineage"

    public var displayTitle: String {
        switch self {
        case .paperNeighborhood: return "Paper Neighborhood"
        case .projectCitation: return "Project Citations"
        case .themeCluster: return "Theme Clusters"
        case .evidenceSupport: return "Evidence Support"
        case .artifactLineage: return "Artifact Lineage"
        }
    }
}

/// LRU cache for computed subgraphs. Keyed by `(viewKind, centerNodeID,
/// depth, kindFilter)`. Capacity defaults to 32 entries.
///
/// The cache listens for `GraphChange.bulkReloaded` events to invalidate
/// all entries when the underlying graph is rebuilt.
public actor SubgraphCache {
    public nonisolated struct Key: Hashable, Sendable {
        public let viewKind: GraphViewKind
        public let centerNodeID: String
        public let depth: Int
        public let kindFilter: Set<GraphEdgeKind>

        public nonisolated init(viewKind: GraphViewKind, centerNodeID: String, depth: Int, kindFilter: Set<GraphEdgeKind>) {
            self.viewKind = viewKind
            self.centerNodeID = centerNodeID
            self.depth = depth
            self.kindFilter = kindFilter
        }
    }

    private var entries: [(Key, GraphSubgraph)] = []
    private let capacity: Int

    public init(capacity: Int = 32) {
        self.capacity = max(1, capacity)
    }

    public func get(_ key: Key) -> GraphSubgraph? {
        guard let index = entries.firstIndex(where: { $0.0 == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.1
    }

    public func put(_ key: Key, _ subgraph: GraphSubgraph) {
        if let index = entries.firstIndex(where: { $0.0 == key }) {
            entries.remove(at: index)
        }
        entries.append((key, subgraph))
        if entries.count > capacity {
            entries.removeFirst()
        }
    }

    public func invalidateAll() {
        entries.removeAll()
    }

    public var count: Int { entries.count }
}

/// Immutable state snapshot for the graph view. Used by the UI layer to
/// drive rendering without holding actor references.
public nonisolated struct GraphViewState: Hashable, Sendable {
    public var kind: GraphViewKind
    public var centerNodeID: String?
    public var depth: Int
    public var kindFilter: Set<GraphEdgeKind>
    public var zoom: Double
    public var panX: Double
    public var panY: Double
    public var selectedNodeID: String?

    public nonisolated init(
        kind: GraphViewKind = .paperNeighborhood,
        centerNodeID: String? = nil,
        depth: Int = 2,
        kindFilter: Set<GraphEdgeKind> = [],
        zoom: Double = 1.0,
        panX: Double = 0,
        panY: Double = 0,
        selectedNodeID: String? = nil
    ) {
        self.kind = kind
        self.centerNodeID = centerNodeID
        self.depth = depth
        self.kindFilter = kindFilter
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.selectedNodeID = selectedNodeID
    }
}

/// Actions that can be performed on a graph node. Write actions require
/// Permission Dock approval; agent actions route through AI Lab graph workflows.
public nonisolated enum NodeAction: Hashable, Sendable {
    case openPaper(paperID: String)
    case openWikiPage(path: String)
    case addToProject(paperID: String, projectID: String)
    case markAsCore(paperID: String, projectID: String)
    case createTodo(targetNodeID: String, title: String)
    case generateReadingOrder(centerPaperID: String)
    case explainConnection(fromID: String, toID: String)
    case findBridgePapers(fromID: String, toID: String)

    public var isWriteAction: Bool {
        switch self {
        case .addToProject, .markAsCore, .createTodo:
            return true
        case .openPaper, .openWikiPage, .generateReadingOrder, .explainConnection, .findBridgePapers:
            return false
        }
    }

    public var isAgentPlaceholder: Bool {
        switch self {
        case .generateReadingOrder, .explainConnection, .findBridgePapers:
            return true
        default:
            return false
        }
    }
}

/// Maximum number of nodes rendered before the UI auto-degrades.
public let graphUINodeCap: Int = 200
