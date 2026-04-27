import Foundation

public struct PaperCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        relativePath
    }

    public var name: String
    public var relativePath: String
    public var parentPath: String?
    public var paperCount: Int

    public nonisolated init(name: String, relativePath: String, parentPath: String?, paperCount: Int) {
        self.name = name
        self.relativePath = relativePath
        self.parentPath = parentPath
        self.paperCount = paperCount
    }
}