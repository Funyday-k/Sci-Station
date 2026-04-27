import Foundation

public struct PaperMetadataCodec {
    public nonisolated init() {}

    public nonisolated func decode(
        _ contents: String,
        directoryRelativePath: String,
        fallbackTitle: String,
        createdAt: Date?,
        updatedAt: Date?
    ) -> Paper {
        let parsed = parse(contents)
        let notes = parsed.objects["notes"] ?? [:]
        let reading = parsed.objects["reading"] ?? [:]
        let parsedCreatedAt = reading["added"].flatMap { makeDayFormatter().date(from: $0) }
        let effectiveCreatedAt = parsedCreatedAt ?? createdAt ?? updatedAt ?? Date()
        let effectiveUpdatedAt = updatedAt ?? effectiveCreatedAt

        return Paper(
            id: stringValue(for: "id", in: parsed) ?? directoryRelativePath.components(separatedBy: "/").last ?? fallbackTitle,
            citekey: stringValue(for: "citekey", in: parsed) ?? "unknownxxxxpaper",
            title: stringValue(for: "title", in: parsed) ?? fallbackTitle,
            authors: arrayValue(for: "authors", in: parsed),
            year: intValue(for: "year", in: parsed),
            venue: optionalStringValue(for: "venue", in: parsed),
            doi: optionalStringValue(for: "doi", in: parsed),
            arxiv: optionalStringValue(for: "arxiv", in: parsed),
            inspireID: optionalStringValue(for: "inspire_id", in: parsed),
            url: optionalStringValue(for: "url", in: parsed),
            pdfURL: optionalStringValue(for: "pdf_url", in: parsed),
            abstract: optionalStringValue(for: "abstract", in: parsed),
            categories: arrayValue(for: "categories", in: parsed),
            collectionPath: optionalStringValue(for: "collection_path", in: parsed),
            pdfRelativePath: optionalStringValue(for: "pdf", in: parsed),
            tags: arrayValue(for: "tags", in: parsed),
            status: ReadingStatus(rawValue: stringValue(for: "status", in: parsed) ?? "") ?? .unread,
            priority: Priority(rawValue: stringValue(for: "priority", in: parsed) ?? "") ?? .medium,
            rating: intValue(for: "rating", in: parsed),
            useFor: arrayValue(for: "use_for", in: parsed),
            createdAt: effectiveCreatedAt,
            updatedAt: effectiveUpdatedAt,
            lastReadAt: reading["last_read_at"].flatMap(parseTimestamp(_:)),
            lastReadPage: reading["last_page"].flatMap(Int.init),
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: emptyToNil(notes["summary_file"]),
            annotationsRelativePath: "annotations.md"
        )
    }

    public nonisolated func encode(_ paper: Paper) -> String {
        [
            "id: \(paper.id)",
            "citekey: \(paper.citekey)",
            "title: \(quoted(paper.title))",
            encodeArray(key: "authors", values: paper.authors),
            encodeScalar(key: "year", value: paper.year.map(String.init)),
            encodeScalar(key: "venue", value: paper.venue),
            encodeScalar(key: "doi", value: paper.doi),
            encodeScalar(key: "arxiv", value: paper.arxiv),
            encodeScalar(key: "inspire_id", value: paper.inspireID),
            encodeScalar(key: "url", value: paper.url),
            encodeScalar(key: "pdf_url", value: paper.pdfURL),
            encodeScalar(key: "pdf", value: paper.pdfRelativePath),
            encodeScalar(key: "collection_path", value: paper.collectionPath),
            encodeArray(key: "categories", values: paper.categories),
            encodeScalar(key: "abstract", value: paper.abstract),
            "",
            encodeArray(key: "tags", values: paper.tags),
            "status: \(paper.status.rawValue)",
            "priority: \(paper.priority.rawValue)",
            encodeScalar(key: "rating", value: paper.rating.map(String.init)),
            "",
            encodeArray(key: "use_for", values: paper.useFor),
            "",
            "reading:",
            "  added: \(makeDayFormatter().string(from: paper.createdAt))",
            encodeNestedScalar(key: "last_page", value: paper.lastReadPage.map(String.init)),
            encodeNestedScalar(key: "last_read_at", value: paper.lastReadAt.map(timestampString(from:))),
            "  first_read:",
            "  deep_read:",
            "",
            "links:",
            "  semantic_scholar:",
            "  github:",
            "  project_page:",
            "",
            "notes:",
            encodeNestedScalar(key: "summary_file", value: paper.notesSummaryRelativePath)
        ]
        .joined(separator: "\n") + "\n"
    }

