import Foundation

public actor WorkspaceService {
    private let fileManager: FileManager
    private let bookmarkStore: WorkspaceBookmarkStore

    public init(
        fileManager: FileManager = .default,
        bookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore()
    ) {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
    }

    public func createWorkspace(at rootURL: URL) async throws -> ResearchWorkspace {
        guard rootURL.isFileURL else {
            throw WorkspaceError.invalidRootURL
        }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        for relativePath in ResearchWorkspace.requiredDirectoryPaths {
            let directoryURL = workspace.directoryURL(for: relativePath)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        for file in ResearchWorkspace.seededFiles {
            let fileURL = workspace.fileURL(for: file.relativePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                continue
            }

            try Data(file.contents.utf8).write(to: fileURL, options: .atomic)
        }

        try await persistBookmark(for: rootURL)
        return try await openWorkspace(at: rootURL)
    }

    public func openWorkspace(at rootURL: URL) async throws -> ResearchWorkspace {
        guard rootURL.isFileURL else {
            throw WorkspaceError.invalidRootURL
        }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        let missingItems = workspace.missingRequiredItems(using: fileManager)

        guard missingItems.isEmpty else {
            throw WorkspaceError.missingRequiredItems(missingItems)
        }

        try await persistBookmark(for: rootURL)
        return workspace
    }

    public func restoreLastWorkspace() async throws -> ResearchWorkspace? {
        guard let lastWorkspaceURL = try await bookmarkStore.restoreBookmarkURL() else {
            return nil
        }

        return try await openWorkspace(at: lastWorkspaceURL)
    }

    private func persistBookmark(for url: URL) async throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        await bookmarkStore.saveBookmarkData(bookmarkData)
    }
}