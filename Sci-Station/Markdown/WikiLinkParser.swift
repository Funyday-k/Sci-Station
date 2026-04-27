import Foundation

public struct WikiLinkParser {
    public nonisolated init() {}

    public nonisolated func parse(_ contents: String) -> [WikiLink] {
        guard let expression = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]"#) else {
            return []
        }

        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let matches = expression.matches(in: contents, range: range)
        var links: [WikiLink] = []
        var seenTargets: Set<String> = []

        for match in matches {
            guard let targetRange = Range(match.range(at: 1), in: contents),
                  let fullRange = Range(match.range(at: 0), in: contents) else {
                continue
            }

            let target = String(contents[targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let link = WikiLink(target: target, originalText: String(contents[fullRange]))
            let normalizedTarget = link.normalizedTarget

            guard !normalizedTarget.isEmpty, seenTargets.insert(normalizedTarget).inserted else {
                continue
            }

            links.append(link)
        }

        return links
    }
}