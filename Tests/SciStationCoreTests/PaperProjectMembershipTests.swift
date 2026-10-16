import Foundation
import Testing
@testable import SciStationCore

@Suite("Paper project membership")
struct PaperProjectMembershipTests {
    @Test("Membership, core and pinned mutations use persisted links and preserve extensions")
    func associationChanges() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try await fixture.useCase.apply(.membership(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.useCase.apply(.pinned(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.links.updateUseFor(["discussion"], projectID: "alpha", paperID: "paper", in: fixture.workspace)
        var linkMapping = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fixture.workspace.projectPaperLinksURL, encoding: .utf8))
        var linkFields = try #require(linkMapping["links"]?.arrayElements?.first?.objectValue)
        linkFields["extension"] = .object(["verified": .boolean(true)])
        linkMapping["links"] = .array([.object(linkFields)])
        linkMapping["custom_root"] = .array([.integer(7)])
        try StandardsYAMLEncoder.encodeMapping(linkMapping).write(to: fixture.workspace.projectPaperLinksURL, atomically: true, encoding: .utf8)

        // Adding an existing member must not replace its richer repository link.
        try await fixture.useCase.apply(.membership(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        let link = try #require(await fixture.links.link(forPaperID: "paper", projectID: "alpha", in: fixture.workspace))
        #expect(link.isCore && link.isPinned)
        #expect(link.useFor == ["discussion"])
        let persistedLinks = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fixture.workspace.projectPaperLinksURL, encoding: .utf8))
        #expect(persistedLinks["custom_root"] == .array([.integer(7)]))
        #expect(persistedLinks["links"]?.arrayElements?.first?.objectValue?["extension"] == .object(["verified": .boolean(true)]))
        let mapping = try fixture.metadata()
        #expect(mapping["project_ids"] == .array([.string("alpha")]))
        #expect(mapping["core_project_ids"] == .array([.string("alpha")]))
        #expect(mapping["title"] == .string("Persisted title"))
        #expect(mapping["external"] == .object(["nested": .array([.integer(3), .boolean(true)])]))

        try await fixture.useCase.apply(.core(false), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["core_project_ids"] == .array([]))
        try await fixture.useCase.apply(.membership(false), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try await fixture.links.load(in: fixture.workspace).isEmpty)
        #expect(try fixture.metadata()["project_ids"] == .array([]))
    }

    @Test("Toggles read current repository state and pinned creates a mirrored membership")
    func persistedTogglesAndPinnedMembership() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try await fixture.useCase.apply(.pinned(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([.string("alpha")]))
        try await fixture.useCase.apply(.toggleCore, paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.useCase.apply(.toggleCore, paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["core_project_ids"] == .array([]))
        try await fixture.useCase.apply(.toggleMembership, paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([]))
        try await fixture.useCase.apply(.toggleMembership, paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([.string("alpha")]))
    }

    @Test("A link persistence failure leaves metadata untouched")
    func firstStageFailure() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.metadataURL)
        try FileManager.default.createDirectory(at: fixture.workspace.projectPaperLinksURL, withIntermediateDirectories: true)
        do {
            try await fixture.useCase.apply(.membership(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
            Issue.record("Expected link persistence failure")
        } catch let error as PaperProjectMembershipError {
            #expect(error.phase == .linkWrite)
        }
        #expect(try Data(contentsOf: fixture.metadataURL) == original)
    }

    @Test("A failed mirror restores the previous association and the action can be retried")
    func mirrorFailureAndRecovery() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let original = try String(contentsOf: fixture.metadataURL, encoding: .utf8)
        let malformed = "title: [unterminated"
        try malformed.write(to: fixture.metadataURL, atomically: true, encoding: .utf8)
        do {
            try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
            Issue.record("Expected mirror failure")
        } catch let error as PaperProjectMembershipError {
            #expect(error.phase == .metadataMirror)
        }
        #expect(try await fixture.links.link(forPaperID: "paper", projectID: "alpha", in: fixture.workspace) == nil)
        #expect(try String(contentsOf: fixture.metadataURL, encoding: .utf8) == malformed)

        try original.replacingOccurrences(of: "Persisted title", with: "Repaired externally")
            .write(to: fixture.metadataURL, atomically: true, encoding: .utf8)
        let reopened = PaperProjectMembershipUseCase(links: fixture.links, papers: fixture.papers)
        try await reopened.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await reopened.synchronizeMetadataMirror(forPaperID: "paper", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([.string("alpha")]))
        #expect(try fixture.metadata()["core_project_ids"] == .array([.string("alpha")]))
        #expect(try fixture.metadata()["title"] == .string("Repaired externally"))
    }

    @Test("Removing the last link restores its previous state when the mirror fails")
    func removalRecovery() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        let previousMetadata = try String(contentsOf: fixture.metadataURL, encoding: .utf8)
        try "title: [unterminated".write(to: fixture.metadataURL, atomically: true, encoding: .utf8)
        do {
            try await fixture.useCase.apply(.membership(false), paperID: "paper", projectID: "alpha", in: fixture.workspace)
            Issue.record("Expected mirror failure")
        } catch let error as PaperProjectMembershipError {
            #expect(error.phase == .metadataMirror)
        }
        try previousMetadata.write(to: fixture.metadataURL, atomically: true, encoding: .utf8)
        let loaded = try #require(await fixture.papers.loadPapers(in: fixture.workspace).first)
        #expect(loaded.projectIDs == ["alpha"])
        #expect(loaded.coreProjectIDs == ["alpha"])
        try await fixture.useCase.apply(.membership(false), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([]))
        #expect(try fixture.metadata()["core_project_ids"] == .array([]))
    }

