import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runGraph() async {
        await runCheck("graphNodeIDDerivationFollowsPriorityOrder") { try graphNodeIDDerivationFollowsPriorityOrder() }
        await runCheck("graphNodeIDResolvedFromPaperInstance") { try graphNodeIDResolvedFromPaperInstance() }
        await runCheck("graphRepositoryAppendsAndReloadsAtomically") { try await graphRepositoryAppendsAndReloadsAtomically() }
        await runCheck("graphRepositoryDropsOrphanEdgesAfterTombstone") { try await graphRepositoryDropsOrphanEdgesAfterTombstone() }
        await runCheck("graphRepositoryCompactPreservesEffectiveState") { try await graphRepositoryCompactPreservesEffectiveState() }
        await runCheck("graphRepositoryCrashRecoveryReplaysJSONL") { try await graphRepositoryCrashRecoveryReplaysJSONL() }
        await runCheck("graphReadModelSubgraphRespectsDepth") { try await graphReadModelSubgraphRespectsDepth() }
        await runCheck("graphReadModelPathReturnsBFSResult") { try await graphReadModelPathReturnsBFSResult() }
        await runCheck("graphAgentToolsExposeReadOnlyDefinitions") { try graphAgentToolsExposeReadOnlyDefinitions() }
        await runCheck("graphToolBackendFindsMissingCorePapers") { try await graphToolBackendFindsMissingCorePapers() }
        await runCheck("graphToolBackendGeneratesReadingPath") { try await graphToolBackendGeneratesReadingPath() }
        await runCheck("graphToolBackendDetectsStaleCitations") { try await graphToolBackendDetectsStaleCitations() }
        await runCheck("graphToolBackendFindsUnsupportedArtifactClaims") { try await graphToolBackendFindsUnsupportedArtifactClaims() }
        await runCheck("graphToolBackendFindsBridgePapers") { try await graphToolBackendFindsBridgePapers() }
        await runCheck("bibtexParserHandlesArticleAndMisc") { try bibtexParserHandlesArticleAndMisc() }
        await runCheck("bibtexParserSkipsMalformedEntry") { try bibtexParserSkipsMalformedEntry() }
        await runCheck("markdownReferencesExtractorReadsSection") { try markdownReferencesExtractorReadsSection() }
        await runCheck("referenceResolverDOIWinsOverTitle") { try referenceResolverDOIWinsOverTitle() }
        await runCheck("referenceResolverProducesExternalOnMiss") { try referenceResolverProducesExternalOnMiss() }
        await runCheck("levenshteinDistanceComputesCorrectly") { try levenshteinDistanceComputesCorrectly() }
        await runCheck("graphLayoutEngineDeterministicWithFixedSeed") { try graphLayoutEngineDeterministicWithFixedSeed() }
        await runCheck("graphLayoutEngineConvergesUnderThreshold") { try graphLayoutEngineConvergesUnderThreshold() }
        await runCheck("subgraphCacheLRUEvictsOldest") { try await subgraphCacheLRUEvictsOldest() }
        await runCheck("citationCriticBlocksUnsupportedClaims") { try citationCriticBlocksUnsupportedClaims() }
    }

    func graphNodeIDDerivationFollowsPriorityOrder() throws {
        let doiBased = PaperIdentityGenerator.graphNodeID(
            doi: "https://doi.org/10.1103/PhysRevD.42.3344",
            arxiv: "2101.12345",
            inspireID: "12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(doiBased == "10.1103/physrevd.42.3344", "DOI should win and be lowercased/trimmed.")

        let arxivBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: "2101.12345v3",
            inspireID: "12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(arxivBased == "arxiv:2101.12345", "arXiv should drop the version suffix.")

        let inspireBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: "https://inspirehep.net/literature/12345",
            citekey: "smith2021abc",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(inspireBased == "inspire:12345", "Inspire URL should reduce to the numeric id.")

        let citekeyBased = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: nil,
            citekey: "Smith2021ABC",
            fallbackPaperID: "smith2021-abc"
        )
        try expect(citekeyBased == "citekey:smith2021abc", "Citekey fallback should be lowercased and prefixed.")

        let localFallback = PaperIdentityGenerator.graphNodeID(
            doi: nil,
            arxiv: nil,
            inspireID: nil,
            citekey: nil,
            fallbackPaperID: "Smith2021-ABC"
        )
        try expect(localFallback == "local:smith2021-abc", "Local fallback should be used when nothing else is available.")
    }

    func graphNodeIDResolvedFromPaperInstance() throws {
        let now = Date()
        let paper = Paper(
            id: "garani2017-dark-matter-sun",
            citekey: "garani2017dark",
            title: "Dark matter in the Sun",
            authors: ["Raghuveer Garani"],
            year: 2017,
            venue: "arXiv",
            doi: nil,
            arxiv: "1702.02768v2",
            url: nil,
            pdfRelativePath: "paper.pdf",
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/Uncategorized/garani2017-dark-matter-sun",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
        try expect(paper.resolvedGraphNodeID == "arxiv:1702.02768", "Paper should resolve graph node id from arXiv without version.")
    }

    func graphRepositoryAppendsAndReloadsAtomically() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphRepoTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        let node = GraphNode(id: "paper:test1", kind: .paper, displayName: "Test Paper", createdAt: now, updatedAt: now, sourceHash: "abc", lastIndexedAt: now)
        try await repo.upsertNode(node)

        let node2 = GraphNode(id: "project:proj1", kind: .project, displayName: "Project 1", createdAt: now, updatedAt: now, sourceHash: "def", lastIndexedAt: now)
        try await repo.upsertNode(node2)

        let edge = GraphEdge(kind: .belongsTo, from: "paper:test1", to: "project:proj1", createdAt: now, updatedAt: now, sourceHash: "ghi", lastIndexedAt: now)
        try await repo.upsertEdge(edge)

        let snap = await repo.snapshot()
        try expect(snap.nodes.count == 2, "GraphRepository should have 2 nodes after upserts.")
        try expect(snap.edges.count == 1, "GraphRepository should have 1 edge after upsert.")

        // Close and reopen — should replay from jsonl.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap2 = await repo2.snapshot()
        try expect(snap2.nodes.count == 2, "GraphRepository should reload 2 nodes from jsonl.")
        try expect(snap2.edges.count == 1, "GraphRepository should reload 1 edge from jsonl.")
        try expect(snap2.node(id: "paper:test1")?.displayName == "Test Paper", "Reloaded node should preserve displayName.")
        await repo2.close()
    }

    func graphRepositoryDropsOrphanEdgesAfterTombstone() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphOrphanTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:a", kind: .paper, displayName: "A", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:b", kind: .paper, displayName: "B", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        try await repo.deleteNode(id: "paper:b")
        let snap = await repo.snapshot()
        try expect(snap.nodes.count == 1, "After deleting node B, only A should remain.")
        try expect(snap.edges.count == 0, "After deleting node B, the incident edge should be removed.")

        // Reopen — tombstone should suppress the edge on replay.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap2 = await repo2.snapshot()
        try expect(snap2.nodes.count == 1, "After replay, only A should remain.")
        try expect(snap2.edges.count == 0, "After replay, orphan edge should be dropped.")
        await repo2.close()
    }

    func graphRepositoryCompactPreservesEffectiveState() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphCompactTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:x", kind: .paper, displayName: "X", createdAt: now, updatedAt: now, sourceHash: "h1", lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:y", kind: .paper, displayName: "Y", createdAt: now, updatedAt: now, sourceHash: "h2", lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:x", to: "paper:y", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let result = try await repo.forceCompact()
        try expect(result.snapshotURL != nil, "Compact should produce a snapshot file.")

        // Reopen after compact — should load from snapshot, not jsonl.
        await repo.close()
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap = await repo2.snapshot()
        try expect(snap.nodes.count == 2, "After compact + reopen, nodes should be preserved.")
        try expect(snap.edges.count == 1, "After compact + reopen, edges should be preserved.")
        await repo2.close()
    }

    func graphRepositoryCrashRecoveryReplaysJSONL() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphCrashTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:crash1", kind: .paper, displayName: "Crash Paper", createdAt: now, updatedAt: now, sourceHash: "c1", lastIndexedAt: now))
        await repo.close()

        // Simulate a crash by appending a damaged line to nodes.jsonl.
        let nodesURL = root.fileURL(for: ".sci-station/graph/nodes.jsonl")
        let existing = try String(contentsOf: nodesURL, encoding: .utf8)
        try (existing + "{not-valid-json}\n").write(to: nodesURL, atomically: true, encoding: .utf8)

        // Reopen — should skip the damaged line and still load the valid node.
        let repo2 = GraphRepository()
        try await repo2.open(in: root)
        let snap = await repo2.snapshot()
        try expect(snap.nodes.count == 1, "Crash recovery should skip damaged lines and load valid nodes.")
        try expect(snap.node(id: "paper:crash1")?.displayName == "Crash Paper", "Valid node should survive crash recovery.")
        await repo2.close()
    }

    func graphReadModelSubgraphRespectsDepth() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphReadModelTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        // Build a chain: A -> B -> C
        try await repo.upsertNode(GraphNode(id: "paper:a", kind: .paper, displayName: "A", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:b", kind: .paper, displayName: "B", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:c", kind: .paper, displayName: "C", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:b", to: "paper:c", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let readModel = GraphReadModel(repository: repo)

        // Depth 1 from A should only reach B.
        let sub1 = await readModel.subgraph(centerNodeID: "paper:a", depth: 1)
        try expect(sub1.nodes.count == 2, "Subgraph depth=1 from A should include A and B.")
        try expect(sub1.edges.count == 1, "Subgraph depth=1 from A should include 1 edge.")

        // Depth 2 from A should reach B and C.
        let sub2 = await readModel.subgraph(centerNodeID: "paper:a", depth: 2)
        try expect(sub2.nodes.count == 3, "Subgraph depth=2 from A should include A, B, and C.")
        try expect(sub2.edges.count == 2, "Subgraph depth=2 from A should include 2 edges.")
        await repo.close()
    }

    func graphReadModelPathReturnsBFSResult() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("GraphPathTest", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)

        let repo = GraphRepository()
        try await repo.open(in: root)

        let now = Date()
        try await repo.upsertNode(GraphNode(id: "paper:s", kind: .paper, displayName: "S", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "concept:dm", kind: .concept, displayName: "Dark Matter", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertNode(GraphNode(id: "paper:t", kind: .paper, displayName: "T", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .mentions, from: "paper:s", to: "concept:dm", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await repo.upsertEdge(GraphEdge(kind: .mentions, from: "paper:t", to: "concept:dm", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let readModel = GraphReadModel(repository: repo)
        let path = await readModel.path(from: "paper:s", to: "paper:t")
        try expect(path != nil, "Path from S to T should exist via concept:dm.")
        try expect(path?.count == 2, "Path should be 2 edges: S->dm, T->dm.")

        let noPath = await readModel.path(from: "paper:s", to: "paper:nonexistent")
        try expect(noPath == nil, "Path to nonexistent node should return nil.")
        await repo.close()
    }

    func graphAgentToolsExposeReadOnlyDefinitions() throws {
        let definitions = GraphAgentTools.makeDefaultTools(paperRepository: PaperRepository(), debugEventLogger: nil).map(\.definition)
        let definitionsByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        try expect(Set(definitionsByName.keys).isSuperset(of: GraphAgentTools.allNames), "Default graph tools should expose all registered graph tool names.")
        for name in GraphAgentTools.allNames {
            guard let definition = definitionsByName[name] else {
                throw ValidationError(message: "Missing graph tool definition for \(name).")
            }
            try expect(definition.risk == .readOnly, "\(name) should be read-only.")
            try expect(definition.requiresConfirmation == false, "\(name) should not require Permission Dock approval.")
            try expect(definition.permissionKey == "graph.read", "\(name) should use graph.read permission key.")
        }
    }

    func graphToolBackendFindsMissingCorePapers() async throws {
        let fixture = try await graphToolFixture(name: "GraphMissingCoreToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        var corePaper = graphPaper(id: "core-paper", graphNodeID: "core-paper", title: "Core Paper", year: 2024, projectID: "proj", isCore: true)
        corePaper = try await fixture.paperRepository.save(corePaper, in: fixture.workspace)
        var linkedPaper = graphPaper(id: "linked-paper", graphNodeID: "linked-paper", title: "Already Linked", year: 2021, projectID: "proj", isCore: false)
        linkedPaper = try await fixture.paperRepository.save(linkedPaper, in: fixture.workspace)

        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:core-paper", kind: .paper, displayName: corePaper.title, payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:missing-paper", kind: .paper, displayName: "Missing Foundational Paper", payload: .object(["year": .number("2020")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:linked-paper", kind: .paper, displayName: linkedPaper.title, payload: .object(["year": .number("2021")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:core-paper", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:linked-paper", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:core-paper", to: "paper:missing-paper", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:core-paper", to: "paper:linked-paper", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findMissingCorePapers(argumentsJSON: #"{"project_id":"proj"}"#, context: fixture.context)
        let object = try jsonObject(result.payload, "Missing core payload should be an object.")
        let rows = object["missing_core_papers"]?.arrayValue ?? []
        try expect(result.succeeded, "Missing core tool should succeed.")
        try expect(result.requiresConfirmation, "Missing core discoveries should create a graph insight draft for review.")
        try expect(rows.count == 1, "Only the unlinked cited paper should be returned.")
        try expect(rows.first?.objectValue?["paper_node_id"]?.stringValue == "paper:missing-paper", "Missing paper node id should match.")
        try expect(object["graph_insight_draft"]?.objectValue?["kind"]?.stringValue == "graph_insight", "Payload should include a nested graph insight draft.")
        await fixture.repo.close()
    }

    func graphToolBackendGeneratesReadingPath() async throws {
        let fixture = try await graphToolFixture(name: "GraphReadingPathToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "paper:foundation", kind: .paper, displayName: "Foundation", payload: .object(["year": .number("2010")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:center", kind: .paper, displayName: "Center", payload: .object(["year": .number("2020")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:followup", kind: .paper, displayName: "Follow Up", payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:center", to: "paper:foundation", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:followup", to: "paper:center", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.generateReadingPath(argumentsJSON: #"{"center_paper_id":"paper:center","k":3}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Reading path payload should be an object.")["reading_path"]?.arrayValue ?? []
        let order = rows.compactMap { $0.objectValue?["paper_node_id"]?.stringValue }
        try expect(order == ["paper:foundation", "paper:center", "paper:followup"], "Reading path should order cited prerequisites before citing follow-ups.")
        await fixture.repo.close()
    }

    func graphToolBackendDetectsStaleCitations() async throws {
        let fixture = try await graphToolFixture(name: "GraphStaleCitationToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:current", kind: .paper, displayName: "Current", payload: .object(["year": .number("2024")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:old", kind: .paper, displayName: "Old Baseline", payload: .object(["year": .number("2000")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "paper:new", kind: .paper, displayName: "New Extension", payload: .object(["year": .number("2023")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "paper:current", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:current", to: "paper:old", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .extends, from: "paper:new", to: "paper:old", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.detectStaleCitations(argumentsJSON: #"{"project_id":"proj","threshold_days":3650}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Stale citation payload should be an object.")["stale_edges"]?.arrayValue ?? []
        try expect(rows.count == 1, "Stale citation detector should flag the old citation with a newer extension.")
        let suggestions = rows.first?.objectValue?["suggested_newer_papers"]?.arrayValue ?? []
        try expect(suggestions.first?.objectValue?["paper_node_id"]?.stringValue == "paper:new", "Stale citation detector should suggest the newer extending paper.")
        await fixture.repo.close()
    }

    func graphToolBackendFindsUnsupportedArtifactClaims() async throws {
        let fixture = try await graphToolFixture(name: "GraphUnsupportedClaimsToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        try await fixture.repo.upsertNode(GraphNode(id: "project:proj", kind: .project, displayName: "Project", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "artifact:one", kind: .artifact, displayName: "Related Work Draft", payload: .object(["status": .string("saved")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "claim:one", kind: .claim, displayName: "Unsupported Claim", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "claim:two", kind: .claim, displayName: "Stale Claim", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertNode(GraphNode(id: "evidence:stale", kind: .evidence, displayName: "Old Evidence", payload: .object(["status": .string("stale")]), createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .belongsTo, from: "artifact:one", to: "project:proj", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .mentions, from: "artifact:one", to: "claim:one", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .mentions, from: "artifact:one", to: "claim:two", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .supports, from: "evidence:stale", to: "claim:two", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findUnsupportedArtifactClaims(argumentsJSON: #"{"project_id":"proj"}"#, context: fixture.context)
        let rows = try jsonObject(result.payload, "Unsupported claims payload should be an object.")["claims"]?.arrayValue ?? []
        let severities = Set(rows.compactMap { $0.objectValue?["severity"]?.stringValue })
        try expect(severities == ["error", "warning"], "Unsupported claims tool should report missing and stale evidence severities.")
        await fixture.repo.close()
    }

    func graphToolBackendFindsBridgePapers() async throws {
        let fixture = try await graphToolFixture(name: "GraphBridgeToolTest")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL.deletingLastPathComponent()) }
        let now = Date()
        for nodeID in ["paper:a", "paper:b", "paper:c"] {
            try await fixture.repo.upsertNode(GraphNode(id: nodeID, kind: .paper, displayName: nodeID, createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        }
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:a", to: "paper:b", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))
        try await fixture.repo.upsertEdge(GraphEdge(kind: .cites, from: "paper:b", to: "paper:c", createdAt: now, updatedAt: now, sourceHash: nil, lastIndexedAt: now))

        let backend = GraphToolBackend(readModel: GraphReadModel(repository: fixture.repo), paperRepository: fixture.paperRepository, debugEventLogger: nil)
        let result = try await backend.findBridgePapers(argumentsJSON: #"{"from_paper_id":"paper:a","to_paper_id":"paper:c"}"#, context: fixture.context)
        let payload = try jsonObject(result.payload, "Bridge payload should be an object.")
        let rows = payload["bridge_papers"]?.arrayValue ?? []
        try expect(payload["path_found"] == .bool(true), "Bridge tool should report path_found=true.")
        try expect(rows.compactMap { $0.objectValue?["paper_node_id"]?.stringValue } == ["paper:a", "paper:b", "paper:c"], "Bridge tool should preserve shortest path paper order.")
        await fixture.repo.close()
    }

    func bibtexParserHandlesArticleAndMisc() throws {
        let bibtex = """
        @article{garani2017dark,
          title = {Dark matter in the Sun: scattering off electrons vs nucleons},
          author = {Raghuveer Garani and Sergio Palomares-Ruiz},
          year = {2017},
          eprint = {1702.02768},
          archivePrefix = {arXiv},
          doi = {10.1088/1475-7516/2017/05/007}
        }

        @misc{nguyen2026sun,
          title = {The Sun Can Strongly Constrain},
          author = {Thong T. Q. Nguyen and Tim Linden},
          year = {2026},
          eprint = {2602.15113}
        }
        """

        let parser = BibtexParser()
        let entries = parser.parse(bibtex)
        try expect(entries.count == 2, "BibtexParser should parse 2 entries.")
        try expect(entries[0].key == "garani2017dark", "First entry key should be garani2017dark.")
        try expect(entries[0].doi == "10.1088/1475-7516/2017/05/007", "First entry should have DOI.")
        try expect(entries[0].arxivID == "1702.02768", "First entry should have arXiv from eprint field.")
        try expect(entries[0].year == 2017, "First entry year should be 2017.")
        try expect(entries[0].firstAuthorLastName == "Garani", "First author last name should be Garani.")
        try expect(entries[1].key == "nguyen2026sun", "Second entry key should be nguyen2026sun.")
        try expect(entries[1].type == "misc", "Second entry type should be misc.")
    }

    func bibtexParserSkipsMalformedEntry() throws {
        let bibtex = """
        @comment{This is a comment block that should be skipped.}

        @article{valid,
          title = {Valid Paper},
          author = {Smith},
          year = {2024}
        }

        @misc{also_valid,
          title = {Also Valid},
          year = {2025}
        }
        """

        let parser = BibtexParser()
        let entries = parser.parse(bibtex)
        try expect(entries.count == 2, "BibtexParser should skip @comment and parse 2 valid entries.")
        try expect(entries[0].key == "valid", "First entry should be 'valid'.")
        try expect(entries[0].title == "Valid Paper", "First entry title should be 'Valid Paper'.")
        try expect(entries[1].key == "also_valid", "Second entry should be 'also_valid'.")
    }

    func markdownReferencesExtractorReadsSection() throws {
        let markdown = """
        # Introduction

        Some text here.

        ## References

        1. Garani, R. & Palomares-Ruiz, S. (2017). Dark matter in the Sun. doi:10.1088/1475-7516/2017/05/007
        2. Nguyen, T. & Linden, T. (2026). The Sun Can Strongly Constrain. arXiv:2602.15113
        - Smith, J. (2024). A third reference without identifiers.

        ## Appendix

        This should not be included.
        """

        let extractor = MarkdownReferencesExtractor()
        let refs = extractor.extract(from: markdown)
        try expect(refs.count == 3, "Extractor should find 3 references.")
        try expect(refs[0].contains("Garani"), "First ref should contain Garani.")
        try expect(refs[1].contains("2602.15113"), "Second ref should contain arXiv id.")
        try expect(refs[2].contains("Smith"), "Third ref should contain Smith.")
    }

    func referenceResolverDOIWinsOverTitle() throws {
        let now = Date()
        let papers = [
            Paper(id: "garani2017", citekey: "garani2017dark", title: "Dark matter in the Sun", authors: ["Raghuveer Garani"], year: 2017, venue: nil, doi: "10.1088/1475-7516/2017/05/007", arxiv: "1702.02768v2", url: nil, pdfRelativePath: nil, tags: [], status: .unread, priority: .medium, rating: nil, useFor: [], createdAt: now, updatedAt: now, paperDirectoryRelativePath: "library/papers/Uncategorized/garani2017", notesSummaryRelativePath: nil, annotationsRelativePath: nil)
        ]
        let index = LocalPaperIndex(papers: papers)
        let resolver = ReferenceResolver()

        // Reference with DOI that matches.
        let ref = CitationReference(
            sourcePaperID: "nguyen2026",
            evidenceSource: .paperMarkdown,
            rawText: "Garani 2017 doi:10.1088/1475-7516/2017/05/007",
            doi: "10.1088/1475-7516/2017/05/007",
            normalizedTitle: "dark matter in the sun"
        )
        let result = resolver.resolve(ref, localIndex: index)
        if case .matchedLocal(let id) = result.outcome {
            try expect(id == "10.1088/1475-7516/2017/05/007", "DOI match should resolve to the local paper's graphNodeID (DOI-based).")
        } else {
            try expect(false, "DOI match should produce .matchedLocal, got \(result.outcome).")
        }
    }

    func referenceResolverProducesExternalOnMiss() throws {
        let index = LocalPaperIndex(papers: [])
        let resolver = ReferenceResolver()

        let ref = CitationReference(
            sourcePaperID: "test",
            evidenceSource: .bibtex,
            rawText: "Unknown paper doi:10.9999/fake",
            doi: "10.9999/fake"
        )
        let result = resolver.resolve(ref, localIndex: index)
        if case .matchedExternal(let nodeID, let source) = result.outcome {
            try expect(nodeID == "paper:external:doi:10.9999/fake", "External node ID should contain the DOI.")
            try expect(source == .doi, "External source should be .doi.")
        } else {
            try expect(false, "Missing DOI should produce .matchedExternal.")
        }

        // No identifiers at all.
        let refNoID = CitationReference(
            sourcePaperID: "test",
            evidenceSource: .paperMarkdown,
            rawText: "Some vague reference"
        )
        let resultNoID = resolver.resolve(refNoID, localIndex: index)
        if case .unresolved(let reason) = resultNoID.outcome {
            try expect(reason == "no_doi_arxiv_or_title", "No identifiers should produce unresolved.")
        } else {
            try expect(false, "No identifiers should produce .unresolved.")
        }
    }

    func levenshteinDistanceComputesCorrectly() throws {
        try expect(Levenshtein.distance("kitten", "sitting") == 3, "Levenshtein(kitten, sitting) should be 3.")
        try expect(Levenshtein.distance("", "abc") == 3, "Levenshtein('', abc) should be 3.")
        try expect(Levenshtein.distance("abc", "abc") == 0, "Levenshtein(abc, abc) should be 0.")
        try expect(Levenshtein.distance("dark matter", "dark mater") == 1, "Levenshtein with 1 char diff should be 1.")
    }

    func graphLayoutEngineDeterministicWithFixedSeed() throws {
        let nodes: [GraphNode] = (0..<5).map { i in
            GraphNode(id: "paper:p\(i)", kind: .paper, displayName: "Paper \(i)", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        }
        let edges: [GraphEdge] = [
            GraphEdge(kind: .cites, from: "paper:p0", to: "paper:p1", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .cites, from: "paper:p1", to: "paper:p2", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .mentions, from: "paper:p2", to: "paper:p3", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .cites, from: "paper:p3", to: "paper:p4", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        ]
        let subgraph = GraphSubgraph(center: "paper:p0", nodes: nodes, edges: edges)
        let engine = GraphLayoutEngine()

        let result1 = engine.layout(subgraph, canvasWidth: 800, canvasHeight: 600, seed: 42)
        let result2 = engine.layout(subgraph, canvasWidth: 800, canvasHeight: 600, seed: 42)

        try expect(result1.positions.count == 5, "Layout should produce positions for all 5 nodes.")
        for (id, pos1) in result1.positions {
            guard let pos2 = result2.positions[id] else {
                try expect(false, "Second run should have position for \(id).")
                continue
            }
            try expect(abs(pos1.x - pos2.x) < 0.001 && abs(pos1.y - pos2.y) < 0.001, "Layout should be deterministic for node \(id).")
        }
    }

    func graphLayoutEngineConvergesUnderThreshold() throws {
        let nodes: [GraphNode] = (0..<3).map { i in
            GraphNode(id: "n\(i)", kind: .concept, displayName: "C\(i)", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        }
        let edges: [GraphEdge] = [
            GraphEdge(kind: .mentions, from: "n0", to: "n1", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date()),
            GraphEdge(kind: .mentions, from: "n1", to: "n2", createdAt: Date(), updatedAt: Date(), sourceHash: nil, lastIndexedAt: Date())
        ]
        let subgraph = GraphSubgraph(center: "n0", nodes: nodes, edges: edges)
        let engine = GraphLayoutEngine()
        let result = engine.layout(subgraph, canvasWidth: 600, canvasHeight: 400, seed: 7)

        try expect(result.settled, "Layout with 3 nodes should converge (settled=true).")
        try expect(result.iterations < 200, "Layout should converge before max iterations.")
    }

    func subgraphCacheLRUEvictsOldest() async throws {
        let cache = SubgraphCache(capacity: 3)
        let emptySubgraph = GraphSubgraph(center: "x", nodes: [], edges: [])

        let key1 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "a", depth: 1, kindFilter: [])
        let key2 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "b", depth: 1, kindFilter: [])
        let key3 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "c", depth: 1, kindFilter: [])
        let key4 = SubgraphCache.Key(viewKind: .paperNeighborhood, centerNodeID: "d", depth: 1, kindFilter: [])

        await cache.put(key1, emptySubgraph)
        await cache.put(key2, emptySubgraph)
        await cache.put(key3, emptySubgraph)
        let count1 = await cache.count
        try expect(count1 == 3, "Cache should have 3 entries.")

        await cache.put(key4, emptySubgraph)
        let count2 = await cache.count
        try expect(count2 == 3, "Cache should evict oldest to stay at capacity 3.")
        let evicted = await cache.get(key1)
        try expect(evicted == nil, "Oldest entry (key1) should be evicted.")
        let newest = await cache.get(key4)
        try expect(newest != nil, "Newest entry (key4) should be present.")

        await cache.invalidateAll()
        let count3 = await cache.count
        try expect(count3 == 0, "invalidateAll should clear all entries.")
    }

    func citationCriticBlocksUnsupportedClaims() throws {
        let report = AgentCitationCriticReport(
            unsupportedClaims: [.object(["claim": .string("Unsupported core claim")])],
            requiredRevisions: ["Core scientific claims must cite evidence before final approval."],
            canRequestApproval: false
        )

        try expect(report.blocksFinalApproval, "Citation critic report should block final approval when unsupported claims exist.")
    }
}
