import Foundation

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

    nonisolated private func parseArxivID(from input: String) -> String? {
        let normalizedInput = input
            .replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "http://arxiv.org/abs/", with: "")
            .replacingOccurrences(of: "https://arxiv.org/pdf/", with: "")
            .replacingOccurrences(of: "http://arxiv.org/pdf/", with: "")
            .replacingOccurrences(of: ".pdf", with: "")

        let range = NSRange(normalizedInput.startIndex..<normalizedInput.endIndex, in: normalizedInput)
        guard let match = try? NSRegularExpression(pattern: "^(\\d{4}\\.\\d{4,5}(v\\d+)?)$")
            .firstMatch(in: normalizedInput, range: range),
            let matchRange = Range(match.range, in: normalizedInput) else {
            return nil
        }

        return String(normalizedInput[matchRange])
    }

    nonisolated private func parseDOI(from input: String) -> String? {
        let normalizedInput = input
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")

        let range = NSRange(normalizedInput.startIndex..<normalizedInput.endIndex, in: normalizedInput)
        guard let match = try? NSRegularExpression(pattern: "(10\\.\\d{4,9}/[-._;()/:A-Z0-9]+)", options: [.caseInsensitive])
            .firstMatch(in: normalizedInput, range: range),
            let matchRange = Range(match.range(at: 1), in: normalizedInput) else {
            return nil
        }

        return String(normalizedInput[matchRange])
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
}