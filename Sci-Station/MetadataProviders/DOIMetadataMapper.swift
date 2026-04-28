import Foundation

public struct DOIMetadataMapper {
    public nonisolated init() {}

    public nonisolated func map(data: Data, doi: String) throws -> PaperMetadataDraft {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let resolvedDOI = trimmedOrNil(message["DOI"] as? String) ?? doi
        return PaperMetadataDraft(
            title: firstString(in: message["title"]) ?? resolvedDOI,
            authors: authorNames(in: message["author"]),
            year: publicationYear(in: message),
            venue: firstString(in: message["container-title"]),
            doi: resolvedDOI,
            arxiv: nil,
            inspireID: nil,
            url: normalizedURL(from: message["URL"] as? String, doi: resolvedDOI),
            pdfURL: nil,
            abstract: cleanedAbstract(from: message["abstract"] as? String),
            categories: stringArray(in: message["subject"]),
            sourceProvider: "doi"
        )
    }

    nonisolated private func firstString(in value: Any?) -> String? {
        if let array = value as? [String] {
            return array.compactMap(trimmedOrNil(_:)).first
        }

        return trimmedOrNil(value as? String)
    }

    nonisolated private func stringArray(in value: Any?) -> [String] {
        guard let array = value as? [String] else {
            return []
        }

        return array.compactMap(trimmedOrNil(_:))
    }

    nonisolated private func authorNames(in value: Any?) -> [String] {
        guard let authors = value as? [[String: Any]] else {
            return []
        }

        return authors.compactMap { author in
            let givenName = trimmedOrNil(author["given"] as? String)
            let familyName = trimmedOrNil(author["family"] as? String)
            let combinedName = [givenName, familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            if !combinedName.isEmpty {
                return combinedName
            }

            return trimmedOrNil(author["name"] as? String)
        }
    }

    nonisolated private func publicationYear(in message: [String: Any]) -> Int? {
        for key in ["published-print", "published-online", "issued", "created"] {
            guard let container = message[key] as? [String: Any],
                  let dateParts = container["date-parts"] as? [[Any]],
                  let firstYear = dateParts.first?.first as? NSNumber else {
                continue
            }

            return firstYear.intValue
        }

        return nil
    }

    nonisolated private func normalizedURL(from value: String?, doi: String) -> String {
        if let url = trimmedOrNil(value) {
            return url
                .replacingOccurrences(of: "http://dx.doi.org/", with: "https://doi.org/")
                .replacingOccurrences(of: "https://dx.doi.org/", with: "https://doi.org/")
        }

        return "https://doi.org/\(doi)"
    }

    nonisolated private func cleanedAbstract(from value: String?) -> String? {
        guard let abstract = trimmedOrNil(value) else {
            return nil
        }

        let withoutTags = abstract.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decodedEntities = withoutTags
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")

        return decodedEntities
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}