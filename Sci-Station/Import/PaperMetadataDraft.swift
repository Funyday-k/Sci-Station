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
        sourceProvider: String
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
    }
}