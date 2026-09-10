import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runKnowledge() async {
        await runCheck("markdownSnippetRepositoryLoadsWorkspaceSnippets") { try await markdownSnippetRepositoryLoadsWorkspaceSnippets() }
        await runCheck("authorizedResourceProviderListsAndReadsDocuments") { try await authorizedResourceProviderListsAndReadsDocuments() }
        await runCheck("authorizedResourceProviderIndexesLegacyRawPaperMarkdown") { try await authorizedResourceProviderIndexesLegacyRawPaperMarkdown() }
        await runCheck("embeddingIndexControllerRebuildsSelectedSource") { try await embeddingIndexControllerRebuildsSelectedSource() }
        await runCheck("embeddingIndexControllerRebuildsLegacyRawPaperSource") { try await embeddingIndexControllerRebuildsLegacyRawPaperSource() }
        await runCheck("embeddingFallbackUsesFTSWhenDisabled") { try embeddingFallbackUsesFTSWhenDisabled() }
        await runCheck("embeddingStorePersistsAndMarksMigrationRequired") { try await embeddingStorePersistsAndMarksMigrationRequired() }
        await runCheck("wikiPageGenerationWritesTemplateAndUpdatesMetadata") { try await wikiPageGenerationWritesTemplateAndUpdatesMetadata() }
        await runCheck("wikiPageGenerationRejectsSilentOverwrite") { try await wikiPageGenerationRejectsSilentOverwrite() }
        await runCheck("markdownRepositoryLoadsAndSavesDocuments") { try await markdownRepositoryLoadsAndSavesDocuments() }
        await runCheck("markdownRepositoryCreatesPageInsideWikiRoot") { try await markdownRepositoryCreatesPageInsideWikiRoot() }
        await runCheck("markdownRepositoryRejectsAbsolutePath") { try await markdownRepositoryRejectsAbsolutePath() }
        await runCheck("markdownRepositoryRenamesSelectedPage") { try await markdownRepositoryRenamesSelectedPage() }
        await runCheck("markdownRepositoryArchivesPageInsteadOfHardDelete") { try await markdownRepositoryArchivesPageInsteadOfHardDelete() }
    }

    func markdownSnippetRepositoryLoadsWorkspaceSnippets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
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
        try expect(defaultSnippets.contains(where: { $0.trigger == ";eq" }), "Default snippets should include an equation trigger.")

        let customSnippets = """
        snippets:
          - trigger: ";thm"
            title: "Theorem"
            body: |
              **Theorem.** ${cursor}
        """
        try customSnippets.write(to: workspace.markdownSnippetsURL, atomically: true, encoding: .utf8)

        let loadedSnippets = try await repository.load(in: workspace)
        try expect(loadedSnippets == [MarkdownSnippet(trigger: ";thm", title: "Theorem", body: "**Theorem.** ${cursor}")], "Markdown snippet repository should load custom workspace snippets.")
    }

    func authorizedResourceProviderListsAndReadsDocuments() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/demo-paper/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nThis paper studies evaporation rate evidence.\n# Method\nThe method is line anchored.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let snapshot = try require(documents.first(where: { $0.relativePath == "library/papers/demo-paper/paper.md" }), "Authorized resources should include converted paper.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(resourceID: snapshot.resourceID, maxBytes: 1_048_576, maxCharacters: 24), in: fixture.root)

        try expect(snapshot.sourceType == "paper", "paper.md should be classified as paper source type.")
        try expect(response.contentHash == snapshot.contentHash, "resources/read should return the snapshot content hash.")
        try expect(response.truncated, "resources/read should mark content truncated when maxCharacters is exceeded.")
    }

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
        let paperSnapshot = try require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/paper.md" }), "Authorized resources should include legacy raw/papers paper.md.")
        let annotationsSnapshot = try require(documents.first(where: { $0.relativePath == "raw/papers/Legacy/demo-paper/annotations.md" }), "Authorized resources should include legacy raw/papers annotations.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(relativePath: "raw/papers/Legacy/demo-paper/paper.md", maxCharacters: 120), in: fixture.root)

        try expect(AgentAuthorizedResourceProvider.defaultAllowedRoots.contains("raw/papers"), "Default allowed roots should include legacy raw/papers.")
        try expect(paperSnapshot.sourceType == "paper", "Legacy raw/papers paper.md should be classified as paper source type.")
        try expect(annotationsSnapshot.sourceType == "paper_annotations", "Legacy raw/papers annotations.md should be classified as paper annotations.")
        try expect(response.content.contains("Legacy raw paper abstract evidence"), "resources/read should read legacy raw/papers paper.md content.")
    }

    func embeddingIndexControllerRebuildsSelectedSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/p37/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Retrieval\nPersistent local embedding retrieval evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("library/papers/p37/paper.md", in: fixture.root)
        let indexURL = fixture.root.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath).appendingPathComponent("deterministic_fallback_chunks.json", isDirectory: false)

        try expect(status.status.uiStatus == .fallback, "Selected source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try expect(status.chunkCount > 0, "Selected source rebuild should write chunks to the local index.")
        try expect(FileManager.default.fileExists(atPath: indexURL.path), "Embedding fallback index should be persisted under .sci-station/index/embeddings.")
    }

    func embeddingIndexControllerRebuildsLegacyRawPaperSource() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EmbeddingLegacyRawIndexControllerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "raw/papers/Legacy/p39/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Abstract\nLegacy raw retrieval evidence should become chunks.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let controller = AgentEmbeddingIndexController()
        let status = await controller.rebuildSelectedSource("raw/papers/Legacy/p39/paper.md", in: fixture.root)

        try expect(status.status.uiStatus == .fallback, "Legacy raw source rebuild should use deterministic fallback when sqlite-vec is unavailable.")
        try expect(status.chunkCount > 0, "Legacy raw paper.md rebuild should produce chunks.")
        try expect(status.diagnosticText.contains("Fallback deterministic retrieval"), "Diagnostics should explain deterministic fallback retrieval.")
    }

    func embeddingFallbackUsesFTSWhenDisabled() throws {
        let configuration = AgentEmbeddingRetrievalConfiguration(enabled: false, provider: "swift-proxy", model: "embedding-test", dimension: 3, store: "sqlite-vec")

        try expect(configuration.usesFTSFallback, "Embedding retrieval should preserve FTS-only fallback when disabled.")
        try expect(configuration.store == "sqlite-vec", "Embedding retrieval config should preserve local store selection.")
    }

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

        try expect(fresh.first?.sourceHashStatus == .fresh, "Embedding store should mark matching source hashes fresh.")
        try expect(stale.first?.sourceHashStatus == .stale, "Embedding store should mark changed source hashes stale.")
        try expect(health.status == .migrationRequired, "Embedding model_id changes should require rebuild/migration.")
        try expect(health.staleCount == 1, "Model mismatch should report stale chunk count.")
    }

    func wikiPageGenerationWritesTemplateAndUpdatesMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
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

        try expect(FileManager.default.fileExists(atPath: result.fileURL.path), "Wiki page should be written to wiki/papers.")
        let wikiContents = try String(contentsOf: result.fileURL, encoding: .utf8)
        try expect(wikiContents.contains("type: paper"), "Wiki page should contain paper frontmatter.")
        try expect(wikiContents.contains("source_pdf: \"../../library/papers/Uncategorized/smith2024-graph-rag/paper.pdf\""), "Wiki page should contain source_pdf path.")
        try expect(wikiContents.contains("## TL;DR"), "Wiki page should contain summary sections.")

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected saved paper metadata to remain loadable after wiki generation."
        )
        try expect(
            loadedPaper.notesSummaryRelativePath == "../../../../wiki/papers/smith2024graph.md",
            "Wiki generation should persist notes.summary_file back to meta.yaml."
        )
    }

    func wikiPageGenerationRejectsSilentOverwrite() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
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
            throw ValidationError(message: "Generating an existing wiki page should not silently overwrite the file.")
        } catch let error as WikiPageGeneratorError {
            switch error {
            case let .alreadyExists(path):
                try expect(path == "wiki/papers/smith2024graph.md", "alreadyExists should report the existing wiki path.")
            }
        }
    }

    func markdownRepositoryLoadsAndSavesDocuments() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MarkdownWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pageRelativePath = "wiki/concepts/rag.md"
        let savedDocument = try await repository.saveContents(
            """
            ---
            title: "Retrieval Augmented Generation"
            tags:
              - "rag"
            ---

            # Retrieval Augmented Generation

            See [[Knowledge Graph]].
            """,
            relativePath: pageRelativePath,
            in: workspace
        )

        try expect(savedDocument.title == "Retrieval Augmented Generation", "MarkdownRepository should resolve titles from frontmatter.")
        try expect(savedDocument.outgoingLinks.map(\.target) == ["Knowledge Graph"], "MarkdownRepository should parse wikilinks when loading documents.")

        let loadedDocuments = try await repository.loadDocuments(in: workspace)
        try expect(loadedDocuments.contains(where: { $0.relativePath == pageRelativePath }), "MarkdownRepository should scan wiki/ for markdown files.")

        let paperMarkdownPath = "library/papers/Uncategorized/demo-paper/paper.md"
        let paperMarkdownURL = workspace.fileURL(for: paperMarkdownPath)
        try FileManager.default.createDirectory(at: paperMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        title: "Converted Demo Paper"
        ---

        # Converted Demo Paper

        This file lives outside wiki/ but should still be viewable from the Markdown editor.
        """.write(to: paperMarkdownURL, atomically: true, encoding: .utf8)
        let paperDocument = try await repository.loadDocument(relativePath: paperMarkdownPath, in: workspace)

        try expect(paperDocument.relativePath == paperMarkdownPath, "MarkdownRepository should load a specific converted paper.md outside wiki/ for preview/editing.")
        try expect(paperDocument.title == "Converted Demo Paper", "MarkdownRepository should parse frontmatter for external Markdown documents.")
    }

    func markdownRepositoryCreatesPageInsideWikiRoot() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownCreateWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/new-page", contents: "# New Page\n", in: fixture.workspace)

        try expect(document.relativePath == "wiki/notes/new-page.md", "MarkdownRepository should default new pages to .md inside wiki root.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Created wiki page should exist on disk.")
    }

    func markdownRepositoryRejectsAbsolutePath() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownAbsolutePathWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        do {
            _ = try await fixture.repository.createDocument(relativePath: "/wiki/escape.md", contents: "# Escape\n", in: fixture.workspace)
            throw ValidationError(message: "MarkdownRepository should reject absolute paths.")
        } catch MarkdownRepositoryError.invalidRelativePath {
        }
    }

    func markdownRepositoryRenamesSelectedPage() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownRenameWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let original = try await fixture.repository.createDocument(relativePath: "wiki/notes/original.md", contents: "# Original\n", in: fixture.workspace)
        let renamed = try await fixture.repository.renameDocument(relativePath: original.relativePath, toFileName: "renamed.md", in: fixture.workspace)

        try expect(renamed.relativePath == "wiki/notes/renamed.md", "MarkdownRepository should rename a selected page within its folder.")
        try expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: original.relativePath).path), "Renaming should remove the old file path.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: renamed.relativePath).path), "Renaming should create the new file path.")
    }

    func markdownRepositoryArchivesPageInsteadOfHardDelete() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownArchiveWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/archive-me.md", contents: "# Archive Me\n", in: fixture.workspace)
        let trashPath = try await fixture.repository.archiveDocument(relativePath: document.relativePath, in: fixture.workspace, now: Date(timeIntervalSince1970: 1_777_000_000))

        try expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Archiving should move the active wiki file away from its original path.")
        try expect(trashPath.hasPrefix(".sci-station/trash/wiki/"), "Archived wiki pages should move into the workspace trash area.")
        try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: trashPath).path), "Archived wiki file should remain recoverable from trash.")
    }
}
