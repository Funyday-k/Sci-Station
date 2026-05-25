import Foundation

public nonisolated struct WorkspaceRelativePath: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public nonisolated init(rawValue: String) {
        do {
            try self.init(validating: rawValue)
        } catch {
            preconditionFailure("Invalid workspace relative path: \(rawValue)")
        }
    }

    public nonisolated init(_ value: String) throws {
        try self.init(validating: value)
    }

    private nonisolated init(validating value: String) throws {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw WorkspaceFileSystemError.invalidRelativePath(value)
        }
        guard !normalized.hasPrefix("/") && !normalized.hasPrefix("~") else {
            throw WorkspaceFileSystemError.invalidRelativePath(value)
        }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else {
            throw WorkspaceFileSystemError.invalidRelativePath(value)
        }
        guard components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("\u{0}")
        }) else {
            throw WorkspaceFileSystemError.invalidRelativePath(value)
        }
        self.rawValue = components.joined(separator: "/")
    }
}

public nonisolated struct WriteOptions: Codable, Hashable, Sendable {
    public var createIntermediateDirectories: Bool
    public var overwrite: Bool
    public var atomic: Bool

    public nonisolated init(createIntermediateDirectories: Bool = true, overwrite: Bool = true, atomic: Bool = true) {
        self.createIntermediateDirectories = createIntermediateDirectories
        self.overwrite = overwrite
        self.atomic = atomic
    }
}

public nonisolated enum WorkspaceFileSystemError: LocalizedError, Sendable {
    case invalidRelativePath(String)
    case pathEscapesWorkspace(String)
    case fileAlreadyExists(String)
    case missingParentDirectory(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRelativePath(path):
            return "Invalid workspace relative path: \(path)"
        case let .pathEscapesWorkspace(path):
            return "Path escapes workspace root: \(path)"
        case let .fileAlreadyExists(path):
            return "File already exists: \(path)"
        case let .missingParentDirectory(path):
            return "Parent directory does not exist: \(path)"
        }
    }
}

public actor WorkspaceFileSystem {
    private let rootURL: URL
    private let fileManager: FileManager

    public init(root: ResearchRoot, fileManager: FileManager = .default) {
        self.rootURL = root.rootURL
        self.fileManager = fileManager
    }

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func readText(_ path: WorkspaceRelativePath) async throws -> String {
        let url = try containedURL(for: path, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeText(_ text: String, to path: WorkspaceRelativePath, options: WriteOptions = WriteOptions()) async throws {
        let url = try containedURL(for: path, isDirectory: false)
        let parentURL = url.deletingLastPathComponent()
        if options.createIntermediateDirectories {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: parentURL.path) {
            throw WorkspaceFileSystemError.missingParentDirectory(path.rawValue)
        }
        if !options.overwrite && fileManager.fileExists(atPath: url.path) {
            throw WorkspaceFileSystemError.fileAlreadyExists(path.rawValue)
        }
        try text.write(to: url, atomically: options.atomic, encoding: .utf8)
    }

    public func createDirectory(_ path: WorkspaceRelativePath) async throws {
        let url = try containedURL(for: path, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func remove(_ path: WorkspaceRelativePath) async throws {
        let url = try containedURL(for: path, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func exists(_ path: WorkspaceRelativePath) async -> Bool {
        guard let url = try? containedURL(for: path, isDirectory: false) else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    public func resolvedURL(_ path: WorkspaceRelativePath, isDirectory: Bool = false) async throws -> URL {
        try containedURL(for: path, isDirectory: isDirectory)
    }

    private func containedURL(for path: WorkspaceRelativePath, isDirectory: Bool) throws -> URL {
        let candidate = path.rawValue.split(separator: "/").reduce(rootURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component), isDirectory: isDirectory)
        }.standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let parentURL = candidate.deletingLastPathComponent()
        let existingURL = fileManager.fileExists(atPath: candidate.path) ? candidate.resolvingSymlinksInPath() : parentURL.resolvingSymlinksInPath().appendingPathComponent(candidate.lastPathComponent, isDirectory: isDirectory)
        let resolvedPath = existingURL.standardizedFileURL.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw WorkspaceFileSystemError.pathEscapesWorkspace(path.rawValue)
        }
        return candidate
    }
}