    @Test("Compensation preserves other links and the affected entry's extensions")
    func compensationPreservesUnrelatedChanges() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        var mapping = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fixture.workspace.projectPaperLinksURL, encoding: .utf8))
        var entry = try #require(mapping["links"]?.arrayElements?.first?.objectValue)
        entry["extension"] = .array([.string("retain")])
        mapping["links"] = .array([.object(entry)])
        try StandardsYAMLEncoder.encodeMapping(mapping).write(to: fixture.workspace.projectPaperLinksURL, atomically: true, encoding: .utf8)
        let receipt = try await fixture.links.apply(.membership(false), projectID: "alpha", paperID: "paper", in: fixture.workspace)
        let unrelated = ProjectPaperLink(projectID: "other-project", paperID: "other-paper", isPinned: true)
        try await fixture.links.upsert(unrelated, in: fixture.workspace)
        try await fixture.links.compensate(receipt, in: fixture.workspace)
        #expect(try await fixture.links.link(forPaperID: "paper", projectID: "alpha", in: fixture.workspace)?.isCore == true)
        #expect(try await fixture.links.link(forPaperID: "other-paper", projectID: "other-project", in: fixture.workspace)?.isPinned == true)
        let restored = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fixture.workspace.projectPaperLinksURL, encoding: .utf8))
        #expect(restored["links"]?.arrayElements?.first(where: { $0.objectValue?["paper_id"]?.stringValue == "paper" })?.objectValue?["extension"] == .array([.string("retain")]))
    }

    @Test("A conflicting compensation preserves the newer association and allows mirror recovery")
    func compensationConflictRecovery() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let failingMirror = ConflictingMirror(links: fixture.links)
        let useCase = PaperProjectMembershipUseCase(links: fixture.links, papers: failingMirror)
        do {
            try await useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
            Issue.record("Expected compensation conflict")
        } catch let error as PaperProjectMembershipError {
            #expect(error.phase == .compensation)
        }
        let current = try #require(await fixture.links.link(forPaperID: "paper", projectID: "alpha", in: fixture.workspace))
        #expect(current.isCore && current.isPinned)
        try await fixture.useCase.synchronizeMetadataMirror(forPaperID: "paper", in: fixture.workspace)
        #expect(try fixture.metadata()["project_ids"] == .array([.string("alpha")]))
        #expect(try fixture.metadata()["core_project_ids"] == .array([.string("alpha")]))
    }

    @Test("Compensation detects a later identical-value write even within the same timestamp second")
    func identicalValueConflict() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let receipt = try await fixture.links.apply(.core(true), projectID: "alpha", paperID: "paper", in: fixture.workspace)
        try await fixture.links.setCore(true, projectID: "alpha", paperID: "paper", in: fixture.workspace)
        await #expect(throws: ProjectPaperLinkCompensationError.self) {
            try await fixture.links.compensate(receipt, in: fixture.workspace)
        }
        #expect(try await fixture.links.link(forPaperID: "paper", projectID: "alpha", in: fixture.workspace)?.isCore == true)
    }

    @Test("Mixed legacy metadata keeps its existing fallback behavior")
    func legacyMetadataFallback() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let contents = try String(contentsOf: fixture.metadataURL, encoding: .utf8)
            .replacingOccurrences(of: "project_ids: []", with: "project_ids: [legacy]")
        try contents.write(to: fixture.metadataURL, atomically: true, encoding: .utf8)
        try await fixture.links.upsert(ProjectPaperLink(projectID: "other-project", paperID: "other-paper"), in: fixture.workspace)
        let paper = try #require(await fixture.papers.loadPapers(in: fixture.workspace).first)
        #expect(paper.projectIDs == ["legacy"])
    }

    @Test("Queued concurrent changes finish with one consistent mirror")
    func concurrentChanges() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "p-\(index)", in: fixture.workspace)
                }
            }
            try await group.waitForAll()
        }
        let links = try await fixture.links.links(forPaperID: "paper", in: fixture.workspace)
        let expected = FrontmatterValue.array(links.map { .string($0.projectID) })
        #expect(links.count == 12)
        #expect(try fixture.metadata()["project_ids"] == expected)
        #expect(try fixture.metadata()["core_project_ids"] == expected)
    }

    @Test("Cancelling a queued action leaves its link untouched while the committed action finishes")
    func queuedCancellation() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let gate = PausingMirror(papers: fixture.papers)
        let useCase = PaperProjectMembershipUseCase(links: fixture.links, papers: gate)
        let first = Task {
            try await useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        }
        await gate.waitUntilStarted()
        let queued = Task {
            try await useCase.apply(.membership(true), paperID: "paper", projectID: "beta", in: fixture.workspace)
        }
        queued.cancel()
        first.cancel()
        await gate.release()
        try await first.value
        do {
            try await queued.value
            Issue.record("Expected queued cancellation")
        } catch is CancellationError {
            // A cancelled queued action never enters the link write phase.
        }
        #expect(try await fixture.links.link(forPaperID: "paper", projectID: "beta", in: fixture.workspace) == nil)
        #expect(try fixture.metadata()["core_project_ids"] == .array([.string("alpha")]))
    }

    @Test("Draft merging retains unsaved text and explicitly edited associations")
    func unsavedDraftIsPreserved() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let original = try #require(await fixture.papers.loadPapers(in: fixture.workspace).first)
        var draft = original
        draft.title = "Unsaved title"
        try await fixture.useCase.apply(.core(true), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.useCase.apply(.useFor(["discussion"]), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        try await fixture.useCase.apply(.folderPath("Discussion"), paperID: "paper", projectID: "alpha", in: fixture.workspace)
        let updated = try #require(await fixture.papers.loadPapers(in: fixture.workspace).first)
        let merged = PaperProjectDraftMerge.merge(draft: draft, original: original, updated: updated)
        #expect(merged.title == "Unsaved title")
        #expect(merged.useFor == ["discussion"])
        #expect(merged.folderPath == "Discussion")
        #expect(merged.projectIDs == ["alpha"])
        #expect(merged.coreProjectIDs == ["alpha"])
        #expect(try fixture.metadata()["title"] == .string("Persisted title"))
        #expect(PaperProjectDraftMerge.merge(draft: original, original: original, updated: updated) == updated)
        draft.projectIDs = ["unsaved-project"]
        #expect(PaperProjectDraftMerge.merge(draft: draft, original: original, updated: updated).projectIDs == ["unsaved-project"])
    }

    @Test("Workspace session revisions survive completion and invalidate same-root reopening")
    @MainActor
    func workspaceRevision() {
        let coordinator = WorkspaceSessionCoordinator()
        let previous = coordinator.revision
        let generation = coordinator.start { _ in }
        #expect(coordinator.revision != previous)
        coordinator.finish(generation)
        #expect(coordinator.revision == generation)
        coordinator.cancel()
        #expect(coordinator.revision != generation)
    }
}

