import Foundation

public struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: TodoStatus
    public var dueDate: Date?
    public var tags: [String]
    public var relatedPaperIDs: [String]
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated init(
        id: String,
        title: String,
        status: TodoStatus,
        dueDate: Date?,
        tags: [String],
        relatedPaperIDs: [String],
        notes: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.dueDate = dueDate
        self.tags = tags
        self.relatedPaperIDs = relatedPaperIDs
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case open
    case inProgress
    case done
    case cancelled

    public var label: String {
        switch self {
        case .open:
            return "Open"
        case .inProgress:
            return "In Progress"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        }
    }
}