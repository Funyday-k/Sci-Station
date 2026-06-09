import Foundation

public struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: TodoKind
    public var status: TodoStatus
    /// Optional start of a multi-day date range. When `nil`, the todo is a
    /// single-day item anchored on `dueDate`. When set, the todo spans
    /// `startDate ... dueDate`.
    public var startDate: Date?
    public var dueDate: Date?
    public var priority: Priority
    public var projectIDs: [String]
    public var tags: [String]
    public var relatedPaperIDs: [String]
    public var notes: String?
    public var externalSource: String?
    public var externalIdentifier: String?
    public var externalUpdatedAt: Date?
    public var completedAt: Date?
    public var dueTime: String?
    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated init(
        id: String,
        title: String,
        kind: TodoKind = .general,
        status: TodoStatus,
        startDate: Date? = nil,
        dueDate: Date?,
        priority: Priority = .medium,
        projectIDs: [String] = [],
        tags: [String],
        relatedPaperIDs: [String],
        notes: String?,
        externalSource: String? = nil,
        externalIdentifier: String? = nil,
        externalUpdatedAt: Date? = nil,
        completedAt: Date? = nil,
        dueTime: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.startDate = startDate
        self.dueDate = dueDate
        self.priority = priority
        self.projectIDs = projectIDs
        self.tags = tags
        self.relatedPaperIDs = relatedPaperIDs
        self.notes = notes
        self.externalSource = externalSource
        self.externalIdentifier = externalIdentifier
        self.externalUpdatedAt = externalUpdatedAt
        self.completedAt = completedAt
        self.dueTime = dueTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TodoItem {
    /// Whether the todo carries an explicit multi-day range.
    public var hasDateRange: Bool {
        guard let startDate, let dueDate else { return false }
        return !Calendar.current.isDate(startDate, inSameDayAs: dueDate) && startDate < dueDate
    }
}

public enum TodoKind: String, Codable, CaseIterable, Sendable {
    case general
    case reading

    public var label: String {
        switch self {
        case .general:
            return "普通任务"
        case .reading:
            return "论文阅读"
        }
    }

    public var englishLabel: String {
        switch self {
        case .general:
            return "General"
        case .reading:
            return "Reading"
        }
    }

    /// SF Symbol used to represent the task kind across the Tasks UI.
    public var systemImage: String {
        switch self {
        case .general:
            return "checklist"
        case .reading:
            return "book"
        }
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
            return "待处理"
        case .inProgress:
            return "进行中"
        case .done:
            return "已完成"
        case .cancelled:
            return "已取消"
        }
    }

    public var englishLabel: String {
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