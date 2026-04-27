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

        return PaperMetadataDraft(
            title: firstString(in: metadata["titles"], key: "title") ?? "INSPIRE Import",
            authors: allStrings(in: metadata["authors"], key: "full_name"),
            year: firstInt(in: metadata["publication_info"], key: "year"),
            venue: "INSPIRE",
            doi: firstString(in: metadata["dois"], key: "value"),
            arxiv: arxivID,
            inspireID: recordID,
            url: "https://inspirehep.net/literature/\(recordID)",
            pdfURL: pdfURL,
            abstract: firstString(in: metadata["abstracts"], key: "value"),
            categories: allStrings(in: metadata["inspire_categories"], key: "term"),
            sourceProvider: "inspire"
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
}