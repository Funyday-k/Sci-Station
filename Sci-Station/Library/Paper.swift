import Foundation

public struct Paper: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var citekey: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var doi: String?
    public var arxiv: String?
    public var url: String?
    public var pdfRelativePath: String?
    public var tags: [String]
    public var status: ReadingStatus
    public var priority: Priority
    public var rating: Int?
    public var useFor: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var directoryRelativePath: String
    public var notesSummaryRelativePath: String?
    public var annotationsRelativePath: String?

    public nonisolated init(
        id: String, citekey: String, title: String, authors: [String], year: Int?,
        venue: String?, doi: String?, arxiv: String?, url: String?,
        pdfRelativePath: String?, tags: [String], status: ReadingStatus,
        priority: Priority, rating: Int?, useFor: [String],
        createdAt: Date, updatedAt: Date, directoryRelativePath: String,
        notesSummaryRelativePath: String?, annotationsRelativePath: String?
    ) {
        self.id = id; self.citekey = citekey; self.title = title; self.authors = authors
        self.year = year; self.venue = venue; self.doi = doi; self.arxiv = arxiv
        self.url = url; self.pdfRelativePath = pdfRelativePath; self.tags = tags
        self.status = status; self.priority = priority; self.rating = rating
        self.useFor = useFor; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.directoryRelativePath = directoryRelativePath
        self.notesSummaryRelativePath = notesSummaryRelativePath
        self.annotationsRelativePath = annotationsRelativePath
    }

    public var displayTitle: String {
        title.isEmpty ? id : title
    }

    public var authorsDisplay: String {
        authors.isEmpty ? "Unknown" : authors.joined(separator: ", ")
    }

    public var tagsDisplay: String {
        tags.isEmpty ? "-" : tags.joined(separator: ", ")
    }

    public var yearText: String {
        year.map(String.init) ?? "-"
    }

    public var ratingText: String {
        rating.map(String.init) ?? "-"
    }

    public var updatedText: String {
        updatedAt.formatted(date: .abbreviated, time: .omitted)
    }

    public func pdfURL(in workspace: ResearchWorkspace) -> URL? {
        guard let pdfRelativePath else {
            return nil
        }

        let directoryURL = workspace.directoryURL(for: directoryRelativePath)
        return workspace.resolve(relativePath: pdfRelativePath, from: directoryURL, isDirectory: false)
    }
}

public enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case unread
    case skimmed
    case deepRead
    case summarized
    case used
    case rejected

    public var label: String {
        switch self {
        case .unread:
            return "Unread"
        case .skimmed:
            return "Skimmed"
        case .deepRead:
            return "Deep Read"
        case .summarized:
            return "Summarized"
        case .used:
            return "Used"
        case .rejected:
            return "Rejected"
        }
    }
}

public enum Priority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case urgent

    public var label: String {
        rawValue.capitalized
    }
}