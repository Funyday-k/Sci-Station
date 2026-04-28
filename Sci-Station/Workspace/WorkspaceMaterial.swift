import Foundation

public enum WorkspaceMaterialKind: String, Sendable {
    case markdown
    case python
    case text
    case image
    case pdf
    case data
    case other
}

public struct WorkspaceMaterial: Identifiable, Hashable, Sendable {
    public let relativePath: String
    public let fileURL: URL
    public let kind: WorkspaceMaterialKind
    public let byteCount: Int64
    public let modifiedAt: Date?

    public nonisolated init(
        relativePath: String,
        fileURL: URL,
        kind: WorkspaceMaterialKind,
        byteCount: Int64,
        modifiedAt: Date?
    ) {
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.kind = kind
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }

    public nonisolated var id: String {
        relativePath
    }

    public nonisolated var displayName: String {
        fileURL.lastPathComponent
    }

    public nonisolated var category: String {
        let components = relativePath.split(separator: "/").map(String.init)
        if components.count >= 3, components.first == "projects" {
            return components[2]
        }

        return components.first ?? "workspace"
    }
}
