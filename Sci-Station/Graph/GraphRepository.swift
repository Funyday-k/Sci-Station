import Foundation

/// Actor-isolated research graph persistence layer.
///
/// On-disk layout under `.sci-station/graph/`:
///
/// - `nodes.jsonl`       — append-only node upserts, one per line
/// - `edges.jsonl`       — append-only edge upserts, one per line
/// - `tombstones.jsonl`  — append-only delete records, one per line
/// - `snapshots/`        — periodic compacted JSON snapshots (kept latest 3)
/// - `manifest.json`     — schema version, counters, timestamps
///
/// The repository fsyncs every append (via `JSONLWriter`), so crash recovery
/// amounts to replaying the three `.jsonl` files on top of the most recent
/// snapshot. Tombstones suppress any prior upsert with the same id.
public actor GraphRepository {
    public static let directoryRelativePath = ".sci-station/graph"
    public static let nodesFileName = "nodes.jsonl"
    public static let edgesFileName = "edges.jsonl"
    public static let tombstonesFileName = "tombstones.jsonl"
    public static let snapshotsDirectoryName = "snapshots"
    public static let manifestFileName = "manifest.json"

    private let fileManager: FileManager
    private let debug: AppDebugEventLogger?
    private let writerRegistry: JSONLWriterRegistry

    // Per-workspace state. `open(in:)` binds the repository to a given root.
    private var root: ResearchRoot?
    private var nodes: [String: GraphNode] = [:]
    private var edges: [String: GraphEdge] = [:]
    private var outEdges: [String: Set<String>] = [:]
    private var inEdges: [String: Set<String>] = [:]
    private var manifest: GraphManifest = GraphManifest()

    private var changeContinuations: [UUID: AsyncStream<GraphChange>.Continuation] = [:]

    public init(
        fileManager: FileManager = .default,
        debug: AppDebugEventLogger? = nil,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.debug = debug
        self.writerRegistry = writerRegistry
    }

    // MARK: - Lifecycle

    public func open(in root: ResearchRoot) async throws {
        self.root = root
        let directory = root.fileURL(for: Self.directoryRelativePath)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true),
            withIntermediateDirectories: true
        )

        // 1. Load manifest (or initialize for V0 → V1).
        manifest = try loadOrInitializeManifest(in: directory)

        // 2. Apply latest snapshot, if any.
        nodes = [:]
        edges = [:]
        outEdges = [:]
        inEdges = [:]
        if let latestSnapshot = try latestSnapshotURL(in: directory) {
            try applySnapshot(at: latestSnapshot)
        }

        // 3. Replay jsonl files on top. `replay_skip` events are emitted for
        //    malformed lines; we never abort startup just because one line is
        //    damaged.
        let tombstoneIDs = try replayTombstones(in: directory)
        try replayNodes(in: directory, tombstoned: tombstoneIDs)
        try replayEdges(in: directory, tombstoned: tombstoneIDs)

        // 4. Validate: drop any orphan edges (edge whose endpoints no longer
        //    exist as nodes).
        let orphanCount = dropOrphanEdges()

        manifest.countNodes = nodes.count
        manifest.countEdges = edges.count
        try saveManifest(in: directory)

        broadcast(.bulkReloaded)
        await emit(
            "graph.repository.loaded",
            payload: .object([
                "count_nodes": .number(String(nodes.count)),
                "count_edges": .number(String(edges.count)),
                "dropped_orphan_edges": .number(String(orphanCount))
            ])
        )
    }

    public func close() async {
        for (_, continuation) in changeContinuations {
            continuation.finish()
        }
        changeContinuations.removeAll()
        root = nil
        nodes.removeAll()
        edges.removeAll()
        outEdges.removeAll()
        inEdges.removeAll()
    }

    // MARK: - Subscriptions

    public func subscribeChanges() -> AsyncStream<GraphChange> {
        AsyncStream { [weak self] continuation in
            let token = UUID()
            Task { [weak self] in
                await self?.attach(continuation: continuation, token: token)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in
                    await self?.detach(token: token)
                }
            }
        }
    }

    private func attach(continuation: AsyncStream<GraphChange>.Continuation, token: UUID) {
        changeContinuations[token] = continuation
    }

    private func detach(token: UUID) {
        changeContinuations.removeValue(forKey: token)
    }

    private func broadcast(_ change: GraphChange) {
        for (_, continuation) in changeContinuations {
            continuation.yield(change)
        }
    }

    // MARK: - Mutations

    public func upsertNode(_ node: GraphNode) async throws {
        guard let root else { return }
        try await append(node, filename: Self.nodesFileName, in: root)
        nodes[node.id] = node
        manifest.countNodes = nodes.count
        broadcast(.upsertNode(node))
        await emit(
            "graph.repository.write",
            payload: .object(["kind": .string("node"), "id": .string(node.id)])
        )
    }

    public func upsertEdge(_ edge: GraphEdge) async throws {
        guard let root else { return }
        // Guard against edges that reference non-existent endpoints. The
        // indexer should write nodes first, but we defensively log and drop
        // orphan edges here so the repository never gets into an inconsistent
        // state.
        guard nodes[edge.from] != nil, nodes[edge.to] != nil else {
            await emit(
                "graph.repository.write",
                payload: .object([
                    "kind": .string("edge"),
                    "id": .string(edge.id),
                    "dropped_reason": .string("orphan_endpoint")
                ])
            )
            return
        }
        try await append(edge, filename: Self.edgesFileName, in: root)
        edges[edge.id] = edge
        outEdges[edge.from, default: []].insert(edge.id)
        inEdges[edge.to, default: []].insert(edge.id)
        manifest.countEdges = edges.count
        broadcast(.upsertEdge(edge))
        await emit(
            "graph.repository.write",
            payload: .object(["kind": .string("edge"), "id": .string(edge.id)])
        )
    }

    public func deleteNode(id: String, reason: String? = nil) async throws {
        guard let root else { return }
        let tombstone = GraphTombstone(id: id, target: .node, reason: reason)
        try await append(tombstone, filename: Self.tombstonesFileName, in: root)
        // Remove the node and all incident edges (with matching tombstones so
        // replay stays consistent).
        if let incidentOut = outEdges[id] {
            for edgeID in incidentOut {
                try await append(
                    GraphTombstone(id: edgeID, target: .edge, reason: "node_deleted"),
                    filename: Self.tombstonesFileName,
                    in: root
                )
                removeEdgeFromMemory(edgeID)
            }
        }
        if let incidentIn = inEdges[id] {
            for edgeID in incidentIn {
                try await append(
                    GraphTombstone(id: edgeID, target: .edge, reason: "node_deleted"),
                    filename: Self.tombstonesFileName,
                    in: root
                )
                removeEdgeFromMemory(edgeID)
            }
        }
        nodes.removeValue(forKey: id)
        outEdges.removeValue(forKey: id)
        inEdges.removeValue(forKey: id)
        manifest.countNodes = nodes.count
        manifest.countEdges = edges.count
        manifest.countTombstones += 1
        broadcast(.deleteNode(id))
        await emit(
            "graph.repository.write",
            payload: .object(["kind": .string("tombstone"), "id": .string(id)])
        )
    }

    public func deleteEdge(id: String, reason: String? = nil) async throws {
        guard let root else { return }
        let tombstone = GraphTombstone(id: id, target: .edge, reason: reason)
        try await append(tombstone, filename: Self.tombstonesFileName, in: root)
        removeEdgeFromMemory(id)
        manifest.countEdges = edges.count
        manifest.countTombstones += 1
        broadcast(.deleteEdge(id))
        await emit(
            "graph.repository.write",
            payload: .object(["kind": .string("tombstone"), "id": .string(id)])
        )
    }

    private func removeEdgeFromMemory(_ id: String) {
        guard let edge = edges.removeValue(forKey: id) else { return }
        outEdges[edge.from]?.remove(id)
        if outEdges[edge.from]?.isEmpty == true {
            outEdges.removeValue(forKey: edge.from)
        }
        inEdges[edge.to]?.remove(id)
        if inEdges[edge.to]?.isEmpty == true {
            inEdges.removeValue(forKey: edge.to)
        }
    }

    // MARK: - Read model accessors

    public func snapshot() -> GraphSnapshot {
        GraphSnapshot(schemaVersion: manifest.schemaVersion, nodes: nodes, edges: edges)
    }

    public func node(id: String) -> GraphNode? { nodes[id] }
    public func edge(id: String) -> GraphEdge? { edges[id] }

    public func outgoingEdges(of nodeID: String) -> [GraphEdge] {
        guard let ids = outEdges[nodeID] else { return [] }
        return ids.compactMap { edges[$0] }
    }

    public func incomingEdges(of nodeID: String) -> [GraphEdge] {
        guard let ids = inEdges[nodeID] else { return [] }
        return ids.compactMap { edges[$0] }
    }

    public func nodesWithIDs(_ ids: Set<String>) -> [String: GraphNode] {
        var result: [String: GraphNode] = [:]
        result.reserveCapacity(ids.count)
        for id in ids {
            if let node = nodes[id] {
                result[id] = node
            }
        }
        return result
    }

    // MARK: - Compact

    public func compactIfNeeded(nowTombstoneCount: Int? = nil) async throws -> GraphCompactResult? {
        let tombstoneLines = try countTombstoneLines()
        let total = nodes.count + edges.count + tombstoneLines
        let ageSeconds: TimeInterval
        if let lastCompact = manifest.lastCompactAt {
            ageSeconds = Date().timeIntervalSince(lastCompact)
        } else {
            ageSeconds = .greatestFiniteMagnitude
        }
        if total > 50_000 || ageSeconds > 24 * 3600 {
            return try await forceCompact()
        }
        _ = nowTombstoneCount
        return nil
    }

    public func forceCompact() async throws -> GraphCompactResult {
        guard let root else { throw GraphError.notOpen }
        let directory = root.fileURL(for: Self.directoryRelativePath)
        let snapshotsDirectory = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)

        let start = Date()
        let beforeLines = try countLines(in: directory)

        let snapshotFormatter = ISO8601DateFormatter()
        snapshotFormatter.formatOptions = [.withInternetDateTime]
        let snapshotName = "snapshot-\(snapshotFormatter.string(from: start).replacingOccurrences(of: ":", with: "-")).json"
        let snapshotURL = snapshotsDirectory.appendingPathComponent(snapshotName, isDirectory: false)

        let encoder = Self.encoder()
        let snapshot = GraphOnDiskSnapshot(
            schemaVersion: manifest.schemaVersion,
            generatedAt: Date(),
            nodes: Array(nodes.values),
            edges: Array(edges.values)
        )
        let snapshotData = try encoder.encode(snapshot)
        do {
            try snapshotData.write(to: snapshotURL, options: .atomic)
        } catch {
            await emit(
                "graph.repository.compact.error",
                payload: .object([
                    "reason": .string(error.localizedDescription),
                    "fallback_to_jsonl": .bool(true)
                ])
            )
            throw error
        }

        // Truncate the three jsonl files. We do this by atomic-replacing each
        // with an empty file, which is safe even if another writer is currently
        // holding the old handle — subsequent `JSONLWriter` appends will reopen
        // the replaced file.
        try truncate(filename: Self.nodesFileName, in: directory)
        try truncate(filename: Self.edgesFileName, in: directory)
        try truncate(filename: Self.tombstonesFileName, in: directory)
        manifest.countTombstones = 0
        manifest.lastCompactAt = Date()
        try saveManifest(in: directory)
        try pruneOldSnapshots(in: snapshotsDirectory, keepLatest: 3)

        // Force the writers to reload their dedup caches on next append, since
        // the underlying files are now empty.
        let nodesURL = directory.appendingPathComponent(Self.nodesFileName, isDirectory: false)
        await writerRegistry.writer(for: nodesURL).invalidateCache()
        let edgesURL = directory.appendingPathComponent(Self.edgesFileName, isDirectory: false)
        await writerRegistry.writer(for: edgesURL).invalidateCache()
        let tombstonesURL = directory.appendingPathComponent(Self.tombstonesFileName, isDirectory: false)
        await writerRegistry.writer(for: tombstonesURL).invalidateCache()

        let afterLines = try countLines(in: directory)
        let duration = Date().timeIntervalSince(start) * 1000
        await emit(
            "graph.repository.compact",
            payload: .object([
                "before_lines": .number(String(beforeLines)),
                "after_lines": .number(String(afterLines)),
                "duration_ms": .number(String(format: "%.2f", duration)),
                "snapshot_path": .string(".sci-station/graph/\(Self.snapshotsDirectoryName)/\(snapshotName)")
            ])
        )

        return GraphCompactResult(
            snapshotURL: snapshotURL,
            beforeLines: beforeLines,
            afterLines: afterLines,
            durationMilliseconds: duration
        )
    }

    public func manifestSnapshot() -> GraphManifest { manifest }

    // MARK: - Private helpers

    private func append<T: Encodable>(
        _ value: T,
        filename: String,
        in root: ResearchRoot
    ) async throws {
        let url = root
            .fileURL(for: Self.directoryRelativePath)
            .appendingPathComponent(filename, isDirectory: false)
        let writer = await writerRegistry.writer(for: url)
        try await writer.append(value, encoder: Self.encoder())
    }

    private func loadOrInitializeManifest(in directory: URL) throws -> GraphManifest {
        let url = directory.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            var manifest = try Self.decoder().decode(GraphManifest.self, from: data)
            if manifest.schemaVersion != graphSchemaVersion {
                // Future migrations will be dispatched here. For V0→V1 there's
                // nothing to do: a missing manifest path is treated as V0.
                manifest.schemaVersion = graphSchemaVersion
            }
            return manifest
        }
        var manifest = GraphManifest()
        try saveManifest(in: directory, override: manifest)
        manifest.generatedAt = Date()
        return manifest
    }

    private func saveManifest(in directory: URL, override: GraphManifest? = nil) throws {
        let url = directory.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let manifestToSave = override ?? manifest
        let data = try Self.encoder().encode(manifestToSave)
        try data.write(to: url, options: .atomic)
    }

    private func latestSnapshotURL(in directory: URL) throws -> URL? {
        let snapshotsDirectory = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: snapshotsDirectory.path) else { return nil }
        let files = try fileManager.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.last
    }

    private func applySnapshot(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let snapshot = try Self.decoder().decode(GraphOnDiskSnapshot.self, from: data)
        for node in snapshot.nodes { nodes[node.id] = node }
        for edge in snapshot.edges {
            edges[edge.id] = edge
            outEdges[edge.from, default: []].insert(edge.id)
            inEdges[edge.to, default: []].insert(edge.id)
        }
    }

    private func replayTombstones(in directory: URL) throws -> Set<String> {
        let url = directory.appendingPathComponent(Self.tombstonesFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        var tombstoned: Set<String> = []
        try iterateLines(at: url) { line, lineNumber in
            let decoder = Self.decoder()
            guard let data = line.data(using: .utf8),
                  let tombstone = try? decoder.decode(GraphTombstone.self, from: data) else {
                Task { [weak self] in
                    await self?.emit(
                        "graph.repository.replay_skip",
                        payload: .object([
                            "line_number": .number(String(lineNumber)),
                            "reason": .string("invalid_tombstone")
                        ])
                    )
                }
                return
            }
            tombstoned.insert(tombstone.id)
            // Apply tombstone to any snapshot-restored nodes/edges.
            switch tombstone.target {
            case .node:
                if nodes[tombstone.id] != nil { nodes.removeValue(forKey: tombstone.id) }
                outEdges.removeValue(forKey: tombstone.id)
                inEdges.removeValue(forKey: tombstone.id)
            case .edge:
                removeEdgeFromMemory(tombstone.id)
            }
        }
        manifest.countTombstones = tombstoned.count
        return tombstoned
    }

    private func replayNodes(in directory: URL, tombstoned: Set<String>) throws {
        let url = directory.appendingPathComponent(Self.nodesFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try iterateLines(at: url) { line, lineNumber in
            let decoder = Self.decoder()
            guard let data = line.data(using: .utf8),
                  let node = try? decoder.decode(GraphNode.self, from: data) else {
                Task { [weak self] in
                    await self?.emit(
                        "graph.repository.replay_skip",
                        payload: .object([
                            "line_number": .number(String(lineNumber)),
                            "reason": .string("invalid_node")
                        ])
                    )
                }
                return
            }
            guard !tombstoned.contains(node.id) else { return }
            nodes[node.id] = node
        }
    }

    private func replayEdges(in directory: URL, tombstoned: Set<String>) throws {
        let url = directory.appendingPathComponent(Self.edgesFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try iterateLines(at: url) { line, lineNumber in
            let decoder = Self.decoder()
            guard let data = line.data(using: .utf8),
                  let edge = try? decoder.decode(GraphEdge.self, from: data) else {
                Task { [weak self] in
                    await self?.emit(
                        "graph.repository.replay_skip",
                        payload: .object([
                            "line_number": .number(String(lineNumber)),
                            "reason": .string("invalid_edge")
                        ])
                    )
                }
                return
            }
            guard !tombstoned.contains(edge.id) else { return }
            edges[edge.id] = edge
            outEdges[edge.from, default: []].insert(edge.id)
            inEdges[edge.to, default: []].insert(edge.id)
        }
    }

    private func iterateLines(at url: URL, body: (String, Int) -> Void) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var lineNumber = 0
        for raw in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            lineNumber += 1
            let line = String(raw)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            body(line, lineNumber)
        }
    }

    private func truncate(filename: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try Data().write(to: url, options: .atomic)
    }

    private func countLines(in directory: URL) throws -> Int {
        var total = 0
        for filename in [Self.nodesFileName, Self.edgesFileName, Self.tombstonesFileName] {
            let url = directory.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            total += contents.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).filter { !$0.isEmpty }.count
        }
        return total
    }

    private func countTombstoneLines() throws -> Int {
        guard let root else { return 0 }
        let url = root.fileURL(for: Self.directoryRelativePath)
            .appendingPathComponent(Self.tombstonesFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return contents.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).filter { !$0.isEmpty }.count
    }

    private func pruneOldSnapshots(in directory: URL, keepLatest: Int) throws {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let toDelete = files.count > keepLatest ? files.prefix(files.count - keepLatest) : []
        for url in toDelete {
            try? fileManager.removeItem(at: url)
        }
    }

    @discardableResult
    private func dropOrphanEdges() -> Int {
        var dropped = 0
        var keepEdges: [String: GraphEdge] = [:]
        outEdges.removeAll()
        inEdges.removeAll()
        for (edgeID, edge) in edges {
            let fromExists = nodes.keys.contains(edge.from)
            let toExists = nodes.keys.contains(edge.to)
            if !fromExists || !toExists {
                dropped += 1
                continue
            }
            keepEdges[edgeID] = edge
            outEdges[edge.from, default: []].insert(edgeID)
            inEdges[edge.to, default: []].insert(edgeID)
        }
        edges = keepEdges
        return dropped
    }

    private func emit(_ event: String, payload: JSONValue) async {
        guard let debug, let root else { return }
        try? await debug.append(
            AppDebugEvent(event: event, payload: payload),
            in: root
        )
    }

    public nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// On-disk payload for snapshots written by `GraphRepository.forceCompact()`.
private nonisolated struct GraphOnDiskSnapshot: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var nodes: [GraphNode]
    var edges: [GraphEdge]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case nodes
        case edges
    }
}

public enum GraphError: Error, Sendable {
    case notOpen
}
