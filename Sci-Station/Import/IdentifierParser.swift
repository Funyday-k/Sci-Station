import Foundation

public struct DetectedPaperIdentifiers: Sendable, Hashable {
    public var doi: String?
    public var arxiv: String?
    /// arXiv version suffix (`vN`) when the input contained one. The primary
    /// `arxiv` field always stores the unversioned identifier so that graph
    /// nodes and reference lookups do not drift between `v1` and `v2`.
    public var arxivVersion: String?

    public nonisolated init(doi: String?, arxiv: String?, arxivVersion: String? = nil) {
        self.doi = doi
        self.arxiv = arxiv
        self.arxivVersion = arxivVersion
    }

    public nonisolated var isEmpty: Bool {
        doi == nil && arxiv == nil
    }
}

public enum ImportIdentifierKind: String, Codable, Sendable {
    case arxiv
    case doi
    case inspire
    case pdfURL
    case url
    case unknown
}

public struct ParsedImportIdentifier: Sendable, Hashable {
    public var kind: ImportIdentifierKind
    public var originalValue: String
    public var normalizedValue: String
}

public struct IdentifierParser {
    public nonisolated init() {}

    public nonisolated func parse(_ input: String) -> ParsedImportIdentifier {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return ParsedImportIdentifier(kind: .unknown, originalValue: input, normalizedValue: "")
        }

        if let arxivID = parseArxivID(from: trimmedInput) {
            return ParsedImportIdentifier(kind: .arxiv, originalValue: input, normalizedValue: arxivID)
        }

        if let doi = parseDOI(from: trimmedInput) {
            return ParsedImportIdentifier(kind: .doi, originalValue: input, normalizedValue: doi)
        }

        if let inspireID = parseInspireID(from: trimmedInput) {
            return ParsedImportIdentifier(kind: .inspire, originalValue: input, normalizedValue: inspireID)
        }

        if let url = URL(string: trimmedInput), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            if url.path.lowercased().hasSuffix(".pdf") {
                return ParsedImportIdentifier(kind: .pdfURL, originalValue: input, normalizedValue: trimmedInput)
            }
            return ParsedImportIdentifier(kind: .url, originalValue: input, normalizedValue: trimmedInput)
        }

        return ParsedImportIdentifier(kind: .unknown, originalValue: input, normalizedValue: trimmedInput)
    }

    public nonisolated func detectPaperIdentifiers(in text: String, fallbackInput: String? = nil) -> DetectedPaperIdentifiers {
        let doi = extractDOI(from: text) ?? fallbackInput.flatMap(extractDOI(from:))
        let arxivDetection = extractArxivIDWithVersion(from: text)
            ?? fallbackInput.flatMap(extractArxivIDWithVersion(from:))
        return DetectedPaperIdentifiers(doi: doi, arxiv: arxivDetection?.id, arxivVersion: arxivDetection?.version)
    }

    public nonisolated func extractArxivID(from text: String) -> String? {
        extractArxivIDWithVersion(from: text)?.id
    }

    /// Extracts an arXiv identifier and splits out the version suffix (`vN`).
    ///
    /// The primary id is always returned without its version suffix. This is
    /// important for graph node ids and reference resolution: `2101.12345` and
    /// `2101.12345v2` refer to the same paper and must hash to the same node.
    public nonisolated func extractArxivIDWithVersion(from text: String) -> (id: String, version: String?)? {
        let normalizedInput = text
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        guard let rawID = firstMatch(
            pattern: "(?:arxiv\\s*:?\\s*|https?://arxiv\\.org/(?:abs|pdf)/)?(\\d{4}\\.\\d{4,5}(?:v\\d+)?)",
            in: normalizedInput,
            captureGroup: 1,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        return Self.splitArxivVersion(rawID)
    }

    public nonisolated func extractDOI(from text: String) -> String? {
        let normalizedInput = text
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "https://dx.doi.org/", with: "")
            .replacingOccurrences(of: "http://dx.doi.org/", with: "")

        guard let match = firstMatch(
            pattern: "(10\\.\\d{4,9}/[-._;()/:A-Z0-9]+)",
            in: normalizedInput,
            captureGroup: 1,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        // DOI identifiers are case-insensitive per the spec. Normalise to
        // lowercase + trim trailing punctuation so that the same paper always
        // hashes to the same graph node regardless of how the DOI was cited.
        return sanitizeDOI(match).lowercased()
    }

    /// Returns the arXiv id without the `vN` version suffix and the numeric
    /// version string (if present). Accepts already-normalized inputs like
    /// `2101.12345` and full forms like `2101.12345v3`.
    public nonisolated static func splitArxivVersion(_ rawID: String) -> (id: String, version: String?) {
        let normalized = rawID.lowercased()
        guard let versionMatchRange = normalized.range(of: #"v(\d+)$"#, options: .regularExpression) else {
            return (normalized, nil)
        }
        let id = String(normalized[..<versionMatchRange.lowerBound])
        // strip the leading `v`
        let version = String(normalized[versionMatchRange.lowerBound...]).dropFirst()
        return (id, String(version))
    }

    nonisolated private func parseArxivID(from input: String) -> String? {
        let normalizedInput = input
            .replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "arXiv ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "http://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "https://arxiv.org/pdf/", with: "")
            .replacingOccurrences(of: "http://arxiv.org/pdf/", with: "")
            .replacingOccurrences(of: ".pdf", with: "")

        let range = NSRange(normalizedInput.startIndex..<normalizedInput.endIndex, in: normalizedInput)
        guard let match = try? NSRegularExpression(pattern: "^(\\d{4}\\.\\d{4,5}(v\\d+)?)$", options: [.caseInsensitive])
            .firstMatch(in: normalizedInput, range: range),
            let matchRange = Range(match.range(at: 1), in: normalizedInput) else {
            return nil
        }

        let raw = String(normalizedInput[matchRange])
        return Self.splitArxivVersion(raw).id
    }

    nonisolated private func parseDOI(from input: String) -> String? {
        extractDOI(from: input)
    }

    nonisolated private func parseInspireID(from input: String) -> String? {
        // Only recognize the canonical `inspirehep.net/literature/<id>` URL
        // or the `inspire:<id>` short form. Other URLs fall through to the
        // generic `.url` branch instead of being mistakenly classified as
        // Inspire records. See docs/development/comment.md §3.7.
        let lowered = input.lowercased()
        if let range = lowered.range(of: "inspirehep.net/literature/") {
            let tail = input[range.upperBound...]
            let digits = tail.prefix(while: { $0.isNumber })
            return digits.isEmpty ? nil : String(digits)
        }

        if lowered.hasPrefix("inspire:") {
            let tail = input.dropFirst("inspire:".count)
            let digits = tail.prefix(while: { $0.isNumber })
            return digits.isEmpty ? nil : String(digits)
        }

        return nil
    }

    nonisolated private func firstMatch(
        pattern: String,
        in input: String,
        captureGroup: Int,
        options: NSRegularExpression.Options = []
    ) -> String? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = try? NSRegularExpression(pattern: pattern, options: options)
            .firstMatch(in: input, range: range),
            let matchRange = Range(match.range(at: captureGroup), in: input) else {
            return nil
        }

        return String(input[matchRange])
    }

    nonisolated private func sanitizeDOI(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.,;:)]}>\"'"))
    }
}
