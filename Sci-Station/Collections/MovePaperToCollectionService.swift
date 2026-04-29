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
        let normalizedCollectionPath = collectionPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        let sourceDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        let targetCollectionURL = workspace.resolve(
            relativePath: normalizedCollectionPath,
            from: papersRootURL(for: paper, in: workspace),
            isDirectory: true
        )
        try fileManager.createDirectory(at: targetCollectionURL, withIntermediateDirectories: true)

        let targetDirectoryURL = targetCollectionURL.appendingPathComponent(paper.id, isDirectory: true)
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

    private func papersRootURL(for paper: Paper, in workspace: ResearchWorkspace) -> URL {
        switch Paper.storageRootRelativePath(for: paper.paperDirectoryRelativePath) {
        case Paper.legacyLibraryRootRelativePath:
            return workspace.rawPapersURL
        default:
            return workspace.globalPapersURL
        }
    }
}