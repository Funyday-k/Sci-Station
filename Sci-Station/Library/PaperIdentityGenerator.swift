import Foundation

public enum PaperIdentityGenerator {
    nonisolated private static let stopWords: Set<String> = [
        "a", "an", "and", "for", "from", "in", "of", "on", "the", "to", "with"
    ]

    public nonisolated static func citekey(
        title: String,
        authors: [String],
        year: Int?,
        existing: Set<String>
    ) -> String {
        let authorToken = normalizedLastName(from: authors.first) ?? "unknown"
        let yearToken = year.map(String.init) ?? "xxxx"
        let keywordToken = keywords(in: title).first ?? "paper"
        let base = "\(authorToken)\(yearToken)\(keywordToken)"
        return uniqued(base: base, existing: existing)
    }

    public nonisolated static func paperID(
        title: String,
        authors: [String],
        year: Int?,
        existing: Set<String>
    ) -> String {
        let authorToken = normalizedLastName(from: authors.first) ?? "unknown"
        let yearToken = year.map(String.init) ?? "xxxx"
        let keywordTokens = Array(keywords(in: title).prefix(3))
        let suffix = keywordTokens.isEmpty ? "paper" : keywordTokens.joined(separator: "-")
        let base = "\(authorToken)\(yearToken)-\(suffix)"
        return uniqued(base: base, existing: existing)
    }

    nonisolated private static func normalizedLastName(from author: String?) -> String? {
        guard let author else {
            return nil
        }

        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let commaIndex = trimmed.firstIndex(of: ",") {
            return normalizedToken(String(trimmed[..<commaIndex]))
        }

        return trimmed.split(separator: " ").last.map { normalizedToken(String($0)) }
    }

    nonisolated private static func keywords(in title: String) -> [String] {
        title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { normalizedToken($0) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    nonisolated private static func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    nonisolated private static func uniqued(base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else {
            return base
        }

        let suffixes = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for suffix in suffixes {
            let candidate = base + String(suffix)
            if !existing.contains(candidate) {
                return candidate
            }
        }

        var counter = 1
        while existing.contains(base + String(counter)) {
            counter += 1
        }
        return base + String(counter)
    }
}