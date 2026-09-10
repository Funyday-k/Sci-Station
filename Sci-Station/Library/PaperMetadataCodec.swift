import Foundation

/// Standards-compliant reader and writer for
/// `library/papers/<id>/meta.yaml` documents.
///
/// Known paper fields are updated from the `Paper` value. Unknown fields and
/// nested extensions are retained semantically through the shared YAML value
/// model, including arrays of objects such as `references:`.
public struct PaperMetadataCodec {
    public nonisolated init() {}

    /// Compatibility wrapper for callers that cannot surface validation
    /// errors. Persistence and migration paths use `decodeThrowing`.
    public nonisolated func decode(
        _ contents: String,
        directoryRelativePath: String,
        fallbackTitle: String,
        createdAt: Date?,
        updatedAt: Date?
    ) -> Paper {
        (try? decodeThrowing(
            contents,
            directoryRelativePath: directoryRelativePath,
            fallbackTitle: fallbackTitle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )) ?? makePaper(
            from: [:],
            directoryRelativePath: directoryRelativePath,
            fallbackTitle: fallbackTitle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func decodeThrowing(
        _ contents: String,
        directoryRelativePath: String,
        fallbackTitle: String,
        createdAt: Date?,
        updatedAt: Date?
    ) throws -> Paper {
        let mapping = try StandardsYAMLDecoder.decodeMapping(contents)
        return makePaper(
            from: mapping,
            directoryRelativePath: directoryRelativePath,
            fallbackTitle: fallbackTitle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Compatibility helper. Persistence paths use
    /// `decodedGraphNodeIDThrowing(from:)` so malformed YAML cannot be
    /// overwritten silently.
    public nonisolated func decodedGraphNodeID(from contents: String) -> String? {
        try? decodedGraphNodeIDThrowing(from: contents)
    }

    public nonisolated func decodedGraphNodeIDThrowing(from contents: String) throws -> String? {
        let mapping = try StandardsYAMLDecoder.decodeMapping(contents)
        return optionalStringValue(for: "graph_node_id", in: mapping)
    }

    public nonisolated func encode(_ paper: Paper) -> String {
        // Encoding a freshly-created paper cannot fail with the in-memory
        // value model. Keep this API for existing call sites and tests.
        (try? encodeThrowing(paper)) ?? ""
    }

    public nonisolated func encode(_ paper: Paper, preserving existingContents: String?) -> String {
        (try? encodeThrowing(paper, preserving: existingContents))
            ?? (try? encodeThrowing(paper))
            ?? ""
    }

    public nonisolated func encodeThrowing(
        _ paper: Paper,
        preserving existingContents: String? = nil
    ) throws -> String {
        var mapping: [String: FrontmatterValue]
        if let existingContents {
            mapping = try StandardsYAMLDecoder.decodeMapping(existingContents)
        } else {
            mapping = [:]
        }

        setKnownPaperFields(on: &mapping, from: paper)
        return try StandardsYAMLEncoder.encodeMapping(
            mapping,
            preferredKeyOrder: Self.preferredTopLevelKeyOrder
        )
    }

    private nonisolated func makePaper(
        from mapping: [String: FrontmatterValue],
        directoryRelativePath: String,
        fallbackTitle: String,
        createdAt: Date?,
        updatedAt: Date?
    ) -> Paper {
        let notes = objectValue(for: "notes", in: mapping)
        let reading = objectValue(for: "reading", in: mapping)
        let parsedCreatedAt = reading["added"]?.stringValue.flatMap { makeDayFormatter().date(from: $0) }
        let effectiveCreatedAt = parsedCreatedAt ?? createdAt ?? updatedAt ?? Date()
        let effectiveUpdatedAt = updatedAt ?? effectiveCreatedAt

        return Paper(
            id: stringValue(for: "id", in: mapping)
                ?? directoryRelativePath.components(separatedBy: "/").last
                ?? fallbackTitle,
            citekey: stringValue(for: "citekey", in: mapping) ?? "unknownxxxxpaper",
            title: stringValue(for: "title", in: mapping) ?? fallbackTitle,
            authors: arrayValue(for: "authors", in: mapping),
            year: intValue(for: "year", in: mapping),
            venue: optionalStringValue(for: "venue", in: mapping),
            doi: optionalStringValue(for: "doi", in: mapping),
            arxiv: optionalStringValue(for: "arxiv", in: mapping),
            inspireID: optionalStringValue(for: "inspire_id", in: mapping),
            url: optionalStringValue(for: "url", in: mapping),
            pdfURL: optionalStringValue(for: "pdf_url", in: mapping),
            abstract: optionalStringValue(for: "abstract", in: mapping),
            categories: arrayValue(for: "categories", in: mapping),
            titleTranslation: optionalStringValue(for: "title_translation", in: mapping),
            itemType: optionalStringValue(for: "item_type", in: mapping),
            publicationTitle: optionalStringValue(for: "publication_title", in: mapping),
            publisher: optionalStringValue(for: "publisher", in: mapping),
            publicationPlace: optionalStringValue(for: "publication_place", in: mapping),
            publishedDate: optionalStringValue(for: "published_date", in: mapping),
            volume: optionalStringValue(for: "volume", in: mapping),
            issue: optionalStringValue(for: "issue", in: mapping),
            pages: optionalStringValue(for: "pages", in: mapping),
            series: optionalStringValue(for: "series", in: mapping),
            seriesTitle: optionalStringValue(for: "series_title", in: mapping),
            journalAbbreviation: optionalStringValue(for: "journal_abbreviation", in: mapping),
            issn: optionalStringValue(for: "issn", in: mapping),
            isbn: optionalStringValue(for: "isbn", in: mapping),
            pmid: optionalStringValue(for: "pmid", in: mapping),
            pmcid: optionalStringValue(for: "pmcid", in: mapping),
            language: optionalStringValue(for: "language", in: mapping),
            archive: optionalStringValue(for: "archive", in: mapping),
            archiveLocation: optionalStringValue(for: "archive_location", in: mapping),
            libraryCatalog: optionalStringValue(for: "library_catalog", in: mapping),
            callNumber: optionalStringValue(for: "call_number", in: mapping),
            shortTitle: optionalStringValue(for: "short_title", in: mapping),
            accessedAt: optionalStringValue(for: "accessed_at", in: mapping),
            bibtex: optionalStringValue(for: "bibtex", in: mapping),
            collectionPath: optionalStringValue(for: "collection_path", in: mapping),
            projectIDs: arrayValue(for: "project_ids", in: mapping),
            coreProjectIDs: arrayValue(for: "core_project_ids", in: mapping),
            folderPath: optionalStringValue(for: "folder_path", in: mapping)
                ?? optionalStringValue(for: "collection_path", in: mapping),
            pdfRelativePath: optionalStringValue(for: "pdf", in: mapping),
            tags: arrayValue(for: "tags", in: mapping),
            status: ReadingStatus(rawValue: stringValue(for: "status", in: mapping) ?? "") ?? .unread,
            priority: Priority(rawValue: stringValue(for: "priority", in: mapping) ?? "") ?? .medium,
            rating: intValue(for: "rating", in: mapping),
            useFor: arrayValue(for: "use_for", in: mapping),
            createdAt: effectiveCreatedAt,
            updatedAt: effectiveUpdatedAt,
            lastReadAt: reading["last_read_at"]?.stringValue.flatMap(parseTimestamp(_:)),
            lastReadPage: reading["last_page"]?.integerValue
                ?? reading["last_page"]?.stringValue.flatMap(Int.init),
            lastReadScale: reading["last_scale"]?.floatingPointValue
                ?? reading["last_scale"]?.stringValue.flatMap(Double.init),
            paperDirectoryRelativePath: directoryRelativePath,
            notesSummaryRelativePath: emptyToNil(notes["summary_file"]?.stringValue),
            annotationsRelativePath: "annotations.md",
            graphNodeID: optionalStringValue(for: "graph_node_id", in: mapping)
        )
    }

    private nonisolated func setKnownPaperFields(
        on mapping: inout [String: FrontmatterValue],
        from paper: Paper
    ) {
        mapping["id"] = .string(paper.id)
        mapping["citekey"] = .string(paper.citekey)
        mapping["graph_node_id"] = .string(paper.resolvedGraphNodeID)
        mapping["title"] = .string(paper.title)
        mapping["authors"] = stringArray(paper.authors)
        mapping["year"] = optionalInteger(paper.year)
        mapping["venue"] = optionalString(paper.venue)
        mapping["doi"] = optionalString(paper.doi)
        mapping["arxiv"] = optionalString(paper.arxiv)
        mapping["inspire_id"] = optionalString(paper.inspireID)
        mapping["url"] = optionalString(paper.url)
        mapping["pdf_url"] = optionalString(paper.pdfURL)
        mapping["pdf"] = optionalString(paper.pdfRelativePath)
        mapping["collection_path"] = optionalString(paper.collectionPath)
        mapping["folder_path"] = optionalString(paper.folderPath)
        mapping["categories"] = stringArray(paper.categories)
        mapping["abstract"] = optionalString(paper.abstract)
        mapping["title_translation"] = optionalString(paper.titleTranslation)
        mapping["item_type"] = optionalString(paper.itemType)
        mapping["publication_title"] = optionalString(paper.publicationTitle)
        mapping["publisher"] = optionalString(paper.publisher)
        mapping["publication_place"] = optionalString(paper.publicationPlace)
        mapping["published_date"] = optionalString(paper.publishedDate)
        mapping["volume"] = optionalString(paper.volume)
        mapping["issue"] = optionalString(paper.issue)
        mapping["pages"] = optionalString(paper.pages)
        mapping["series"] = optionalString(paper.series)
        mapping["series_title"] = optionalString(paper.seriesTitle)
        mapping["journal_abbreviation"] = optionalString(paper.journalAbbreviation)
        mapping["issn"] = optionalString(paper.issn)
        mapping["isbn"] = optionalString(paper.isbn)
        mapping["pmid"] = optionalString(paper.pmid)
        mapping["pmcid"] = optionalString(paper.pmcid)
        mapping["language"] = optionalString(paper.language)
        mapping["archive"] = optionalString(paper.archive)
        mapping["archive_location"] = optionalString(paper.archiveLocation)
        mapping["library_catalog"] = optionalString(paper.libraryCatalog)
        mapping["call_number"] = optionalString(paper.callNumber)
        mapping["short_title"] = optionalString(paper.shortTitle)
        mapping["accessed_at"] = optionalString(paper.accessedAt)
        mapping["bibtex"] = optionalString(paper.bibtex)
        mapping["tags"] = stringArray(paper.tags)
        mapping["project_ids"] = stringArray(paper.projectIDs)
        mapping["core_project_ids"] = stringArray(paper.coreProjectIDs)
        mapping["status"] = .string(paper.status.rawValue)
        mapping["priority"] = .string(paper.priority.rawValue)
        mapping["rating"] = optionalInteger(paper.rating)
        mapping["use_for"] = stringArray(paper.useFor)

        var reading = objectValue(for: "reading", in: mapping)
        reading["added"] = .string(makeDayFormatter().string(from: paper.createdAt))
        reading["last_page"] = optionalInteger(paper.lastReadPage)
        reading["last_scale"] = paper.lastReadScale.map(FrontmatterValue.floatingPoint) ?? .null
        reading["last_read_at"] = paper.lastReadAt.map { .string(timestampString(from: $0)) } ?? .null
        reading["first_read"] = reading["first_read"] ?? .null
        reading["deep_read"] = reading["deep_read"] ?? .null
        mapping["reading"] = .object(reading)

        var links = objectValue(for: "links", in: mapping)
        links["semantic_scholar"] = links["semantic_scholar"] ?? .null
        links["github"] = links["github"] ?? .null
        links["project_page"] = links["project_page"] ?? .null
        mapping["links"] = .object(links)

        var notes = objectValue(for: "notes", in: mapping)
        notes["summary_file"] = optionalString(paper.notesSummaryRelativePath)
        mapping["notes"] = .object(notes)
    }

    private static let preferredTopLevelKeyOrder = [
        "id", "citekey", "graph_node_id", "title", "authors", "year", "venue",
        "doi", "arxiv", "inspire_id", "url", "pdf_url", "pdf", "collection_path",
        "folder_path", "categories", "abstract", "title_translation", "item_type",
        "publication_title", "publisher", "publication_place", "published_date",
        "volume", "issue", "pages", "series", "series_title", "journal_abbreviation",
        "issn", "isbn", "pmid", "pmcid", "language", "archive", "archive_location",
        "library_catalog", "call_number", "short_title", "accessed_at", "bibtex",
        "tags", "project_ids", "core_project_ids", "status", "priority", "rating",
        "use_for", "reading", "links", "notes"
    ]

    private nonisolated func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private nonisolated func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private nonisolated func stringValue(
        for key: String,
        in mapping: [String: FrontmatterValue]
    ) -> String? {
        emptyToNil(mapping[key]?.stringValue)
    }

    private nonisolated func optionalStringValue(
        for key: String,
        in mapping: [String: FrontmatterValue]
    ) -> String? {
        emptyToNil(mapping[key]?.stringValue)
    }

    private nonisolated func intValue(
        for key: String,
        in mapping: [String: FrontmatterValue]
    ) -> Int? {
        mapping[key]?.integerValue ?? mapping[key]?.stringValue.flatMap(Int.init)
    }

    private nonisolated func arrayValue(
        for key: String,
        in mapping: [String: FrontmatterValue]
    ) -> [String] {
        mapping[key]?.arrayValue ?? []
    }

    private nonisolated func objectValue(
        for key: String,
        in mapping: [String: FrontmatterValue]
    ) -> [String: FrontmatterValue] {
        mapping[key]?.objectValue ?? [:]
    }

    private nonisolated func optionalString(_ value: String?) -> FrontmatterValue {
        emptyToNil(value).map(FrontmatterValue.string) ?? .null
    }

    private nonisolated func optionalInteger(_ value: Int?) -> FrontmatterValue {
        value.map(FrontmatterValue.integer) ?? .null
    }

    private nonisolated func stringArray(_ values: [String]) -> FrontmatterValue {
        .array(values.map(FrontmatterValue.string))
    }

    private nonisolated func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private nonisolated func timestampString(from date: Date) -> String {
        makeTimestampFormatter().string(from: date)
    }

    private nonisolated func parseTimestamp(_ value: String) -> Date? {
        makeTimestampFormatter().date(from: value) ?? makeDayFormatter().date(from: value)
    }
}
