import Foundation

public struct LibrarySearchService: Sendable {
    public nonisolated init() {}

    public nonisolated func matches(_ paper: Paper, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return searchableValues(for: paper).contains { value in
            value.lowercased().contains(normalizedQuery)
        }
    }

    public nonisolated func matchingIDs(in papers: [Paper], query: String) -> [Paper.ID] {
        papers.filter { matches($0, query: query) }.map(\.id)
    }

    private nonisolated func searchableValues(for paper: Paper) -> [String] {
        [
            paper.title,
            paper.titleTranslation,
            paper.shortTitle,
            paper.citekey,
            paper.authors.joined(separator: " "),
            paper.tags.joined(separator: " "),
            paper.doi,
            paper.arxiv,
            paper.inspireID,
            paper.url,
            paper.pdfURL,
            paper.abstract,
            paper.bibtex,
            paper.publicationTitle,
            paper.venue,
            paper.publisher,
            paper.archive,
            paper.archiveLocation,
            paper.categories.joined(separator: " "),
            paper.useFor.joined(separator: " ")
        ]
        .compactMap { $0 }
    }
}
