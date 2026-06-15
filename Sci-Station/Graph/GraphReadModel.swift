import Foundation

/// Read-only query interface over the research graph. All queries are
/// forwarded to the underlying `GraphRepository` actor. UI and agent tools
/// consume this struct rather than the repository directly.
public nonisolated struct GraphReadModel: Sendable {
    private let repository: GraphRepository

    public nonisolated init(repository: GraphRepository) {
        self.repository = repository
    }

    public func node(id: String) async -> GraphNode? {
        await repository.node(id: id)
    }

    public func neighbors(of nodeID: String, depth: Int = 1, kinds: Set<GraphEdgeKind> = []) async -> [GraphEdge] {
        var visited: Set<String> = [nodeID]
        var frontier: [String] = [nodeID]
        var collected: [GraphEdge] = []

        for _ in 0..<max(1, depth) {
            var nextFrontier: [String] = []
            for node in frontier {
                let outgoing = await repository.outgoingEdges(of: node)
                let incoming = await repository.incomingEdges(of: node)
                let all = (outgoing + incoming).filter { kinds.isEmpty || kinds.contains($0.kind) }
                for edge in all {
                    let other = (edge.from == node) ? edge.to : edge.from
                    if !visited.contains(other) {
                        visited.insert(other)
                        nextFrontier.append(other)
                    }
                    if !collected.contains(where: { $0.id == edge.id }) {
                        collected.append(edge)
                    }
                }
            }
            frontier = nextFrontier
            if frontier.isEmpty { break }
        }
        return collected
    }

    public func subgraph(centerNodeID: String, depth: Int = 2, kinds: Set<GraphEdgeKind> = []) async -> GraphSubgraph {
        let edges = await neighbors(of: centerNodeID, depth: depth, kinds: kinds)
        let nodeIDs = Set(edges.flatMap { [$0.from, $0.to] }).union([centerNodeID])
        let nodes = await repository.nodesWithIDs(nodeIDs)
        return GraphSubgraph(center: centerNodeID, nodes: Array(nodes.values), edges: edges)
    }

    public func path(from source: String, to target: String, maxDepth: Int = 6) async -> [GraphEdge]? {
        var queue: [(String, [GraphEdge])] = [(source, [])]
        var visited: Set<String> = [source]

        while !queue.isEmpty {
            let (current, trail) = queue.removeFirst()
            if current == target { return trail }
            if trail.count >= maxDepth { continue }
            let outgoing = await repository.outgoingEdges(of: current)
            let incoming = await repository.incomingEdges(of: current)
            for edge in outgoing + incoming {
                let other = (edge.from == current) ? edge.to : edge.from
                if !visited.contains(other) {
                    visited.insert(other)
                    queue.append((other, trail + [edge]))
                }
            }
        }
        return nil
    }

    public func ancestors(of nodeID: String, relation: GraphEdgeKind, maxDepth: Int = 10) async -> [GraphNode] {
        var visited: Set<String> = [nodeID]
        var frontier: [String] = [nodeID]
        var result: [GraphNode] = []

        for _ in 0..<maxDepth {
            var nextFrontier: [String] = []
            for node in frontier {
                let incoming = await repository.incomingEdges(of: node)
                    .filter { $0.kind == relation }
                for edge in incoming {
                    if !visited.contains(edge.from) {
                        visited.insert(edge.from)
                        nextFrontier.append(edge.from)
                        if let ancestor = await repository.node(id: edge.from) {
                            result.append(ancestor)
                        }
                    }
                }
            }
            frontier = nextFrontier
            if frontier.isEmpty { break }
        }
        return result
    }

    public func descendants(of nodeID: String, relation: GraphEdgeKind, maxDepth: Int = 10) async -> [GraphNode] {
        var visited: Set<String> = [nodeID]
        var frontier: [String] = [nodeID]
        var result: [GraphNode] = []

        for _ in 0..<maxDepth {
            var nextFrontier: [String] = []
            for node in frontier {
                let outgoing = await repository.outgoingEdges(of: node)
                    .filter { $0.kind == relation }
                for edge in outgoing {
                    if !visited.contains(edge.to) {
                        visited.insert(edge.to)
                        nextFrontier.append(edge.to)
                        if let descendant = await repository.node(id: edge.to) {
                            result.append(descendant)
                        }
                    }
                }
            }
            frontier = nextFrontier
            if frontier.isEmpty { break }
        }
        return result
    }

    public func snapshot() async -> GraphSnapshot {
        await repository.snapshot()
    }

    public func subscribeChanges() async -> AsyncStream<GraphChange> {
        await repository.subscribeChanges()
    }
}
