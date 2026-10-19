import Foundation
import Testing
@testable import SciStationCore

@Suite("Knowledge repositories")
struct KnowledgeDomainTests {
    @Test
    func markdownSnippetRepositoryLoadsWorkspaceSnippets() async throws {
        let suiteName = "SciStationCoreTests.Knowledge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownSnippetRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("SnippetsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let defaultSnippets = try await repository.load(in: workspace)
        try #require(defaultSnippets.contains(where: { $0.trigger == ";eq" }), "Default snippets should include an equation trigger.")

        let customSnippets = """
        snippets:
          - trigger: ";thm"
            title: "Theorem"
            body: |
              **Theorem.** ${cursor}
        """
        try customSnippets.write(to: workspace.markdownSnippetsURL, atomically: true, encoding: .utf8)

        let loadedSnippets = try await repository.load(in: workspace)
        try #require(loadedSnippets == [MarkdownSnippet(trigger: ";thm", title: "Theorem", body: "**Theorem.** ${cursor}")], "Markdown snippet repository should load custom workspace snippets.")
    }

    @Test
    func authorizedResourceProviderListsAndReadsDocuments() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/demo-paper/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nThis paper studies evaporation rate evidence.\n# Method\nThe method is line anchored.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let snapshot = try #require(documents.first(where: { $0.relativePath == "library/papers/demo-paper/paper.md" }), "Authorized resources should include converted paper.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(resourceID: snapshot.resourceID, maxBytes: 1_048_576, maxCharacters: 24), in: fixture.root)

