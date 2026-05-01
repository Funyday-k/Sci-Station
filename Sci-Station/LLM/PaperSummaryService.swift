import Foundation
import PDFKit

public actor PaperSummaryService {
    private let provider: any LLMProvider
    private let promptBuilder: PaperSummaryPromptBuilder
    private let maximumPromptSourceCharacters = 60_000

    public init(provider: any LLMProvider, promptBuilder: PaperSummaryPromptBuilder = PaperSummaryPromptBuilder()) {
        self.provider = provider
        self.promptBuilder = promptBuilder
    }

    public func summarize(
        _ paper: Paper,
        in workspace: ResearchWorkspace,
        configuration: LLMConfiguration,
        apiKey: String
    ) async throws -> String {
        let rawMarkdown = rawMarkdownForPrompt(paper, in: workspace)
        let annotations = paper.annotationsRelativePath.flatMap { path in
            try? String(contentsOf: workspace.resolve(relativePath: path, from: workspace.directoryURL(for: paper.paperDirectoryRelativePath), isDirectory: false), encoding: .utf8)
        } ?? ""
        let existingWiki = paper.summaryURL(in: workspace).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let prompt = promptBuilder.buildPrompt(for: paper, rawMarkdown: rawMarkdown, annotations: annotations, existingWiki: existingWiki)
        return try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
    }

    private func rawMarkdownForPrompt(_ paper: Paper, in workspace: ResearchWorkspace) -> String {
        let rawMarkdown = (try? String(contentsOf: paper.rawMarkdownURL(in: workspace), encoding: .utf8)) ?? ""
        guard shouldUsePDFTextFallback(rawMarkdown),
              let pdfURL = paper.pdfURL(in: workspace),
              let pdfText = extractedText(from: pdfURL),
              !pdfText.isEmpty else {
            return limited(rawMarkdown)
        }

        return limited(
            [
                rawMarkdown,
                "## Extracted PDF Text",
                pdfText
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        )
    }

    private nonisolated func shouldUsePDFTextFallback(_ rawMarkdown: String) -> Bool {
        let trimmedRawMarkdown = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRawMarkdown.count < 500
            || rawMarkdown.contains("status: not_extracted")
            || rawMarkdown.localizedCaseInsensitiveContains("PDF text has not been extracted yet")
    }

    private nonisolated func extractedText(from pdfURL: URL) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            return nil
        }

        var pageTexts: [String] = []
        var collectedLength = 0

        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else {
                continue
            }

            pageTexts.append("### Page \(pageIndex + 1)\n\(pageText)")
            collectedLength += pageText.count

            if collectedLength >= maximumPromptSourceCharacters {
                break
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    private nonisolated func limited(_ value: String) -> String {
        guard value.count > maximumPromptSourceCharacters else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maximumPromptSourceCharacters)
        return String(value[..<endIndex]) + "\n\n[Input truncated by Sci-Station.]"
    }
}

public struct PaperMarkdownConversionResult: Identifiable, Hashable, Sendable {
    public var id: String { paperID }
    public var paperID: String
    public var title: String
    public var markdownRelativePath: String?
    public var didWriteMarkdown: Bool
    public var errorMessage: String?
}

public struct PaperMarkdownConversionConfiguration: Hashable, Sendable {
    public var minerUCommand: String
    public var overwriteExistingMarkdown: Bool

    public nonisolated init(minerUCommand: String = "mineru", overwriteExistingMarkdown: Bool = true) {
        let trimmedCommand = minerUCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minerUCommand = trimmedCommand.isEmpty ? "mineru" : trimmedCommand
        self.overwriteExistingMarkdown = overwriteExistingMarkdown
    }
}

