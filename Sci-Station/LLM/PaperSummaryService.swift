import Foundation

public actor PaperSummaryService {
    private let provider: OpenAICompatibleProvider
    private let promptBuilder: PaperSummaryPromptBuilder

    public init(provider: OpenAICompatibleProvider, promptBuilder: PaperSummaryPromptBuilder = PaperSummaryPromptBuilder()) {
        self.provider = provider
        self.promptBuilder = promptBuilder
    }

    public func summarize(
        _ paper: Paper,
        in workspace: ResearchWorkspace,
        configuration: LLMConfiguration,
        apiKey: String
    ) async throws -> String {
        let rawMarkdown = (try? String(contentsOf: paper.rawMarkdownURL(in: workspace), encoding: .utf8)) ?? ""
        let annotations = paper.annotationsRelativePath.flatMap { path in
            try? String(contentsOf: workspace.resolve(relativePath: path, from: workspace.directoryURL(for: paper.paperDirectoryRelativePath), isDirectory: false), encoding: .utf8)
        } ?? ""
        let existingWiki = paper.summaryURL(in: workspace).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let prompt = promptBuilder.buildPrompt(for: paper, rawMarkdown: rawMarkdown, annotations: annotations, existingWiki: existingWiki)
        return try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
    }
}