import Foundation

/// Hand-written YAML encoder/decoder for `library/queue.yaml` and
/// `projects/<id>/queue.yaml`. We deliberately avoid third-party YAML libraries
/// (matching `TodoRepository` and `CalendarRepository`) so that the disk
/// schema stays auditable and round-trip stable. See `docs/development/Proposal48.md` §5.3.
public nonisolated enum ResearchQueueYAMLEncoder {
    public static let schemaVersion: Int = 1

    /// Result of decoding a queue file. Malformed entries are skipped rather
    /// than aborting; the count is surfaced so the caller can emit a debug
    /// warning (`queue.load.error` → `reason: yaml_parse_failure`) without
    /// destroying the file.
    public struct DecodeResult: Sendable {
        public var entries: [ResearchQueueEntry]
        public var skippedEntryCount: Int
        public var fileSchemaVersion: Int?

        public init(entries: [ResearchQueueEntry], skippedEntryCount: Int, fileSchemaVersion: Int?) {
            self.entries = entries
            self.skippedEntryCount = skippedEntryCount
            self.fileSchemaVersion = fileSchemaVersion
        }
    }

    public static func encode(
        entries: [ResearchQueueEntry],
        scope: QueueScope,
        generatedAt: Date
    ) -> String {
        let formatter = isoFormatter()
        var lines: [String] = []
        lines.append("schema_version: \(schemaVersion)")
        lines.append("scope: \(quoted(scope.identifier))")
        lines.append("generated_at: \(quoted(formatter.string(from: generatedAt)))")

        if entries.isEmpty {
            lines.append("entries: []")
            return lines.joined(separator: "\n") + "\n"
        }

        lines.append("entries:")
        let sortedEntries = entries.sorted { $0.order < $1.order }
        for entry in sortedEntries {
            lines.append(contentsOf: encodeEntry(entry, formatter: formatter))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func decode(contents: String) -> DecodeResult {
        let lines = contents.components(separatedBy: .newlines)
        var fileSchemaVersion: Int?
        var entries: [ResearchQueueEntry] = []
        var skipped = 0

        var cursor = 0
        var insideEntries = false

        while cursor < lines.count {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if !insideEntries {
                if trimmed.hasPrefix("schema_version:") {
                    let value = trimmed
                        .replacingOccurrences(of: "schema_version:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    fileSchemaVersion = Int(value)
                } else if trimmed == "entries: []" {
                    return DecodeResult(entries: [], skippedEntryCount: 0, fileSchemaVersion: fileSchemaVersion)
                } else if trimmed == "entries:" {
                    insideEntries = true
                }
                cursor += 1
                continue
            }

            if !trimmed.hasPrefix("- id:") {
                cursor += 1
                continue
            }

            let entryStart = cursor
            let entryEnd = endOfEntry(lines: lines, start: entryStart + 1)
            let block = Array(lines[entryStart..<entryEnd])
            if let entry = decodeEntry(block: block) {
                entries.append(entry)
            } else {
                skipped += 1
            }
            cursor = entryEnd
        }

        return DecodeResult(entries: entries, skippedEntryCount: skipped, fileSchemaVersion: fileSchemaVersion)
    }

    private static func encodeEntry(_ entry: ResearchQueueEntry, formatter: ISO8601DateFormatter) -> [String] {
        var lines: [String] = []
        lines.append("  - id: \(quoted(entry.id))")
        lines.append("    paper_id: \(quotedOrNull(entry.paperID))")
        lines.append("    external_key: \(quotedOrNull(entry.externalKey))")
        lines.append("    display_title: \(quoted(entry.displayTitle))")
        lines.append("    scope: \(quoted(entry.scope.identifier))")
        lines.append("    status: \(entry.status.rawValue)")
        lines.append("    source: \(entry.source.rawValue)")
        lines.append("    order: \(entry.order)")
        lines.append("    added_at: \(quoted(formatter.string(from: entry.addedAt)))")
        lines.append("    started_at: \(timestampOrNull(entry.startedAt, formatter: formatter))")
        lines.append("    finished_at: \(timestampOrNull(entry.finishedAt, formatter: formatter))")
        lines.append("    last_touched_at: \(quoted(formatter.string(from: entry.lastTouchedAt)))")
        lines.append("    note_summary: \(quotedOrNull(entry.noteSummary))")
        if entry.sourceRefs.isEmpty {
            lines.append("    source_refs: []")
        } else {
            lines.append("    source_refs:")
            for ref in entry.sourceRefs {
                lines.append("      - \(quoted(ref))")
            }
        }
        return lines
    }

    private static func decodeEntry(block: [String]) -> ResearchQueueEntry? {
        guard let firstLine = block.first else {
            return nil
        }

        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmedFirst.hasPrefix("- id:") else {
            return nil
        }

        var fields: [String: String] = [:]
        var sourceRefs: [String] = []
        var sourceRefsHandled = false

        let idLiteral = trimmedFirst.replacingOccurrences(of: "- id:", with: "").trimmingCharacters(in: .whitespaces)
        fields["id"] = unquoted(idLiteral)

        var cursor = 1
        while cursor < block.count {
            let line = block[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }

            if trimmed == "source_refs:" {
                let parsed = parseIndentedArray(lines: block, start: cursor + 1)
                sourceRefs = parsed.values
                sourceRefsHandled = true
                cursor = parsed.nextIndex
                continue
            }

            if trimmed == "source_refs: []" {
                sourceRefs = []
                sourceRefsHandled = true
                cursor += 1
                continue
            }

            if let separatorIndex = trimmed.firstIndex(of: ":") {
                let rawKey = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                fields[rawKey] = rawValue
            }
            cursor += 1
        }

        guard
            let id = fields["id"], !id.isEmpty,
            let displayTitle = fields["display_title"].map(unquoted), !displayTitle.isEmpty,
            let scopeRaw = fields["scope"].map(unquoted),
            let scope = QueueScope(identifier: scopeRaw),
            let statusRaw = fields["status"], let status = QueueStatus(rawValue: statusRaw),
            let sourceRaw = fields["source"], let source = QueueSource(rawValue: sourceRaw),
            let orderRaw = fields["order"], let order = Int(orderRaw),
            let addedAtRaw = fields["added_at"], let addedAt = parseTimestamp(addedAtRaw),
            let lastTouchedAtRaw = fields["last_touched_at"], let lastTouchedAt = parseTimestamp(lastTouchedAtRaw)
        else {
            return nil
        }

        let paperID = fields["paper_id"].flatMap(parseOptionalScalar)
        let externalKey = fields["external_key"].flatMap(parseOptionalScalar)
        let startedAt = fields["started_at"].flatMap(parseOptionalTimestamp)
        let finishedAt = fields["finished_at"].flatMap(parseOptionalTimestamp)
        let noteSummary = fields["note_summary"].flatMap(parseOptionalScalar)

        let resolvedSourceRefs = sourceRefsHandled ? sourceRefs : []

        return ResearchQueueEntry(
            id: id,
            paperID: paperID,
            externalKey: externalKey,
            displayTitle: displayTitle,
            scope: scope,
            status: status,
            source: source,
            order: order,
            addedAt: addedAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            lastTouchedAt: lastTouchedAt,
            noteSummary: noteSummary,
            sourceRefs: resolvedSourceRefs
        )
    }

    private static func endOfEntry(lines: [String], start: Int) -> Int {
        var cursor = start
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            // The next entry always starts with `- id:`; bare `- value` items
            // belong to the current entry (e.g. inside `source_refs:`).
            if trimmed.hasPrefix("- id:") {
                return cursor
            }
            // Top-level keys (no leading whitespace) end the entries section.
            if !trimmed.isEmpty {
                let leading = lines[cursor].prefix { $0 == " " }.count
                if leading == 0 {
                    return cursor
                }
            }
            cursor += 1
        }
        return cursor
    }

    private static func parseIndentedArray(lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start
        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if !trimmed.hasPrefix("-") {
                break
            }
            let valueLiteral = trimmed
                .replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex))
                .trimmingCharacters(in: .whitespaces)
            values.append(unquoted(valueLiteral))
            cursor += 1
        }
        return (values, cursor)
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func quotedOrNull(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "null"
        }
        return quoted(value)
    }

    private static func timestampOrNull(_ value: Date?, formatter: ISO8601DateFormatter) -> String {
        guard let value else {
            return "null"
        }
        return quoted(formatter.string(from: value))
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseOptionalScalar(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "null" || trimmed == "~" {
            return nil
        }
        let unwrapped = unquoted(trimmed)
        return unwrapped.isEmpty ? nil : unwrapped
    }

    private static func parseOptionalTimestamp(_ raw: String) -> Date? {
        guard let scalar = parseOptionalScalar(raw) else {
            return nil
        }
        return parseTimestamp(scalar)
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let unwrapped = unquoted(raw.trimmingCharacters(in: .whitespaces))
        guard !unwrapped.isEmpty else {
            return nil
        }
        let formatter = isoFormatter()
        if let value = formatter.date(from: unwrapped) {
            return value
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fallback.date(from: unwrapped)
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
