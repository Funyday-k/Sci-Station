import Foundation

public struct PaperMetadataDraft: Codable, Hashable, Sendable {
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
    public var sourceProvider: String
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

    public nonisolated init(
        title: String,
        authors: [String],
        year: Int?,
        venue: String?,
        doi: String?,
        arxiv: String?,
        inspireID: String?,
        url: String?,
        pdfURL: String?,
        abstract: String?,
        categories: [String],
        sourceProvider: String,
        titleTranslation: String? = nil,
        itemType: String? = nil,
        publicationTitle: String? = nil,
        publisher: String? = nil,
        publicationPlace: String? = nil,
        publishedDate: String? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pages: String? = nil,
        series: String? = nil,
        seriesTitle: String? = nil,
        journalAbbreviation: String? = nil,
        issn: String? = nil,
        isbn: String? = nil,
        pmid: String? = nil,
        pmcid: String? = nil,
        language: String? = nil,
        archive: String? = nil,
        archiveLocation: String? = nil,
        libraryCatalog: String? = nil,
        callNumber: String? = nil,
        shortTitle: String? = nil,
        accessedAt: String? = nil,
        bibtex: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.doi = doi
        self.arxiv = arxiv
        self.inspireID = inspireID
        self.url = url
        self.pdfURL = pdfURL
        self.abstract = abstract
        self.categories = categories
        self.sourceProvider = sourceProvider
        self.titleTranslation = titleTranslation
        self.itemType = itemType
        self.publicationTitle = publicationTitle
        self.publisher = publisher
        self.publicationPlace = publicationPlace
        self.publishedDate = publishedDate
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.series = series
        self.seriesTitle = seriesTitle
        self.journalAbbreviation = journalAbbreviation
        self.issn = issn
        self.isbn = isbn
        self.pmid = pmid
        self.pmcid = pmcid
        self.language = language
        self.archive = archive
        self.archiveLocation = archiveLocation
        self.libraryCatalog = libraryCatalog
        self.callNumber = callNumber
        self.shortTitle = shortTitle
        self.accessedAt = accessedAt
        self.bibtex = bibtex
    }
}