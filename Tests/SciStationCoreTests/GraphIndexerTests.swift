import Foundation
import Testing
@testable import SciStationCore

@Suite("Graph indexing", .serialized)
struct GraphIndexerTests {
    @Test("First rebuild creates project edges, updates changed fields, and supports ID reuse")
    func rebuildReconcilesPaperLifecycle() async throws {
        let project = project(id: "project-a", name: "Project A")
        let fixture = try await GraphFixture.make(projects: [project])
        defer { fixture.remove() }

        var paper = samplePaper(
            id: "paper-a",
            citekey: "alpha2026",
            title: "Alpha",
            doi: "10.1000/alpha",
            projectIDs: [project.id]
        )
        paper = try await fixture.paperRepository.save(paper, in: fixture.workspace)

        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        var snapshot = await fixture.repository.snapshot()
        let paperNodeID = "paper:\(paper.resolvedGraphNodeID)"
        let projectNodeID = "project:\(project.id)"
        let belongsToID = GraphEdge.computeID(from: paperNodeID, kind: .belongsTo, to: projectNodeID)
        #expect(snapshot.node(id: paperNodeID) != nil)
        #expect(snapshot.node(id: projectNodeID) != nil)
        #expect(snapshot.edge(id: belongsToID) != nil)

        let originalHash = try #require(snapshot.node(id: paperNodeID)?.sourceHash)
        paper.citekey = "alpha-renamed-2026"
        paper.status = .deepRead
        paper = try await fixture.paperRepository.save(paper, in: fixture.workspace)
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        snapshot = await fixture.repository.snapshot()
        #expect(snapshot.node(id: paperNodeID)?.sourceHash != originalHash)
        #expect(snapshot.node(id: paperNodeID)?.payload.objectValue?["citekey"]?.stringValue == "alpha-renamed-2026")
        #expect(snapshot.node(id: paperNodeID)?.payload.objectValue?["status"]?.stringValue == ReadingStatus.deepRead.rawValue)

        try await fixture.paperRepository.delete(paper, in: fixture.workspace)
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        snapshot = await fixture.repository.snapshot()
        #expect(snapshot.node(id: paperNodeID) == nil)
        #expect(snapshot.edge(id: belongsToID) == nil)

        paper = try await fixture.paperRepository.save(paper, in: fixture.workspace)
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        #expect(await fixture.repository.node(id: paperNodeID) != nil)

        await fixture.repository.close()
        let reopened = GraphRepository()
        try await reopened.open(in: fixture.root)
        #expect(await reopened.node(id: paperNodeID) != nil)
        #expect(await reopened.edge(id: belongsToID) != nil)
        await reopened.close()
    }

    @Test("Repeated citations preserve occurrences and clearing references removes evidence")
    func citationOccurrencesAreLosslessAndReconciled() async throws {
        let fixture = try await GraphFixture.make(projects: [])
        defer { fixture.remove() }

        var source = samplePaper(
            id: "source",
            citekey: "source2026",
            title: "Source Paper",
            doi: "10.1000/source"
        )
        var target = samplePaper(
            id: "target",
            citekey: "target2025",
            title: "Target Paper",
            doi: "10.1000/target"
        )
        source = try await fixture.paperRepository.save(source, in: fixture.workspace)
        target = try await fixture.paperRepository.save(target, in: fixture.workspace)
        try fixture.write(
            """
            # Source Paper

            ## References
            - Target, T. \"Target Paper\". doi:10.1000/target
            - Target, T. \"Target Paper\". doi:10.1000/target
            """,
            to: source.rawMarkdownURL(in: fixture.workspace)
        )

        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        var snapshot = await fixture.repository.snapshot()
        let sourceNodeID = "paper:\(source.resolvedGraphNodeID)"
        let targetNodeID = "paper:\(target.resolvedGraphNodeID)"
        let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .cites, to: targetNodeID)
        #expect(snapshot.edge(id: edgeID) != nil)
        #expect(snapshot.citationOccurrences.values.filter { $0.edgeID == edgeID }.count == 2)
        #expect(snapshot.sourceAnchors.values.filter { $0.sourceNodeID == sourceNodeID }.count == 2)

