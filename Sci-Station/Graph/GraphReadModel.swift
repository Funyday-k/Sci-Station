import Foundation

/// Read-only query interface over the research graph. Traversals take one
/// repository snapshot and build O(1) adjacency indexes locally, avoiding an
/// actor hop per visited node and quadratic edge de-duplication.
public nonisolated struct GraphReadModel: Sendable {
    private let repository: GraphRepository

    public nonisolated init(repository: GraphRepository) {
        self.repository = repository
    }

    public func node(id: String) async -> GraphNode? {
        await repository.node(id: id)
    }

    public func neighbors(of nodeID: String, depth: Int = 1, kinds: Set<GraphEdgeKind> = []) async -> [GraphEdge] {
        (try? await neighborsCancellable(of: nodeID, depth: depth, kinds: kinds)) ?? []
    }

    public func neighborsCancellable(
        of nodeID: String,
        depth: Int = 1,
        kinds: Set<GraphEdgeKind> = []
    ) async throws -> [GraphEdge] {
        try Task.checkCancellation()
        let index = GraphTraversalIndex(snapshot: await repository.snapshot())
        try Task.checkCancellation()

        var visited: Set<String> = [nodeID]
        var frontier: [String] = [nodeID]
        var collectedIDs: Set<String> = []
        var collected: [GraphEdge] = []

        for _ in 0..<max(1, depth) {
            try Task.checkCancellation()
            var nextFrontier: Set<String> = []
            for node in frontier.sorted() {
                for edge in index.undirected[node] ?? [] where kinds.isEmpty || kinds.contains(edge.kind) {
                    if collectedIDs.insert(edge.id).inserted { collected.append(edge) }
                    let other = edge.from == node ? edge.to : edge.from
                    if visited.insert(other).inserted { nextFrontier.insert(other) }
                }
            }
            frontier = nextFrontier.sorted()
            if frontier.isEmpty { break }
        }
        return collected.sorted { $0.id < $1.id }
    }

    public func subgraph(centerNodeID: String, depth: Int = 2, kinds: Set<GraphEdgeKind> = []) async -> GraphSubgraph {
        (try? await subgraphCancellable(centerNodeID: centerNodeID, depth: depth, kinds: kinds))
            ?? GraphSubgraph(center: centerNodeID, nodes: [], edges: [])
    }

    public func subgraphCancellable(
        centerNodeID: String,
        depth: Int = 2,
        kinds: Set<GraphEdgeKind> = []
    ) async throws -> GraphSubgraph {
        let snapshot = await repository.snapshot()
        try Task.checkCancellation()
        let index = GraphTraversalIndex(snapshot: snapshot)
        let edges = try index.neighbors(of: centerNodeID, depth: depth, kinds: kinds)
        let nodeIDs = Set(edges.flatMap { [$0.from, $0.to] }).union([centerNodeID])
        let nodes = nodeIDs.compactMap { snapshot.nodes[$0] }.sorted { $0.id < $1.id }
        return GraphSubgraph(center: centerNodeID, nodes: nodes, edges: edges)
    }

    public func path(from source: String, to target: String, maxDepth: Int = 6) async -> [GraphEdge]? {
        try? await pathCancellable(from: source, to: target, maxDepth: maxDepth)
    }

    public func pathCancellable(from source: String, to target: String, maxDepth: Int = 6) async throws -> [GraphEdge]? {
        try Task.checkCancellation()
        if source == target { return [] }
        guard maxDepth > 0 else { return nil }
        let index = GraphTraversalIndex(snapshot: await repository.snapshot())
        try Task.checkCancellation()

        var queue: [String] = [source]
        var head = 0
        var depthByNode: [String: Int] = [source: 0]
        var predecessor: [String: (node: String, edge: GraphEdge)] = [:]

        while head < queue.count {
            try Task.checkCancellation()
            let current = queue[head]
            head += 1
            let currentDepth = depthByNode[current] ?? 0
            guard currentDepth < maxDepth else { continue }

            for edge in index.undirected[current] ?? [] {
                let other = edge.from == current ? edge.to : edge.from
                guard depthByNode[other] == nil else { continue }
                depthByNode[other] = currentDepth + 1
                predecessor[other] = (current, edge)
                if other == target {
                    return Self.reconstructPath(source: source, target: target, predecessor: predecessor)
                }
                queue.append(other)
            }
        }
        return nil
    }

    public func ancestors(of nodeID: String, relation: GraphEdgeKind, maxDepth: Int = 10) async -> [GraphNode] {
        (try? await ancestorsCancellable(of: nodeID, relation: relation, maxDepth: maxDepth)) ?? []
    }

    public func ancestorsCancellable(
        of nodeID: String,
        relation: GraphEdgeKind,
        maxDepth: Int = 10
    ) async throws -> [GraphNode] {
        let snapshot = await repository.snapshot()
        try Task.checkCancellation()
        let index = GraphTraversalIndex(snapshot: snapshot)
        return try traverseDirected(
            from: nodeID,
            maxDepth: maxDepth,
            edges: { index.incoming[$0] ?? [] },
            nextNode: { $0.from },
            relation: relation,
            nodes: snapshot.nodes
        )
    }

    public func descendants(of nodeID: String, relation: GraphEdgeKind, maxDepth: Int = 10) async -> [GraphNode] {
        (try? await descendantsCancellable(of: nodeID, relation: relation, maxDepth: maxDepth)) ?? []
    }

    public func descendantsCancellable(
        of nodeID: String,
        relation: GraphEdgeKind,
        maxDepth: Int = 10
    ) async throws -> [GraphNode] {
        let snapshot = await repository.snapshot()
        try Task.checkCancellation()
        let index = GraphTraversalIndex(snapshot: snapshot)
        return try traverseDirected(
            from: nodeID,
            maxDepth: maxDepth,
            edges: { index.outgoing[$0] ?? [] },
            nextNode: { $0.to },
            relation: relation,
            nodes: snapshot.nodes
        )
    }

    public func snapshot() async -> GraphSnapshot {
        await repository.snapshot()
    }

    public func subscribeChanges() async -> AsyncStream<GraphChange> {
        await repository.subscribeChanges()
    }

    private nonisolated static func reconstructPath(
        source: String,
        target: String,
        predecessor: [String: (node: String, edge: GraphEdge)]
    ) -> [GraphEdge]? {
        var current = target
        var reversed: [GraphEdge] = []
        while current != source {
            guard let step = predecessor[current] else { return nil }
            reversed.append(step.edge)
            current = step.node
        }
        return Array(reversed.reversed())
    }

    private nonisolated func traverseDirected(
        from start: String,
        maxDepth: Int,
        edges: (String) -> [GraphEdge],
        nextNode: (GraphEdge) -> String,
        relation: GraphEdgeKind,
        nodes: [String: GraphNode]
    ) throws -> [GraphNode] {
        guard maxDepth > 0 else { return [] }
        var visited: Set<String> = [start]
        var frontier: [String] = [start]
        var result: [GraphNode] = []

        for _ in 0..<maxDepth {
            try Task.checkCancellation()
            var nextFrontier: Set<String> = []
            for nodeID in frontier.sorted() {
                for edge in edges(nodeID) where edge.kind == relation {
                    let candidateID = nextNode(edge)
                    guard visited.insert(candidateID).inserted else { continue }
                    nextFrontier.insert(candidateID)
                    if let node = nodes[candidateID] { result.append(node) }
                }
            }
            frontier = nextFrontier.sorted()
            if frontier.isEmpty { break }
        }
        return result
    }
}

