import Foundation

public enum CollectionRepositoryError: LocalizedError {
    case invalidRelativePath
    case alreadyExists(String)
    case notEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            return "Collection path must be relative to raw/papers."
        case let .alreadyExists(path):
            return "Collection already exists at \(path)."
        case let .notEmpty(path):
            return "Collection \(path) is not empty."
        }
    }
}

public actor CollectionRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadCollections(in workspace: ResearchWorkspace) throws -> [PaperCollection] {
        let result = try scanCollections(at: workspace.rawPapersURL, relativePath: nil, workspace: workspace)
        return result.collections.sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    public func createCollection(at relativePath: String, in workspace: ResearchWorkspace) throws -> PaperCollection {
        let normalizedPath = try normalize(relativePath)
        let collectionURL = workspace.resolve(relativePath: normalizedPath, from: workspace.rawPapersURL, isDirectory: true)

        guard !fileManager.fileExists(atPath: collectionURL.path) else {
            throw CollectionRepositoryError.alreadyExists(normalizedPath)
        }

        try fileManager.createDirectory(at: collectionURL, withIntermediateDirectories: true)
        return makeCollection(relativePath: normalizedPath, paperCount: 0)
    }

    public func renameCollection(at relativePath: String, to newName: String, in workspace: ResearchWorkspace) throws -> PaperCollection {
        let normalizedPath = try normalize(relativePath)
        let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedName.isEmpty else {
            throw CollectionRepositoryError.invalidRelativePath
        }

        let sourceURL = workspace.resolve(relativePath: normalizedPath, from: workspace.rawPapersURL, isDirectory: true)
        var pathComponents = normalizedPath
            .split(separator: "/")
            .dropLast()
            .map(String.init)
        pathComponents.append(sanitizedName)
        let targetRelativePath = pathComponents.joined(separator: "/")
        let targetURL = workspace.resolve(relativePath: targetRelativePath, from: workspace.rawPapersURL, isDirectory: true)

        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw CollectionRepositoryError.alreadyExists(targetRelativePath)
        }

        try fileManager.moveItem(at: sourceURL, to: targetURL)

        let collections = try loadCollections(in: workspace)
        return collections.first(where: { $0.relativePath == targetRelativePath })
            ?? makeCollection(relativePath: targetRelativePath, paperCount: 0)
    }

    public func deleteCollection(at relativePath: String, in workspace: ResearchWorkspace) throws {
        let normalizedPath = try normalize(relativePath)
        let collectionURL = workspace.resolve(relativePath: normalizedPath, from: workspace.rawPapersURL, isDirectory: true)
        let contents = try fileManager.contentsOfDirectory(at: collectionURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        guard contents.isEmpty else {
            throw CollectionRepositoryError.notEmpty(normalizedPath)
        }

        try fileManager.removeItem(at: collectionURL)
    }

    private func scanCollections(
        at directoryURL: URL,
        relativePath: String?,
        workspace: ResearchWorkspace
    ) throws -> (collections: [PaperCollection], paperCount: Int) {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var collections: [PaperCollection] = []
        var directPaperCount = 0

        for childURL in childURLs {
            let resourceValues = try childURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else {
                continue
            }

            let metadataURL = childURL.appendingPathComponent("meta.yaml", isDirectory: false)
            if fileManager.fileExists(atPath: metadataURL.path) {
                directPaperCount += 1
                continue
            }

            let childRelativePath = workspace.relativePath(to: childURL)
                .replacingOccurrences(of: "raw/papers/", with: "")
            let nestedResult = try scanCollections(
                at: childURL,
                relativePath: childRelativePath,
                workspace: workspace
            )
            let collection = makeCollection(relativePath: childRelativePath, paperCount: nestedResult.paperCount)
            collections.append(collection)
            collections.append(contentsOf: nestedResult.collections)
        }

        return (collections, directPaperCount + collections.filter { $0.parentPath == relativePath }.map(\.paperCount).reduce(0, +))
    }

    private func makeCollection(relativePath: String, paperCount: Int) -> PaperCollection {
        let components = relativePath.split(separator: "/").map(String.init)
        let name = components.last ?? relativePath
        let parentPath = components.dropLast().isEmpty ? nil : components.dropLast().joined(separator: "/")
        return PaperCollection(name: name, relativePath: relativePath, parentPath: parentPath, paperCount: paperCount)
    }

    private func normalize(_ relativePath: String) throws -> String {
        let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !normalized.isEmpty, !normalized.contains("..") else {
            throw CollectionRepositoryError.invalidRelativePath
        }

        return normalized
    }
}