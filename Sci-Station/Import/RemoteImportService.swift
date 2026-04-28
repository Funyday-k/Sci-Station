import Foundation

public enum RemoteImportError: LocalizedError {
    case unsupportedIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedIdentifier(value):
            return "Unsupported import identifier: \(value)"
        }
    }
}

public actor RemoteImportService {
    private let parser: IdentifierParser
    private let doiProvider: DOIMetadataProvider
    private let arxivProvider: ArxivMetadataProvider
    private let inspireProvider: InspireMetadataProvider
    private let downloadService: DownloadService
    private let pdfImportService: PDFImportService
    private let linkOnlyImportService: LinkOnlyImportService
    private let paperRepository: PaperRepository

    public init(
        parser: IdentifierParser = IdentifierParser(),
        doiProvider: DOIMetadataProvider = DOIMetadataProvider(),
        arxivProvider: ArxivMetadataProvider = ArxivMetadataProvider(),
        inspireProvider: InspireMetadataProvider = InspireMetadataProvider(),
        downloadService: DownloadService = DownloadService(),
        pdfImportService: PDFImportService,
        linkOnlyImportService: LinkOnlyImportService,
        paperRepository: PaperRepository = PaperRepository()
    ) {
        self.parser = parser
        self.doiProvider = doiProvider
        self.arxivProvider = arxivProvider
        self.inspireProvider = inspireProvider
        self.downloadService = downloadService
        self.pdfImportService = pdfImportService
        self.linkOnlyImportService = linkOnlyImportService
        self.paperRepository = paperRepository
    }

    public func preview(for input: String) async throws -> PaperMetadataDraft {
        let parsedIdentifier = parser.parse(input)

        switch parsedIdentifier.kind {
        case .arxiv:
            return await previewArxivMetadata(for: parsedIdentifier.normalizedValue, doi: nil)
        case .inspire:
            return try await inspireProvider.fetchMetadata(for: parsedIdentifier.normalizedValue)
        case .doi:
            return await previewDOIMetadata(for: parsedIdentifier.normalizedValue)
        case .pdfURL:
            return PaperMetadataDraft(
                title: URL(string: parsedIdentifier.normalizedValue)?.deletingPathExtension().lastPathComponent ?? "Imported PDF",
                authors: [],
                year: nil,
                venue: nil,
                doi: nil,
                arxiv: nil,
                inspireID: nil,
                url: parsedIdentifier.normalizedValue,
                pdfURL: parsedIdentifier.normalizedValue,
                abstract: nil,
                categories: [],
                sourceProvider: "pdf-url"
            )
        case .url:
            return PaperMetadataDraft(
                title: URL(string: parsedIdentifier.normalizedValue)?.host ?? parsedIdentifier.normalizedValue,
                authors: [],
                year: nil,
                venue: nil,
                doi: nil,
                arxiv: nil,
                inspireID: nil,
                url: parsedIdentifier.normalizedValue,
                pdfURL: nil,
                abstract: nil,
                categories: [],
                sourceProvider: "url"
            )
        case .unknown:
            throw RemoteImportError.unsupportedIdentifier(input)
        }
    }

    private func previewArxivMetadata(for arxivID: String, doi: String?) async -> PaperMetadataDraft {
        do {
            var draft = try await arxivProvider.fetchMetadata(for: arxivID)
            draft.doi = draft.doi ?? doi
            return draft
        } catch {
            return fallbackArxivDraft(for: arxivID, doi: doi)
        }
    }

    private func previewDOIMetadata(for doi: String) async -> PaperMetadataDraft {
        if let arxivID = parser.extractArxivID(from: doi), doi.localizedCaseInsensitiveContains("arxiv") {
            return await previewArxivMetadata(for: arxivID, doi: doi)
        }

        do {
            return try await doiProvider.fetchMetadata(for: doi)
        } catch {
            return fallbackDOIDraft(for: doi)
        }
    }

    public func importItem(
        from input: String,
        draftPreview: PaperMetadataDraft?,
        into workspace: ResearchWorkspace,
        existingPapers: [Paper],
        collectionPath: String,
        tags: [String]
    ) async throws -> Paper {
        let draft: PaperMetadataDraft
        if let draftPreview {
            draft = draftPreview
        } else {
            draft = try await self.preview(for: input)
        }

        if let pdfURLString = draft.pdfURL,
           let pdfURL = URL(string: pdfURLString) {
            do {
                let downloadedPDFURL = try await downloadService.downloadPDF(from: pdfURL)
                var importedPaper = try await pdfImportService.importPDF(
                    from: downloadedPDFURL,
                    into: workspace,
                    existingPapers: existingPapers,
                    collectionPath: collectionPath
                )
                importedPaper = merged(importedPaper, with: draft, tags: tags)
                return try await paperRepository.save(importedPaper, in: workspace)
            } catch {
                return try await linkOnlyImportService.importDraft(
                    draft,
                    into: workspace,
                    existingPapers: existingPapers,
                    collectionPath: collectionPath,
                    tags: tags
                )
            }
        }

        return try await linkOnlyImportService.importDraft(
            draft,
            into: workspace,
            existingPapers: existingPapers,
            collectionPath: collectionPath,
            tags: tags
        )
    }

    private func merged(_ paper: Paper, with draft: PaperMetadataDraft, tags: [String]) -> Paper {
        var updatedPaper = paper
        updatedPaper.title = trimmedOrNil(draft.title) ?? paper.title
        updatedPaper.authors = draft.authors
        updatedPaper.year = draft.year
        updatedPaper.venue = draft.venue
        updatedPaper.doi = draft.doi
        updatedPaper.arxiv = draft.arxiv
        updatedPaper.inspireID = draft.inspireID
        updatedPaper.url = draft.url
        updatedPaper.pdfURL = draft.pdfURL
        updatedPaper.abstract = draft.abstract
        updatedPaper.categories = draft.categories
        updatedPaper.tags = tags
        return updatedPaper
    }

    nonisolated private func fallbackArxivDraft(for arxivID: String, doi: String?) -> PaperMetadataDraft {
        PaperMetadataDraft(
            title: "arXiv \(arxivID)",
            authors: [],
            year: nil,
            venue: "arXiv",
            doi: doi,
            arxiv: arxivID,
            inspireID: nil,
            url: "https://arxiv.org/abs/\(arxivID)",
            pdfURL: "https://arxiv.org/pdf/\(arxivID).pdf",
            abstract: "Metadata lookup did not complete. Imported as an arXiv link.",
            categories: [],
            sourceProvider: "arxiv-link"
        )
    }

    nonisolated private func fallbackDOIDraft(for doi: String) -> PaperMetadataDraft {
        PaperMetadataDraft(
            title: "DOI \(doi)",
            authors: [],
            year: nil,
            venue: nil,
            doi: doi,
            arxiv: nil,
            inspireID: nil,
            url: "https://doi.org/\(doi)",
            pdfURL: nil,
            abstract: "Metadata lookup did not complete. Imported as a DOI link.",
            categories: [],
            sourceProvider: "doi-link"
        )
    }

    nonisolated private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}