import Foundation

public struct WorkspacePreferences: Hashable, Sendable {
    public nonisolated static let currentSchemaVersion = 1
    public nonisolated static let defaultLibraryVisibleColumns = ["title", "authors", "year", "tags", "projects", "collection"]

    public var schemaVersion: Int
    public var libraryVisibleColumns: [String]
    public var librarySortState: LibrarySortState
    public var defaultCollectionPath: String?
    public var recentSection: String?
    public var syncTodosToAppleReminders: Bool

    public nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        libraryVisibleColumns: [String] = Self.defaultLibraryVisibleColumns,
        librarySortState: LibrarySortState = LibrarySortState(),
        defaultCollectionPath: String? = nil,
        recentSection: String? = "library",
        syncTodosToAppleReminders: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.libraryVisibleColumns = libraryVisibleColumns.isEmpty ? Self.defaultLibraryVisibleColumns : libraryVisibleColumns
        self.librarySortState = librarySortState
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

public enum LibrarySortField: String, CaseIterable, Hashable, Sendable {
    case title
    case authors
    case year
    case updated
    case rating
    case priority
    case status

    public nonisolated var label: String {
        switch self {
        case .title:
            return "Title"
        case .authors:
            return "Authors"
        case .year:
            return "Year"
        case .updated:
            return "Updated"
        case .rating:
            return "Rating"
        case .priority:
            return "Priority"
        case .status:
            return "Status"
        }
    }
}

public struct LibrarySortState: Hashable, Sendable {
    public var field: LibrarySortField?
    public var isAscending: Bool

    public nonisolated init(field: LibrarySortField? = nil, isAscending: Bool = true) {
        self.field = field
        self.isAscending = isAscending
    }

    public nonisolated func sorted(_ papers: [Paper]) -> [Paper] {
        guard let field else {
            return papers
        }

        return papers.enumerated()
            .sorted { first, second in
                let comparison = compare(first.element, second.element, by: field)
                if comparison == .orderedSame {
                    return first.offset < second.offset
                }

                return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            .map(\.element)
    }

    private nonisolated func compare(_ first: Paper, _ second: Paper, by field: LibrarySortField) -> ComparisonResult {
        switch field {
        case .title:
            return compareStrings(first.displayTitle, second.displayTitle)
        case .authors:
            return compareStrings(first.authorsDisplay, second.authorsDisplay)
        case .year:
            return compareOptionalInts(first.year, second.year)
        case .updated:
            return compareDates(first.updatedAt, second.updatedAt)
        case .rating:
            return compareOptionalInts(first.rating, second.rating)
        case .priority:
            return compareInts(prioritySortValue(first.priority), prioritySortValue(second.priority))
        case .status:
            return compareInts(statusSortValue(first.status), statusSortValue(second.status))
        }
    }

    private nonisolated func compareStrings(_ first: String, _ second: String) -> ComparisonResult {
        first.localizedStandardCompare(second)
    }

    private nonisolated func compareDates(_ first: Date, _ second: Date) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private nonisolated func compareOptionalInts(_ first: Int?, _ second: Int?) -> ComparisonResult {
        switch (first, second) {
        case let (first?, second?):
            return compareInts(first, second)
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private nonisolated func compareInts(_ first: Int, _ second: Int) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private nonisolated func prioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent:
            return 0
        case .high:
            return 1
        case .medium:
            return 2
        case .low:
            return 3
        }
    }

    private nonisolated func statusSortValue(_ status: ReadingStatus) -> Int {
        ReadingStatus.allCases.firstIndex(of: status) ?? ReadingStatus.allCases.count
    }
}
