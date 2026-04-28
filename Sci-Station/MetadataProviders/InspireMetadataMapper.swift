import Foundation

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