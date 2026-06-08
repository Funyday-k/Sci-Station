import Foundation

public enum TodoQueries {
    public nonisolated static func isCompleted(_ todo: TodoItem) -> Bool {
        todo.status == .done || todo.status == .cancelled
    }

    public nonisolated static func isOpen(_ todo: TodoItem) -> Bool {
        !isCompleted(todo)
    }

    public nonisolated static func priorityRank(_ priority: Priority) -> Int {
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

    public nonisolated static func forProject(_ todos: [TodoItem], projectID: String) -> [TodoItem] {
        todos.filter { $0.projectIDs.contains(projectID) }
    }

    public nonisolated static func openCount(_ todos: [TodoItem]) -> Int {
        todos.filter(isOpen).count
    }

    public nonisolated static func dueThenPriority(_ first: TodoItem, _ second: TodoItem) -> Bool {
        if first.dueDate == second.dueDate {
            return priorityRank(first.priority) < priorityRank(second.priority)
        }
        return (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
    }

    public nonisolated static func dueOn(_ todos: [TodoItem], date: Date, calendar: Calendar = .current) -> [TodoItem] {
        todos
            .filter { todo in
                guard let dueDate = todo.dueDate else {
                    return false
                }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
            .sorted(by: dueThenPriority)
    }

    public nonisolated static func listSort(_ first: TodoItem, _ second: TodoItem) -> Bool {
        if first.status != second.status {
            return first.status.rawValue.localizedStandardCompare(second.status.rawValue) == .orderedAscending
        }
        if first.dueDate != second.dueDate {
            return (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }
        if first.priority != second.priority {
            return priorityRank(first.priority) < priorityRank(second.priority)
        }
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }
}
