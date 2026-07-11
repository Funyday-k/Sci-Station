import Foundation

/// Extracts reference entries from the "References" / "Bibliography" section
/// of a paper's Markdown file. Each entry is returned as raw text; downstream
/// `ReferenceTextNormalizer` extracts DOI / arXiv / title / author.
public struct MarkdownReferencesExtractor {
    public static let referencesHeadings: Set<String> = [
        "references", "bibliography", "参考文献", "引用文献",
        "works cited", "cited references", "literature"
    ]

    public nonisolated init() {}

    /// Returns the raw text of each reference entry found under a recognized
    /// heading. Continuation lines (non-list lines that follow a list item)
    /// are merged into the preceding entry.
    public nonisolated func extract(from markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: { isReferencesHeading($0) }) else {
            return []
        }

        var collected: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Stop at the next top-level heading (## or #).
            if isAnotherTopHeading(line) { break }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isListItem(trimmed) {
                collected.append(stripListMarker(trimmed))
            } else if !collected.isEmpty {
                // Continuation line — merge into the last entry.
                collected[collected.count - 1] += " " + trimmed
            } else {
                // Non-list text before any list item; treat as a standalone entry.
                collected.append(trimmed)
            }
            index += 1
        }

        return collected.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private nonisolated func isReferencesHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match `## References`, `# Bibliography`, `### 参考文献`, etc.
        guard trimmed.hasPrefix("#") else { return false }
        let stripped = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
        return Self.referencesHeadings.contains(stripped)
    }

    private nonisolated func isAnotherTopHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return false }
        let stripped = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
        // It's another heading if it's NOT a references heading.
        return !Self.referencesHeadings.contains(stripped) && !stripped.isEmpty
    }

    private nonisolated func isListItem(_ line: String) -> Bool {
        // Matches `- text`, `* text`, `1. text`, `[1] text`, `[1]. text`
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return true }
        if let dotIndex = line.firstIndex(of: "."),
           line[..<dotIndex].allSatisfy({ $0.isNumber }),
           line.distance(from: line.startIndex, to: dotIndex) <= 4 {
            return true
        }
        if line.hasPrefix("[") {
            if let closeBracket = line.firstIndex(of: "]") {
                let afterBracket = line.index(after: closeBracket)
                if afterBracket < line.endIndex {
                    let next = line[afterBracket...]
                    if next.hasPrefix(" ") || next.hasPrefix(". ") || next.hasPrefix(".") {
                        return true
                    }
                }
            }
        }
        return false
    }

    private nonisolated func stripListMarker(_ line: String) -> String {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        // Numbered: `1. text`
        if let dotIndex = line.firstIndex(of: "."),
           line[..<dotIndex].allSatisfy({ $0.isNumber }),
           line.distance(from: line.startIndex, to: dotIndex) <= 4 {
            let afterDot = line.index(after: dotIndex)
            if afterDot < line.endIndex, line[afterDot] == " " {
                return String(line[line.index(after: afterDot)...])
            }
            return String(line[afterDot...])
        }
        // Bracketed: `[1] text` or `[1]. text`
        if line.hasPrefix("["), let closeBracket = line.firstIndex(of: "]") {
            var afterBracket = line.index(after: closeBracket)
            if afterBracket < line.endIndex, line[afterBracket] == "." {
                afterBracket = line.index(after: afterBracket)
            }
            if afterBracket < line.endIndex, line[afterBracket] == " " {
                afterBracket = line.index(after: afterBracket)
            }
            return String(line[afterBracket...])
        }
        return line
    }
}

/// Extracts structured identifiers from a raw reference text line.
public struct ReferenceTextNormalizer {
    private let identifierParser = IdentifierParser()

    public nonisolated init() {}

    public nonisolated func normalize(_ rawText: String) -> (doi: String?, arxivID: String?, title: String?, firstAuthorLastName: String?, year: Int?) {
        let doi = identifierParser.extractDOI(from: rawText)
        let arxivID = identifierParser.extractArxivID(from: rawText)
        let year = extractYear(from: rawText)
        let title = extractTitle(from: rawText)
        let firstAuthor = extractFirstAuthorLastName(from: rawText)
        return (doi, arxivID, title, firstAuthor, year)
    }

