import Foundation

/// A parsed BibTeX entry. Fields are stored with lowercase keys.
public nonisolated struct BibtexEntry: Hashable, Sendable {
    public let key: String
    public let type: String
    public let fields: [String: String]

    public nonisolated init(key: String, type: String, fields: [String: String]) {
        self.key = key
        self.type = type
        self.fields = fields
    }

    public var doi: String? { fields["doi"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyBibtex }
    public var arxivID: String? {
        (fields["eprint"] ?? fields["arxiv"] ?? fields["arxivid"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyBibtex
    }
    public var title: String? { fields["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyBibtex }
    public var year: Int? { fields["year"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    public var authors: [String] {
        guard let raw = fields["author"] else { return [] }
        return raw.components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    public var firstAuthorLastName: String? {
        guard let first = authors.first else { return nil }
        if let commaIndex = first.firstIndex(of: ",") {
            return String(first[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyBibtex
        }
        return first.split(separator: " ").last.map(String.init)
    }
}

/// Pure-Swift BibTeX parser. Handles common entry types, skips `@comment`,
/// `@preamble`, `@string` blocks. Tolerant of malformed entries (skips them
/// without crashing).
public struct BibtexParser {
    public nonisolated init() {}

    public nonisolated func parse(_ text: String) -> [BibtexEntry] {
        var entries: [BibtexEntry] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard let atIndex = text[index...].firstIndex(of: "@") else { break }
            index = text.index(after: atIndex)

            guard let (type, afterType) = readWord(in: text, from: index) else { continue }
            index = afterType
            let loweredType = type.lowercased()

            if loweredType == "comment" || loweredType == "preamble" || loweredType == "string" {
                // Skip the block by finding the matching brace/paren.
                if let end = skipBlock(in: text, from: index) {
                    index = end
                }
                continue
            }

            guard let openBrace = text[index...].firstIndex(where: { $0 == "{" || $0 == "(" }) else { continue }
            let closingChar: Character = text[openBrace] == "{" ? "}" : ")"
            index = text.index(after: openBrace)

            // Read the key (everything up to the first comma).
            guard let commaIndex = text[index...].firstIndex(of: ",") else { continue }
            let key = String(text[index..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            index = text.index(after: commaIndex)

            // Parse fields until the matching closing brace.
            var fields: [String: String] = [:]
            var depth = 1
            while index < text.endIndex, depth > 0 {
                skipWhitespaceAndCommas(in: text, index: &index)
                if index >= text.endIndex { break }

                if text[index] == closingChar {
                    depth -= 1
                    index = text.index(after: index)
                    break
                }

                // Read field name.
                guard let (fieldName, afterFieldName) = readFieldName(in: text, from: index) else {
                    // Can't parse field; skip to closing brace.
                    if let end = findClosing(closingChar, in: text, from: index, depth: depth) {
                        index = end
                    }
                    break
                }
                index = afterFieldName
                skipWhitespace(in: text, index: &index)

                guard index < text.endIndex, text[index] == "=" else {
                    // Malformed; try to recover.
                    continue
                }
                index = text.index(after: index)
                skipWhitespace(in: text, index: &index)

                // Read field value.
                guard let (value, afterValue) = readFieldValue(in: text, from: index) else {
                    break
                }
                fields[fieldName.lowercased()] = value
                index = afterValue
            }

            guard !key.isEmpty else { continue }
            entries.append(BibtexEntry(key: key, type: loweredType, fields: fields))
        }

        return entries
    }

    // MARK: - Helpers

    private func readWord(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = start
        skipWhitespace(in: text, index: &index)
        let wordStart = index
        while index < text.endIndex, text[index].isLetter || text[index].isNumber || text[index] == "_" || text[index] == "-" {
            index = text.index(after: index)
        }
        guard wordStart != index else { return nil }
        return (String(text[wordStart..<index]), index)
    }

    private func readFieldName(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = start
        skipWhitespace(in: text, index: &index)
        let nameStart = index
        while index < text.endIndex, text[index].isLetter || text[index].isNumber || text[index] == "_" || text[index] == "-" {
            index = text.index(after: index)
        }
        guard nameStart != index else { return nil }
        return (String(text[nameStart..<index]), index)
    }

    private func readFieldValue(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = start
        skipWhitespace(in: text, index: &index)
        guard index < text.endIndex else { return nil }

        if text[index] == "{" {
            return readBracedValue(in: text, from: index)
        } else if text[index] == "\"" {
            return readQuotedValue(in: text, from: index)
        } else {
            // Bare number or concatenated string reference.
            let valueStart = index
            while index < text.endIndex, text[index] != "," && text[index] != "}" && text[index] != ")" && !text[index].isNewline {
                index = text.index(after: index)
            }
            return (String(text[valueStart..<index]).trimmingCharacters(in: .whitespaces), index)
        }
    }

    private func readBracedValue(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = text.index(after: start) // skip opening {
        var depth = 1
        var value = ""
        while index < text.endIndex, depth > 0 {
            let ch = text[index]
            if ch == "{" {
                depth += 1
                value.append(ch)
            } else if ch == "}" {
                depth -= 1
                if depth > 0 { value.append(ch) }
            } else {
                value.append(ch)
            }
            index = text.index(after: index)
        }
        return (value, index)
    }

    private func readQuotedValue(in text: String, from start: String.Index) -> (String, String.Index)? {
        var index = text.index(after: start) // skip opening "
        var value = ""
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\\" {
                value.append(ch)
                index = text.index(after: index)
                if index < text.endIndex {
                    value.append(text[index])
                    index = text.index(after: index)
                }
            } else if ch == "\"" {
                index = text.index(after: index)
                break
            } else {
                value.append(ch)
                index = text.index(after: index)
            }
        }
        return (value, index)
    }

    private func skipBlock(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        skipWhitespace(in: text, index: &index)
        guard index < text.endIndex else { return nil }
        let open = text[index]
        let close: Character
        if open == "{" { close = "}" }
        else if open == "(" { close = ")" }
        else { return nil }
        return findClosing(close, in: text, from: text.index(after: index), depth: 1)
    }

    private func findClosing(_ closing: Character, in text: String, from start: String.Index, depth initialDepth: Int) -> String.Index? {
        let opening: Character = closing == "}" ? "{" : "("
        var depth = initialDepth
        var index = start
        while index < text.endIndex {
            if text[index] == opening { depth += 1 }
            else if text[index] == closing {
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func skipWhitespace(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
    }

    private func skipWhitespaceAndCommas(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace || text[index] == "," { index = text.index(after: index) }
    }
}

private extension String {
    var nilIfEmptyBibtex: String? { isEmpty ? nil : self }
}
