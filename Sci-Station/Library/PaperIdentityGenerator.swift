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

    /// Computes a stable identifier used for graph nodes (`paper:<graphNodeID>`).
    ///
    /// Priority:
    /// 1. DOI (lowercased, trimmed)
    /// 2. arXiv id (lowercased, without version suffix `vN`)
    /// 3. Inspire id (prefixed with `inspire:`)
    /// 4. citekey (lowercased)
    /// 5. fallback paperID
    ///
    /// Once a paper has a graphNodeID persisted in its `meta.yaml`, callers must not
    /// recompute it from mutable metadata. This function only produces the initial
    /// value; the freeze-on-first-write policy lives in `PaperRepository.save`.
    public nonisolated static func graphNodeID(
        doi: String?,
        arxiv: String?,
        inspireID: String?,
        citekey: String?,
        fallbackPaperID: String
    ) -> String {
        if let normalizedDOI = normalizedDOI(doi) {
            return normalizedDOI
        }
        if let normalizedArxiv = normalizedArxiv(arxiv) {
            return "arxiv:" + normalizedArxiv
        }
        if let normalizedInspire = normalizedInspire(inspireID) {
            return "inspire:" + normalizedInspire
        }
        if let trimmed = citekey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !trimmed.isEmpty {
            return "citekey:" + trimmed
        }
        return "local:" + fallbackPaperID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public nonisolated static func normalizedDOI(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let prefixes = ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:"]
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count))
            break
        }

        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;")))
            .lowercased()
        return normalized.hasPrefix("10.") ? normalized : nil
    }

    public nonisolated static func normalizedArxiv(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let prefixes = [
            "https://arxiv.org/abs/", "http://arxiv.org/abs/",
            "https://arxiv.org/pdf/", "http://arxiv.org/pdf/",
            "arxiv:"
        ]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count))
            break
        }

        if trimmed.hasSuffix(".pdf") {
            trimmed = String(trimmed.dropLast(4))
        }

        if let versionRange = trimmed.range(of: #"v\d+$"#, options: .regularExpression) {
            trimmed = String(trimmed[..<versionRange.lowerBound])
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    public nonisolated static func normalizedInspire(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if let range = lowered.range(of: "inspirehep.net/literature/") {
            trimmed = String(trimmed[range.upperBound...])
        } else if lowered.hasPrefix("inspire:") {
            trimmed = String(trimmed.dropFirst("inspire:".count))
        }

        let digits = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/?#"))
        return digits.isEmpty ? nil : digits
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