    private nonisolated func extractYear(from text: String) -> Int? {
        let pattern = #"(19|20)\d{2}"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(text[match])
    }

    private nonisolated func extractTitle(from text: String) -> String? {
        // Heuristic: the title is often the longest quoted segment, or the
        // text between the author list and the journal/year. We use a simple
        // approach: strip known prefixes (author names before the first period
        // or comma-separated list), then take up to the next period or comma
        // that precedes a year.
        var cleaned = text
        // Remove DOI URLs.
        cleaned = cleaned.replacingOccurrences(of: #"https?://doi\.org/[^\s,]+"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"doi:\s*[^\s,]+"#, with: "", options: .regularExpression)
        // Remove arXiv references.
        cleaned = cleaned.replacingOccurrences(of: #"arXiv:\s*\d{4}\.\d{4,5}(v\d+)?"#, with: "", options: [.regularExpression, .caseInsensitive])

        // Try to find a quoted title: "Title" or 'Title'
        if let quoted = firstQuoted(in: cleaned) {
            return TitleNormalizer.normalize(quoted)
        }

        // Fallback: take the segment after the first period (author separator)
        // up to the next period or end.
        let segments = cleaned.components(separatedBy: ".")
        if segments.count >= 2 {
            let candidate = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count > 10 {
                return TitleNormalizer.normalize(candidate)
            }
        }

        // Last resort: use the whole text minus numbers and short tokens.
        let normalized = TitleNormalizer.normalize(cleaned)
        return normalized.count > 5 ? normalized : nil
    }

    private nonisolated func firstQuoted(in text: String) -> String? {
        let patterns = [#""([^"]{5,})""#, #"\"([^\"]{5,})\""#, #""([^"]{5,})""#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                // Strip the quotes.
                let inner = match.dropFirst().dropLast()
                if inner.count > 5 { return String(inner) }
            }
        }
        return nil
    }

    private nonisolated func extractFirstAuthorLastName(from text: String) -> String? {
        // Heuristic: the first word before a comma or "and" or "et al" is
        // likely the first author's last name.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // If starts with `[N]` or `N.`, skip the marker.
        var start = trimmed.startIndex
        if trimmed.hasPrefix("[") {
            if let close = trimmed.firstIndex(of: "]") {
                start = trimmed.index(after: close)
                if start < trimmed.endIndex, trimmed[start] == " " {
                    start = trimmed.index(after: start)
                }
            }
        } else if let dotIdx = trimmed.firstIndex(of: "."),
                  trimmed[..<dotIdx].allSatisfy({ $0.isNumber }),
                  trimmed.distance(from: trimmed.startIndex, to: dotIdx) <= 3 {
            start = trimmed.index(after: dotIdx)
            if start < trimmed.endIndex, trimmed[start] == " " {
                start = trimmed.index(after: start)
            }
        }

        let authorSection = String(trimmed[start...])
        // Take the first word (likely last name in "LastName, First" or "LastName First" format).
        let firstWord = authorSection.prefix(while: { $0.isLetter || $0 == "-" || $0 == "'" })
        let result = String(firstWord).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.count >= 2 ? result : nil
    }
}

/// Normalizes a title for fuzzy comparison.
public enum TitleNormalizer {
    public nonisolated static func normalize(_ title: String) -> String {
        var result = title
        // Strip LaTeX commands.
        result = result.replacingOccurrences(of: #"\\(textit|emph|textbf|mathrm|mathbf)\{([^}]*)\}"#, with: "$2", options: .regularExpression)
        // Strip inline math.
        result = result.replacingOccurrences(of: #"\$[^$]+\$"#, with: "", options: .regularExpression)
        // Strip Markdown bold/italic.
        result = result.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
        // Drop punctuation.
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        result = String(result.unicodeScalars.filter { allowed.contains($0) })
        // Collapse whitespace and lowercase.
        result = result.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return result
    }
}
