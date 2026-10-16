import Foundation
import Testing
@testable import SciStationCore

@Suite("Markdown repository")
struct MarkdownRepositoryTests {
    @Test
    func markdownRepositoryLoadsAndSavesDocuments() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }
        let repository = fixture.repository
        let workspace = fixture.workspace
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

        #expect(savedDocument.title == "Retrieval Augmented Generation", "MarkdownRepository should resolve titles from frontmatter.")
        #expect(savedDocument.outgoingLinks.map(\.target) == ["Knowledge Graph"], "MarkdownRepository should parse wikilinks when loading documents.")

        let loadedDocuments = try await repository.loadDocuments(in: workspace)
        #expect(loadedDocuments.contains(where: { $0.relativePath == pageRelativePath }), "MarkdownRepository should scan wiki/ for markdown files.")

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

        #expect(paperDocument.relativePath == paperMarkdownPath, "MarkdownRepository should load a specific converted paper.md outside wiki/ for preview/editing.")
        #expect(paperDocument.title == "Converted Demo Paper", "MarkdownRepository should parse frontmatter for external Markdown documents.")
    }

    @Test
    func markdownRepositoryCreatesPageInsideWikiRoot() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownCreateWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/new-page", contents: "# New Page\n", in: fixture.workspace)

        #expect(document.relativePath == "wiki/notes/new-page.md", "MarkdownRepository should default new pages to .md inside wiki root.")
        #expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Created wiki page should exist on disk.")
    }

    @Test
    func markdownRepositoryRejectsAbsolutePath() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownAbsolutePathWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        do {
            _ = try await fixture.repository.createDocument(relativePath: "/wiki/escape.md", contents: "# Escape\n", in: fixture.workspace)
            Issue.record("MarkdownRepository should reject absolute paths.")
        } catch MarkdownRepositoryError.invalidRelativePath {
        }
    }

    @Test
    func markdownRepositoryRenamesSelectedPage() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownRenameWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let original = try await fixture.repository.createDocument(relativePath: "wiki/notes/original.md", contents: "# Original\n", in: fixture.workspace)
        let renamed = try await fixture.repository.renameDocument(relativePath: original.relativePath, toFileName: "renamed.md", in: fixture.workspace)

        #expect(renamed.relativePath == "wiki/notes/renamed.md", "MarkdownRepository should rename a selected page within its folder.")
        #expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: original.relativePath).path), "Renaming should remove the old file path.")
        #expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: renamed.relativePath).path), "Renaming should create the new file path.")
    }

    @Test
    func markdownRepositoryArchivesPageInsteadOfHardDelete() async throws {
        let fixture = try await markdownRepositoryFixture(named: "MarkdownArchiveWorkspace")
        defer { cleanupMarkdownRepositoryFixture(fixture) }

        let document = try await fixture.repository.createDocument(relativePath: "wiki/notes/archive-me.md", contents: "# Archive Me\n", in: fixture.workspace)
        let trashPath = try await fixture.repository.archiveDocument(relativePath: document.relativePath, in: fixture.workspace, now: Date(timeIntervalSince1970: 1_777_000_000))

        #expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: document.relativePath).path), "Archiving should move the active wiki file away from its original path.")
        #expect(trashPath.hasPrefix(".sci-station/trash/wiki/"), "Archived wiki pages should move into the workspace trash area.")
        #expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: trashPath).path), "Archived wiki file should remain recoverable from trash.")
    }

    private struct MarkdownRepositoryFixture {
        let workspace: ResearchWorkspace
        let repository: MarkdownRepository
        let defaults: UserDefaults
        let suiteName: String
        let containerURL: URL
    }

    private func markdownRepositoryFixture(named name: String) async throws -> MarkdownRepositoryFixture {
        let suiteName = "SciStationCoreTests.MarkdownRepository.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceRoot = containerURL.appendingPathComponent(name, isDirectory: true)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        do {
            let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
            return MarkdownRepositoryFixture(workspace: workspace, repository: MarkdownRepository(), defaults: defaults, suiteName: suiteName, containerURL: containerURL)
        } catch {
            try? FileManager.default.removeItem(at: containerURL)
            defaults.removePersistentDomain(forName: suiteName)
            throw error
        }
    }

    private func cleanupMarkdownRepositoryFixture(_ fixture: MarkdownRepositoryFixture) {
        try? FileManager.default.removeItem(at: fixture.containerURL)
        fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
    }
}
