import Foundation

public enum LLMWritebackMode: String, Sendable {
    case replace
    case append
    case saveDraft
}

public actor LLMWritebackService {
    public init() {}

    public func write(
        _ content: String,
        to wikiURL: URL,
        mode: LLMWritebackMode,
        paper: Paper,
        in workspace: ResearchWorkspace
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: wikiURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch mode {
        case .replace:
            try content.write(to: wikiURL, atomically: true, encoding: .utf8)
        case .append:
            let existing = (try? String(contentsOf: wikiURL, encoding: .utf8)) ?? "# \(paper.displayTitle)\n\n"
            let updated = existing + "\n\n## AI Summary\n\n" + content
            try updated.write(to: wikiURL, atomically: true, encoding: .utf8)
        case .saveDraft:
            let draftURL = wikiURL.deletingPathExtension().appendingPathExtension("draft.md")
            try content.write(to: draftURL, atomically: true, encoding: .utf8)
        }
    }
}