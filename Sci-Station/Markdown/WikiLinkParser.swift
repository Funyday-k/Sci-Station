import Foundation

public struct WikiLinkParser {
    /// Capture 1: optional namespace (e.g. `concept`, `method`)
    /// Capture 2: target page key
    ///
    /// Example matches:
    /// - `[[Page Title]]`                -> ns=nil, target="Page Title"
    /// - `[[concept:dark-matter]]`       -> ns="concept", target="dark-matter"
    /// - `[[method:glauber|GM]]`         -> ns="method", target="glauber"
    /// - `[[concept:X#section]]`         -> ns="concept", target="X"
    private static let pattern = #"\[\[(?:([A-Za-z][A-Za-z0-9_-]*):)?([^|#\]]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]"#

    public nonisolated init() {}

    public nonisolated func parse(_ contents: String) -> [WikiLink] {
        guard let expression = try? NSRegularExpression(pattern: Self.pattern) else {
            return []
        }

        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let matches = expression.matches(in: contents, range: range)
        var links: [WikiLink] = []
        var seenTargets: Set<String> = []

        for match in matches {
            guard let targetRange = Range(match.range(at: 2), in: contents),
                  let fullRange = Range(match.range(at: 0), in: contents) else {
                continue
            }

            let target = String(contents[targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let namespace: String? = {
                guard match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound,
                      let nsRange = Range(match.range(at: 1), in: contents) else {
                    return nil
                }
                return String(contents[nsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            let link = WikiLink(
                target: target,
                originalText: String(contents[fullRange]),
                namespace: namespace
            )
            let normalizedTarget = link.normalizedTarget

            guard !WikiLink.normalizePageKey(target).isEmpty, seenTargets.insert(normalizedTarget).inserted else {
                continue
            }

            links.append(link)
        }

        return links
    }
}
