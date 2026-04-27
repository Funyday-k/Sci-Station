import Foundation

public actor LinkOnlyImportService {
    private let fileManager: FileManager
    private let repository: PaperRepository

    public init(fileManager: FileManager = .default, repository: PaperRepository) {
        self.fileManager = fileManager
        self.repository = repository
    }

    public func importDraft(
        _ draft: PaperMetadataDraft,
        into workspace: ResearchWorkspace,
        existingPapers: [Paper],
        collectionPath: String,
        tags: [String]
    ) async throws -> Paper {
        let normalizedCollectionPath = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedOrNil(draft.title) ?? draft.url ?? draft.doi ?? draft.arxiv ?? "Imported Link"
        let paperID = PaperIdentityGenerator.paperID(
            title: title,
            authors: draft.authors,
            year: draft.year,
            existing: Set(existingPapers.map(\.id))
        )
        let citekey = PaperIdentityGenerator.citekey(
            title: title,
            authors: draft.authors,
            year: draft.year,
            existing: Set(existingPapers.map(\.citekey))
        )

        let directoryRelativePath = normalizedCollectionPath.isEmpty
            ? "raw/papers/\(paperID)"
            : "raw/papers/\(normalizedCollectionPath)/\(paperID)"
        let paperDirectoryURL = workspace.directoryURL(for: directoryRelativePath)
        try fileManager.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paperDirectoryURL.appendingPathComponent("figures", isDirectory: true), withIntermediateDirectories: true)

        let paperMarkdownURL = paperDirectoryURL.appendingPathComponent("paper.md", isDirectory: false)
        if !fileManager.fileExists(atPath: paperMarkdownURL.path) {
            try linkTemplate(from: draft).write(to: paperMarkdownURL, atomically: true, encoding: .utf8)
        }

        let annotationsURL = paperDirectoryURL.appendingPathComponent("annotations.md", isDirectory: false)
        if !fileManager.fileExists(atPath: annotationsURL.path) {
            try "# Annotations\n\n".write(to: annotationsURL, atomically: true, encoding: .utf8)
        }

        let now = Date()
        let paper = Paper(
            id: paperID,
            citekey: citekey,
            title: title,
            authors: draft.authors,
            year: draft.year,
            venue: draft.venue,
            doi: draft.doi,
            arxiv: draft.arxiv,
            inspireID: draft.inspireID,
            url: draft.url,
            pdfURL: draft.pdfURL,
            abstract: draft.abstract,
            categories: draft.categories,
            collectionPath: trimmedOrNil(normalizedCollectionPath),
            pdfRelativePath: nil,
            tags: tags,
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: Paper.summaryRelativePath(for: citekey, paperDirectoryRelativePath: directoryRelativePath),
            annotationsRelativePath: "annotations.md"
        )

        let savedPaper = try await repository.save(paper, in: workspace)
        try await repository.appendBibliographyStub(for: savedPaper, in: workspace)
        return savedPaper
    }

    private func linkTemplate(from draft: PaperMetadataDraft) -> String {
        let source = draft.url ?? draft.pdfURL ?? draft.doi ?? draft.arxiv ?? ""
        let abstract = draft.abstract.flatMap(trimmedOrNil(_:)) ?? "Metadata imported without local PDF."
        return """
        ---
        type: raw-link
        source_url: \(source)
        status: imported
        ---

        # Imported Link

        \(abstract)
        """
    }

    nonisolated private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}