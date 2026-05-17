import Foundation

public nonisolated struct InspireCitationPaper: Codable, Hashable, Sendable, Identifiable {
    public var id: String { inspireID }
    public var inspireID: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var doi: String?
    public var arxiv: String?
    public var url: String?
    public var abstract: String?
    public var categories: [String]
    public var citationCount: Int?
    public var referenceCount: Int?

    public nonisolated init(
        inspireID: String,
        title: String,
        authors: [String],
        year: Int?,
        venue: String?,
        doi: String?,
        arxiv: String?,
        url: String?,
        abstract: String?,
        categories: [String],
        citationCount: Int?,
        referenceCount: Int?
    ) {
        self.inspireID = inspireID
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.doi = doi
        self.arxiv = arxiv
        self.url = url
        self.abstract = abstract
        self.categories = categories
        self.citationCount = citationCount
        self.referenceCount = referenceCount
    }

    public nonisolated var firstAuthorLastName: String? {
        guard let firstAuthor = authors.first else { return nil }
        if let comma = firstAuthor.firstIndex(of: ",") {
            return String(firstAuthor[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return firstAuthor.split(separator: " ").last.map(String.init)
    }
}

public nonisolated struct InspireCitationGraph: Hashable, Sendable {
    public var center: InspireCitationPaper?
    public var references: [InspireCitationPaper]
    public var citedBy: [InspireCitationPaper]

    public nonisolated init(center: InspireCitationPaper?, references: [InspireCitationPaper], citedBy: [InspireCitationPaper]) {
        self.center = center
        self.references = references
        self.citedBy = citedBy
    }
}

public struct InspireMetadataMapper {
    public nonisolated init() {}

    public nonisolated func map(data: Data, recordID: String) throws -> PaperMetadataDraft {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let arxivID = firstString(in: metadata["arxiv_eprints"], key: "value")
        let pdfURL = arxivID.map { "https://arxiv.org/pdf/\($0).pdf" }
            ?? firstString(in: metadata["documents"], key: "url")
        let publicationInfo = firstDictionary(in: metadata["publication_info"])
        let journalTitle = trimmedOrNil(publicationInfo?["journal_title"] as? String)
        let year = firstInt(in: metadata["publication_info"], key: "year")

        return PaperMetadataDraft(
            title: firstString(in: metadata["titles"], key: "title") ?? "INSPIRE Import",
            authors: allStrings(in: metadata["authors"], key: "full_name"),
            year: year,
            venue: journalTitle ?? "INSPIRE",
            doi: firstString(in: metadata["dois"], key: "value"),
            arxiv: arxivID,
            inspireID: recordID,
            url: "https://inspirehep.net/literature/\(recordID)",
            pdfURL: pdfURL,
            abstract: firstString(in: metadata["abstracts"], key: "value"),
            categories: allStrings(in: metadata["inspire_categories"], key: "term"),
            sourceProvider: "inspire",
            itemType: journalTitle == nil ? "preprint" : "journal-article",
            publicationTitle: journalTitle,
            publishedDate: year.map(String.init),
            volume: stringValue(publicationInfo?["journal_volume"]),
            pages: publicationPages(in: publicationInfo),
            archive: "INSPIRE",
            archiveLocation: recordID
        )
    }

    public nonisolated func mapCitationPaper(data: Data, fallbackRecordID: String) throws -> InspireCitationPaper {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try mapCitationPaper(root: root, fallbackRecordID: fallbackRecordID)
    }

    public nonisolated func mapCitationSearch(data: Data) throws -> [InspireCitationPaper] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [String: Any],
              let records = hits["hits"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return records.compactMap { record in
            let fallbackID = stringValue(record["id"])
                ?? stringValue((record["metadata"] as? [String: Any])?["control_number"])
                ?? "unknown"
            return try? mapCitationPaper(root: record, fallbackRecordID: fallbackID)
        }
    }

    public nonisolated func referenceRecordIDs(data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any],
              let references = metadata["references"] as? [[String: Any]] else {
            return []
        }

        var seen: Set<String> = []
        var ids: [String] = []
        for reference in references {
            guard let id = recordID(in: reference), !seen.contains(id) else { continue }
            seen.insert(id)
            ids.append(id)
        }
        return ids
    }

    nonisolated private func mapCitationPaper(root: [String: Any], fallbackRecordID: String) throws -> InspireCitationPaper {
        let metadata = root["metadata"] as? [String: Any] ?? root
        let publicationInfo = firstDictionary(in: metadata["publication_info"])
        let journalTitle = trimmedOrNil(publicationInfo?["journal_title"] as? String)
        let title = firstString(in: metadata["titles"], key: "title")
            ?? trimmedOrNil(root["title"] as? String)
            ?? "INSPIRE \(fallbackRecordID)"
        let recordID = stringValue(metadata["control_number"])
            ?? stringValue(root["id"])
            ?? fallbackRecordID

        return InspireCitationPaper(
            inspireID: recordID,
            title: title,
            authors: allStrings(in: metadata["authors"], key: "full_name"),
            year: firstInt(in: metadata["publication_info"], key: "year") ?? yearFromDateString(metadata["earliest_date"] as? String),
            venue: journalTitle ?? trimmedOrNil(publicationInfo?["pubinfo_freetext"] as? String),
            doi: firstString(in: metadata["dois"], key: "value"),
            arxiv: firstString(in: metadata["arxiv_eprints"], key: "value"),
            url: "https://inspirehep.net/literature/\(recordID)",
            abstract: firstString(in: metadata["abstracts"], key: "value"),
            categories: allStrings(in: metadata["inspire_categories"], key: "term"),
            citationCount: intValue(metadata["citation_count"]),
            referenceCount: intValue(metadata["reference_count"])
        )
    }

    nonisolated private func firstString(in value: Any?, key: String) -> String? {
        guard let array = value as? [[String: Any]],
              let first = array.first?[key] as? String else {
            return nil
        }

        return first
    }

    nonisolated private func allStrings(in value: Any?, key: String) -> [String] {
        guard let array = value as? [[String: Any]] else {
            return []
        }

        return array.compactMap { $0[key] as? String }
    }

    nonisolated private func firstInt(in value: Any?, key: String) -> Int? {
        guard let array = value as? [[String: Any]],
              let first = array.first?[key] as? Int else {
            return nil
        }

        return first
    }

    nonisolated private func firstDictionary(in value: Any?) -> [String: Any]? {
        guard let array = value as? [[String: Any]] else {
            return nil
        }

        return array.first
    }

    nonisolated private func recordID(in reference: [String: Any]) -> String? {
        if let value = stringValue(reference["recid"]) ?? stringValue(reference["control_number"]) {
            return value
        }

        if let record = reference["record"] as? [String: Any] {
            if let value = stringValue(record["control_number"]) ?? stringValue(record["recid"]) {
                return value
            }
            if let ref = record["$ref"] as? String {
                return recordID(fromReferenceURL: ref)
            }
        }

        if let record = reference["record"] as? String {
            return recordID(fromReferenceURL: record)
        }

        return nil
    }

    nonisolated private func recordID(fromReferenceURL value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.split(separator: "/").last?.prefix(while: { $0.isNumber }) ?? ""
        return digits.isEmpty ? nil : String(digits)
    }

    nonisolated private func publicationPages(in value: [String: Any]?) -> String? {
        if let articleID = trimmedOrNil(value?["artid"] as? String) {
            return articleID
        }

        let start = stringValue(value?["page_start"])
        let end = stringValue(value?["page_end"])
        return [start, end].compactMap { $0 }.joined(separator: "-").nilIfEmpty
    }

    nonisolated private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return trimmedOrNil(value)
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    nonisolated private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    nonisolated private func yearFromDateString(_ value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    nonisolated private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}