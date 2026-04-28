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
