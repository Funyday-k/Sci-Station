import Foundation

public enum LLMWritebackMode: String, Sendable {
    case replace
    case append
    case saveDraft
}

public struct LLMWritebackResult: Sendable, Hashable {
    public var writtenURL: URL
    public var didModifyWiki: Bool
}

public actor LLMWritebackService {
    public init() {}

    public func write(
        _ content: String,
        to wikiURL: URL,
        mode: LLMWritebackMode,
        paper: Paper,
        in workspace: ResearchWorkspace
    ) throws -> LLMWritebackResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: wikiURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch mode {
        case .replace:
            try content.write(to: wikiURL, atomically: true, encoding: .utf8)
            return LLMWritebackResult(writtenURL: wikiURL, didModifyWiki: true)
        case .append:
            let existing = (try? String(contentsOf: wikiURL, encoding: .utf8)) ?? "# \(paper.displayTitle)\n\n"
            let updated = existing + "\n\n## AI Summary\n\n" + content
            try updated.write(to: wikiURL, atomically: true, encoding: .utf8)
            return LLMWritebackResult(writtenURL: wikiURL, didModifyWiki: true)
        case .saveDraft:
            let draftURL = uniqueDraftURL(for: wikiURL, fileManager: fileManager)
            try content.write(to: draftURL, atomically: true, encoding: .utf8)
            return LLMWritebackResult(writtenURL: draftURL, didModifyWiki: false)
        }
    }

    private nonisolated func uniqueDraftURL(for wikiURL: URL, fileManager: FileManager) -> URL {
        let directoryURL = wikiURL.deletingLastPathComponent()
        let baseName = wikiURL.deletingPathExtension().lastPathComponent
        var candidateURL = directoryURL.appendingPathComponent("\(baseName).draft.md", isDirectory: false)
        var counter = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL.appendingPathComponent("\(baseName).draft-\(counter).md", isDirectory: false)
            counter += 1
        }

        return candidateURL
    }
}
