import Foundation

public actor WorkspaceService {
    private let fileManager: FileManager
    private let bookmarkStore: WorkspaceBookmarkStore
    private let projectRegistryRepository: ProjectRegistryRepository
    private let workspaceTemplateRepository: WorkspaceTemplateRepository
    private var activeSecurityScopedURL: URL?
    private var activeSecurityScopeStarted = false

    public init(
        fileManager: FileManager = .default,
        bookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore(),
        projectRegistryRepository: ProjectRegistryRepository = ProjectRegistryRepository(),
        workspaceTemplateRepository: WorkspaceTemplateRepository = WorkspaceTemplateRepository()
    ) {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
        self.projectRegistryRepository = projectRegistryRepository
        self.workspaceTemplateRepository = workspaceTemplateRepository
    }

    public func createWorkspace(at rootURL: URL, template: WorkspaceTemplate = WorkspaceTemplateRegistry.literatureReview) async throws -> ResearchWorkspace {
        guard rootURL.isFileURL else {
            throw WorkspaceError.invalidRootURL
        }

        activateSecurityScope(for: rootURL)

        let targetValidation = WorkspaceCreationWizard.validateTargetURL(rootURL, using: fileManager)
        guard targetValidation.canCreate else {
            throw WorkspaceError.incompatibleCreationTarget(targetValidation.message)
        }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        let researchRoot = ResearchRoot(rootURL: rootURL)
        let compatibility = ResearchRoot.compatibility(at: rootURL, using: fileManager)
        try ensureWorkspaceStructure(for: workspace)
        try ensureResearchRootStructure(for: researchRoot)
        if compatibility == .emptyOrNew {
            try workspaceTemplateRepository.overwriteTemplateConfiguration(template, in: researchRoot)
        } else {
            try workspaceTemplateRepository.ensureTemplateConfiguration(template, in: researchRoot)
        }
        try await projectRegistryRepository.ensureDefaultProject(
            in: researchRoot,
            named: rootURL.lastPathComponent,
            compatibility: compatibility
        )

        try await persistBookmark(for: rootURL)
        return try await openWorkspace(at: rootURL)
    }

    /// Create a workspace pre-populated with example research content so a
    /// first-time tester immediately sees a realistic Library / Wiki / project
    /// instead of an empty shell. Example files only; no network access.
    public func createSampleWorkspace(at rootURL: URL) async throws -> ResearchWorkspace {
        let workspace = try await createWorkspace(at: rootURL, template: WorkspaceTemplateRegistry.literatureReview)
        try seedSampleContent(into: workspace)
        return workspace
    }

    private func seedSampleContent(into workspace: ResearchWorkspace) throws {
        let sampleFiles: [(relativePath: String, contents: String)] = [
            (
                "shared_research.md",
                """
                # Shared Research Context (Sample)

                This is an example Research Root created by Sci-Station so you can
                explore the app with realistic content. Everything here lives only
                in this local folder — delete it any time.

                ## Current Focus
                - Survey efficient attention mechanisms for long-context models.
                - Compare memory/compute trade-offs across recent papers.

                ## Reusable Prompts
                - "Summarize this paper's method in 3 bullets and list its key assumption."
                - "Contrast this paper with the core papers in the project canon."
                """
            ),
            (
                "wiki/concepts/attention-mechanism.md",
                """
                # Attention Mechanism (Sample)

                Concept note demonstrating how Sci-Station stores knowledge pages.

                ## Definition
                A mechanism that weights input tokens by learned relevance so a
                model can focus on the most informative context.

                ## Why It Matters
                Quadratic cost in sequence length motivates the efficiency work
                tracked in `shared_research.md`.

                ## Related
                - See `wiki/papers/example-paper-note.md` for a worked example.
                """
            ),
            (
                "wiki/papers/example-paper-note.md",
                """
                # Example Paper Note (Sample)

                Reading note showing the per-paper structure Sci-Station expects.

                ## Citation
                Placeholder et al., *An Example Paper on Efficient Attention*, 2026.

                ## Contribution
                Introduces a linear-time attention approximation.

                ## Method
                - Replace the full softmax attention with a kernel feature map.
                - Maintain a running state to avoid storing the full matrix.

                ## My Take
                Strong fit for the long-context focus; verify the accuracy claims
                against the benchmarks before adding to the core canon.
                """
            )
        ]

        for file in sampleFiles {
            let fileURL = workspace.fileURL(for: file.relativePath)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: fileURL, options: .atomic)
        }
    }

    public func openWorkspace(at rootURL: URL) async throws -> ResearchWorkspace {
        guard rootURL.isFileURL else {
            throw WorkspaceError.invalidRootURL
        }

        activateSecurityScope(for: rootURL)

        let workspace = ResearchWorkspace(rootURL: rootURL)
        let researchRoot = ResearchRoot(rootURL: rootURL)
        let compatibility = ResearchRoot.compatibility(at: rootURL, using: fileManager)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError.missingRequiredItems([rootURL.lastPathComponent])
        }

        try ensureWorkspaceStructure(for: workspace)
        try ensureResearchRootStructure(for: researchRoot)
        try workspaceTemplateRepository.ensureTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: researchRoot)
        try await projectRegistryRepository.ensureDefaultProject(
            in: researchRoot,
            named: rootURL.lastPathComponent,
            compatibility: compatibility
        )

        try await persistBookmark(for: rootURL)
        return workspace
    }

    public func classifyResearchRoot(at rootURL: URL) -> ResearchRootCompatibility {
        ResearchRoot.compatibility(at: rootURL, using: fileManager)
    }

    private func ensureWorkspaceStructure(for workspace: ResearchWorkspace) throws {
        try fileManager.createDirectory(at: workspace.rootURL, withIntermediateDirectories: true)

        for relativePath in ResearchWorkspace.requiredDirectoryPaths {
            let directoryURL = workspace.directoryURL(for: relativePath)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        for file in ResearchWorkspace.seededFiles {
            let fileURL = workspace.fileURL(for: file.relativePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                continue
            }

            let parentDirectoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: fileURL, options: .atomic)
        }
    }

    private func ensureResearchRootStructure(for root: ResearchRoot) throws {
        try fileManager.createDirectory(at: root.rootURL, withIntermediateDirectories: true)

        for relativePath in ResearchRoot.requiredDirectoryPaths {
            try fileManager.createDirectory(at: root.directoryURL(for: relativePath), withIntermediateDirectories: true)
        }

        for file in ResearchRoot.seededFiles {
            let fileURL = root.fileURL(for: file.relativePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                continue
            }

            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: fileURL, options: .atomic)
        }
    }

    public func restoreLastWorkspace() async -> ResearchWorkspace? {
        do {
            guard let lastWorkspaceURL = try await bookmarkStore.restoreBookmarkURL() else {
                return nil
            }

            return try await openWorkspace(at: lastWorkspaceURL)
        } catch {
            await bookmarkStore.clearBookmarkData()
            return nil
        }
    }

    public func clearRecentWorkspaceBookmark() async {
        if activeSecurityScopeStarted {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURL = nil
        activeSecurityScopeStarted = false
        await bookmarkStore.clearBookmarkData()
    }

    private func persistBookmark(for url: URL) async throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        await bookmarkStore.saveBookmarkData(bookmarkData)
    }

    private func activateSecurityScope(for url: URL) {
        if activeSecurityScopedURL == url {
            return
        }

        if activeSecurityScopeStarted {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }

        activeSecurityScopedURL = url
        activeSecurityScopeStarted = url.startAccessingSecurityScopedResource()
    }
}