        try #require(snapshot.sourceType == "paper", "paper.md should be classified as paper source type.")
        try #require(response.contentHash == snapshot.contentHash, "resources/read should return the snapshot content hash.")
        try #require(response.truncated, "resources/read should mark content truncated when maxCharacters is exceeded.")
    }

    @Test
    func authorizedResourceProviderIndexesLegacyRawPaperMarkdown() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedLegacyRawResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "raw/papers/Legacy/demo-paper/paper.md")
        let annotationsURL = fixture.root.fileURL(for: "raw/papers/Legacy/demo-paper/annotations.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Abstract\nLegacy raw paper abstract evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        try "# Notes\nLegacy annotations evidence.\n".write(to: annotationsURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let paperSnapshot = try #require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/paper.md" }), "Authorized resources should include legacy raw/papers paper.md.")
        let annotationsSnapshot = try #require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/annotations.md" }), "Authorized resources should include legacy raw/papers annotations.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(relativePath: "raw/papers/Legacy/demo-paper/paper.md", maxCharacters: 120), in: fixture.root)

        try #require(AgentAuthorizedResourceProvider.defaultAllowedRoots.contains("raw/papers"), "Default allowed roots should include legacy raw/papers.")
        try #require(paperSnapshot.sourceType == "paper", "Legacy raw/papers paper.md should be classified as paper source type.")
        try #require(annotationsSnapshot.sourceType == "paper_annotations", "Legacy raw/papers annotations.md should be classified as paper annotations.")
        try #require(response.content.contains("Legacy raw paper abstract evidence"), "resources/read should read legacy raw/papers paper.md content.")
    }

    @Test
    func embeddingIndexControllerRebuildsSelectedSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/p37/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Retrieval\nPersistent local embedding retrieval evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("library/papers/p37/paper.md", in: fixture.root)
        let indexURL = fixture.root.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath).appendingPathComponent("deterministic_fallback_chunks.json", isDirectory: false)

        try #require(status.status.uiStatus == .fallback, "Selected source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try #require(status.chunkCount > 0, "Selected source rebuild should write chunks to the local index.")
        try #require(FileManager.default.fileExists(atPath: indexURL.path), "Embedding fallback index should be persisted under .sci-station/index/embeddings.")
    }

    @Test
    func embeddingIndexControllerRebuildsLegacyRawPaperSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingLegacyRawIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "raw/papers/Legacy/p39/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Abstract\nLegacy raw retrieval evidence should become chunks.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("raw/papers/Legacy/p39/paper.md", in: fixture.root)

        try #require(status.status.uiStatus == .fallback, "Legacy raw source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try #require(status.chunkCount > 0, "Legacy raw paper.md rebuild should produce chunks.")
        try #require(status.diagnosticText.contains("Fallback deterministic retrieval"), "Diagnostics should explain deterministic fallback retrieval.")
    }

    @Test
    func embeddingFallbackUsesFTSWhenDisabled() throws {
        let configuration = AgentEmbeddingRetrievalConfiguration(enabled: false, provider: "swift-proxy", model: "embedding-test", dimension: 3, store: "sqlite-vec")

        try #require(configuration.usesFTSFallback, "Embedding retrieval should preserve FTS-only fallback when disabled.")
        try #require(configuration.store == "sqlite-vec", "Embedding retrieval config should preserve local store selection.")
    }

    @Test
    func embeddingStorePersistsAndMarksMigrationRequired() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingStoreWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let content = "# Retrieval\nPersistent embedding chunks should be stale after source changes.\n"
        let snapshot = IndexableDocumentSnapshot(
            resourceID: "paper:p37:library/papers/p37/paper.md",
            relativePath: "library/papers/p37/paper.md",
            sourceType: "paper",
            sourceID: "p37",
            updatedAt: Date(),
            contentHash: AgentEmbeddingHashing.sha256(content)
        )
        let modelA = AgentEmbeddingModelIdentity(modelID: "model-a", dimension: 32)
        let modelB = AgentEmbeddingModelIdentity(modelID: "model-b", dimension: 32)
        let store = AgentDeterministicEmbeddingStore(indexDirectoryURL: fixture.root.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath), fallbackReason: "test fallback")
        try await store.open()
        try await store.beginTransaction()
        try await store.upsertChunks(AgentEmbeddingChunker.chunks(from: snapshot, content: content, model: modelA))
        try await store.commitTransaction()
        let fresh = await store.query("persistent embedding", limit: 3, currentSourceHashes: [snapshot.relativePath: snapshot.contentHash])
        let stale = await store.query("persistent embedding", limit: 3, currentSourceHashes: [snapshot.relativePath: "sha256:changed"])
        let health = await store.healthCheck(model: modelB, schemaVersion: AgentEmbeddingChunker.chunkSchemaVersion)

        try #require(fresh.first?.sourceHashStatus == .fresh, "Embedding store should mark matching source hashes fresh.")
        try #require(stale.first?.sourceHashStatus == .stale, "Embedding store should mark changed source hashes stale.")
        try #require(health.status == .migrationRequired, "Embedding model_id changes should require rebuild/migration.")
        try #require(health.staleCount == 1, "Model mismatch should report stale chunk count.")
    }

    @Test
    func wikiPageGenerationWritesTemplateAndUpdatesMetadata() async throws {
        let suiteName = "SciStationCoreTests.Knowledge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        let result = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        try #require(FileManager.default.fileExists(atPath: result.fileURL.path), "Wiki page should be written to wiki/papers.")
        let wikiContents = try String(contentsOf: result.fileURL, encoding: .utf8)
        try #require(wikiContents.contains("type: paper"), "Wiki page should contain paper frontmatter.")
        try #require(wikiContents.contains("source_pdf: \"../../library/papers/Uncategorized/smith2024-graph-rag/paper.pdf\""), "Wiki page should contain source_pdf path.")
        try #require(wikiContents.contains("## TL;DR"), "Wiki page should contain summary sections.")

        let loadedPaper = try #require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected saved paper metadata to remain loadable after wiki generation."
        )
        try #require(
            loadedPaper.notesSummaryRelativePath == "../../../../wiki/papers/smith2024graph.md",
            "Wiki generation should persist notes.summary_file back to meta.yaml."
        )
    }

    @Test
    func wikiPageGenerationRejectsSilentOverwrite() async throws {
        let suiteName = "SciStationCoreTests.Knowledge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiConflictWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        do {
            _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)
            Issue.record("Generating an existing wiki page should not silently overwrite the file.")
        } catch let error as WikiPageGeneratorError {
            switch error {
            case let .alreadyExists(path):
                try #require(path == "wiki/papers/smith2024graph.md", "alreadyExists should report the existing wiki path.")
            }
        }
    }

    struct LoopWorkspaceFixture {
        let workspace: ResearchWorkspace
        let root: ResearchRoot
        let suiteName: String
        let containerURL: URL
    }

    func loopWorkspaceFixture(named name: String) async throws -> LoopWorkspaceFixture {
        let suiteName = "SciStationCoreTests.Knowledge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let containerURL = temporaryDirectoryURL()
        let workspaceURL = containerURL.appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        return LoopWorkspaceFixture(
            workspace: workspace,
            root: ResearchRoot(rootURL: workspace.rootURL),
            suiteName: suiteName,
            containerURL: containerURL
        )
    }

    func cleanupLoopWorkspaceFixture(_ fixture: LoopWorkspaceFixture) {
        try? FileManager.default.removeItem(at: fixture.containerURL)
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    func samplePaper(id: String) -> Paper {
        Paper(
            id: id,
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["rag"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    func temporaryDirectoryURL() -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

}