        try fixture.write("# Source Paper\n\nNo references remain.\n", to: source.rawMarkdownURL(in: fixture.workspace))
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        snapshot = await fixture.repository.snapshot()
        #expect(snapshot.edge(id: edgeID) == nil)
        #expect(snapshot.citationOccurrences.values.allSatisfy { $0.sourceNodeID != sourceNodeID })
        #expect(snapshot.sourceAnchors.values.allSatisfy { $0.sourceNodeID != sourceNodeID })
        await fixture.repository.close()
    }

    @Test("Project-scoped concepts do not collide and rebuilds are deterministic")
    func scopedWikiGraphIsDeterministic() async throws {
        let firstProject = project(id: "first", name: "First")
        let secondProject = project(id: "second", name: "Second")
        let fixture = try await GraphFixture.make(projects: [secondProject, firstProject])
        defer { fixture.remove() }

        try fixture.write(
            "# C++\n\nUses [[method:Solver]].\n",
            relativePath: "projects/first/wiki/concepts/c-plus-plus.md"
        )
        try fixture.write(
            "# C++\n\nUses [[method:Solver]].\n",
            relativePath: "projects/second/wiki/concepts/c-plus-plus.md"
        )
        try fixture.write("# C\n", relativePath: "projects/first/wiki/concepts/c.md")
        try fixture.write("# C#\n", relativePath: "projects/first/wiki/concepts/c-sharp.md")

        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        let firstSnapshot = await fixture.repository.snapshot()
        let firstScope = "project:first"
        let secondScope = "project:second"
        let firstCPP = GraphIdentifier.scopedEntityID(kind: .concept, name: "C++", scope: firstScope)
        let secondCPP = GraphIdentifier.scopedEntityID(kind: .concept, name: "C++", scope: secondScope)
        let plainC = GraphIdentifier.scopedEntityID(kind: .concept, name: "C", scope: firstScope)
        let sharpC = GraphIdentifier.scopedEntityID(kind: .concept, name: "C#", scope: firstScope)
        #expect(firstCPP != secondCPP)
        #expect(plainC != sharpC)
        #expect(firstSnapshot.node(id: firstCPP) != nil)
        #expect(firstSnapshot.node(id: secondCPP) != nil)
        #expect(firstSnapshot.node(id: plainC) != nil)
        #expect(firstSnapshot.node(id: sharpC) != nil)
        #expect(firstSnapshot.edges.values.filter { $0.kind == .mentions }.count == 2)

        let firstNodeHashes = canonicalNodeHashes(firstSnapshot)
        let firstEdgeHashes = canonicalEdgeHashes(firstSnapshot)
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        let secondSnapshot = await fixture.repository.snapshot()
        #expect(canonicalNodeHashes(secondSnapshot) == firstNodeHashes)
        #expect(canonicalEdgeHashes(secondSnapshot) == firstEdgeHashes)

        try FileManager.default.removeItem(
            at: fixture.workspace.fileURL(for: "projects/first/wiki/concepts/c-plus-plus.md")
        )
        try await fixture.indexer.run(in: fixture.workspace, root: fixture.root)
        let afterDeletion = await fixture.repository.snapshot()
        #expect(afterDeletion.node(id: firstCPP) == nil)
        #expect(afterDeletion.edges.values.allSatisfy { $0.from != firstCPP && $0.to != firstCPP })

        await fixture.repository.close()
        let reopened = GraphRepository()
        try await reopened.open(in: fixture.root)
        let reopenedSnapshot = await reopened.snapshot()
        #expect(canonicalNodeHashes(reopenedSnapshot) == canonicalNodeHashes(afterDeletion))
        #expect(canonicalEdgeHashes(reopenedSnapshot) == canonicalEdgeHashes(afterDeletion))
        await reopened.close()
    }

    private func project(id: String, name: String) -> ResearchProject {
        ResearchProject(id: id, name: name, relativePath: "projects/\(id)")
    }

    private func samplePaper(
        id: String,
        citekey: String,
        title: String,
        doi: String,
        projectIDs: [String] = []
    ) -> Paper {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Paper(
            id: id,
            citekey: citekey,
            title: title,
            authors: ["Ada Lovelace"],
            year: 2026,
            venue: nil,
            doi: doi,
            arxiv: nil,
            url: nil,
            collectionPath: "Uncategorized",
            projectIDs: projectIDs,
            pdfRelativePath: nil,
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/Uncategorized/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    private func canonicalNodeHashes(_ snapshot: GraphSnapshot) -> [String: String] {
        snapshot.nodes.mapValues(\.canonicalContentHash)
    }

    private func canonicalEdgeHashes(_ snapshot: GraphSnapshot) -> [String: String] {
        snapshot.edges.mapValues(\.canonicalContentHash)
    }
}

private struct GraphFixture {
    let containerURL: URL
    let workspace: ResearchWorkspace
    let root: ResearchRoot
    let repository: GraphRepository
    let indexer: GraphIndexer
    let paperRepository: PaperRepository

    static func make(projects: [ResearchProject]) async throws -> GraphFixture {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SciStationGraphIndexerTests-\(UUID().uuidString)", isDirectory: true)
        let workspaceURL = containerURL.appendingPathComponent("Workspace", isDirectory: true)
        let workspace = ResearchWorkspace(rootURL: workspaceURL)
        let root = ResearchRoot(rootURL: workspaceURL)
        let directories = [
            "library/papers",
            "library/refs",
            "raw/papers",
            "wiki/concepts",
            "wiki/methods",
            "tasks",
            ".sci-station"
        ] + projects.flatMap { project in
            [project.relativePath, project.relativePath + "/wiki/concepts", project.relativePath + "/wiki/methods"]
        }
        for path in directories {
            try FileManager.default.createDirectory(at: workspace.directoryURL(for: path), withIntermediateDirectories: true)
        }
        try "todos: []\n".write(to: workspace.fileURL(for: "tasks/todos.yaml"), atomically: true, encoding: .utf8)
        try "% test bibliography\n".write(to: workspace.globalLibraryBibURL, atomically: true, encoding: .utf8)

        let projectRepository = ProjectRegistryRepository()
        try await projectRepository.save(
            ProjectRegistry(lastOpenedProjectID: projects.first?.id, projects: projects),
            in: root
        )
        let paperRepository = PaperRepository()
        let graphRepository = GraphRepository()
        try await graphRepository.open(in: root)
        let indexer = GraphIndexer(
            repository: graphRepository,
            paperRepository: paperRepository,
            projectRegistryRepository: projectRepository
        )
        return GraphFixture(
            containerURL: containerURL,
            workspace: workspace,
            root: root,
            repository: graphRepository,
            indexer: indexer,
            paperRepository: paperRepository
        )
    }

    func write(_ contents: String, relativePath: String) throws {
        try write(contents, to: workspace.fileURL(for: relativePath))
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: containerURL)
    }
}