    nonisolated private func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    nonisolated private func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    nonisolated private func stringValue(for key: String, in document: ParsedDocument) -> String? {
        emptyToNil(document.scalars[key])
    }

    nonisolated private func optionalStringValue(for key: String, in document: ParsedDocument) -> String? {
        emptyToNil(document.scalars[key])
    }

    nonisolated private func intValue(for key: String, in document: ParsedDocument) -> Int? {
        guard let value = document.scalars[key], !value.isEmpty else {
            return nil
        }

        return Int(value)
    }

    nonisolated private func arrayValue(for key: String, in document: ParsedDocument) -> [String] {
        document.arrays[key] ?? []
    }

    nonisolated private func encodeScalar(key: String, value: String?) -> String {
        guard let value = emptyToNil(value) else {
            return "\(key):"
        }

        return "\(key): \(quoted(value))"
    }

    nonisolated private func encodeNestedScalar(key: String, value: String?) -> String {
        guard let value = emptyToNil(value) else {
            return "  \(key):"
        }

        return "  \(key): \(quoted(value))"
    }

    nonisolated private func encodeArray(key: String, values: [String]) -> String {
        guard !values.isEmpty else {
            return "\(key): []"
        }

        let items = values.map { "  - \(quoted($0))" }.joined(separator: "\n")
        return "\(key):\n\(items)"
    }

    nonisolated private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    nonisolated private func emptyToNil(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    nonisolated private func timestampString(from date: Date) -> String {
        makeTimestampFormatter().string(from: date)
    }

    nonisolated private func parseTimestamp(_ value: String) -> Date? {
        makeTimestampFormatter().date(from: value) ?? makeDayFormatter().date(from: value)
    }

    nonisolated private func parse(_ contents: String) -> ParsedDocument {
        var parsedDocument = ParsedDocument()
        let lines = contents.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                index += 1
                continue
            }

            let indentLevel = indentation(of: line)
            guard indentLevel == 0, let colonIndex = trimmedLine.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(trimmedLine[..<colonIndex])
            let remainder = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if remainder == "[]" {
                parsedDocument.arrays[key] = []
                index += 1
                continue
            }

            if !remainder.isEmpty {
                parsedDocument.scalars[key] = unquoted(remainder)
                index += 1
                continue
            }

            let childIndex = nextNonEmptyLine(after: index, in: lines)
            guard childIndex < lines.count, indentation(of: lines[childIndex]) > indentLevel else {
                parsedDocument.scalars[key] = ""
                index += 1
                continue
            }

            let childTrimmedLine = lines[childIndex].trimmingCharacters(in: .whitespaces)
            if childTrimmedLine.hasPrefix("- ") {
                var values: [String] = []
                var cursor = childIndex

                while cursor < lines.count {
                    let childLine = lines[cursor]
                    let childIndentation = indentation(of: childLine)
                    let childTrimmed = childLine.trimmingCharacters(in: .whitespaces)

                    if childTrimmed.isEmpty {
                        cursor += 1
                        continue
                    }

                    guard childIndentation > indentLevel, childTrimmed.hasPrefix("- ") else {
                        break
                    }

                    values.append(unquoted(String(childTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                    cursor += 1
                }

                parsedDocument.arrays[key] = values
                index = cursor
                continue
            }

            var object: [String: String] = [:]
            var cursor = childIndex

            while cursor < lines.count {
                let childLine = lines[cursor]
                let childIndentation = indentation(of: childLine)
                let childTrimmed = childLine.trimmingCharacters(in: .whitespaces)

                if childTrimmed.isEmpty {
                    cursor += 1
                    continue
                }

                guard childIndentation > indentLevel, let childColonIndex = childTrimmed.firstIndex(of: ":") else {
                    break
                }

                let childKey = String(childTrimmed[..<childColonIndex])
                let childValue = String(childTrimmed[childTrimmed.index(after: childColonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                object[childKey] = unquoted(childValue)
                cursor += 1
            }

            parsedDocument.objects[key] = object
            index = cursor
        }

        return parsedDocument
    }

    nonisolated private func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    nonisolated private func nextNonEmptyLine(after index: Int, in lines: [String]) -> Int {
        var cursor = index + 1
        while cursor < lines.count {
            if !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                return cursor
            }
            cursor += 1
        }
        return cursor
    }

    nonisolated private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }

        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private struct ParsedDocument {
    var scalars: [String: String] = [:]
    var arrays: [String: [String]] = [:]
    var objects: [String: [String: String]] = [:]

    nonisolated init() {}
}