private nonisolated struct GraphTraversalIndex {
    let undirected: [String: [GraphEdge]]
    let outgoing: [String: [GraphEdge]]
    let incoming: [String: [GraphEdge]]

    init(snapshot: GraphSnapshot) {
        var undirected: [String: [GraphEdge]] = [:]
        var outgoing: [String: [GraphEdge]] = [:]
        var incoming: [String: [GraphEdge]] = [:]
        for edge in snapshot.edges.values.sorted(by: { $0.id < $1.id }) {
            undirected[edge.from, default: []].append(edge)
            if edge.to != edge.from { undirected[edge.to, default: []].append(edge) }
            outgoing[edge.from, default: []].append(edge)
            incoming[edge.to, default: []].append(edge)
        }
        self.undirected = undirected
        self.outgoing = outgoing
        self.incoming = incoming
    }

    func neighbors(of nodeID: String, depth: Int, kinds: Set<GraphEdgeKind>) throws -> [GraphEdge] {
        var visited: Set<String> = [nodeID]
        var frontier: [String] = [nodeID]
        var collectedIDs: Set<String> = []
        var collected: [GraphEdge] = []
        for _ in 0..<max(1, depth) {
            try Task.checkCancellation()
            var nextFrontier: Set<String> = []
            for node in frontier.sorted() {
                for edge in undirected[node] ?? [] where kinds.isEmpty || kinds.contains(edge.kind) {
                    if collectedIDs.insert(edge.id).inserted { collected.append(edge) }
                    let other = edge.from == node ? edge.to : edge.from
                    if visited.insert(other).inserted { nextFrontier.insert(other) }
                }
            }
            frontier = nextFrontier.sorted()
            if frontier.isEmpty { break }
        }
        return collected.sorted { $0.id < $1.id }
    }
}
