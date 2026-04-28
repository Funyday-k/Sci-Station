import Foundation

public actor CalendarRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadEvents(in workspace: ResearchWorkspace) throws -> [CalendarEvent] {
        let fileURL = workspace.fileURL(for: "tasks/calendar.yaml")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return decode(contents)
    }

    private func decode(_ contents: String) -> [CalendarEvent] {
        let formatter = makeDayFormatter()
        var events: [CalendarEvent] = []
        var current: [String: String] = [:]

        func commitCurrent() {
            guard let id = current["id"],
                  let title = current["title"],
                  let dateString = current["date"],
                  let date = formatter.date(from: dateString) else {
                current = [:]
                return
            }

            events.append(CalendarEvent(
                id: id,
                title: title,
                date: date,
                category: current["category"] ?? "Project",
                colorHex: current["color"],
                projectID: current["project_id"],
                notes: current["notes"]
            ))
            current = [:]
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "events:", trimmed != "events: []" else {
                continue
            }

            if trimmed.hasPrefix("- id:") {
                commitCurrent()
                current["id"] = unquoted(trimmed.replacingOccurrences(of: "- id:", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("title:") {
                current["title"] = unquoted(trimmed.replacingOccurrences(of: "title:", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("date:") {
                current["date"] = trimmed.replacingOccurrences(of: "date:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("category:") {
                current["category"] = unquoted(trimmed.replacingOccurrences(of: "category:", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("color:") {
                current["color"] = unquoted(trimmed.replacingOccurrences(of: "color:", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("project_id:") {
                current["project_id"] = unquoted(trimmed.replacingOccurrences(of: "project_id:", with: "").trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("notes:") {
                current["notes"] = unquoted(trimmed.replacingOccurrences(of: "notes:", with: "").trimmingCharacters(in: .whitespaces))
            }
        }

        commitCurrent()
        return events
    }

    private func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
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
}