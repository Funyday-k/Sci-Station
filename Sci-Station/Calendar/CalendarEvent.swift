import Foundation

public struct CalendarEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var date: Date
    public var notes: String?

    public nonisolated init(id: String, title: String, date: Date, notes: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.notes = notes
    }
}