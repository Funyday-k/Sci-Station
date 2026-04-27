import Foundation

public enum WikiPageGeneratorError: LocalizedError {
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case let .alreadyExists(path):
            return "Wiki page already exists at \(path)."
        }
    }
}

public struct WikiPageGenerationResult: Sendable {
    public let paper: Paper
    public let fileURL: URL

    public nonisolated init(paper: Paper, fileURL: URL) {
        self.paper = paper
        self.fileURL = fileURL
    }
}

public actor WikiPageGenerator {
    private let fileManager: FileManager
    private let paperRepository: PaperRepository

    public init(
        fileManager: FileManager = .default,
        paperRepository: PaperRepository
    ) {
        self.fileManager = fileManager
        self.paperRepository = paperRepository
    }

    public func generatePaperWikiPage(
        for paper: Paper,
        in workspace: ResearchWorkspace,
        overwriteExisting: Bool = false
    ) async throws -> WikiPageGenerationResult {
        let wikiRelativePath = "wiki/papers/\(paper.citekey).md"
        let wikiFileURL = workspace.fileURL(for: wikiRelativePath)

        if fileManager.fileExists(atPath: wikiFileURL.path), !overwriteExisting {
            throw WikiPageGeneratorError.alreadyExists(workspace.relativePath(to: wikiFileURL))
        }

        try fileManager.createDirectory(at: wikiFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let updatedPaper = paperWithSummaryPath(paper)
        let contents = makePaperWikiTemplate(for: updatedPaper)
        try contents.write(to: wikiFileURL, atomically: true, encoding: .utf8)

        let savedPaper = try await paperRepository.save(updatedPaper, in: workspace)
        return WikiPageGenerationResult(paper: savedPaper, fileURL: wikiFileURL)
    }

    private func paperWithSummaryPath(_ paper: Paper) -> Paper {
        var updatedPaper = paper
        updatedPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: paper.citekey,
            paperDirectoryRelativePath: paper.paperDirectoryRelativePath
        )
        return updatedPaper
    }

    private func makePaperWikiTemplate(for paper: Paper) -> String {
        let today = dayString(from: Date())
        let authorLines = paper.authors.isEmpty
            ? "authors: []"
            : (["authors:"] + paper.authors.map { "  - \(quoted($0))" }).joined(separator: "\n")
        let yearLine = paper.year.map(String.init) ?? ""
        let tagLines = paper.tags.isEmpty
            ? "tags: []"
            : (["tags:"] + paper.tags.map { "  - \(quoted($0))" }).joined(separator: "\n")

        return """
        ---
        type: paper
        id: \(paper.id)
        citekey: \(paper.citekey)
        title: \(quoted(paper.title))
        year: \(yearLine)
        \(authorLines)
        \(tagLines)
        status: imported
        source_pdf: \(quoted("../../\(paper.paperDirectoryRelativePath)/paper.pdf"))
        source_raw_md: \(quoted("../../\(paper.paperDirectoryRelativePath)/paper.md"))
        created: \(today)
        updated: \(today)
        ---

        # \(paper.displayTitle)

        ## TL;DR

        待总结。

        ## 研究问题

        待补充。

        ## 方法概述

        待补充。

        ## 关键贡献

        待补充。

        ## 实验与证据

        待补充。

        ## 局限性

        待补充。

        ## 与已有工作的关系

        待补充。

        ## 可复现性检查

        待补充。

        ## 对我研究的启发

        待补充。

        ## 相关概念

        - 

        ## 可能研究空白

        - 

        ## 引用

        [@\(paper.citekey)]
        """
    }

    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}