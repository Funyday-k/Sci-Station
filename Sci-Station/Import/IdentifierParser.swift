import Foundation

public struct DetectedPaperIdentifiers: Sendable, Hashable {
    public var doi: String?
    public var arxiv: String?

    public nonisolated init(doi: String?, arxiv: String?) {
        self.doi = doi
        self.arxiv = arxiv
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
        let arxiv = extractArxivID(from: text) ?? fallbackInput.flatMap(extractArxivID(from:))
        return DetectedPaperIdentifiers(doi: doi, arxiv: arxiv)
    }

    public nonisolated func extractArxivID(from text: String) -> String? {
        let normalizedInput = text
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        return firstMatch(
            pattern: "(?:arxiv\\s*:?\\s*|https?://arxiv\\.org/(?:abs|pdf)/)?(\\d{4}\\.\\d{4,5}(?:v\\d+)?)",
            in: normalizedInput,
            captureGroup: 1,
            options: [.caseInsensitive]
        )
    }

    public nonisolated func extractDOI(from text: String) -> String? {
        let normalizedInput = text
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")

        guard let match = firstMatch(
            pattern: "(10\\.\\d{4,9}/[-._;()/:A-Z0-9]+)",
            in: normalizedInput,
            captureGroup: 1,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        return sanitizeDOI(match)
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

        return String(normalizedInput[matchRange])
    }

    nonisolated private func parseDOI(from input: String) -> String? {
        extractDOI(from: input)
    }

    nonisolated private func parseInspireID(from input: String) -> String? {
        if let match = input.split(separator: "/").last, input.contains("inspirehep.net/literature/") {
            return String(match)
        }

        if input.lowercased().hasPrefix("inspire:"), let id = input.split(separator: ":").last {
            return String(id)
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