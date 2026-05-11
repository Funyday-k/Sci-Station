import Foundation

public enum MarkdownRepositoryError: LocalizedError, Equatable, Sendable {
    case invalidRelativePath(String)
    case pathOutsideWikiRoot(String)
    case unsupportedFileType(String)
    case destinationAlreadyExists(String)
    case sourceMissing(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRelativePath(path):
            return "Invalid workspace-relative path: \(path)"
        case let .pathOutsideWikiRoot(path):
            return "Markdown file operation must stay inside wiki/ or projects/<project-id>/wiki/: \(path)"
        case let .unsupportedFileType(path):
            return "Unsupported wiki file type: \(path)"
        case let .destinationAlreadyExists(path):
            return "Destination already exists: \(path)"
        case let .sourceMissing(path):
            return "Source file does not exist: \(path)"
        }
    }
}

public actor MarkdownRepository {
    public static let managedFileExtensions: Set<String> = ["md", "markdown", "txt"]

    private let fileManager: FileManager
    private let frontmatterParser: FrontmatterParser
    private let wikiLinkParser: WikiLinkParser

    public init(
        fileManager: FileManager = .default,
        frontmatterParser: FrontmatterParser = FrontmatterParser(),
        wikiLinkParser: WikiLinkParser = WikiLinkParser()
    ) {
        self.fileManager = fileManager
        self.frontmatterParser = frontmatterParser
        self.wikiLinkParser = wikiLinkParser
    }

    public func loadDocuments(in workspace: ResearchWorkspace, project: ResearchProject? = nil) throws -> [MarkdownDocument] {
        let wikiRootURL = project.map { workspace.directoryURL(for: $0.relativePath + "/wiki") } ?? workspace.directoryURL(for: "wiki")
        guard fileManager.fileExists(atPath: wikiRootURL.path) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: wikiRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var documents: [MarkdownDocument] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard Self.managedFileExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }

            documents.append(try loadDocument(at: fileURL, in: workspace))
        }

        return documents.sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    public func loadDocument(relativePath: String, in workspace: ResearchWorkspace) throws -> MarkdownDocument {
        let normalizedPath = try normalizedWorkspaceRelativePath(relativePath)
        let fileURL = try workspaceContainedURL(for: normalizedPath, in: workspace, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        guard Self.managedFileExtensions.contains(fileURL.pathExtension.lowercased()) else {
            throw MarkdownRepositoryError.unsupportedFileType(normalizedPath)
        }
        return try loadDocument(at: fileURL, in: workspace)
    }

    public func saveContents(
        _ contents: String,
        relativePath: String,
        in workspace: ResearchWorkspace
    ) throws -> MarkdownDocument {
        let fileURL = workspace.fileURL(for: relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try loadDocument(at: fileURL, in: workspace)
    }

    public func createDocument(
        relativePath: String,
        contents: String = "",
        in workspace: ResearchWorkspace
    ) throws -> MarkdownDocument {
        let targetPath = try normalizedWikiFilePath(relativePath, defaultExtension: "md")
        let fileURL = try workspaceContainedURL(for: targetPath, in: workspace, isDirectory: false)
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            throw MarkdownRepositoryError.destinationAlreadyExists(targetPath)
        }

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try loadDocument(at: fileURL, in: workspace)
    }

    public func createFolder(relativePath: String, in workspace: ResearchWorkspace) throws -> String {
        let folderPath = try normalizedWikiFolderPath(relativePath)
        let folderURL = try workspaceContainedURL(for: folderPath, in: workspace, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderPath
    }

    public func renameDocument(
        relativePath: String,
        toFileName newFileName: String,
        in workspace: ResearchWorkspace
    ) throws -> MarkdownDocument {
        let sourcePath = try normalizedWikiFilePath(relativePath)
        let normalizedName = try normalizedFileName(newFileName, defaultExtension: sourcePath.pathExtensionOrDefault("md"))
        let destinationPath = sourcePath.deletingLastPathComponent().appendingPathComponent(normalizedName)
        return try moveDocument(from: sourcePath, to: destinationPath, in: workspace)
    }

    public func moveDocument(
        from sourceRelativePath: String,
        to destinationRelativePath: String,
        in workspace: ResearchWorkspace
    ) throws -> MarkdownDocument {
        let sourcePath = try normalizedWikiFilePath(sourceRelativePath)
        let destinationPath = try normalizedWikiFilePath(destinationRelativePath, defaultExtension: sourcePath.pathExtensionOrDefault("md"))
        let sourceURL = try workspaceContainedURL(for: sourcePath, in: workspace, isDirectory: false)
        let destinationURL = try workspaceContainedURL(for: destinationPath, in: workspace, isDirectory: false)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MarkdownRepositoryError.sourceMissing(sourcePath)
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw MarkdownRepositoryError.destinationAlreadyExists(destinationPath)
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return try loadDocument(at: destinationURL, in: workspace)
    }

    public func archiveDocument(relativePath: String, in workspace: ResearchWorkspace, now: Date = Date()) throws -> String {
        let sourcePath = try normalizedWikiFilePath(relativePath)
        let sourceURL = try workspaceContainedURL(for: sourcePath, in: workspace, isDirectory: false)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MarkdownRepositoryError.sourceMissing(sourcePath)
        }

        let timestamp = Self.archiveTimestamp(for: now)
            .replacingOccurrences(of: ":", with: "-")
        let archivePath = ".sci-station/trash/wiki/\(timestamp)/\(sourcePath)"
        let archiveURL = try workspaceContainedURL(for: archivePath, in: workspace, isDirectory: false)
        guard !fileManager.fileExists(atPath: archiveURL.path) else {
            throw MarkdownRepositoryError.destinationAlreadyExists(archivePath)
        }

        try fileManager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: sourceURL, to: archiveURL)
        return archivePath
    }

    private func loadDocument(at fileURL: URL, in workspace: ResearchWorkspace) throws -> MarkdownDocument {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let parsedDocument = frontmatterParser.parse(contents)
        let relativePath = workspace.relativePath(to: fileURL)
        let category = categoryName(from: relativePath)
        let title = resolvedTitle(
            frontmatter: parsedDocument.frontmatter,
            body: parsedDocument.body,
            fallback: fileURL.deletingPathExtension().lastPathComponent
        )
        let outgoingLinks = wikiLinkParser.parse(parsedDocument.body)
        let pageKeys = uniquePageKeys(for: fileURL, title: title)

        return MarkdownDocument(
            fileURL: fileURL,
            relativePath: relativePath,
            category: category,
            title: title,
            frontmatter: parsedDocument.frontmatter,
            body: parsedDocument.body,
            rawContents: contents,
            outgoingLinks: outgoingLinks,
            pageKeys: pageKeys
        )
    }

    private func categoryName(from relativePath: String) -> String {
        let components = relativePath.split(separator: "/")
        if components.count >= 4, components[0] == "projects", components[2] == "wiki" {
            return String(components[3])
        }
        guard components.count >= 2 else {
            return "wiki"
        }

        return String(components[1])
    }

    private func resolvedTitle(
        frontmatter: [String: FrontmatterValue],
        body: String,
        fallback: String
    ) -> String {
        if let title = frontmatter["title"]?.stringValue,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        if let heading = body.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fallback
    }

    private func uniquePageKeys(for fileURL: URL, title: String) -> [String] {
        let candidates = [
            WikiLink.normalizePageKey(title),
            WikiLink.normalizePageKey(fileURL.deletingPathExtension().lastPathComponent)
        ]

        var pageKeys: [String] = []
        for candidate in candidates where !candidate.isEmpty && !pageKeys.contains(candidate) {
            pageKeys.append(candidate)
        }
        return pageKeys
    }

    private func normalizedWikiFilePath(_ relativePath: String, defaultExtension: String? = nil) throws -> String {
        var normalizedPath = try normalizedWorkspaceRelativePath(relativePath)
        if normalizedPath.pathExtensionOrDefault("").isEmpty, let defaultExtension {
            normalizedPath += ".\(defaultExtension)"
        }
        guard Self.managedFileExtensions.contains(normalizedPath.pathExtensionOrDefault("")) else {
            throw MarkdownRepositoryError.unsupportedFileType(normalizedPath)
        }
        guard Self.isWikiManagedPath(normalizedPath) else {
            throw MarkdownRepositoryError.pathOutsideWikiRoot(normalizedPath)
        }
        return normalizedPath
    }

    private func normalizedWikiFolderPath(_ relativePath: String) throws -> String {
        let normalizedPath = try normalizedWorkspaceRelativePath(relativePath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard Self.isWikiManagedPath(normalizedPath) else {
            throw MarkdownRepositoryError.pathOutsideWikiRoot(normalizedPath)
        }
        return normalizedPath
    }

    private func normalizedWorkspaceRelativePath(_ relativePath: String) throws -> String {
        let normalizedPath = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !normalizedPath.isEmpty,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/"),
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("~"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw MarkdownRepositoryError.invalidRelativePath(relativePath)
        }
        return normalizedPath
    }

    private func normalizedFileName(_ fileName: String, defaultExtension: String) throws -> String {
        let normalizedName = fileName
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !normalizedName.contains("/"),
              normalizedName != ".",
              normalizedName != ".." else {
            throw MarkdownRepositoryError.invalidRelativePath(fileName)
        }
        var candidate = normalizedName
        if candidate.pathExtensionOrDefault("").isEmpty {
            candidate += ".\(defaultExtension)"
        }
        guard Self.managedFileExtensions.contains(candidate.pathExtensionOrDefault("")) else {
            throw MarkdownRepositoryError.unsupportedFileType(candidate)
        }
        return candidate
    }

    private func workspaceContainedURL(for relativePath: String, in workspace: ResearchWorkspace, isDirectory: Bool) throws -> URL {
        let url = workspace.resolve(relativePath: relativePath, from: workspace.rootURL, isDirectory: isDirectory).standardizedFileURL
        let rootPath = workspace.rootURL.standardizedFileURL.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            throw MarkdownRepositoryError.invalidRelativePath(relativePath)
        }
        return url
    }

    private nonisolated static func isWikiManagedPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        if components.count >= 2, components[0] == "wiki" {
            return true
        }
        return components.count >= 4 && components[0] == "projects" && components[2] == "wiki"
    }

    private nonisolated static func archiveTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension String {
    nonisolated func pathExtensionOrDefault(_ fallback: String) -> String {
        let pathExtension = (self as NSString).pathExtension.lowercased()
        return pathExtension.isEmpty ? fallback : pathExtension
    }

    nonisolated func deletingLastPathComponent() -> String {
        let value = (self as NSString).deletingLastPathComponent
        return value == "." ? "" : value
    }

    nonisolated func appendingPathComponent(_ component: String) -> String {
        guard !isEmpty else { return component }
        return (self as NSString).appendingPathComponent(component)
            .replacingOccurrences(of: "\\", with: "/")
    }
}