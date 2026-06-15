import Foundation

/// Parses and serialises `library/papers/<id>/meta.yaml` documents.
///
/// # Round-trip guarantees
///
/// - Unknown top-level blocks (scalar or block-form) are preserved verbatim and
///   re-emitted at the end of the document. This keeps `references:`,
///   user-added fields, and later metadata extensions alive across `decode → encode`.
/// - Unknown child keys under known block sections (`reading:`, `notes:`,
///   `links:`) are preserved and re-emitted under the same section.
/// - The graph node identifier is serialised as `graph_node_id:` and never
///   recomputed by the codec itself.
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
        let notes = parsed.objects["notes"] ?? ParsedObjectBlock()
        let reading = parsed.objects["reading"] ?? ParsedObjectBlock()
        let parsedCreatedAt = reading.scalars["added"].flatMap { makeDayFormatter().date(from: $0) }
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
            titleTranslation: optionalStringValue(for: "title_translation", in: parsed),
            itemType: optionalStringValue(for: "item_type", in: parsed),
            publicationTitle: optionalStringValue(for: "publication_title", in: parsed),
            publisher: optionalStringValue(for: "publisher", in: parsed),
            publicationPlace: optionalStringValue(for: "publication_place", in: parsed),
            publishedDate: optionalStringValue(for: "published_date", in: parsed),
            volume: optionalStringValue(for: "volume", in: parsed),
            issue: optionalStringValue(for: "issue", in: parsed),
            pages: optionalStringValue(for: "pages", in: parsed),
            series: optionalStringValue(for: "series", in: parsed),
            seriesTitle: optionalStringValue(for: "series_title", in: parsed),
            journalAbbreviation: optionalStringValue(for: "journal_abbreviation", in: parsed),
            issn: optionalStringValue(for: "issn", in: parsed),
            isbn: optionalStringValue(for: "isbn", in: parsed),
            pmid: optionalStringValue(for: "pmid", in: parsed),
            pmcid: optionalStringValue(for: "pmcid", in: parsed),
            language: optionalStringValue(for: "language", in: parsed),
            archive: optionalStringValue(for: "archive", in: parsed),
            archiveLocation: optionalStringValue(for: "archive_location", in: parsed),
            libraryCatalog: optionalStringValue(for: "library_catalog", in: parsed),
            callNumber: optionalStringValue(for: "call_number", in: parsed),
            shortTitle: optionalStringValue(for: "short_title", in: parsed),
            accessedAt: optionalStringValue(for: "accessed_at", in: parsed),
            bibtex: optionalStringValue(for: "bibtex", in: parsed),
            collectionPath: optionalStringValue(for: "collection_path", in: parsed),
            projectIDs: arrayValue(for: "project_ids", in: parsed),
            coreProjectIDs: arrayValue(for: "core_project_ids", in: parsed),
            folderPath: optionalStringValue(for: "folder_path", in: parsed) ?? optionalStringValue(for: "collection_path", in: parsed),
            pdfRelativePath: optionalStringValue(for: "pdf", in: parsed),
            tags: arrayValue(for: "tags", in: parsed),
            status: ReadingStatus(rawValue: stringValue(for: "status", in: parsed) ?? "") ?? .unread,
            priority: Priority(rawValue: stringValue(for: "priority", in: parsed) ?? "") ?? .medium,
            rating: intValue(for: "rating", in: parsed),
            useFor: arrayValue(for: "use_for", in: parsed),
            createdAt: effectiveCreatedAt,
            updatedAt: effectiveUpdatedAt,
            lastReadAt: reading.scalars["last_read_at"].flatMap(parseTimestamp(_:)),
            lastReadPage: reading.scalars["last_page"].flatMap(Int.init),
            lastReadScale: reading.scalars["last_scale"].flatMap(Double.init),
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: emptyToNil(notes.scalars["summary_file"]),
            annotationsRelativePath: "annotations.md",
            graphNodeID: optionalStringValue(for: "graph_node_id", in: parsed)
        )
    }

    /// Fast-path helper used by `PaperRepository` to implement the
    /// freeze-on-first-write policy for `graphNodeID` without having to decode
    /// the full `Paper` struct.
    public nonisolated func decodedGraphNodeID(from contents: String) -> String? {
        optionalStringValue(for: "graph_node_id", in: parse(contents))
    }

    public nonisolated func encode(_ paper: Paper) -> String {
        // We need access to the original parsed document to preserve unknown blocks.
        // Callers who want round-trip fidelity should use `encode(_:preserving:)`.
        // This overload preserves no unknown fields.
        encode(paper, preserving: nil)
    }

    /// Encodes a paper to YAML. When `existingContents` is provided, any
    /// unknown top-level blocks or unknown child keys under known block
    /// sections (`reading:`, `notes:`, `links:`) are preserved and re-emitted.
    public nonisolated func encode(_ paper: Paper, preserving existingContents: String?) -> String {
        let preserved: ParsedDocument? = existingContents.map { parse($0) }

        var lines: [String] = [
            "id: \(paper.id)",
            "citekey: \(paper.citekey)",
            "graph_node_id: \(quoted(paper.resolvedGraphNodeID))",
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
            encodeScalar(key: "folder_path", value: paper.folderPath),
            encodeArray(key: "categories", values: paper.categories),
            encodeScalar(key: "abstract", value: paper.abstract),
            encodeScalar(key: "title_translation", value: paper.titleTranslation),
            encodeScalar(key: "item_type", value: paper.itemType),
            encodeScalar(key: "publication_title", value: paper.publicationTitle),
            encodeScalar(key: "publisher", value: paper.publisher),
            encodeScalar(key: "publication_place", value: paper.publicationPlace),
            encodeScalar(key: "published_date", value: paper.publishedDate),
            encodeScalar(key: "volume", value: paper.volume),
            encodeScalar(key: "issue", value: paper.issue),
            encodeScalar(key: "pages", value: paper.pages),
            encodeScalar(key: "series", value: paper.series),
            encodeScalar(key: "series_title", value: paper.seriesTitle),
            encodeScalar(key: "journal_abbreviation", value: paper.journalAbbreviation),
            encodeScalar(key: "issn", value: paper.issn),
            encodeScalar(key: "isbn", value: paper.isbn),
            encodeScalar(key: "pmid", value: paper.pmid),
            encodeScalar(key: "pmcid", value: paper.pmcid),
            encodeScalar(key: "language", value: paper.language),
            encodeScalar(key: "archive", value: paper.archive),
            encodeScalar(key: "archive_location", value: paper.archiveLocation),
            encodeScalar(key: "library_catalog", value: paper.libraryCatalog),
            encodeScalar(key: "call_number", value: paper.callNumber),
            encodeScalar(key: "short_title", value: paper.shortTitle),
            encodeScalar(key: "accessed_at", value: paper.accessedAt),
            encodeScalar(key: "bibtex", value: paper.bibtex),
            "",
            encodeArray(key: "tags", values: paper.tags),
            encodeArray(key: "project_ids", values: paper.projectIDs),
            encodeArray(key: "core_project_ids", values: paper.coreProjectIDs),
            "status: \(paper.status.rawValue)",
            "priority: \(paper.priority.rawValue)",
            encodeScalar(key: "rating", value: paper.rating.map(String.init)),
            "",
            encodeArray(key: "use_for", values: paper.useFor),
            "",
            "reading:",
            "  added: \(makeDayFormatter().string(from: paper.createdAt))",
            encodeNestedScalar(key: "last_page", value: paper.lastReadPage.map(String.init)),
            encodeNestedScalar(key: "last_scale", value: paper.lastReadScale.map { String(format: "%.4f", $0) }),
            encodeNestedScalar(key: "last_read_at", value: paper.lastReadAt.map(timestampString(from:))),
            "  first_read:",
            "  deep_read:"
        ]

        // Preserve any unknown child keys inside `reading:` that the codec
        // does not explicitly manage.
        if let preservedReading = preserved?.objects["reading"] {
            let reservedReading: Set<String> = ["added", "last_page", "last_scale", "last_read_at", "first_read", "deep_read"]
            for unknownLine in preservedReading.unknownLines(reserved: reservedReading) {
                lines.append(unknownLine)
            }
        }

        lines.append("")
        lines.append("links:")
        let preservedLinks = preserved?.objects["links"]
        let reservedLinkKeys: Set<String> = ["semantic_scholar", "github", "project_page"]
        lines.append(encodeNestedScalar(key: "semantic_scholar", value: preservedLinks?.scalars["semantic_scholar"]))
        lines.append(encodeNestedScalar(key: "github", value: preservedLinks?.scalars["github"]))
        lines.append(encodeNestedScalar(key: "project_page", value: preservedLinks?.scalars["project_page"]))
        if let preservedLinks {
            for unknownLine in preservedLinks.unknownLines(reserved: reservedLinkKeys) {
                lines.append(unknownLine)
            }
        }

        lines.append("")
        lines.append("notes:")
        lines.append(encodeNestedScalar(key: "summary_file", value: paper.notesSummaryRelativePath))
        if let preservedNotes = preserved?.objects["notes"] {
            let reservedNotesKeys: Set<String> = ["summary_file"]
            for unknownLine in preservedNotes.unknownLines(reserved: reservedNotesKeys) {
                lines.append(unknownLine)
            }
        }

        // Any fully unknown top-level blocks (e.g. future `references:` list)
        // are emitted verbatim in their original order.
        if let preserved {
            let knownTopLevel = Self.knownTopLevelKeys
            for block in preserved.orderedUnknownBlocks where !knownTopLevel.contains(block.key) {
                lines.append("")
                lines.append(contentsOf: block.rawLines)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static let knownTopLevelKeys: Set<String> = [
        "id", "citekey", "graph_node_id", "title", "authors", "year", "venue",
        "doi", "arxiv", "inspire_id", "url", "pdf_url", "pdf", "collection_path",
        "folder_path", "categories", "abstract", "title_translation", "item_type",
        "publication_title", "publisher", "publication_place", "published_date",
        "volume", "issue", "pages", "series", "series_title",
        "journal_abbreviation", "issn", "isbn", "pmid", "pmcid", "language",
        "archive", "archive_location", "library_catalog", "call_number",
        "short_title", "accessed_at", "bibtex", "tags", "project_ids",
        "core_project_ids", "status", "priority", "rating", "use_for",
        "reading", "links", "notes"
    ]

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
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
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
                parsedDocument.orderedUnknownBlocks.append(ParsedBlock(key: key, rawLines: [line]))
                index += 1
                continue
            }

            if !remainder.isEmpty {
                parsedDocument.scalars[key] = unquoted(remainder)
                parsedDocument.orderedUnknownBlocks.append(ParsedBlock(key: key, rawLines: [line]))
                index += 1
                continue
            }

            let childIndex = nextNonEmptyLine(after: index, in: lines)
            guard childIndex < lines.count, indentation(of: lines[childIndex]) > indentLevel else {
                parsedDocument.scalars[key] = ""
                parsedDocument.orderedUnknownBlocks.append(ParsedBlock(key: key, rawLines: [line]))
                index += 1
                continue
            }

            let childTrimmedLine = lines[childIndex].trimmingCharacters(in: .whitespaces)
            if childTrimmedLine.hasPrefix("- ") {
                var values: [String] = []
                var rawLines: [String] = [line]
                var cursor = childIndex

                // For list blocks we need to capture every line whose indent
                // is greater than the parent block, not just lines that begin
                // with `- `. This keeps list-of-objects blocks (such as the
                // `references:` extension) intact across round-trips —
                // each list item's sub-keys sit at a deeper indent level and
                // must survive verbatim.
                while cursor < lines.count {
                    let childLine = lines[cursor]
                    let childIndentation = indentation(of: childLine)
                    let childTrimmed = childLine.trimmingCharacters(in: .whitespaces)

                    if childTrimmed.isEmpty {
                        cursor += 1
                        continue
                    }

                    guard childIndentation > indentLevel else {
                        break
                    }

                    if childTrimmed.hasPrefix("- ") {
                        values.append(unquoted(String(childTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                    }
                    rawLines.append(childLine)
                    cursor += 1
                }

                parsedDocument.arrays[key] = values
                parsedDocument.orderedUnknownBlocks.append(ParsedBlock(key: key, rawLines: rawLines))
                index = cursor
                continue
            }

            // Generic block object (may contain scalars and/or nested structures).
            var object = ParsedObjectBlock()
            var rawLines: [String] = [line]
            var cursor = childIndex

            while cursor < lines.count {
                let childLine = lines[cursor]
                let childIndentation = indentation(of: childLine)
                let childTrimmed = childLine.trimmingCharacters(in: .whitespaces)

                if childTrimmed.isEmpty {
                    cursor += 1
                    continue
                }

                guard childIndentation > indentLevel else {
                    break
                }

                if let childColonIndex = childTrimmed.firstIndex(of: ":") {
                    let childKey = String(childTrimmed[..<childColonIndex])
                    let childValue = String(childTrimmed[childTrimmed.index(after: childColonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    object.scalars[childKey] = unquoted(childValue)
                    object.rawChildLines.append(childLine)
                } else {
                    // Not a key: value pair (could be "- item", etc.). Still preserve raw.
                    object.rawChildLines.append(childLine)
                }
                rawLines.append(childLine)
                cursor += 1
            }

            parsedDocument.objects[key] = object
            parsedDocument.orderedUnknownBlocks.append(ParsedBlock(key: key, rawLines: rawLines))
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
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private struct ParsedDocument {
    var scalars: [String: String] = [:]
    var arrays: [String: [String]] = [:]
    var objects: [String: ParsedObjectBlock] = [:]
    /// Ordered list of parsed top-level blocks (key + raw lines). Used by the
    /// encoder to preserve unknown blocks in their original order.
    var orderedUnknownBlocks: [ParsedBlock] = []

    nonisolated init() {}
}

private struct ParsedObjectBlock {
    var scalars: [String: String] = [:]
    /// Raw lines for children of this block, preserving indentation and
    /// original ordering. Used to re-emit unknown child keys.
    var rawChildLines: [String] = []

    nonisolated init() {}

    /// Returns the raw child lines whose `key:` is not in `reserved`.
    /// Child lines without a `:` (e.g. list items) are included as-is when
    /// they sit under an unknown key.
    nonisolated func unknownLines(reserved: Set<String>) -> [String] {
        var result: [String] = []
        var inUnknownBlock = false
        var unknownBlockIndent = -1

        for raw in rawChildLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix(while: { $0 == " " }).count

            if trimmed.isEmpty {
                continue
            }

            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex])
                if !reserved.contains(key) {
                    result.append(raw)
                    inUnknownBlock = true
                    unknownBlockIndent = indent
                } else {
                    inUnknownBlock = false
                    unknownBlockIndent = -1
                }
            } else if inUnknownBlock, indent > unknownBlockIndent {
                // Continuation of an unknown block (list items, etc.)
                result.append(raw)
            }
        }
        return result
    }
}

private struct ParsedBlock {
    var key: String
    var rawLines: [String]
}
