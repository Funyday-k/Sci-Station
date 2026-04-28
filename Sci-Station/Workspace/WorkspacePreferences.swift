import Foundation

public struct WorkspacePreferences: Hashable, Sendable {
    public nonisolated static let currentSchemaVersion = 1
    public nonisolated static let defaultLibraryVisibleColumns = ["title", "authors", "year", "tags", "projects", "collection"]

    public var schemaVersion: Int
    public var libraryVisibleColumns: [String]
    public var defaultCollectionPath: String?
    public var recentSection: String?
    public var syncTodosToAppleReminders: Bool

    public nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        libraryVisibleColumns: [String] = Self.defaultLibraryVisibleColumns,
        defaultCollectionPath: String? = nil,
        recentSection: String? = "library",
        syncTodosToAppleReminders: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.libraryVisibleColumns = libraryVisibleColumns.isEmpty ? Self.defaultLibraryVisibleColumns : libraryVisibleColumns
        self.defaultCollectionPath = defaultCollectionPath
        self.recentSection = recentSection
        self.syncTodosToAppleReminders = syncTodosToAppleReminders
    }

    public nonisolated var libraryVisibleColumnsStorageValue: String {
        libraryVisibleColumns.joined(separator: ",")
    }

    public nonisolated mutating func updateLibraryVisibleColumns(from storageValue: String) {
        let columns = storageValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        libraryVisibleColumns = columns.isEmpty ? Self.defaultLibraryVisibleColumns : columns
    }
}
