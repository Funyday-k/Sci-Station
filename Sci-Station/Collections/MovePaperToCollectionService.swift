import Foundation

public enum MovePaperToCollectionError: LocalizedError {
    case targetAlreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case let .targetAlreadyExists(path):
            return "A paper already exists at \(path)."
        }
    }
}

public actor MovePaperToCollectionService {
    private let fileManager: FileManager
    private let paperRepository: PaperRepository

    public init(
        fileManager: FileManager = .default,
        paperRepository: PaperRepository
    ) {
        self.fileManager = fileManager
        self.paperRepository = paperRepository
    }

    public func move(_ paper: Paper, to collectionPath: String, in workspace: ResearchWorkspace) async throws -> Paper {
        let fileSystem = WorkspaceFileSystem(rootURL: workspace.rootURL)
        let sourceDirectoryURL = try await fileSystem.resolvedURL(
            WorkspaceRelativePath(paper.paperDirectoryRelativePath),
            isDirectory: true
        )
        let storageRootRelativePath = Paper.storageRootRelativePath(
            for: paper.paperDirectoryRelativePath
        ) ?? Paper.globalLibraryRootRelativePath
        let targetRelativePath = try Paper.directoryRelativePath(
            for: paper.id,
            collectionPath: collectionPath,
            storageRootRelativePath: storageRootRelativePath
        )
        let targetDirectoryURL = try await fileSystem.resolvedURL(
            WorkspaceRelativePath(targetRelativePath),
            isDirectory: true
        )
        let targetCollectionURL = targetDirectoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetCollectionURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: targetDirectoryURL.path) else {
            throw MovePaperToCollectionError.targetAlreadyExists(workspace.relativePath(to: targetDirectoryURL))
        }

        try fileManager.moveItem(at: sourceDirectoryURL, to: targetDirectoryURL)

        var movedPaper = paper
        movedPaper.paperDirectoryRelativePath = workspace.relativePath(to: targetDirectoryURL)
        movedPaper.collectionPath = Paper.collectionPath(for: movedPaper.paperDirectoryRelativePath)
        movedPaper.folderPath = movedPaper.collectionPath
        movedPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: movedPaper.citekey,
            paperDirectoryRelativePath: movedPaper.paperDirectoryRelativePath
        )

        return try await paperRepository.save(movedPaper, in: workspace)
    }
}
