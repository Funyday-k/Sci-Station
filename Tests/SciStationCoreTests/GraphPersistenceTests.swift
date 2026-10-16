import Foundation
import Testing
@testable import SciStationCore

@Suite("Graph persistence and traversal")
struct GraphPersistenceTests {
    @Test("Writes fail explicitly before the repository is opened")
    func notOpenFailsExplicitly() async {
        let repository = GraphRepository()
        do {
            try await repository.upsertNode(Self.node("paper:not-open"))
            Issue.record("Expected GraphError.notOpen")
        } catch GraphError.notOpen {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Orphan edges are rejected instead of silently dropped")
    func orphanEdgeFailsExplicitly() async throws {
        let fixture = try Self.makeFixture("orphan")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        try await repository.upsertNode(Self.node("paper:a"))

        do {
            try await repository.upsertEdge(Self.edge(from: "paper:a", to: "paper:missing"))
            Issue.record("Expected GraphError.orphanEdge")
        } catch GraphError.orphanEdge(let edgeID, let missingEndpoints) {
            #expect(edgeID == GraphEdge.computeID(from: "paper:a", kind: .cites, to: "paper:missing"))
            #expect(missingEndpoints == ["paper:missing"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await repository.close()
    }

    @Test("Corrupt databases recover from a validated SQLite backup")
    func corruptDatabaseRecoversFromBackup() async throws {
        let fixture = try Self.makeFixture("corrupt-recovery")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        try await repository.upsertNode(Self.node("paper:a", name: "Recovered A"))
        try await repository.upsertNode(Self.node("paper:b", name: "Recovered B"))
        try await repository.upsertEdge(Self.edge(from: "paper:a", to: "paper:b"))
        let compact = try await repository.forceCompact()
        let backupURL = try #require(compact.snapshotURL)
        #expect(!backupURL.lastPathComponent.contains(":"))
        let backupCheck = try GraphSQLiteDatabase(url: backupURL, readOnly: true)
        #expect(try backupCheck.scalarString("PRAGMA quick_check") == "ok")
        #expect(try backupCheck.scalarInt("SELECT COUNT(*) FROM nodes") == 2)
        backupCheck.close()
        await repository.close()

        let databaseURL = fixture.graphDirectory.appendingPathComponent(GraphRepository.databaseFileName)
        try Data("not a sqlite database".utf8).write(to: databaseURL, options: .atomic)

        let recovered = GraphRepository()
        try await recovered.open(in: fixture.root)
        let snapshot = await recovered.snapshot()
        #expect(snapshot.nodes["paper:a"]?.displayName == "Recovered A")
        #expect(snapshot.edges.count == 1)
        await recovered.close()

        let corruptCopies = try FileManager.default.contentsOfDirectory(
            at: fixture.graphDirectory.appendingPathComponent(GraphRepository.backupsDirectoryName),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("corrupt-") }
        #expect(corruptCopies.count == 1)
        #expect(corruptCopies.allSatisfy { !$0.lastPathComponent.contains(":") })
    }

    @Test("Recovery skips a newer semantically invalid backup and tries the next candidate")
    func recoveryFallsBackAcrossValidatedBackups() async throws {
        let fixture = try Self.makeFixture("backup-fallback")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        try await repository.upsertNode(Self.node("paper:durable", name: "Durable Paper"))
        await repository.close()

        let databaseURL = fixture.graphDirectory.appendingPathComponent(GraphRepository.databaseFileName)
        let backupsDirectory = fixture.graphDirectory.appendingPathComponent(GraphRepository.backupsDirectoryName)
        let validOlderURL = backupsDirectory.appendingPathComponent("aaa-older.sqlite")
        let invalidNewerURL = backupsDirectory.appendingPathComponent("zzz-newer.sqlite")
        let source = try GraphSQLiteDatabase(url: databaseURL)
        try source.backup(to: validOlderURL)
        try source.backup(to: invalidNewerURL)
        source.close()

        let invalid = try GraphSQLiteDatabase(url: invalidNewerURL)
        try invalid.execute("PRAGMA foreign_keys = OFF")
        try invalid.execute(
            """
            INSERT INTO embeddings(node_id, model, dimensions, vector, content_hash, updated_at)
            VALUES('paper:missing', 'test', 1, X'0000', 'hash', '2026-08-06T00:00:00Z')
            """
        )
        invalid.close()

        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: validOlderURL.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: invalidNewerURL.path)
        try Data("not a sqlite database".utf8).write(to: databaseURL, options: .atomic)

        let recovered = GraphRepository()
        try await recovered.open(in: fixture.root)
        #expect(await recovered.node(id: "paper:durable")?.displayName == "Durable Paper")
        await recovered.close()

        let restored = try GraphSQLiteDatabase(url: databaseURL, readOnly: true)
        #expect(try restored.scalarString("PRAGMA foreign_key_check") == nil)
        restored.close()
    }

    @Test("Legacy import uses the newest valid snapshot and event-order last-write-wins")
    func legacyImportIsOrderedAndRecoverable() async throws {
        let fixture = try Self.makeFixture("legacy-import")
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.graphDirectory, withIntermediateDirectories: true)
        let snapshotsDirectory = fixture.graphDirectory.appendingPathComponent(GraphRepository.snapshotsDirectoryName)
        try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)

        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t2 = Date(timeIntervalSince1970: 3_000)
        let t3 = Date(timeIntervalSince1970: 4_000)
        let t4 = Date(timeIntervalSince1970: 5_000)
        let project = Self.node("project:p", kind: .project, name: "Project", date: t0)
        let snapshotNode = Self.node("paper:a", name: "Snapshot A", date: t0)
        let validSnapshot = TestLegacyGraphSnapshot(
            schemaVersion: graphSchemaVersion,
            generatedAt: t0,
            nodes: [snapshotNode, project],
            edges: []
        )
        try GraphRepository.encoder().encode(validSnapshot).write(
            to: snapshotsDirectory.appendingPathComponent("snapshot-2026-01-01T00-00-00Z.json"),
            options: .atomic
        )
        try Data("{broken".utf8).write(
            to: snapshotsDirectory.appendingPathComponent("snapshot-2026-02-01T00-00-00Z.json"),
            options: .atomic
        )

        let firstUpsert = Self.node("paper:a", name: "Before deletion", date: t1)
        let rebuilt = Self.node("paper:a", name: "Rebuilt A", date: t3)
        try Self.writeJSONLines(
            [firstUpsert, rebuilt],
            to: fixture.graphDirectory.appendingPathComponent(GraphRepository.nodesFileName)
        )
        let edgeBeforeDeletion = Self.edge(from: "paper:a", to: "project:p", date: Date(timeIntervalSince1970: 2_500))
        let edgeAfterRebuild = Self.edge(from: "paper:a", to: "project:p", date: t4)
        try Self.writeJSONLines(
            [edgeBeforeDeletion, edgeAfterRebuild],
            to: fixture.graphDirectory.appendingPathComponent(GraphRepository.edgesFileName)
        )
        try Self.writeJSONLines(
            [GraphTombstone(id: "paper:a", target: .node, createdAt: t2, reason: "deleted")],
            to: fixture.graphDirectory.appendingPathComponent(GraphRepository.tombstonesFileName)
        )

        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        let migrated = await repository.snapshot()
        #expect(migrated.nodes["paper:a"]?.displayName == "Rebuilt A")
        #expect(migrated.edges[edgeAfterRebuild.id] != nil)
        await repository.close()

        let backupRoot = fixture.graphDirectory.appendingPathComponent(GraphRepository.backupsDirectoryName)
        let legacyBackup = try #require(
            FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("legacy-jsonl-") }
        )
        #expect(!legacyBackup.lastPathComponent.contains(":"))
        #expect(FileManager.default.fileExists(
            atPath: legacyBackup.appendingPathComponent(GraphRepository.snapshotsDirectoryName).path
        ))
    }

    @Test("A real V2 database migrates to V3 without losing graph rows")
    func realV2SchemaMigratesToV3() async throws {
        let fixture = try Self.makeFixture("v2-migration")
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.graphDirectory, withIntermediateDirectories: true)
        let databaseURL = fixture.graphDirectory.appendingPathComponent(GraphRepository.databaseFileName)
        let v2 = try GraphSQLiteDatabase(url: databaseURL)
        try v2.execute(Self.v2SchemaSQL)
        let legacyNode = Self.node("paper:v2", name: "V2 Paper")
        let insert = try v2.prepare(
            """
            INSERT INTO nodes(id, kind, display_name, payload, created_at, updated_at, source_hash, last_indexed_at, canonical_hash)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try insert.bind(legacyNode.id, at: 1)
        try insert.bind(legacyNode.kind.rawValue, at: 2)
        try insert.bind(legacyNode.displayName, at: 3)
        try insert.bind(try GraphRepository.encoder().encode(legacyNode.payload), at: 4)
        try insert.bind(legacyNode.createdAt.timeIntervalSince1970, at: 5)
        try insert.bind(legacyNode.updatedAt.timeIntervalSince1970, at: 6)
        try insert.bind(legacyNode.sourceHash, at: 7)
        try insert.bind(legacyNode.lastIndexedAt.timeIntervalSince1970, at: 8)
        try insert.bind(legacyNode.canonicalContentHash, at: 9)
        try insert.stepDone()
        v2.close()

        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        #expect(await repository.node(id: "paper:v2")?.displayName == "V2 Paper")
        await repository.close()

        let migrated = try GraphSQLiteDatabase(url: databaseURL, readOnly: true)
        #expect(try migrated.scalarInt("PRAGMA user_version") == GraphRepository.storageSchemaVersion)
        #expect(try migrated.scalarInt("SELECT COUNT(*) FROM schema_migrations") == 3)
        #expect(try migrated.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='index_runs'") == 1)
        #expect(try migrated.scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='embeddings'") == 1)
        #expect(try migrated.scalarString("PRAGMA foreign_key_check") == nil)
        migrated.close()

        let migrationBackups = try FileManager.default.contentsOfDirectory(
            at: fixture.graphDirectory.appendingPathComponent(GraphRepository.backupsDirectoryName),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("pre-migration-v2-") }
        #expect(migrationBackups.count == 1)
        #expect(migrationBackups.allSatisfy { !$0.lastPathComponent.contains(":") })
    }

    @Test("Foreign key violations are rejected during open")
    func foreignKeyViolationsAreRejected() async throws {
        let fixture = try Self.makeFixture("foreign-key")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        await repository.close()

        let databaseURL = fixture.graphDirectory.appendingPathComponent(GraphRepository.databaseFileName)
        let database = try GraphSQLiteDatabase(url: databaseURL)
        try database.execute("PRAGMA foreign_keys = OFF")
        try database.execute(
            """
            INSERT INTO embeddings(node_id, model, dimensions, vector, content_hash, updated_at)
            VALUES('paper:missing', 'test', 1, X'0000', 'hash', '2026-08-06T00:00:00Z')
            """
        )
        database.close()

        let invalid = GraphRepository()
        do {
            try await invalid.open(in: fixture.root)
            Issue.record("Expected GraphError.foreignKeyViolation")
        } catch GraphError.foreignKeyViolation(let details) {
            #expect(details.contains("embeddings"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Reconcile removes deleted entities and citation evidence, then permits same-ID rebuild")
    func reconciliationCleansAndRebuilds() async throws {
        let fixture = try Self.makeFixture("reconcile")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)

        let source = Self.node("paper:source")
        let target = Self.node("paper:target")
        let cites = Self.edge(from: source.id, to: target.id)
        let anchor = GraphSourceAnchor(
            id: "anchor:1",
            sourceNodeID: source.id,
            relativePath: "library/papers/source/paper.md",
            locator: "references/1",
            excerpt: "Target",
            sourceHash: "anchor-hash"
        )
        let occurrence = GraphCitationOccurrence(
            id: "occurrence:1",
            edgeID: cites.id,
            sourceNodeID: source.id,
            targetNodeID: target.id,
            evidenceSource: "paper_md",
            rawText: "Target",
            ordinal: 1,
            sourceHash: "occurrence-hash",
            anchorID: anchor.id
        )
        _ = try await repository.reconcile(GraphExpectedState(
            nodes: [source.id: source, target.id: target],
            edges: [cites.id: cites],
            citationOccurrences: [occurrence.id: occurrence],
            sourceAnchors: [anchor.id: anchor]
        ))
        #expect((await repository.snapshot()).citationOccurrences.count == 1)

        _ = try await repository.reconcile(GraphExpectedState(nodes: [source.id: source], edges: [:]))
        let cleaned = await repository.snapshot()
        #expect(cleaned.nodes[target.id] == nil)
        #expect(cleaned.edges.isEmpty)
        #expect(cleaned.citationOccurrences.isEmpty)
        #expect(cleaned.sourceAnchors.isEmpty)

        let rebuilt = Self.node("paper:target", name: "Rebuilt target")
        _ = try await repository.reconcile(GraphExpectedState(
            nodes: [source.id: source, rebuilt.id: rebuilt],
            edges: [:]
        ))
        #expect(await repository.node(id: rebuilt.id)?.displayName == "Rebuilt target")
        await repository.close()
    }

    @Test("Large graph BFS is deterministic and cancellable")
    func traversalIsDeterministicAndCancellable() async throws {
        let fixture = try Self.makeFixture("traversal")
        defer { fixture.cleanup() }
        let repository = GraphRepository()
        try await repository.open(in: fixture.root)
        let count = 600
        var nodes: [String: GraphNode] = [:]
        var edges: [String: GraphEdge] = [:]
        for index in 0..<count {
            let node = Self.node("paper:\(index)")
            nodes[node.id] = node
            if index > 0 {
                let edge = Self.edge(from: "paper:\(index - 1)", to: node.id)
                edges[edge.id] = edge
            }
        }
        _ = try await repository.reconcile(GraphExpectedState(nodes: nodes, edges: edges))
        let readModel = GraphReadModel(repository: repository)
        let path = try await readModel.pathCancellable(from: "paper:0", to: "paper:599", maxDepth: 600)
        #expect(path?.count == 599)
        #expect(path?.first?.from == "paper:0")

        let cancelled = Task {
            try await readModel.pathCancellable(from: "paper:0", to: "paper:599", maxDepth: 600)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            Issue.record("Expected traversal cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        await repository.close()
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func node(
        _ id: String,
        kind: GraphNodeKind = .paper,
        name: String? = nil,
        date: Date = fixedDate
    ) -> GraphNode {
        GraphNode(
            id: id,
            kind: kind,
            displayName: name ?? id,
            createdAt: date,
            updatedAt: date,
            sourceHash: "hash:\(id):\(name ?? id)",
            lastIndexedAt: date
        )
    }

    private static func edge(from: String, to: String, date: Date = fixedDate) -> GraphEdge {
        GraphEdge(
            kind: .cites,
            from: from,
            to: to,
            createdAt: date,
            updatedAt: date,
            sourceHash: "hash:\(from):\(to):\(date.timeIntervalSince1970)",
            lastIndexedAt: date
        )
    }

    private static func makeFixture(_ name: String) throws -> GraphTestFixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SciStationGraphTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return GraphTestFixture(rootURL: url)
    }

    private static func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        let encoder = GraphRepository.encoder()
        let contents = try values.map { value in
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let v2SchemaSQL = """
    CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
    CREATE TABLE nodes (
        id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, display_name TEXT NOT NULL,
        payload BLOB NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL,
        source_hash TEXT, last_indexed_at REAL NOT NULL, canonical_hash TEXT NOT NULL
    );
    CREATE TABLE edges (
        id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL,
        from_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        to_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        weight REAL NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL,
        updated_at REAL NOT NULL, source_hash TEXT, last_indexed_at REAL NOT NULL,
        canonical_hash TEXT NOT NULL
    );
    CREATE TABLE source_anchors (
        id TEXT PRIMARY KEY NOT NULL,
        source_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        relative_path TEXT NOT NULL, locator TEXT NOT NULL, excerpt TEXT,
        source_hash TEXT NOT NULL, canonical_hash TEXT NOT NULL
    );
    CREATE TABLE citation_occurrences (
        id TEXT PRIMARY KEY NOT NULL,
        edge_id TEXT NOT NULL REFERENCES edges(id) ON DELETE CASCADE,
        source_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        target_node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
        evidence_source TEXT NOT NULL, bibtex_key TEXT, raw_text TEXT NOT NULL,
        ordinal INTEGER NOT NULL, source_hash TEXT NOT NULL,
        anchor_id TEXT REFERENCES source_anchors(id) ON DELETE SET NULL,
        canonical_hash TEXT NOT NULL
    );
    PRAGMA user_version = 2;
    """
}

private struct GraphTestFixture {
    let rootURL: URL

    var root: ResearchRoot { ResearchRoot(rootURL: rootURL) }
    var graphDirectory: URL { root.fileURL(for: GraphRepository.directoryRelativePath) }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct TestLegacyGraphSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case nodes
        case edges
    }
}
