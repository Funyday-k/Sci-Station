import Foundation

public struct FrontmatterParseResult: Sendable {
    public let frontmatter: [String: FrontmatterValue]
    public let body: String

    public nonisolated init(frontmatter: [String: FrontmatterValue], body: String) {
        self.frontmatter = frontmatter
        self.body = body
    }
}

public struct FrontmatterParser {
    public nonisolated init() {}

    /// Compatibility entry point for existing document-loading call sites.
    /// Invalid YAML produces an empty metadata mapping while preserving the
    /// Markdown body. Validation-sensitive callers should use `parseThrowing`.
    public nonisolated func parse(_ contents: String) -> FrontmatterParseResult {
        do {
            return try parseThrowing(contents)
        } catch {
            let sections = splitFrontmatter(from: contents)
            return FrontmatterParseResult(frontmatter: [:], body: sections?.body ?? normalize(contents))
        }
    }

    public nonisolated func parseThrowing(_ contents: String) throws -> FrontmatterParseResult {
        guard let sections = splitFrontmatter(from: contents) else {
            return FrontmatterParseResult(frontmatter: [:], body: normalize(contents))
        }

        let frontmatter = try StandardsYAMLDecoder.decodeMapping(sections.yaml)
        return FrontmatterParseResult(frontmatter: frontmatter, body: sections.body)
    }

    private nonisolated func splitFrontmatter(from contents: String) -> (yaml: String, body: String)? {
        let normalized = normalize(contents)
        var lines = normalized.components(separatedBy: "\n")

        if lines.first?.hasPrefix("\u{FEFF}") == true {
            lines[0].removeFirst()
        }
        guard lines.first == "---" else {
            return nil
        }

        guard let closingIndex = lines.indices.dropFirst().first(where: { index in
            let line = lines[index]
            guard line.first != " ", line.first != "\t" else {
                return false
            }
            let delimiter = line.trimmingCharacters(in: .whitespaces)
            return delimiter == "---" || delimiter == "..."
        }) else {
            return nil
        }

        let yaml = lines[1..<closingIndex].joined(separator: "\n")
        var body = lines.suffix(from: closingIndex + 1).joined(separator: "\n")
        while body.hasPrefix("\n") {
            body.removeFirst()
        }
        return (yaml, body)
    }

    private nonisolated func normalize(_ contents: String) -> String {
        contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
