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
    public var inspireID: String?
    public var url: String?
    public var pdfURL: String?
    public var abstract: String?
    public var categories: [String]
    public var collectionPath: String?
    public var pdfRelativePath: String?
    public var tags: [String]
    public var status: ReadingStatus
    public var priority: Priority
    public var rating: Int?
    public var useFor: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var lastReadAt: Date?
    public var lastReadPage: Int?
    public var paperDirectoryRelativePath: String
    public var notesSummaryRelativePath: String?
    public var annotationsRelativePath: String?

    public nonisolated init(
        id: String, citekey: String, title: String, authors: [String], year: Int?,
        venue: String?, doi: String?, arxiv: String?, inspireID: String? = nil,
        url: String?, pdfURL: String? = nil, abstract: String? = nil, categories: [String] = [],
        collectionPath: String? = nil,
        pdfRelativePath: String?, tags: [String], status: ReadingStatus,
        priority: Priority, rating: Int?, useFor: [String],
        createdAt: Date, updatedAt: Date, lastReadAt: Date? = nil,
        lastReadPage: Int? = nil,
        paperDirectoryRelativePath: String,
        notesSummaryRelativePath: String?, annotationsRelativePath: String?
    ) {
        self.id = id; self.citekey = citekey; self.title = title; self.authors = authors
        self.year = year; self.venue = venue; self.doi = doi; self.arxiv = arxiv
        self.inspireID = inspireID; self.url = url; self.pdfURL = pdfURL
        self.abstract = abstract; self.categories = categories
        self.collectionPath = collectionPath ?? Self.collectionPath(for: paperDirectoryRelativePath)
        self.pdfRelativePath = pdfRelativePath; self.tags = tags
        self.status = status; self.priority = priority; self.rating = rating
        self.useFor = useFor; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
        self.lastReadPage = lastReadPage
        self.paperDirectoryRelativePath = paperDirectoryRelativePath
        self.notesSummaryRelativePath = notesSummaryRelativePath
        self.annotationsRelativePath = annotationsRelativePath
    }

    public nonisolated init(
        id: String, citekey: String, title: String, authors: [String], year: Int?,
        venue: String?, doi: String?, arxiv: String?, url: String?,
        pdfRelativePath: String?, tags: [String], status: ReadingStatus,
        priority: Priority, rating: Int?, useFor: [String],
        createdAt: Date, updatedAt: Date, directoryRelativePath: String,
        notesSummaryRelativePath: String?, annotationsRelativePath: String?
    ) {
        self.init(
            id: id,
            citekey: citekey,
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            doi: doi,
            arxiv: arxiv,
            url: url,
            pdfRelativePath: pdfRelativePath,
            tags: tags,
            status: status,
            priority: priority,
            rating: rating,
            useFor: useFor,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastReadPage: nil,
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: notesSummaryRelativePath,
            annotationsRelativePath: annotationsRelativePath
        )
    }

    public var directoryRelativePath: String {
        get { paperDirectoryRelativePath }
        set {
            paperDirectoryRelativePath = newValue
            collectionPath = Self.collectionPath(for: newValue)
        }
    }

    public nonisolated var displayTitle: String {
        title.isEmpty ? id : title
    }

    public nonisolated var authorsDisplay: String {
        authors.isEmpty ? "Unknown" : authors.joined(separator: ", ")
    }

    public nonisolated var tagsDisplay: String {
        tags.isEmpty ? "-" : tags.joined(separator: ", ")
    }

    public nonisolated var yearText: String {
        year.map(String.init) ?? "-"
    }

    public nonisolated var ratingText: String {
        rating.map(String.init) ?? "-"
    }

    public nonisolated var updatedText: String {
        updatedAt.formatted(date: .abbreviated, time: .omitted)
    }

    public nonisolated func pdfURL(in workspace: ResearchWorkspace) -> URL? {
        guard let pdfRelativePath else {
            return nil
        }

        let directoryURL = workspace.directoryURL(for: paperDirectoryRelativePath)
        return workspace.resolve(relativePath: pdfRelativePath, from: directoryURL, isDirectory: false)
    }

    public nonisolated func rawMarkdownURL(in workspace: ResearchWorkspace) -> URL {
        let directoryURL = workspace.directoryURL(for: paperDirectoryRelativePath)
        return workspace.resolve(relativePath: "paper.md", from: directoryURL, isDirectory: false)
    }

    public nonisolated func summaryURL(in workspace: ResearchWorkspace) -> URL? {
        guard let notesSummaryRelativePath else {
            return nil
        }

        let directoryURL = workspace.directoryURL(for: paperDirectoryRelativePath)
        return workspace.resolve(relativePath: notesSummaryRelativePath, from: directoryURL, isDirectory: false)
    }

    public nonisolated static func collectionPath(for paperDirectoryRelativePath: String) -> String? {
        let components = paperDirectoryRelativePath
            .split(separator: "/")
            .map(String.init)

        guard components.count > 3 else {
            return nil
        }

        guard components[0] == "raw", components[1] == "papers" else {
            return nil
        }

        let collectionComponents = components.dropFirst(2).dropLast()
        guard !collectionComponents.isEmpty else {
            return nil
        }

        return collectionComponents.joined(separator: "/")
    }

    public nonisolated static func summaryRelativePath(for citekey: String, paperDirectoryRelativePath: String) -> String {
        let depth = paperDirectoryRelativePath.split(separator: "/").count
        let prefix = Array(repeating: "..", count: depth).joined(separator: "/")
        return [prefix, "wiki", "papers", "\(citekey).md"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
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