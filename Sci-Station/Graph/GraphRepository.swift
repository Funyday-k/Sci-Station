import Foundation

/// SQLite-backed, actor-isolated research graph persistence.
///
/// `graph.sqlite` is the only live write store. Legacy JSONL/snapshots are
/// imported once, backed up, and then left untouched for compatibility and
/// forensic recovery.
public actor GraphRepository {
    /// SQLite storage schema. This is intentionally independent from the
    /// logical graph payload schema exposed by `graphSchemaVersion`.
    public static let storageSchemaVersion = 3
    public static let directoryRelativePath = ".sci-station/graph"
    public static let databaseFileName = "graph.sqlite"
    public static let nodesFileName = "nodes.jsonl"
    public static let edgesFileName = "edges.jsonl"
    public static let tombstonesFileName = "tombstones.jsonl"
    public static let snapshotsDirectoryName = "snapshots"
    public static let backupsDirectoryName = "backups"
    public static let manifestFileName = "manifest.json"

    private let fileManager: FileManager
    private let debug: AppDebugEventLogger?

    private var root: ResearchRoot?
    private var database: GraphSQLiteDatabase?
    private var nodes: [String: GraphNode] = [:]
    private var edges: [String: GraphEdge] = [:]
    private var occurrences: [String: GraphCitationOccurrence] = [:]
    private var anchors: [String: GraphSourceAnchor] = [:]
    private var outEdges: [String: Set<String>] = [:]
    private var inEdges: [String: Set<String>] = [:]
    private var manifest = GraphManifest()
    private var hasUncompactedWrites = false
    private var changeContinuations: [UUID: AsyncStream<GraphChange>.Continuation] = [:]

    public init(
        fileManager: FileManager = .default,
        debug: AppDebugEventLogger? = nil,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.debug = debug
        _ = writerRegistry // Kept for source compatibility with older callers.
    }

    // MARK: - Lifecycle

    public func open(in root: ResearchRoot) async throws {
        closeStorage(finishSubscriptions: false)
        self.root = root

        let directory = root.fileURL(for: Self.directoryRelativePath)
        let backupsDirectory = directory.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true)
        let snapshotsDirectory = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent(Self.databaseFileName, isDirectory: false)
        do {
            database = try openRecoveringDatabase(at: databaseURL, graphDirectory: directory)
            guard let database else { throw GraphError.notOpen }
            try importLegacyStoreIfNeeded(into: database, directory: directory)
            try verifyForeignKeys(database)
            try loadCache(from: database)
            try updateManifest(in: directory)
            try ensureLegacyCompatibilityFiles(in: directory)
        } catch {
            closeStorage(finishSubscriptions: false)
            throw map(error)
        }

        broadcast(.bulkReloaded)
        await emit(
            "graph.repository.loaded",
            payload: .object([
                "storage": .string("sqlite"),
                "schema_version": .number(String(graphSchemaVersion)),
                "count_nodes": .number(String(nodes.count)),
                "count_edges": .number(String(edges.count)),
                "count_occurrences": .number(String(occurrences.count))
            ])
        )
    }

    public func close() async {
        closeStorage(finishSubscriptions: true)
    }

    private func closeStorage(finishSubscriptions: Bool) {
        if finishSubscriptions {
            for continuation in changeContinuations.values { continuation.finish() }
            changeContinuations.removeAll()
        }
        database?.close()
        database = nil
        root = nil
        nodes.removeAll()
        edges.removeAll()
        occurrences.removeAll()
        anchors.removeAll()
        outEdges.removeAll()
        inEdges.removeAll()
        hasUncompactedWrites = false
    }

    // MARK: - Subscriptions

    public func subscribeChanges() -> AsyncStream<GraphChange> {
        AsyncStream { [weak self] continuation in
            let token = UUID()
            Task { [weak self] in await self?.attach(continuation: continuation, token: token) }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in await self?.detach(token: token) }
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
        for continuation in changeContinuations.values { continuation.yield(change) }
    }

    // MARK: - Mutations

    public func upsertNode(_ node: GraphNode) async throws {
        let database = try requireDatabase()
        do {
            try database.transaction { try writeNode(node, to: database) }
            nodes[node.id] = node
            hasUncompactedWrites = true
            refreshManifestCounts()
            broadcast(.upsertNode(node))
            await emit("graph.repository.write", payload: .object(["kind": .string("node"), "id": .string(node.id)]))
        } catch {
            throw map(error)
        }
    }

    public func upsertEdge(_ edge: GraphEdge) async throws {
        let database = try requireDatabase()
        let missing = [edge.from, edge.to].filter { nodes[$0] == nil }
        guard missing.isEmpty else {
            throw GraphError.orphanEdge(edgeID: edge.id, missingEndpoints: missing.sorted())
        }
        do {
            try database.transaction { try writeEdge(edge, to: database) }
            if let previous = edges[edge.id] { removeEdgeFromIndexes(previous) }
            edges[edge.id] = edge
            addEdgeToIndexes(edge)
            hasUncompactedWrites = true
            refreshManifestCounts()
            broadcast(.upsertEdge(edge))
            await emit("graph.repository.write", payload: .object(["kind": .string("edge"), "id": .string(edge.id)]))
        } catch {
            throw map(error)
        }
    }

    public func upsertCitationOccurrence(
        _ occurrence: GraphCitationOccurrence,
        anchor: GraphSourceAnchor? = nil
    ) async throws {
        let database = try requireDatabase()
        guard edges[occurrence.edgeID] != nil else {
            throw GraphError.missingCitationEdge(occurrenceID: occurrence.id, edgeID: occurrence.edgeID)
        }
        do {
            try database.transaction {
                if let anchor { try writeAnchor(anchor, to: database) }
                try writeOccurrence(occurrence, to: database)
            }
            if let anchor { anchors[anchor.id] = anchor }
            occurrences[occurrence.id] = occurrence
            hasUncompactedWrites = true
        } catch {
            throw map(error)
        }
    }

    public func deleteNode(id: String, reason: String? = nil) async throws {
        let database = try requireDatabase()
        let incidentIDs = Set(outEdges[id] ?? []).union(inEdges[id] ?? [])
        do {
            let statement = try database.prepare("DELETE FROM nodes WHERE id = ?")
            try statement.bind(id, at: 1)
            try statement.stepDone()
            nodes.removeValue(forKey: id)
            for edgeID in incidentIDs { removeEdgeFromMemory(edgeID) }
            occurrences = occurrences.filter { $0.value.sourceNodeID != id && $0.value.targetNodeID != id }
            anchors = anchors.filter { $0.value.sourceNodeID != id }
            hasUncompactedWrites = true
            refreshManifestCounts()
            broadcast(.deleteNode(id))
            await emit(
                "graph.repository.write",
                payload: .object(["kind": .string("delete_node"), "id": .string(id), "reason": reason.map(JSONValue.string) ?? .null])
            )
        } catch {
            throw map(error)
        }
    }

    public func deleteEdge(id: String, reason: String? = nil) async throws {
        let database = try requireDatabase()
        do {
            let statement = try database.prepare("DELETE FROM edges WHERE id = ?")
            try statement.bind(id, at: 1)
            try statement.stepDone()
            removeEdgeFromMemory(id)
            occurrences = occurrences.filter { $0.value.edgeID != id }
            let referencedAnchorIDs = Set(occurrences.values.compactMap(\.anchorID))
            anchors = anchors.filter { referencedAnchorIDs.contains($0.key) }
            hasUncompactedWrites = true
            refreshManifestCounts()
            broadcast(.deleteEdge(id))
            await emit(
                "graph.repository.write",
                payload: .object(["kind": .string("delete_edge"), "id": .string(id), "reason": reason.map(JSONValue.string) ?? .null])
            )
        } catch {
            throw map(error)
        }
    }

    /// Atomically reconciles one complete expected graph. The transaction order
    /// is deliberate: all nodes, then all edges/evidence, then stale evidence,
    /// edges, and finally nodes. Foreign-key checks stay enabled throughout.
    public func reconcile(_ expected: GraphExpectedState) async throws -> GraphReconciliationResult {
        try Task.checkCancellation()
        let database = try requireDatabase()

        for edge in expected.edges.values {
            let missing = [edge.from, edge.to].filter { nodeID in
                if expected.nodes[nodeID] != nil { return false }
                guard let existing = nodes[nodeID] else { return true }
                return expected.managedNodeKinds.contains(existing.kind)
            }
            guard missing.isEmpty else {
                throw GraphError.orphanEdge(edgeID: edge.id, missingEndpoints: missing.sorted())
            }
        }
        for occurrence in expected.citationOccurrences.values {
            guard expected.edges[occurrence.edgeID] != nil else {
                throw GraphError.missingCitationEdge(occurrenceID: occurrence.id, edgeID: occurrence.edgeID)
            }
            if let anchorID = occurrence.anchorID, expected.sourceAnchors[anchorID] == nil {
                throw GraphError.missingSourceAnchor(occurrenceID: occurrence.id, anchorID: anchorID)
            }
        }

        let existingManagedNodeIDs = Set(nodes.values.filter { expected.managedNodeKinds.contains($0.kind) }.map(\.id))
        let existingManagedEdgeIDs = Set(edges.values.filter { expected.managedEdgeKinds.contains($0.kind) }.map(\.id))
        let staleNodeIDs = existingManagedNodeIDs.subtracting(expected.nodes.keys)
        let staleEdgeIDs = existingManagedEdgeIDs.subtracting(expected.edges.keys)
        let changedNodeCount = expected.nodes.values.reduce(into: 0) { count, node in
            if nodes[node.id]?.canonicalContentHash != node.canonicalContentHash { count += 1 }
        }
        let changedEdgeCount = expected.edges.values.reduce(into: 0) { count, edge in
            if edges[edge.id]?.canonicalContentHash != edge.canonicalContentHash { count += 1 }
        }
        let result = GraphReconciliationResult(
            insertedOrUpdatedNodes: changedNodeCount,
            insertedOrUpdatedEdges: changedEdgeCount,
            deletedNodes: staleNodeIDs.count,
            deletedEdges: staleEdgeIDs.count,
            citationOccurrences: expected.citationOccurrences.count,
            sourceAnchors: expected.sourceAnchors.count
        )
        let indexRunID = UUID().uuidString.lowercased()
        try recordIndexRunStarted(
            id: indexRunID,
            expectedNodes: expected.nodes.count,
            expectedEdges: expected.edges.count,
            database: database
        )

        do {
            try database.transaction {
                for node in expected.nodes.values.sorted(by: { $0.id < $1.id }) {
                    try Task.checkCancellation()
                    try writeNode(node, to: database)
                }
                for edge in expected.edges.values.sorted(by: { $0.id < $1.id }) {
                    try Task.checkCancellation()
                    try writeEdge(edge, to: database)
                }
                for anchor in expected.sourceAnchors.values.sorted(by: { $0.id < $1.id }) {
                    try Task.checkCancellation()
                    try writeAnchor(anchor, to: database)
                }
                for occurrence in expected.citationOccurrences.values.sorted(by: { $0.id < $1.id }) {
                    try Task.checkCancellation()
                    try writeOccurrence(occurrence, to: database)
                }

                try deleteRows(
                    from: "citation_occurrences",
                    existingIDs: Set(occurrences.keys),
                    keeping: Set(expected.citationOccurrences.keys),
                    database: database
                )
                try deleteRows(
                    from: "source_anchors",
                    existingIDs: Set(anchors.keys),
                    keeping: Set(expected.sourceAnchors.keys),
                    database: database
                )
                try deleteRows(from: "edges", ids: staleEdgeIDs, database: database)
                try deleteRows(from: "nodes", ids: staleNodeIDs, database: database)
                try setMetadata("last_indexed_at", value: Self.iso8601.string(from: Date()), database: database)
                try finishIndexRun(id: indexRunID, status: "completed", result: result, error: nil, database: database)
            }
            try loadCache(from: database)
            hasUncompactedWrites = true
            refreshManifestCounts()
            manifest.lastIndexedAt = Date()
            broadcast(.bulkReloaded)

            await emit(
                "graph.repository.reconciled",
                payload: .object([
                    "upserted_nodes": .number(String(result.insertedOrUpdatedNodes)),
                    "upserted_edges": .number(String(result.insertedOrUpdatedEdges)),
                    "deleted_nodes": .number(String(result.deletedNodes)),
                    "deleted_edges": .number(String(result.deletedEdges)),
                    "occurrences": .number(String(result.citationOccurrences))
                ])
            )
            return result
        } catch {
            let status = error is CancellationError ? "cancelled" : "failed"
            try? finishIndexRun(
                id: indexRunID,
                status: status,
                result: nil,
                error: String(describing: error),
                database: database
            )
            throw map(error)
        }
    }

    // MARK: - Read model accessors

    public func snapshot() -> GraphSnapshot {
        GraphSnapshot(
            schemaVersion: graphSchemaVersion,
            nodes: nodes,
            edges: edges,
            citationOccurrences: occurrences,
            sourceAnchors: anchors
        )
    }

    public func node(id: String) -> GraphNode? { nodes[id] }
    public func edge(id: String) -> GraphEdge? { edges[id] }

    public func outgoingEdges(of nodeID: String) -> [GraphEdge] {
        (outEdges[nodeID] ?? []).compactMap { edges[$0] }.sorted { $0.id < $1.id }
    }

    public func incomingEdges(of nodeID: String) -> [GraphEdge] {
        (inEdges[nodeID] ?? []).compactMap { edges[$0] }.sorted { $0.id < $1.id }
    }

    public func nodesWithIDs(_ ids: Set<String>) -> [String: GraphNode] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in nodes[id].map { (id, $0) } })
    }

    public func citationOccurrences(forEdgeID edgeID: String) -> [GraphCitationOccurrence] {
        occurrences.values.filter { $0.edgeID == edgeID }.sorted {
            if $0.ordinal != $1.ordinal { return $0.ordinal < $1.ordinal }
            return $0.id < $1.id
        }
    }

    public func sourceAnchor(id: String) -> GraphSourceAnchor? { anchors[id] }

    // MARK: - Maintenance and backup

    public func compactIfNeeded(nowTombstoneCount: Int? = nil) async throws -> GraphCompactResult? {
        _ = nowTombstoneCount
        guard hasUncompactedWrites, let root else { return nil }
        let databaseURL = root.fileURL(for: Self.directoryRelativePath)
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
        let bytes = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let age = manifest.lastCompactAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        guard bytes > 50 * 1_024 * 1_024 || age > 7 * 24 * 3_600 else { return nil }
        return try await forceCompact()
    }

    public func forceCompact() async throws -> GraphCompactResult {
        let database = try requireDatabase()
        guard let root else { throw GraphError.notOpen }
        let directory = root.fileURL(for: Self.directoryRelativePath)
        let snapshotsDirectory = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent(Self.databaseFileName, isDirectory: false)
        let beforeBytes = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let start = Date()

        do {
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            try database.execute("VACUUM")
            let name = "graph-backup-\(Self.fileTimestamp(start)).sqlite"
            let backupURL = snapshotsDirectory.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: backupURL.path) { try fileManager.removeItem(at: backupURL) }
            try database.backup(to: backupURL)
            try pruneBackups(in: snapshotsDirectory, prefix: "graph-backup-", keepLatest: 3)
            manifest.lastCompactAt = Date()
            hasUncompactedWrites = false
            try updateManifest(in: directory)
            let afterBytes = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return GraphCompactResult(
                snapshotURL: backupURL,
                beforeLines: beforeBytes,
                afterLines: afterBytes,
                durationMilliseconds: Date().timeIntervalSince(start) * 1_000
            )
        } catch {
            throw map(error)
        }
    }

    public func manifestSnapshot() -> GraphManifest { manifest }

    // MARK: - Database opening, recovery, and migration

    private func openRecoveringDatabase(at url: URL, graphDirectory: URL) throws -> GraphSQLiteDatabase {
        do {
            let database = try GraphSQLiteDatabase(url: url)
            try configure(database)
            try verifyIntegrity(database)
            try migrate(database, graphDirectory: graphDirectory)
            try verifyForeignKeys(database)
            return database
        } catch {
            let recoverable = (error as? GraphSQLiteFailure)?.isCorruption == true
                || (error as? GraphError).map { if case .databaseCorrupt = $0 { return true }; return false } == true
            guard recoverable else { throw error }
            return try recoverDatabase(at: url, graphDirectory: graphDirectory, underlying: error)
        }
    }

    private func configure(_ database: GraphSQLiteDatabase) throws {
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("PRAGMA synchronous = FULL")
        try database.execute("PRAGMA temp_store = MEMORY")
    }

    private func verifyIntegrity(_ database: GraphSQLiteDatabase) throws {
        let result = try database.scalarString("PRAGMA quick_check") ?? "missing quick_check result"
        guard result.lowercased() == "ok" else { throw GraphError.databaseCorrupt(details: result) }
    }

    private func verifyForeignKeys(_ database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare("PRAGMA foreign_key_check")
        guard try statement.stepRow() else { return }
        let table = statement.string(at: 0) ?? "unknown"
        let rowID = statement.string(at: 1) ?? String(statement.int(at: 1))
        let parent = statement.string(at: 2) ?? "unknown"
        throw GraphError.foreignKeyViolation(details: "table=\(table), rowid=\(rowID), parent=\(parent)")
    }

    private func migrate(_ database: GraphSQLiteDatabase, graphDirectory: URL) throws {
        var version = try database.scalarInt("PRAGMA user_version")
        guard version <= Self.storageSchemaVersion else {
            throw GraphError.unsupportedSchema(found: version, supported: Self.storageSchemaVersion)
        }
        if version > 0, version < Self.storageSchemaVersion {
            let backups = graphDirectory.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true)
            let url = backups.appendingPathComponent(
                "pre-migration-v\(version)-\(Self.fileTimestamp(Date())).sqlite",
                isDirectory: false
            )
            try database.execute("PRAGMA wal_checkpoint(FULL)")
            try database.backup(to: url)
        }
        while version < Self.storageSchemaVersion {
            switch version + 1 {
            case 1:
                try database.transaction {
                    try database.execute(Self.schemaV1)
                    try database.execute("PRAGMA user_version = 1")
                }
            case 2:
                try database.transaction {
                    try database.execute(Self.schemaV2)
                    try database.execute("PRAGMA user_version = 2")
                }
            case 3:
                try database.transaction {
                    try database.execute(Self.schemaV3)
                    let appliedAt = Self.iso8601.string(from: Date())
                    for (migrationVersion, name) in [
                        (1, "initial_nodes_edges"),
                        (2, "citation_occurrences_and_anchors"),
                        (3, "migration_audit_index_runs_embeddings")
                    ] {
                        let statement = try database.prepare(
                            "INSERT OR IGNORE INTO schema_migrations(version, name, applied_at) VALUES(?, ?, ?)"
                        )
                        try statement.bind(migrationVersion, at: 1)
                        try statement.bind(name, at: 2)
                        try statement.bind(appliedAt, at: 3)
                        try statement.stepDone()
                    }
                    try database.execute("PRAGMA user_version = 3")
                }
            default:
                throw GraphError.unsupportedSchema(found: version, supported: Self.storageSchemaVersion)
            }
            version += 1
        }
        // A database can be copied while a migration is being finalized. Make
        // the V3 schema idempotent on every open so a missing auxiliary table
        // is repaired before cache loading rather than surfacing as a mystery
        // query failure.
        if version == Self.storageSchemaVersion {
            try database.transaction {
                try database.execute(Self.schemaV1)
                try database.execute(Self.schemaV2)
                try database.execute(Self.schemaV3)
                let appliedAt = Self.iso8601.string(from: Date())
                for (migrationVersion, name) in [
                    (1, "initial_nodes_edges"),
                    (2, "citation_occurrences_and_anchors"),
                    (3, "migration_audit_index_runs_embeddings")
                ] {
                    let statement = try database.prepare(
                        "INSERT OR IGNORE INTO schema_migrations(version, name, applied_at) VALUES(?, ?, ?)"
                    )
                    try statement.bind(migrationVersion, at: 1)
                    try statement.bind(name, at: 2)
                    try statement.bind(appliedAt, at: 3)
                    try statement.stepDone()
                }
            }
        }
    }

    private func recoverDatabase(at url: URL, graphDirectory: URL, underlying: Error) throws -> GraphSQLiteDatabase {
        database?.close()
        let backupsDirectory = graphDirectory.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let corruptURL = backupsDirectory.appendingPathComponent(
                "corrupt-\(Self.fileTimestamp(Date())).sqlite",
                isDirectory: false
            )
            try? fileManager.copyItem(at: url, to: corruptURL)
        }
        try removeDatabaseFamily(at: url)

        var backupFailures: [String] = []
        for backup in try validBackups(in: graphDirectory) {
            try removeDatabaseFamily(at: url)
            try fileManager.copyItem(at: backup, to: url)
            do {
                let restored = try GraphSQLiteDatabase(url: url)
                try configure(restored)
                try verifyIntegrity(restored)
                try migrate(restored, graphDirectory: graphDirectory)
                try verifyForeignKeys(restored)
                return restored
            } catch {
                backupFailures.append("\(backup.lastPathComponent): \(error)")
                try removeDatabaseFamily(at: url)
            }
        }

        do {
            let fresh = try GraphSQLiteDatabase(url: url)
            try configure(fresh)
            try migrate(fresh, graphDirectory: graphDirectory)
            try verifyForeignKeys(fresh)
            return fresh
        } catch {
            let attemptedBackups = backupFailures.isEmpty
                ? "no usable backups"
                : backupFailures.joined(separator: "; ")
            throw GraphError.recoveryFailed(
                details: "\(underlying); backups: \(attemptedBackups); recreation failed: \(error)"
            )
        }
    }

    private func validBackups(in graphDirectory: URL) throws -> [URL] {
        let directories = [
            graphDirectory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true),
            graphDirectory.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true)
        ]
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        let candidates = try directories.flatMap { directory -> [URL] in
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys)
            )
                .filter { $0.pathExtension == "sqlite" && !$0.lastPathComponent.hasPrefix("corrupt-") }
        }.sorted { first, second in
            let firstValues = try? first.resourceValues(forKeys: resourceKeys)
            let secondValues = try? second.resourceValues(forKeys: resourceKeys)
            let firstDate = firstValues?.contentModificationDate ?? firstValues?.creationDate ?? .distantPast
            let secondDate = secondValues?.contentModificationDate ?? secondValues?.creationDate ?? .distantPast
            if firstDate != secondDate { return firstDate > secondDate }
            return first.lastPathComponent > second.lastPathComponent
        }
        var valid: [URL] = []
        for candidate in candidates {
            if let check = try? GraphSQLiteDatabase(url: candidate, readOnly: true),
               (try? check.scalarString("PRAGMA quick_check"))?.lowercased() == "ok",
               (try? check.scalarInt("PRAGMA user_version")).map({ $0 <= Self.storageSchemaVersion }) == true {
                valid.append(candidate)
            }
        }
        return valid
    }

    private func removeDatabaseFamily(at url: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let candidate = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: candidate.path) { try fileManager.removeItem(at: candidate) }
        }
    }

    // MARK: - Legacy importer

    private func importLegacyStoreIfNeeded(into database: GraphSQLiteDatabase, directory: URL) throws {
        guard try metadata("legacy_import_complete", database: database) == nil else { return }
        guard try database.scalarInt("SELECT COUNT(*) FROM nodes") == 0 else {
            try setMetadata("legacy_import_complete", value: "existing_sqlite", database: database)
            return
        }

        let legacy = try loadLegacyState(in: directory)
        if !legacy.nodes.isEmpty || !legacy.edges.isEmpty {
            try database.transaction {
                for node in legacy.nodes.values.sorted(by: { $0.id < $1.id }) { try writeNode(node, to: database) }
                for edge in legacy.edges.values.sorted(by: { $0.id < $1.id }) { try writeEdge(edge, to: database) }
                try setMetadata("legacy_import_complete", value: Self.iso8601.string(from: Date()), database: database)
            }
            try backupLegacyFiles(in: directory)
        } else {
            try setMetadata("legacy_import_complete", value: "no_legacy_data", database: database)
        }
    }

    private func loadLegacyState(in directory: URL) throws -> LegacyGraphState {
        var state = LegacyGraphState()
        var snapshotDate = Date.distantPast
        if let snapshot = try latestValidLegacySnapshot(in: directory) {
            snapshotDate = snapshot.generatedAt
            for node in snapshot.nodes { state.nodes[node.id] = node }
            for edge in snapshot.edges { state.edges[edge.id] = edge }
        }

        var events: [LegacyGraphEvent] = []
        events += decodeJSONLineRecords(GraphNode.self, at: directory.appendingPathComponent(Self.nodesFileName))
            .map { record in
                LegacyGraphEvent(
                    timestamp: max(record.value.updatedAt, record.value.lastIndexedAt),
                    fileOrder: 0,
                    lineNumber: record.lineNumber,
                    payload: .upsertNode(record.value)
                )
            }
        events += decodeJSONLineRecords(GraphEdge.self, at: directory.appendingPathComponent(Self.edgesFileName))
            .map { record in
                LegacyGraphEvent(
                    timestamp: max(record.value.updatedAt, record.value.lastIndexedAt),
                    fileOrder: 1,
                    lineNumber: record.lineNumber,
                    payload: .upsertEdge(record.value)
                )
            }
        events += decodeJSONLineRecords(GraphTombstone.self, at: directory.appendingPathComponent(Self.tombstonesFileName))
            .map { record in
                LegacyGraphEvent(
                    timestamp: record.value.createdAt,
                    fileOrder: 2,
                    lineNumber: record.lineNumber,
                    payload: .tombstone(record.value)
                )
            }

        events.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.fileOrder != $1.fileOrder { return $0.fileOrder < $1.fileOrder }
            return $0.lineNumber < $1.lineNumber
        }
        for event in events where event.timestamp >= snapshotDate {
            switch event.payload {
            case .upsertNode(let node):
                state.nodes[node.id] = node
            case .upsertEdge(let edge):
                guard state.nodes[edge.from] != nil, state.nodes[edge.to] != nil else { continue }
                state.edges[edge.id] = edge
            case .tombstone(let tombstone):
                switch tombstone.target {
                case .node:
                    state.nodes.removeValue(forKey: tombstone.id)
                    state.edges = state.edges.filter {
                        $0.value.from != tombstone.id && $0.value.to != tombstone.id
                    }
                case .edge:
                    state.edges.removeValue(forKey: tombstone.id)
                }
            }
        }
        state.edges = state.edges.filter { state.nodes[$0.value.from] != nil && state.nodes[$0.value.to] != nil }
        return state
    }

    private func latestValidLegacySnapshot(in directory: URL) throws -> LegacySnapshot? {
        let snapshots = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: snapshots.path) else { return nil }
        let candidates = try fileManager.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("snapshot-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                  let snapshot = try? Self.decoder().decode(LegacySnapshot.self, from: data),
                  snapshot.schemaVersion <= graphSchemaVersion else { continue }
            return snapshot
        }
        return nil
    }

    private func decodeJSONLineRecords<T: Decodable>(_ type: T.Type, at url: URL) -> [LegacyLineRecord<T>] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contents.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            guard let value = try? Self.decoder().decode(T.self, from: Data(line.utf8)) else { return nil }
            return LegacyLineRecord(lineNumber: index + 1, value: value)
        }
    }

    private func backupLegacyFiles(in directory: URL) throws {
        let backupDirectory = directory.appendingPathComponent(Self.backupsDirectoryName, isDirectory: true)
            .appendingPathComponent("legacy-jsonl-\(Self.fileTimestamp(Date()))", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        for name in [Self.nodesFileName, Self.edgesFileName, Self.tombstonesFileName, Self.manifestFileName] {
            let source = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: backupDirectory.appendingPathComponent(name))
        }
        let snapshots = directory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: snapshots.path) {
            try fileManager.copyItem(
                at: snapshots,
                to: backupDirectory.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
            )
        }
    }

    private func ensureLegacyCompatibilityFiles(in directory: URL) throws {
        for name in [Self.nodesFileName, Self.edgesFileName, Self.tombstonesFileName] {
            let url = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) { try Data().write(to: url, options: .atomic) }
        }
    }

    // MARK: - SQL record mapping

    private func loadCache(from database: GraphSQLiteDatabase) throws {
        var loadedNodes: [String: GraphNode] = [:]
        let nodeStatement = try database.prepare(
            "SELECT id, kind, display_name, payload, created_at, updated_at, source_hash, last_indexed_at FROM nodes ORDER BY id"
        )
        while try nodeStatement.stepRow() {
            guard let id = nodeStatement.string(at: 0),
                  let rawKind = nodeStatement.string(at: 1),
                  let kind = GraphNodeKind(rawValue: rawKind),
                  let displayName = nodeStatement.string(at: 2) else {
                throw GraphError.databaseCorrupt(details: "invalid node row")
            }
            let payload = try Self.decoder().decode(JSONValue.self, from: nodeStatement.data(at: 3))
            loadedNodes[id] = GraphNode(
                id: id,
                kind: kind,
                displayName: displayName,
                payload: payload,
                createdAt: Date(timeIntervalSince1970: nodeStatement.double(at: 4)),
                updatedAt: Date(timeIntervalSince1970: nodeStatement.double(at: 5)),
                sourceHash: nodeStatement.string(at: 6),
                lastIndexedAt: Date(timeIntervalSince1970: nodeStatement.double(at: 7))
            )
        }

        var loadedEdges: [String: GraphEdge] = [:]
        let edgeStatement = try database.prepare(
            "SELECT id, kind, from_id, to_id, weight, payload, created_at, updated_at, source_hash, last_indexed_at FROM edges ORDER BY id"
        )
        while try edgeStatement.stepRow() {
            guard let id = edgeStatement.string(at: 0),
                  let rawKind = edgeStatement.string(at: 1),
                  let kind = GraphEdgeKind(rawValue: rawKind),
                  let from = edgeStatement.string(at: 2),
                  let to = edgeStatement.string(at: 3) else {
                throw GraphError.databaseCorrupt(details: "invalid edge row")
            }
            let payload = try Self.decoder().decode(JSONValue.self, from: edgeStatement.data(at: 5))
            loadedEdges[id] = GraphEdge(
                id: id,
                kind: kind,
                from: from,
                to: to,
                weight: edgeStatement.double(at: 4),
                payload: payload,
                createdAt: Date(timeIntervalSince1970: edgeStatement.double(at: 6)),
                updatedAt: Date(timeIntervalSince1970: edgeStatement.double(at: 7)),
                sourceHash: edgeStatement.string(at: 8),
                lastIndexedAt: Date(timeIntervalSince1970: edgeStatement.double(at: 9))
            )
        }

        var loadedAnchors: [String: GraphSourceAnchor] = [:]
        let anchorStatement = try database.prepare(
            "SELECT id, source_node_id, relative_path, locator, excerpt, source_hash FROM source_anchors ORDER BY id"
        )
        while try anchorStatement.stepRow() {
            guard let id = anchorStatement.string(at: 0),
                  let sourceNodeID = anchorStatement.string(at: 1),
                  let relativePath = anchorStatement.string(at: 2),
                  let locator = anchorStatement.string(at: 3),
                  let sourceHash = anchorStatement.string(at: 5) else {
                throw GraphError.databaseCorrupt(details: "invalid source anchor row")
            }
            loadedAnchors[id] = GraphSourceAnchor(
                id: id,
                sourceNodeID: sourceNodeID,
                relativePath: relativePath,
                locator: locator,
                excerpt: anchorStatement.string(at: 4),
                sourceHash: sourceHash
            )
        }

        var loadedOccurrences: [String: GraphCitationOccurrence] = [:]
        let occurrenceStatement = try database.prepare(
            "SELECT id, edge_id, source_node_id, target_node_id, evidence_source, bibtex_key, raw_text, ordinal, source_hash, anchor_id FROM citation_occurrences ORDER BY id"
        )
        while try occurrenceStatement.stepRow() {
            guard let id = occurrenceStatement.string(at: 0),
                  let edgeID = occurrenceStatement.string(at: 1),
                  let sourceNodeID = occurrenceStatement.string(at: 2),
                  let targetNodeID = occurrenceStatement.string(at: 3),
                  let evidenceSource = occurrenceStatement.string(at: 4),
                  let rawText = occurrenceStatement.string(at: 6),
                  let sourceHash = occurrenceStatement.string(at: 8) else {
                throw GraphError.databaseCorrupt(details: "invalid citation occurrence row")
            }
            loadedOccurrences[id] = GraphCitationOccurrence(
                id: id,
                edgeID: edgeID,
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                evidenceSource: evidenceSource,
                bibtexKey: occurrenceStatement.string(at: 5),
                rawText: rawText,
                ordinal: occurrenceStatement.int(at: 7),
                sourceHash: sourceHash,
                anchorID: occurrenceStatement.string(at: 9)
            )
        }

        nodes = loadedNodes
        edges = loadedEdges
        anchors = loadedAnchors
        occurrences = loadedOccurrences
        rebuildEdgeIndexes()
        refreshManifestCounts()
    }

    private func writeNode(_ node: GraphNode, to database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare(Self.upsertNodeSQL)
        try statement.bind(node.id, at: 1)
        try statement.bind(node.kind.rawValue, at: 2)
        try statement.bind(node.displayName, at: 3)
        try statement.bind(try Self.encoder().encode(node.payload), at: 4)
        try statement.bind(node.createdAt.timeIntervalSince1970, at: 5)
        try statement.bind(node.updatedAt.timeIntervalSince1970, at: 6)
        try statement.bind(node.sourceHash, at: 7)
        try statement.bind(node.lastIndexedAt.timeIntervalSince1970, at: 8)
        try statement.bind(node.canonicalContentHash, at: 9)
        try statement.stepDone()
    }

    private func writeEdge(_ edge: GraphEdge, to database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare(Self.upsertEdgeSQL)
        try statement.bind(edge.id, at: 1)
        try statement.bind(edge.kind.rawValue, at: 2)
        try statement.bind(edge.from, at: 3)
        try statement.bind(edge.to, at: 4)
        try statement.bind(edge.weight, at: 5)
        try statement.bind(try Self.encoder().encode(edge.payload), at: 6)
        try statement.bind(edge.createdAt.timeIntervalSince1970, at: 7)
        try statement.bind(edge.updatedAt.timeIntervalSince1970, at: 8)
        try statement.bind(edge.sourceHash, at: 9)
        try statement.bind(edge.lastIndexedAt.timeIntervalSince1970, at: 10)
        try statement.bind(edge.canonicalContentHash, at: 11)
        try statement.stepDone()
    }

    private func writeAnchor(_ anchor: GraphSourceAnchor, to database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare(Self.upsertAnchorSQL)
        try statement.bind(anchor.id, at: 1)
        try statement.bind(anchor.sourceNodeID, at: 2)
        try statement.bind(anchor.relativePath, at: 3)
        try statement.bind(anchor.locator, at: 4)
        try statement.bind(anchor.excerpt, at: 5)
        try statement.bind(anchor.sourceHash, at: 6)
        try statement.bind(GraphIdentifier.canonicalHash(of: anchor), at: 7)
        try statement.stepDone()
    }

    private func writeOccurrence(_ occurrence: GraphCitationOccurrence, to database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare(Self.upsertOccurrenceSQL)
        try statement.bind(occurrence.id, at: 1)
        try statement.bind(occurrence.edgeID, at: 2)
        try statement.bind(occurrence.sourceNodeID, at: 3)
        try statement.bind(occurrence.targetNodeID, at: 4)
        try statement.bind(occurrence.evidenceSource, at: 5)
        try statement.bind(occurrence.bibtexKey, at: 6)
        try statement.bind(occurrence.rawText, at: 7)
        try statement.bind(occurrence.ordinal, at: 8)
        try statement.bind(occurrence.sourceHash, at: 9)
        try statement.bind(occurrence.anchorID, at: 10)
        try statement.bind(GraphIdentifier.canonicalHash(of: occurrence), at: 11)
        try statement.stepDone()
    }

    private func deleteRows(from table: String, ids: Set<String>, database: GraphSQLiteDatabase) throws {
        guard !ids.isEmpty else { return }
        guard ["nodes", "edges", "citation_occurrences", "source_anchors"].contains(table) else {
            throw GraphError.invalidTable(table)
        }
        let statement = try database.prepare("DELETE FROM \(table) WHERE id = ?")
        for id in ids.sorted() {
            try statement.reset()
            try statement.bind(id, at: 1)
            try statement.stepDone()
        }
    }

    private func deleteRows(
        from table: String,
        existingIDs: Set<String>,
        keeping keptIDs: Set<String>,
        database: GraphSQLiteDatabase
    ) throws {
        try deleteRows(from: table, ids: existingIDs.subtracting(keptIDs), database: database)
    }

    private func metadata(_ key: String, database: GraphSQLiteDatabase) throws -> String? {
        let statement = try database.prepare("SELECT value FROM metadata WHERE key = ?")
        try statement.bind(key, at: 1)
        return try statement.stepRow() ? statement.string(at: 0) : nil
    }

    private func setMetadata(_ key: String, value: String, database: GraphSQLiteDatabase) throws {
        let statement = try database.prepare(
            "INSERT INTO metadata(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        )
        try statement.bind(key, at: 1)
        try statement.bind(value, at: 2)
        try statement.stepDone()
    }

    private func recordIndexRunStarted(
        id: String,
        expectedNodes: Int,
        expectedEdges: Int,
        database: GraphSQLiteDatabase
    ) throws {
        let statement = try database.prepare(
            """
            INSERT INTO index_runs(id, started_at, status, force, expected_nodes, expected_edges)
            VALUES(?, ?, 'running', 0, ?, ?)
            """
        )
        try statement.bind(id, at: 1)
        try statement.bind(Self.iso8601.string(from: Date()), at: 2)
        try statement.bind(expectedNodes, at: 3)
        try statement.bind(expectedEdges, at: 4)
        try statement.stepDone()
    }

    private func finishIndexRun(
        id: String,
        status: String,
        result: GraphReconciliationResult?,
        error: String?,
        database: GraphSQLiteDatabase
    ) throws {
        let statement = try database.prepare(
            """
            UPDATE index_runs SET
                finished_at = ?, status = ?, upserted_nodes = ?, upserted_edges = ?,
                deleted_nodes = ?, deleted_edges = ?, error_message = ?
            WHERE id = ?
            """
        )
        try statement.bind(Self.iso8601.string(from: Date()), at: 1)
        try statement.bind(status, at: 2)
        try statement.bind(result?.insertedOrUpdatedNodes, at: 3)
        try statement.bind(result?.insertedOrUpdatedEdges, at: 4)
        try statement.bind(result?.deletedNodes, at: 5)
        try statement.bind(result?.deletedEdges, at: 6)
        try statement.bind(error, at: 7)
        try statement.bind(id, at: 8)
        try statement.stepDone()
    }

    // MARK: - In-memory indexes and manifest

    private func rebuildEdgeIndexes() {
        outEdges.removeAll(keepingCapacity: true)
        inEdges.removeAll(keepingCapacity: true)
        for edge in edges.values { addEdgeToIndexes(edge) }
    }

    private func addEdgeToIndexes(_ edge: GraphEdge) {
        outEdges[edge.from, default: []].insert(edge.id)
        inEdges[edge.to, default: []].insert(edge.id)
    }

    private func removeEdgeFromIndexes(_ edge: GraphEdge) {
        outEdges[edge.from]?.remove(edge.id)
        inEdges[edge.to]?.remove(edge.id)
        if outEdges[edge.from]?.isEmpty == true { outEdges.removeValue(forKey: edge.from) }
        if inEdges[edge.to]?.isEmpty == true { inEdges.removeValue(forKey: edge.to) }
    }

    private func removeEdgeFromMemory(_ id: String) {
        guard let edge = edges.removeValue(forKey: id) else { return }
        removeEdgeFromIndexes(edge)
    }

    private func refreshManifestCounts() {
        manifest.schemaVersion = graphSchemaVersion
        manifest.countNodes = nodes.count
        manifest.countEdges = edges.count
        manifest.countTombstones = 0
    }

    private func updateManifest(in directory: URL) throws {
        refreshManifestCounts()
        manifest.generatedAt = Date()
        let data = try Self.encoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent(Self.manifestFileName), options: .atomic)
    }

    private func pruneBackups(in directory: URL, prefix: String, keepLatest: Int) throws {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files.dropLast(keepLatest) { try fileManager.removeItem(at: url) }
    }

    private func requireDatabase() throws -> GraphSQLiteDatabase {
        guard let database, root != nil else { throw GraphError.notOpen }
        return database
    }

    private func map(_ error: Error) -> Error {
        if let graphError = error as? GraphError { return graphError }
        if error is CancellationError { return error }
        if let sqlite = error as? GraphSQLiteFailure { return GraphError.sqlite(details: sqlite.description) }
        return error
    }

    private func emit(_ event: String, payload: JSONValue) async {
        guard let debug, let root else { return }
        try? await debug.append(AppDebugEvent(event: event, payload: payload), in: root)
    }

    public nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let iso8601 = ISO8601DateFormatter()
    private static func fileTimestamp(_ date: Date) -> String {
        iso8601.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    private static let schemaV1 = """
    CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS nodes (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        display_name TEXT NOT NULL,
        payload BLOB NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        source_hash TEXT,
        last_indexed_at REAL NOT NULL,
        canonical_hash TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS edges (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        from_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        to_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        weight REAL NOT NULL,
        payload BLOB NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        source_hash TEXT,
        last_indexed_at REAL NOT NULL,
        canonical_hash TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS edges_from_kind_idx ON edges(from_id, kind);
    CREATE INDEX IF NOT EXISTS edges_to_kind_idx ON edges(to_id, kind);
    """

    private static let schemaV2 = """
    CREATE TABLE IF NOT EXISTS source_anchors (
        id TEXT PRIMARY KEY NOT NULL,
        source_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        relative_path TEXT NOT NULL,
        locator TEXT NOT NULL,
        excerpt TEXT,
        source_hash TEXT NOT NULL,
        canonical_hash TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS citation_occurrences (
        id TEXT PRIMARY KEY NOT NULL,
        edge_id TEXT NOT NULL REFERENCES edges(id) ON DELETE CASCADE,
        source_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        target_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        evidence_source TEXT NOT NULL,
        bibtex_key TEXT,
        raw_text TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        source_hash TEXT NOT NULL,
        anchor_id TEXT REFERENCES source_anchors(id) ON DELETE SET NULL,
        canonical_hash TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS citation_occurrences_edge_idx ON citation_occurrences(edge_id, ordinal);
    CREATE INDEX IF NOT EXISTS citation_occurrences_source_idx ON citation_occurrences(source_node_id);
    CREATE INDEX IF NOT EXISTS source_anchors_source_idx ON source_anchors(source_node_id, relative_path);
    """

    private static let schemaV3 = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS index_runs (
        id TEXT PRIMARY KEY NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        status TEXT NOT NULL CHECK(status IN ('running', 'completed', 'failed', 'cancelled')),
        force INTEGER NOT NULL DEFAULT 0,
        expected_nodes INTEGER NOT NULL DEFAULT 0,
        expected_edges INTEGER NOT NULL DEFAULT 0,
        upserted_nodes INTEGER,
        upserted_edges INTEGER,
        deleted_nodes INTEGER,
        deleted_edges INTEGER,
        error_message TEXT
    );
    CREATE INDEX IF NOT EXISTS index_runs_started_at_idx ON index_runs(started_at DESC);
    CREATE TABLE IF NOT EXISTS embeddings (
        node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        model TEXT NOT NULL,
        dimensions INTEGER NOT NULL CHECK(dimensions > 0),
        vector BLOB NOT NULL,
        content_hash TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(node_id, model)
    );
    CREATE INDEX IF NOT EXISTS embeddings_content_hash_idx ON embeddings(content_hash);
    """

    private static let upsertNodeSQL = """
    INSERT INTO nodes(id, kind, display_name, payload, created_at, updated_at, source_hash, last_indexed_at, canonical_hash)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        kind = excluded.kind,
        display_name = excluded.display_name,
        payload = excluded.payload,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        source_hash = excluded.source_hash,
        last_indexed_at = excluded.last_indexed_at,
        canonical_hash = excluded.canonical_hash
    WHERE nodes.canonical_hash <> excluded.canonical_hash
    """

    private static let upsertEdgeSQL = """
    INSERT INTO edges(id, kind, from_id, to_id, weight, payload, created_at, updated_at, source_hash, last_indexed_at, canonical_hash)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        kind = excluded.kind,
        from_id = excluded.from_id,
        to_id = excluded.to_id,
        weight = excluded.weight,
        payload = excluded.payload,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        source_hash = excluded.source_hash,
        last_indexed_at = excluded.last_indexed_at,
        canonical_hash = excluded.canonical_hash
    WHERE edges.canonical_hash <> excluded.canonical_hash
    """

    private static let upsertAnchorSQL = """
    INSERT INTO source_anchors(id, source_node_id, relative_path, locator, excerpt, source_hash, canonical_hash)
    VALUES(?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        source_node_id = excluded.source_node_id,
        relative_path = excluded.relative_path,
        locator = excluded.locator,
        excerpt = excluded.excerpt,
        source_hash = excluded.source_hash,
        canonical_hash = excluded.canonical_hash
    WHERE source_anchors.canonical_hash <> excluded.canonical_hash
    """

    private static let upsertOccurrenceSQL = """
    INSERT INTO citation_occurrences(id, edge_id, source_node_id, target_node_id, evidence_source, bibtex_key, raw_text, ordinal, source_hash, anchor_id, canonical_hash)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        edge_id = excluded.edge_id,
        source_node_id = excluded.source_node_id,
        target_node_id = excluded.target_node_id,
        evidence_source = excluded.evidence_source,
        bibtex_key = excluded.bibtex_key,
        raw_text = excluded.raw_text,
        ordinal = excluded.ordinal,
        source_hash = excluded.source_hash,
        anchor_id = excluded.anchor_id,
        canonical_hash = excluded.canonical_hash
    WHERE citation_occurrences.canonical_hash <> excluded.canonical_hash
    """
}

private nonisolated struct LegacyGraphState {
    var nodes: [String: GraphNode] = [:]
    var edges: [String: GraphEdge] = [:]
}

private nonisolated struct LegacyLineRecord<Value> {
    let lineNumber: Int
    let value: Value
}

private nonisolated struct LegacyGraphEvent {
    enum Payload {
        case upsertNode(GraphNode)
        case upsertEdge(GraphEdge)
        case tombstone(GraphTombstone)
    }

    let timestamp: Date
    let fileOrder: Int
    let lineNumber: Int
    let payload: Payload
}

private nonisolated struct LegacySnapshot: Codable {
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

public nonisolated enum GraphError: Error, Sendable, LocalizedError {
    case notOpen
    case orphanEdge(edgeID: String, missingEndpoints: [String])
    case missingCitationEdge(occurrenceID: String, edgeID: String)
    case missingSourceAnchor(occurrenceID: String, anchorID: String)
    case unsupportedSchema(found: Int, supported: Int)
    case databaseCorrupt(details: String)
    case foreignKeyViolation(details: String)
    case recoveryFailed(details: String)
    case sqlite(details: String)
    case invalidTable(String)

    public var errorDescription: String? {
        switch self {
        case .notOpen:
            return "Graph repository is not open."
        case .orphanEdge(let edgeID, let missing):
            return "Graph edge \(edgeID) references missing endpoints: \(missing.joined(separator: ", "))."
        case .missingCitationEdge(let occurrenceID, let edgeID):
            return "Citation occurrence \(occurrenceID) references missing edge \(edgeID)."
        case .missingSourceAnchor(let occurrenceID, let anchorID):
            return "Citation occurrence \(occurrenceID) references missing source anchor \(anchorID)."
        case .unsupportedSchema(let found, let supported):
            return "Graph schema \(found) is newer than supported schema \(supported)."
        case .databaseCorrupt(let details):
            return "Graph database failed integrity checks: \(details)"
        case .foreignKeyViolation(let details):
            return "Graph database contains invalid foreign keys: \(details)"
        case .recoveryFailed(let details):
            return "Graph database recovery failed: \(details)"
        case .sqlite(let details):
            return details
        case .invalidTable(let table):
            return "Invalid internal graph table: \(table)"
        }
    }
}

private nonisolated struct GraphNodeCanonicalContent: Encodable {
    let id: String
    let kind: String
    let displayName: String
    let payload: JSONValue
    let sourceHash: String?
}

private nonisolated struct GraphEdgeCanonicalContent: Encodable {
    let id: String
    let kind: String
    let from: String
    let to: String
    let weight: Double
    let payload: JSONValue
    let sourceHash: String?
}

public extension GraphNode {
    nonisolated var canonicalContentHash: String {
        GraphIdentifier.canonicalHash(of: GraphNodeCanonicalContent(
            id: id,
            kind: kind.rawValue,
            displayName: displayName,
            payload: payload,
            sourceHash: sourceHash
        ))
    }
}

public extension GraphEdge {
    nonisolated var canonicalContentHash: String {
        GraphIdentifier.canonicalHash(of: GraphEdgeCanonicalContent(
            id: id,
            kind: kind.rawValue,
            from: from,
            to: to,
            weight: weight,
            payload: payload,
            sourceHash: sourceHash
        ))
    }
}