private struct MembershipFixture: Sendable {
    let workspace: ResearchWorkspace
    let metadataURL: URL
    let links: ProjectPaperLinkRepository
    let papers: PaperRepository
    let useCase: PaperProjectMembershipUseCase

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SciStationMembership-\(UUID().uuidString)")
        workspace = ResearchWorkspace(rootURL: root)
        metadataURL = workspace.directoryURL(for: "library/papers/paper").appendingPathComponent("meta.yaml")
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        id: paper
        citekey: fixture2026
        title: Persisted title
        project_ids: []
        core_project_ids: []
        external:
          nested: [3, true]
        """.write(to: metadataURL, atomically: true, encoding: .utf8)
        links = ProjectPaperLinkRepository()
        papers = PaperRepository(projectPaperLinkRepository: links)
        useCase = PaperProjectMembershipUseCase(links: links, papers: papers)
    }

    func metadata() throws -> [String: FrontmatterValue] {
        try StandardsYAMLDecoder.decodeMapping(String(contentsOf: metadataURL, encoding: .utf8))
    }

    func remove() {
        try? FileManager.default.removeItem(at: workspace.rootURL)
    }
}

private actor ConflictingMirror: PaperProjectMetadataMirroring {
    let links: ProjectPaperLinkRepository

    init(links: ProjectPaperLinkRepository) { self.links = links }

    func updateProjectMetadataMirror(forPaperID paperID: Paper.ID, links: [ProjectPaperLink], in workspace: ResearchWorkspace) async throws {
        let projectID = try #require(links.first?.projectID)
        try await self.links.setPinned(true, projectID: projectID, paperID: paperID, in: workspace)
        throw CocoaError(.fileWriteNoPermission)
    }
}

private actor PausingMirror: PaperProjectMetadataMirroring {
    let papers: PaperRepository
    var started = false
    var startedWaiter: CheckedContinuation<Void, Never>?
    var releaseWaiter: CheckedContinuation<Void, Never>?

    init(papers: PaperRepository) { self.papers = papers }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func release() { releaseWaiter?.resume() }

    func updateProjectMetadataMirror(forPaperID paperID: Paper.ID, links: [ProjectPaperLink], in workspace: ResearchWorkspace) async throws {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            started = true
            startedWaiter?.resume()
        }
        try await papers.updateProjectMetadataMirror(forPaperID: paperID, links: links, in: workspace)
    }
}
