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