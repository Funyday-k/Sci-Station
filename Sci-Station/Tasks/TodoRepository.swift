import Foundation

public actor TodoRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadTodos(in workspace: ResearchWorkspace) throws -> [TodoItem] {
        let fileURL = workspace.fileURL(for: "tasks/todos.yaml")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        return decode(try String(contentsOf: fileURL, encoding: .utf8))
            .sorted { ($0.dueDate ?? .distantFuture, $0.updatedAt) < ($1.dueDate ?? .distantFuture, $1.updatedAt) }
    }

    public func upsert(_ todo: TodoItem, in workspace: ResearchWorkspace) throws {
        var todos = try loadTodos(in: workspace)

        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
        } else {
            todos.append(todo)
        }

        try saveTodos(todos, in: workspace)
    }

    public func delete(todoID: String, in workspace: ResearchWorkspace) throws {
        let todos = try loadTodos(in: workspace).filter { $0.id != todoID }
        try saveTodos(todos, in: workspace)
    }

    private func saveTodos(_ todos: [TodoItem], in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.fileURL(for: "tasks/todos.yaml")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(todos).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func encode(_ todos: [TodoItem]) -> String {
        guard !todos.isEmpty else {
            return "todos: []\n"
        }

        let formatter = makeDayFormatter()
        let body = todos.map { todo in
            var lines = [
                "  - id: \(quoted(todo.id))",
                "    title: \(quoted(todo.title))",
                "    status: \(todo.status.rawValue)",
                "    due: \(todo.dueDate.map { formatter.string(from: $0) } ?? "")"
            ]

            if todo.tags.isEmpty {
                lines.append("    tags: []")
            } else {
                lines.append("    tags:")
                lines.append(contentsOf: todo.tags.map { "      - \(quoted($0))" })
            }

            if todo.relatedPaperIDs.isEmpty {
                lines.append("    related_papers: []")
            } else {
                lines.append("    related_papers:")
                lines.append(contentsOf: todo.relatedPaperIDs.map { "      - \(quoted($0))" })
            }

            lines.append("    notes: \(todo.notes.map(quoted) ?? "")")
            lines.append("    created: \(formatter.string(from: todo.createdAt))")
            lines.append("    updated: \(formatter.string(from: todo.updatedAt))")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")

        return "todos:\n\(body)\n"
    }

    private func decode(_ contents: String) -> [TodoItem] {
        let lines = contents.components(separatedBy: .newlines)
        var todos: [TodoItem] = []
        var cursor = 0

        while cursor < lines.count {
            let trimmedLine = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("- id:") else {
                cursor += 1
                continue
            }

            let id = unquoted(trimmedLine.replacingOccurrences(of: "- id:", with: "").trimmingCharacters(in: .whitespaces))
            var title = ""
            var status = TodoStatus.open
            var dueDate: Date?
            var tags: [String] = []
            var relatedPaperIDs: [String] = []
            var notes: String?
            var createdAt = Date()
            var updatedAt = Date()
            cursor += 1

            while cursor < lines.count {
                let line = lines[cursor]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    cursor += 1
                    continue
                }
                if trimmed.hasPrefix("- id:") {
                    break
                }
                if trimmed.hasPrefix("title:") {
                    title = unquoted(trimmed.replacingOccurrences(of: "title:", with: "").trimmingCharacters(in: .whitespaces))
                } else if trimmed.hasPrefix("status:") {
                    status = TodoStatus(rawValue: trimmed.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)) ?? .open
                } else if trimmed.hasPrefix("due:") {
                    dueDate = parseDate(trimmed.replacingOccurrences(of: "due:", with: "").trimmingCharacters(in: .whitespaces))
                } else if trimmed == "tags:" {
                    let result = parseIndentedArray(from: lines, start: cursor + 1)
                    tags = result.values
                    cursor = result.nextIndex - 1
                } else if trimmed == "related_papers:" {
                    let result = parseIndentedArray(from: lines, start: cursor + 1)
                    relatedPaperIDs = result.values
                    cursor = result.nextIndex - 1
                } else if trimmed.hasPrefix("notes:") {
                    notes = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "notes:", with: "").trimmingCharacters(in: .whitespaces)))
                } else if trimmed.hasPrefix("created:") {
                    createdAt = parseDate(trimmed.replacingOccurrences(of: "created:", with: "").trimmingCharacters(in: .whitespaces)) ?? createdAt
                } else if trimmed.hasPrefix("updated:") {
                    updatedAt = parseDate(trimmed.replacingOccurrences(of: "updated:", with: "").trimmingCharacters(in: .whitespaces)) ?? updatedAt
                }
                cursor += 1
            }

            todos.append(
                TodoItem(
                    id: id,
                    title: title,
                    status: status,
                    dueDate: dueDate,
                    tags: tags,
                    relatedPaperIDs: relatedPaperIDs,
                    notes: notes,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return todos
    }

    private func parseIndentedArray(from lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("-") {
                break
            }

            values.append(unquoted(trimmed.replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)).trimmingCharacters(in: .whitespaces)))
            cursor += 1
        }

        return (values, cursor)
    }

    private func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else {
            return nil
        }

        return makeDayFormatter().date(from: value)
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }

        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}