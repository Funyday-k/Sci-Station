import Foundation

public struct Paper: Identifiable, Codable, Hashable, Sendable {
    public nonisolated static let globalLibraryRootRelativePath = "library/papers"
    public nonisolated static let legacyLibraryRootRelativePath = "raw/papers"

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
    public var titleTranslation: String?
    public var itemType: String?
    public var publicationTitle: String?
    public var publisher: String?
    public var publicationPlace: String?
    public var publishedDate: String?
    public var volume: String?
    public var issue: String?
    public var pages: String?
    public var series: String?
    public var seriesTitle: String?
    public var journalAbbreviation: String?
    public var issn: String?
    public var isbn: String?
    public var pmid: String?
    public var pmcid: String?
    public var language: String?
    public var archive: String?
    public var archiveLocation: String?
    public var libraryCatalog: String?
    public var callNumber: String?
    public var shortTitle: String?
    public var accessedAt: String?
    public var bibtex: String?
    public var collectionPath: String?
    public var pdfRelativePath: String?
    public var tags: [String]
    public var status: ReadingStatus
    public var priority: Priority
    public var rating: Int?
    public var projectIDs: [String] = []
    public var coreProjectIDs: [String] = []
    public var folderPath: String? = nil
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
        titleTranslation: String? = nil, itemType: String? = nil,
        publicationTitle: String? = nil, publisher: String? = nil,
        publicationPlace: String? = nil, publishedDate: String? = nil,
        volume: String? = nil, issue: String? = nil, pages: String? = nil,
        series: String? = nil, seriesTitle: String? = nil,
        journalAbbreviation: String? = nil, issn: String? = nil, isbn: String? = nil,
        pmid: String? = nil, pmcid: String? = nil, language: String? = nil,
        archive: String? = nil, archiveLocation: String? = nil,
        libraryCatalog: String? = nil, callNumber: String? = nil,
        shortTitle: String? = nil, accessedAt: String? = nil,
        bibtex: String? = nil,
        collectionPath: String? = nil,
        projectIDs: [String] = [], coreProjectIDs: [String] = [], folderPath: String? = nil,
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
        self.titleTranslation = titleTranslation; self.itemType = itemType
        self.publicationTitle = publicationTitle; self.publisher = publisher
        self.publicationPlace = publicationPlace; self.publishedDate = publishedDate
        self.volume = volume; self.issue = issue; self.pages = pages
        self.series = series; self.seriesTitle = seriesTitle
        self.journalAbbreviation = journalAbbreviation; self.issn = issn; self.isbn = isbn
        self.pmid = pmid; self.pmcid = pmcid; self.language = language
        self.archive = archive; self.archiveLocation = archiveLocation
        self.libraryCatalog = libraryCatalog; self.callNumber = callNumber
        self.shortTitle = shortTitle; self.accessedAt = accessedAt
        self.bibtex = bibtex
        self.collectionPath = collectionPath ?? Self.collectionPath(for: paperDirectoryRelativePath)
        self.pdfRelativePath = pdfRelativePath; self.tags = tags
        self.status = status; self.priority = priority; self.rating = rating
        self.useFor = useFor; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
        self.lastReadPage = lastReadPage
        self.paperDirectoryRelativePath = paperDirectoryRelativePath
        self.notesSummaryRelativePath = notesSummaryRelativePath
        self.annotationsRelativePath = annotationsRelativePath
        self.projectIDs = projectIDs
        self.coreProjectIDs = coreProjectIDs
        self.folderPath = folderPath ?? self.collectionPath
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
            folderPath = collectionPath
        }
    }

    public nonisolated var displayTitle: String {
        title.isEmpty ? id : title
    }

    public nonisolated var authorsDisplay: String {
        authors.isEmpty ? "Unknown" : authors.joined(separator: ", ")
    }

    public nonisolated var publicationDisplay: String {
        publicationTitle ?? venue ?? "-"
    }

    public nonisolated var tagsDisplay: String {
        tags.isEmpty ? "-" : tags.joined(separator: ", ")
    }

    public nonisolated var folderDisplay: String {
        folderPath ?? collectionPath ?? "Unfiled"
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

    public nonisolated func belongs(to projectID: String) -> Bool {
        projectIDs.contains(projectID)
    }

    public nonisolated func isCorePaper(in projectID: String) -> Bool {
        coreProjectIDs.contains(projectID)
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

    public nonisolated func annotationsURL(in workspace: ResearchWorkspace) -> URL {
        let directoryURL = workspace.directoryURL(for: paperDirectoryRelativePath)
        return workspace.resolve(relativePath: annotationsRelativePath ?? "annotations.md", from: directoryURL, isDirectory: false)
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

        let isGlobalLibraryPath = components[0] == "library" && components[1] == "papers"
        let isLegacyLibraryPath = components[0] == "raw" && components[1] == "papers"
        guard isGlobalLibraryPath || isLegacyLibraryPath else {
            return nil
        }

        let collectionComponents = components.dropFirst(2).dropLast()
        guard !collectionComponents.isEmpty else {
            return nil
        }

        return collectionComponents.joined(separator: "/")
    }

    public nonisolated static func directoryRelativePath(for paperID: String, collectionPath: String?) -> String {
        let normalizedCollectionPath = collectionPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard let normalizedCollectionPath, !normalizedCollectionPath.isEmpty else {
            return "\(globalLibraryRootRelativePath)/\(paperID)"
        }

        return "\(globalLibraryRootRelativePath)/\(normalizedCollectionPath)/\(paperID)"
    }

    public nonisolated static func storageRootRelativePath(for paperDirectoryRelativePath: String) -> String? {
        let components = paperDirectoryRelativePath
            .split(separator: "/")
            .map(String.init)

        guard components.count >= 2 else {
            return nil
        }

        if components[0] == "library", components[1] == "papers" {
            return globalLibraryRootRelativePath
        }

        if components[0] == "raw", components[1] == "papers" {
            return legacyLibraryRootRelativePath
        }

        return nil
    }

    public nonisolated var isStoredInGlobalLibrary: Bool {
        Self.storageRootRelativePath(for: paperDirectoryRelativePath) == Self.globalLibraryRootRelativePath
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