public actor PaperMarkdownConversionService {
    public init() {}

    public func convert(
        _ papers: [Paper],
        in workspace: ResearchWorkspace,
        configuration: PaperMarkdownConversionConfiguration = PaperMarkdownConversionConfiguration()
    ) async throws -> [PaperMarkdownConversionResult] {
        var results: [PaperMarkdownConversionResult] = []
        for paper in papers {
            results.append(await convertOne(paper, in: workspace, configuration: configuration))
        }
        return results
    }

    private func convertOne(
        _ paper: Paper,
        in workspace: ResearchWorkspace,
        configuration: PaperMarkdownConversionConfiguration
    ) async -> PaperMarkdownConversionResult {
        guard let pdfURL = paper.pdfURL(in: workspace) else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "No PDF path is configured for this paper."
            )
        }

        let markdownURL = paper.rawMarkdownURL(in: workspace)
        if FileManager.default.fileExists(atPath: markdownURL.path), !configuration.overwriteExistingMarkdown {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                didWriteMarkdown: false,
                errorMessage: "paper.md already exists; overwrite is disabled."
            )
        }

        if let minerUResult = await convertWithMinerU(
            paper,
            pdfURL: pdfURL,
            markdownURL: markdownURL,
            configuration: configuration
        ) {
            return minerUResult
        }

        guard let document = PDFDocument(url: pdfURL) else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "Failed to load PDF."
            )
        }

        let pageMarkdown = extractedMarkdown(from: document)
        guard !pageMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: "PDF did not expose extractable text."
            )
        }

        let markdown = markdownDocument(
            for: paper,
            pageMarkdown: pageMarkdown,
            extractionEngine: "pdfkit_fallback",
            fallbackReason: "MinerU command failed or did not produce Markdown."
        )

        do {
            try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                didWriteMarkdown: true,
                errorMessage: nil
            )
        } catch {
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: nil,
                didWriteMarkdown: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func convertWithMinerU(
        _ paper: Paper,
        pdfURL: URL,
        markdownURL: URL,
        configuration: PaperMarkdownConversionConfiguration
    ) async -> PaperMarkdownConversionResult? {
        let outputDirectory = markdownURL.deletingLastPathComponent().appendingPathComponent("mineru-output", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let result = try runMinerU(command: configuration.minerUCommand, pdfURL: pdfURL, outputDirectory: outputDirectory)
            guard result.exitCode == 0,
                  let generatedMarkdownURL = newestMarkdownFile(in: outputDirectory),
                  let generatedMarkdown = try? String(contentsOf: generatedMarkdownURL, encoding: .utf8),
                  !generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let markdown = markdownDocument(
                for: paper,
                pageMarkdown: generatedMarkdown,
                extractionEngine: "mineru",
                fallbackReason: nil
            )
            try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            return PaperMarkdownConversionResult(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                didWriteMarkdown: true,
                errorMessage: nil
            )
        } catch {
            return nil
        }
    }

    private nonisolated func runMinerU(command: String, pdfURL: URL, outputDirectory: URL) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, "-p", pdfURL.path, "-o", outputDirectory.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private nonisolated func newestMarkdownFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { first, second in
                let firstDate = (try? first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let secondDate = (try? second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return firstDate > secondDate
            }
            .first
    }

    private nonisolated func extractedMarkdown(from document: PDFDocument) -> String {
        var sections: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }

            sections.append("## Page \(pageIndex + 1)\n\n\(text)")
        }

        return sections.joined(separator: "\n\n")
    }

    private nonisolated func markdownDocument(
        for paper: Paper,
        pageMarkdown: String,
        extractionEngine: String,
        fallbackReason: String?
    ) -> String {
        let authors = paper.authors.isEmpty ? "[]" : "[" + paper.authors.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"
        let tags = paper.tags.isEmpty ? "[]" : "[" + paper.tags.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"
        let categories = paper.categories.isEmpty ? "[]" : "[" + paper.categories.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ") + "]"

        return """
        ---
        type: paper_raw_markdown
        extraction_engine: \(extractionEngine)
        mineru_compatible: true
        extracted_at: "\(ISO8601DateFormatter().string(from: Date()))"
        fallback_reason: "\((fallbackReason ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        paper_id: \(paper.id)
        citekey: \(paper.citekey)
        title: "\(paper.displayTitle.replacingOccurrences(of: "\"", with: "\\\""))"
        authors: \(authors)
        year: \(paper.year.map(String.init) ?? "")
        venue: "\((paper.publicationTitle ?? paper.venue ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        doi: "\((paper.doi ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        arxiv: "\((paper.arxiv ?? "").replacingOccurrences(of: "\"", with: "\\\""))"
        tags: \(tags)
        categories: \(categories)
        source_pdf: "\(paper.pdfRelativePath ?? "paper.pdf")"
        ---

        # \(paper.displayTitle)

        > Generated by Sci-Station's PDF-to-Markdown bridge using \(extractionEngine).

        \(pageMarkdown)
        """
    }
}
