import Foundation

public struct CalendarEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var date: Date
    public var category: String
    public var colorHex: String?
    public var projectID: String?
    public var notes: String?

    public nonisolated init(
        id: String,
        title: String,
        date: Date,
        category: String = "Project",
        colorHex: String? = nil,
        projectID: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.category = category
        self.colorHex = colorHex
        self.projectID = projectID
        self.notes = notes
    }
}