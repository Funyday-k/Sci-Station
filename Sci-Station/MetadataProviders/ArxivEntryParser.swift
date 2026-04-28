import Foundation

public struct ArxivEntryParser {
    public nonisolated init() {}

    public nonisolated func parse(_ xmlData: Data) throws -> PaperMetadataDraft {
        guard let xmlString = String(data: xmlData, encoding: .utf8),
              let entry = matchFirst("<entry>([\\s\\S]*?)</entry>", in: xmlString)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let title = matchFirst("<title>([\\s\\S]*?)</title>", in: entry)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "arXiv Import"
        let summary = matchFirst("<summary>([\\s\\S]*?)</summary>", in: entry)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let published = matchFirst("<published>([\\s\\S]*?)</published>", in: entry)
        let authors = matchAll("<author>[\\s\\S]*?<name>([\\s\\S]*?)</name>[\\s\\S]*?</author>", in: entry)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let categories = matchAllAttributeValues("<category[^>]*term=\"([^\"]+)\"", in: entry)
        let absURL = matchFirst("<id>([\\s\\S]*?)</id>", in: entry)
        let doi = matchFirst("<doi>([\\s\\S]*?)</doi>", in: entry)
        let arxivID = absURL?.split(separator: "/").last.map(String.init)
        let pdfURL = pdfLink(in: entry) ?? arxivID.map { "https://arxiv.org/pdf/\($0).pdf" }

        return PaperMetadataDraft(
            title: title,
            authors: authors,
            year: published.flatMap { Int($0.prefix(4)) },
            venue: "arXiv",
            doi: doi,
            arxiv: arxivID,
            inspireID: nil,
            url: absURL,
            pdfURL: pdfURL,
            abstract: summary,
            categories: categories,
            sourceProvider: "arxiv",
            itemType: "preprint",
            publicationTitle: "arXiv",
            publishedDate: published.map { String($0.prefix(10)) },
            archive: "arXiv",
            archiveLocation: arxivID
        )
    }

    nonisolated private func matchFirst(_ pattern: String, in input: String) -> String? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            .firstMatch(in: input, range: range),
            let matchRange = Range(match.range(at: 1), in: input) else {
            return nil
        }

        return String(input[matchRange])
    }

    nonisolated private func matchAll(_ pattern: String, in input: String) -> [String] {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .matches(in: input, range: range) ?? []

        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: input) else {
                return nil
            }

            return String(input[matchRange])
        }
    }

    nonisolated private func matchFirstAttribute(_ pattern: String, in input: String) -> String? {
        matchFirst(pattern, in: input)
    }

    nonisolated private func matchAllAttributeValues(_ pattern: String, in input: String) -> [String] {
        matchAll(pattern, in: input)
    }

    nonisolated private func pdfLink(in entry: String) -> String? {
        let linkTags = matchAll("(<link[^>]*>)", in: entry)

        for linkTag in linkTags {
            let lowercasedTag = linkTag.lowercased()
            guard lowercasedTag.contains("title=\"pdf\"") || lowercasedTag.contains("type=\"application/pdf\"") else {
                continue
            }

            if let href = matchFirst("href=\"([^\"]+)\"", in: linkTag) {
                return href
            }
        }

        return nil
    }
}