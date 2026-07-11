import Foundation
import PDFKit

public enum PDFImportError: LocalizedError {
    case unsupportedFileType

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Only PDF files can be imported."
        }
    }
}

public actor PDFImportService {
    private let fileManager: FileManager
    private let repository: PaperRepository
    private let parser: IdentifierParser
    private let doiProvider: DOIMetadataProvider
    private let arxivProvider: ArxivMetadataProvider

    public init(
        fileManager: FileManager = .default,
        repository: PaperRepository,
        parser: IdentifierParser = IdentifierParser(),
        doiProvider: DOIMetadataProvider = DOIMetadataProvider(),
        arxivProvider: ArxivMetadataProvider = ArxivMetadataProvider()
    ) {
        self.fileManager = fileManager
        self.repository = repository
        self.parser = parser
        self.doiProvider = doiProvider
        self.arxivProvider = arxivProvider
    }

    public func importPDF(
        from sourceURL: URL,
        into workspace: ResearchWorkspace,
        existingPapers: [Paper],
        collectionPath: String = "Uncategorized"
    ) async throws -> Paper {
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw PDFImportError.unsupportedFileType
        }

        let detectedIdentifiers = detectIdentifiers(from: sourceURL)
        let metadataDraft = await fetchedMetadata(for: detectedIdentifiers)
        let title = resolvedTitle(from: metadataDraft, sourceURL: sourceURL)
        let authors = resolvedAuthors(from: metadataDraft, sourceURL: sourceURL)
        let year = metadataDraft?.year ?? detectedYear(from: sourceURL)
        let paperID = PaperIdentityGenerator.paperID(
            title: title,
            authors: authors,
            year: year,
            existing: Set(existingPapers.map(\.id))
        )
        let citekey = PaperIdentityGenerator.citekey(
            title: title,
            authors: authors,
            year: year,
            existing: Set(existingPapers.map(\.citekey))
        )

        try fileManager.createDirectory(at: workspace.inboxURL, withIntermediateDirectories: true)

        let stagedPDFURL = uniqueFileURL(
            in: workspace.inboxURL,
            preferredFileName: sourceURL.lastPathComponent
        )
        try fileManager.copyItem(at: sourceURL, to: stagedPDFURL)

        let normalizedCollectionPath = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryRelativePath = try Paper.directoryRelativePath(
            for: paperID,
            collectionPath: normalizedCollectionPath
        )
        let paperDirectoryURL = try await WorkspaceFileSystem(rootURL: workspace.rootURL).resolvedURL(
            WorkspaceRelativePath(directoryRelativePath),
            isDirectory: true
        )
        try fileManager.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)

        let normalizedPDFURL = paperDirectoryURL.appendingPathComponent("paper.pdf", isDirectory: false)
        try fileManager.moveItem(at: stagedPDFURL, to: normalizedPDFURL)

        let figuresURL = paperDirectoryURL.appendingPathComponent("figures", isDirectory: true)
        try fileManager.createDirectory(at: figuresURL, withIntermediateDirectories: true)

        let paperMarkdownURL = paperDirectoryURL.appendingPathComponent("paper.md", isDirectory: false)
        if !fileManager.fileExists(atPath: paperMarkdownURL.path) {
            try rawPaperTemplate(citekey: citekey).write(to: paperMarkdownURL, atomically: true, encoding: .utf8)
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
            authors: authors,
            year: year,
            venue: trimmedOrNil(metadataDraft?.venue),
            doi: trimmedOrNil(metadataDraft?.doi) ?? detectedIdentifiers.doi,
            arxiv: trimmedOrNil(metadataDraft?.arxiv) ?? detectedIdentifiers.arxiv,
            url: resolvedSourceURL(from: metadataDraft, identifiers: detectedIdentifiers),
            pdfURL: trimmedOrNil(metadataDraft?.pdfURL),
            abstract: trimmedOrNil(metadataDraft?.abstract),
            categories: metadataDraft?.categories ?? [],
            titleTranslation: trimmedOrNil(metadataDraft?.titleTranslation),
            itemType: trimmedOrNil(metadataDraft?.itemType),
            publicationTitle: trimmedOrNil(metadataDraft?.publicationTitle),
            publisher: trimmedOrNil(metadataDraft?.publisher),
            publicationPlace: trimmedOrNil(metadataDraft?.publicationPlace),
            publishedDate: trimmedOrNil(metadataDraft?.publishedDate),
            volume: trimmedOrNil(metadataDraft?.volume),
            issue: trimmedOrNil(metadataDraft?.issue),
            pages: trimmedOrNil(metadataDraft?.pages),
            series: trimmedOrNil(metadataDraft?.series),
            seriesTitle: trimmedOrNil(metadataDraft?.seriesTitle),
            journalAbbreviation: trimmedOrNil(metadataDraft?.journalAbbreviation),
            issn: trimmedOrNil(metadataDraft?.issn),
            isbn: trimmedOrNil(metadataDraft?.isbn),
            pmid: trimmedOrNil(metadataDraft?.pmid),
            pmcid: trimmedOrNil(metadataDraft?.pmcid),
            language: trimmedOrNil(metadataDraft?.language),
            archive: trimmedOrNil(metadataDraft?.archive),
            archiveLocation: trimmedOrNil(metadataDraft?.archiveLocation),
            libraryCatalog: trimmedOrNil(metadataDraft?.libraryCatalog),
            callNumber: trimmedOrNil(metadataDraft?.callNumber),
            shortTitle: trimmedOrNil(metadataDraft?.shortTitle),
            accessedAt: trimmedOrNil(metadataDraft?.accessedAt),
            bibtex: trimmedOrNil(metadataDraft?.bibtex),
            pdfRelativePath: "paper.pdf",
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            lastReadPage: nil,
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: Paper.summaryRelativePath(for: citekey, paperDirectoryRelativePath: directoryRelativePath),
            annotationsRelativePath: "annotations.md"
        )

        let savedPaper = try await repository.save(paper, in: workspace)
        try await repository.appendBibliographyStub(for: savedPaper, in: workspace)
        return savedPaper
    }

    private func rawPaperTemplate(citekey: String) -> String {
        """
        ---
        type: raw-paper
        citekey: \(citekey)
        source_pdf: paper.pdf
        status: not_extracted
        ---

        # Raw Text

        PDF text has not been extracted yet.

        ## Extraction Notes

        - Source: paper.pdf
        - Method: pending
        """
    }

    private func uniqueFileURL(in directoryURL: URL, preferredFileName: String) -> URL {
        let fileExtension = URL(fileURLWithPath: preferredFileName).pathExtension
        let baseName = URL(fileURLWithPath: preferredFileName).deletingPathExtension().lastPathComponent
        var candidateURL = directoryURL.appendingPathComponent(preferredFileName, isDirectory: false)
        var counter = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            let suffix = "-\(counter)"
            let candidateName = fileExtension.isEmpty
                ? baseName + suffix
                : baseName + suffix + "." + fileExtension
            candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false)
            counter += 1
        }

        return candidateURL
    }

    private func resolvedTitle(from metadataDraft: PaperMetadataDraft?, sourceURL: URL) -> String {
        if let title = trimmedOrNil(metadataDraft?.title) {
            return title
        }

        if let documentTitle = documentAttribute(.titleAttribute, from: sourceURL) {
            return documentTitle
        }

        return sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func resolvedAuthors(from metadataDraft: PaperMetadataDraft?, sourceURL: URL) -> [String] {
        let metadataAuthors = metadataDraft?.authors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return metadataAuthors.isEmpty ? documentAuthors(from: sourceURL) : metadataAuthors
    }

    private func documentAuthors(from sourceURL: URL) -> [String] {
        guard let authorText = documentAttribute(.authorAttribute, from: sourceURL) else {
            return []
        }

        return authorText
            .replacingOccurrences(of: " and ", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func documentAttribute(_ attribute: PDFDocumentAttribute, from sourceURL: URL) -> String? {
        guard let document = PDFDocument(url: sourceURL),
              let value = document.documentAttributes?[attribute] as? String else {
            return nil
        }

        return trimmedOrNil(value)
    }

    private func detectedYear(from sourceURL: URL) -> Int? {
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = try? NSRegularExpression(pattern: "(19|20)\\d{2}")
            .firstMatch(in: filename, range: range),
            let matchRange = Range(match.range, in: filename) else {
            return nil
        }

        return Int(String(filename[matchRange]))
    }

    private func detectIdentifiers(from sourceURL: URL) -> DetectedPaperIdentifiers {
        let previewText = extractedPreviewText(from: sourceURL)
        return parser.detectPaperIdentifiers(in: previewText, fallbackInput: sourceURL.lastPathComponent)
    }

    private func extractedPreviewText(from sourceURL: URL) -> String {
        guard let document = PDFDocument(url: sourceURL) else {
            return sourceURL.lastPathComponent
        }

        let previewPageCount = min(document.pageCount, 5)
        let previewText = (0..<previewPageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        return [previewText, sourceURL.lastPathComponent]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func fetchedMetadata(for identifiers: DetectedPaperIdentifiers) async -> PaperMetadataDraft? {
        if let doi = identifiers.doi,
           let draft = try? await doiProvider.fetchMetadata(for: doi) {
            var enrichedDraft = draft
            enrichedDraft.arxiv = trimmedOrNil(enrichedDraft.arxiv) ?? identifiers.arxiv
            return enrichedDraft
        }

        if let arxiv = identifiers.arxiv,
           let draft = try? await arxivProvider.fetchMetadata(for: arxiv) {
            var enrichedDraft = draft
            enrichedDraft.doi = trimmedOrNil(enrichedDraft.doi) ?? identifiers.doi
            return enrichedDraft
        }

        return nil
    }

    private func resolvedSourceURL(from metadataDraft: PaperMetadataDraft?, identifiers: DetectedPaperIdentifiers) -> String? {
        if let resolvedURL = trimmedOrNil(metadataDraft?.url) {
            return resolvedURL
        }

        if let doi = identifiers.doi {
            return "https://doi.org/\(doi)"
        }

        if let arxiv = identifiers.arxiv {
            return "https://arxiv.org/abs/\(arxiv)"
        }

        return nil
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
