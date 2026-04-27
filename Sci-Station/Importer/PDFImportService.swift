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

    public init(
        fileManager: FileManager = .default,
        repository: PaperRepository
    ) {
        self.fileManager = fileManager
        self.repository = repository
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

        let title = detectedTitle(from: sourceURL)
        let authors = detectedAuthors(from: sourceURL)
        let year = detectedYear(from: sourceURL)
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
        let directoryRelativePath = normalizedCollectionPath.isEmpty
            ? "raw/papers/\(paperID)"
            : "raw/papers/\(normalizedCollectionPath)/\(paperID)"
        let paperDirectoryURL = workspace.directoryURL(for: directoryRelativePath)
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
            venue: nil,
            doi: nil,
            arxiv: nil,
            url: nil,
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

    private func detectedTitle(from sourceURL: URL) -> String {
        if let document = PDFDocument(url: sourceURL),
           let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func detectedAuthors(from sourceURL: URL) -> [String] {
        guard let document = PDFDocument(url: sourceURL),
              let authorText = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String else {
            return []
        }

        return authorText
            .replacingOccurrences(of: " and ", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
}