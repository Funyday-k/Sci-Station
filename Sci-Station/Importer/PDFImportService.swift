import Foundation
import PDFKit

public enum PDFImportError: LocalizedError {
    case unsupportedFileType
    case invalidPDFSignature
    case unreadablePDFDocument
    case destinationAlreadyExists
    case commitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Only PDF files can be imported."
        case .invalidPDFSignature:
            return "The selected file does not contain a valid PDF header."
        case .unreadablePDFDocument:
            return "The selected file could not be opened as a PDF document."
        case .destinationAlreadyExists:
            return "A paper already exists at the generated destination."
        case let .commitFailed(message):
            return "The PDF import could not be committed: \(message)"
        }
    }

    public var allowsLinkOnlyFallback: Bool {
        switch self {
        case .unsupportedFileType, .invalidPDFSignature, .unreadablePDFDocument:
            return true
        case .destinationAlreadyExists, .commitFailed:
            return false
        }
    }
}

enum PDFImportCommitStage: Equatable, Sendable {
    case paperMetadata
    case projectLinks
    case bibliography
}

public actor PDFImportService {
    private let fileManager: FileManager
    private let repository: PaperRepository
    private let parser: IdentifierParser
    private let doiProvider: DOIMetadataProvider
    private let arxivProvider: ArxivMetadataProvider
    private let commitStageHook: @Sendable (PDFImportCommitStage) async throws -> Void

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
        self.commitStageHook = { _ in }
    }

    init(
        fileManager: FileManager = .default,
        repository: PaperRepository,
        parser: IdentifierParser = IdentifierParser(),
        doiProvider: DOIMetadataProvider = DOIMetadataProvider(),
        arxivProvider: ArxivMetadataProvider = ArxivMetadataProvider(),
        commitStageHook: @escaping @Sendable (PDFImportCommitStage) async throws -> Void
    ) {
        self.fileManager = fileManager
        self.repository = repository
        self.parser = parser
        self.doiProvider = doiProvider
        self.arxivProvider = arxivProvider
        self.commitStageHook = commitStageHook
    }

    public func importPDF(
        from sourceURL: URL,
        into workspace: ResearchWorkspace,
        existingPapers: [Paper],
        collectionPath: String = "Uncategorized",
        metadataOverride: PaperMetadataDraft? = nil,
        tags: [String] = [],
        projectIDs: [String] = []
    ) async throws -> Paper {
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw PDFImportError.unsupportedFileType
        }
        guard try DownloadService.hasPDFSignature(at: sourceURL) else {
            throw PDFImportError.invalidPDFSignature
        }
        guard let pdfDocument = PDFDocument(url: sourceURL), pdfDocument.pageCount > 0 else {
            throw PDFImportError.unreadablePDFDocument
        }

        let detectedIdentifiers = detectIdentifiers(from: sourceURL)
        let detectedMetadataDraft = await fetchedMetadata(for: detectedIdentifiers)
        let metadataDraft = metadataOverride ?? detectedMetadataDraft
        let titleDraft = metadataOverride?.sourceProvider.hasSuffix("-link") == true
            ? detectedMetadataDraft
            : metadataDraft
        let title = resolvedTitle(from: titleDraft, sourceURL: sourceURL)
        let authors = resolvedAuthors(from: metadataDraft ?? detectedMetadataDraft, sourceURL: sourceURL)
        let year = metadataDraft?.year ?? detectedMetadataDraft?.year ?? detectedYear(from: sourceURL)
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

        let normalizedCollectionPath = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryRelativePath = try Paper.directoryRelativePath(
            for: paperID,
            collectionPath: normalizedCollectionPath
        )
        let paperDirectoryURL = try workspace.validatedResolve(
            relativePath: directoryRelativePath,
            from: workspace.rootURL,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: paperDirectoryURL.path) else {
            throw PDFImportError.destinationAlreadyExists
        }

        let now = Date()
        let paper = Paper(
            id: paperID,
            citekey: citekey,
            title: title,
            authors: authors,
            year: year,
            venue: trimmedOrNil(metadataDraft?.venue ?? detectedMetadataDraft?.venue),
            doi: trimmedOrNil(metadataDraft?.doi ?? detectedMetadataDraft?.doi) ?? detectedIdentifiers.doi,
            arxiv: trimmedOrNil(metadataDraft?.arxiv ?? detectedMetadataDraft?.arxiv) ?? detectedIdentifiers.arxiv,
            inspireID: trimmedOrNil(metadataDraft?.inspireID ?? detectedMetadataDraft?.inspireID),
            url: resolvedSourceURL(from: metadataDraft ?? detectedMetadataDraft, identifiers: detectedIdentifiers),
            pdfURL: trimmedOrNil(metadataDraft?.pdfURL ?? detectedMetadataDraft?.pdfURL),
            abstract: trimmedOrNil(metadataDraft?.abstract ?? detectedMetadataDraft?.abstract),
            categories: metadataDraft?.categories.isEmpty == false
                ? metadataDraft?.categories ?? []
                : detectedMetadataDraft?.categories ?? [],
            titleTranslation: trimmedOrNil(metadataDraft?.titleTranslation ?? detectedMetadataDraft?.titleTranslation),
            itemType: trimmedOrNil(metadataDraft?.itemType ?? detectedMetadataDraft?.itemType),
            publicationTitle: trimmedOrNil(metadataDraft?.publicationTitle ?? detectedMetadataDraft?.publicationTitle),
            publisher: trimmedOrNil(metadataDraft?.publisher ?? detectedMetadataDraft?.publisher),
            publicationPlace: trimmedOrNil(metadataDraft?.publicationPlace ?? detectedMetadataDraft?.publicationPlace),
            publishedDate: trimmedOrNil(metadataDraft?.publishedDate ?? detectedMetadataDraft?.publishedDate),
            volume: trimmedOrNil(metadataDraft?.volume ?? detectedMetadataDraft?.volume),
            issue: trimmedOrNil(metadataDraft?.issue ?? detectedMetadataDraft?.issue),
            pages: trimmedOrNil(metadataDraft?.pages ?? detectedMetadataDraft?.pages),
            series: trimmedOrNil(metadataDraft?.series ?? detectedMetadataDraft?.series),
            seriesTitle: trimmedOrNil(metadataDraft?.seriesTitle ?? detectedMetadataDraft?.seriesTitle),
            journalAbbreviation: trimmedOrNil(metadataDraft?.journalAbbreviation ?? detectedMetadataDraft?.journalAbbreviation),
            issn: trimmedOrNil(metadataDraft?.issn ?? detectedMetadataDraft?.issn),
            isbn: trimmedOrNil(metadataDraft?.isbn ?? detectedMetadataDraft?.isbn),
            pmid: trimmedOrNil(metadataDraft?.pmid ?? detectedMetadataDraft?.pmid),
            pmcid: trimmedOrNil(metadataDraft?.pmcid ?? detectedMetadataDraft?.pmcid),
            language: trimmedOrNil(metadataDraft?.language ?? detectedMetadataDraft?.language),
            archive: trimmedOrNil(metadataDraft?.archive ?? detectedMetadataDraft?.archive),
            archiveLocation: trimmedOrNil(metadataDraft?.archiveLocation ?? detectedMetadataDraft?.archiveLocation),
            libraryCatalog: trimmedOrNil(metadataDraft?.libraryCatalog ?? detectedMetadataDraft?.libraryCatalog),
            callNumber: trimmedOrNil(metadataDraft?.callNumber ?? detectedMetadataDraft?.callNumber),
            shortTitle: trimmedOrNil(metadataDraft?.shortTitle ?? detectedMetadataDraft?.shortTitle),
            accessedAt: trimmedOrNil(metadataDraft?.accessedAt ?? detectedMetadataDraft?.accessedAt),
            bibtex: trimmedOrNil(metadataDraft?.bibtex ?? detectedMetadataDraft?.bibtex),
            projectIDs: uniqueOrdered(projectIDs),
            pdfRelativePath: "paper.pdf",
            tags: uniqueOrdered(tags),
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

        let stagingRootURL = workspace.rootURL
            .appendingPathComponent(".sci-station/import-staging", isDirectory: true)
        let stagingDirectoryURL = stagingRootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rollbackDirectoryCandidates = directoriesMissingBeforeImport(
            requiredDirectories: [
                stagingDirectoryURL,
                paperDirectoryURL.deletingLastPathComponent(),
                workspace.projectPaperLinksURL.deletingLastPathComponent(),
                workspace.globalLibraryBibURL.deletingLastPathComponent()
            ],
            within: workspace.rootURL
        )
        var sharedFileSnapshot: PDFImportSharedFileSnapshot?
        var projectLinksCommitAttempted = false
        var committedProjectLinksContents: Data?
        var bibliographyCommitAttempted = false
        var committedBibliographyContents: Data?
        var movedToFinalDestination = false

        do {
            sharedFileSnapshot = try await repository.snapshotPDFImportSharedFiles(in: workspace)
            try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(
                at: sourceURL,
                to: stagingDirectoryURL.appendingPathComponent("paper.pdf", isDirectory: false)
            )
            try fileManager.createDirectory(
                at: stagingDirectoryURL.appendingPathComponent("figures", isDirectory: true),
                withIntermediateDirectories: true
            )
            try rawPaperTemplate(citekey: citekey).write(
                to: stagingDirectoryURL.appendingPathComponent("paper.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
            try "# Annotations\n\n".write(
                to: stagingDirectoryURL.appendingPathComponent("annotations.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )

            try fileManager.createDirectory(
                at: paperDirectoryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: stagingDirectoryURL, to: paperDirectoryURL)
            movedToFinalDestination = true

            let savedPaper = try await repository.saveMetadataMirror(paper, in: workspace)
            try await commitStageHook(.paperMetadata)
            projectLinksCommitAttempted = true
            committedProjectLinksContents = try await repository.syncProjectLinks(for: savedPaper, in: workspace)
            try await commitStageHook(.projectLinks)
            bibliographyCommitAttempted = true
            committedBibliographyContents = try await repository.appendBibliographyStubAndSnapshot(
                for: savedPaper,
                in: workspace
            )
            try await commitStageHook(.bibliography)
            try removeStagingRootIfEmpty(stagingRootURL)
            return savedPaper
        } catch {
            let rollbackFailures = await rollbackImport(
                paper: paper,
                workspace: workspace,
                paperDirectoryURL: paperDirectoryURL,
                stagingDirectoryURL: stagingDirectoryURL,
                stagingRootURL: stagingRootURL,
                movedToFinalDestination: movedToFinalDestination,
                sharedFileSnapshot: sharedFileSnapshot,
                projectLinksCommitAttempted: projectLinksCommitAttempted,
                committedProjectLinksContents: committedProjectLinksContents,
                bibliographyCommitAttempted: bibliographyCommitAttempted,
                committedBibliographyContents: committedBibliographyContents,
                directoryCandidates: rollbackDirectoryCandidates
            )
            if let importError = error as? PDFImportError, rollbackFailures.isEmpty {
                throw importError
            }
            let rollbackSuffix = rollbackFailures.isEmpty
                ? ""
                : " Rollback also reported: \(rollbackFailures.joined(separator: "; "))"
            throw PDFImportError.commitFailed(error.localizedDescription + rollbackSuffix)
        }
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

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private func removeStagingRootIfEmpty(_ stagingRootURL: URL) throws {
        guard fileManager.fileExists(atPath: stagingRootURL.path) else {
            return
        }
        let contents = try fileManager.contentsOfDirectory(
            at: stagingRootURL,
            includingPropertiesForKeys: nil
        )
        guard contents.isEmpty else {
            return
        }
        try fileManager.removeItem(at: stagingRootURL)
    }

    private func rollbackImport(
        paper: Paper,
        workspace: ResearchWorkspace,
        paperDirectoryURL: URL,
        stagingDirectoryURL: URL,
        stagingRootURL: URL,
        movedToFinalDestination: Bool,
        sharedFileSnapshot: PDFImportSharedFileSnapshot?,
        projectLinksCommitAttempted: Bool,
        committedProjectLinksContents: Data?,
        bibliographyCommitAttempted: Bool,
        committedBibliographyContents: Data?,
        directoryCandidates: [URL]
    ) async -> [String] {
        var failures: [String] = []

        if bibliographyCommitAttempted {
            do {
                try await repository.rollbackBibliographyStub(
                    for: paper,
                    originalContents: sharedFileSnapshot?.bibliography,
                    committedContents: committedBibliographyContents,
                    in: workspace
                )
            } catch {
                failures.append("bibliography rollback failed: \(error.localizedDescription)")
            }
        }

        if projectLinksCommitAttempted {
            do {
                try await repository.rollbackProjectLinks(
                    for: paper,
                    originalContents: sharedFileSnapshot?.projectLinks,
                    committedContents: committedProjectLinksContents,
                    in: workspace
                )
            } catch {
                failures.append("project-link rollback failed: \(error.localizedDescription)")
            }
        }

        if movedToFinalDestination {
            removeIfPresent(
                paperDirectoryURL,
                failurePrefix: "paper directory cleanup failed",
                failures: &failures
            )
        }
        removeIfPresent(
            stagingDirectoryURL,
            failurePrefix: "staging cleanup failed",
            failures: &failures
        )

        do {
            try removeStagingRootIfEmpty(stagingRootURL)
        } catch {
            failures.append("staging-root cleanup failed: \(error.localizedDescription)")
        }
        pruneEmptyDirectories(directoryCandidates, failures: &failures)
        return failures
    }

    private func removeIfPresent(
        _ url: URL,
        failurePrefix: String,
        failures: inout [String]
    ) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            failures.append("\(failurePrefix): \(error.localizedDescription)")
        }
    }

    private func directoriesMissingBeforeImport(
        requiredDirectories: [URL],
        within rootURL: URL
    ) -> [URL] {
        let standardizedRootURL = rootURL.standardizedFileURL
        let rootPath = standardizedRootURL.path
        var missingDirectoriesByPath: [String: URL] = [:]

        for requiredDirectory in requiredDirectories {
            var candidateURL = requiredDirectory.standardizedFileURL
            while candidateURL.path != rootPath,
                  candidateURL.path.hasPrefix(rootPath + "/") {
                if !fileManager.fileExists(atPath: candidateURL.path) {
                    missingDirectoriesByPath[candidateURL.path] = candidateURL
                }
                let parentURL = candidateURL.deletingLastPathComponent()
                guard parentURL.path != candidateURL.path else {
                    break
                }
                candidateURL = parentURL
            }
        }

        return missingDirectoriesByPath.values.sorted {
            $0.pathComponents.count > $1.pathComponents.count
        }
    }

    private func pruneEmptyDirectories(_ directoryURLs: [URL], failures: inout [String]) {
        for directoryURL in directoryURLs {
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                continue
            }
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil
                )
                guard contents.isEmpty else {
                    continue
                }
                try fileManager.removeItem(at: directoryURL)
            } catch {
                failures.append("failed to prune \(directoryURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
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
