import Foundation

public enum CitationFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bibTeX = "BibTeX"
    case apa = "APA"
    case mla = "MLA"
    case chicago = "Chicago"
    case ieee = "IEEE"
    case ris = "RIS"

    public var id: String { rawValue }
}

public struct BibTeXFormatter {
    public nonisolated init() {}

    public nonisolated static func bibTeX(for paper: Paper) -> String {
        if let existingBibTeX = trimmedOrNil(paper.bibtex) {
            return existingBibTeX
        }

        let entryType = entryType(for: paper)
        var fields: [(String, String)] = []
        fields.append(("title", paper.title))

        if !paper.authors.isEmpty {
            fields.append(("author", paper.authors.joined(separator: " and ")))
        }
        if let year = paper.year {
            fields.append(("year", String(year)))
        }
        if let publicationTitle = trimmedOrNil(paper.publicationTitle ?? paper.venue) {
            fields.append((entryType == "inproceedings" ? "booktitle" : "journal", publicationTitle))
        }
        appendOptionalField("publisher", paper.publisher, to: &fields)
        appendOptionalField("volume", paper.volume, to: &fields)
        appendOptionalField("number", paper.issue, to: &fields)
        appendOptionalField("pages", paper.pages, to: &fields)
        appendOptionalField("doi", paper.doi, to: &fields)
        appendOptionalField("url", paper.url, to: &fields)

        if let arxiv = trimmedOrNil(paper.arxiv) {
            fields.append(("eprint", arxiv))
            fields.append(("archivePrefix", "arXiv"))
            if let primaryClass = paper.categories.first {
                fields.append(("primaryClass", primaryClass))
            }
        }

        let fieldLines = fields
            .map { "  \($0.0) = {\(escaped($0.1))}" }
            .joined(separator: ",\n")

        return "@\(entryType){\(paper.citekey),\n\(fieldLines)\n}\n"
    }

    public nonisolated static func citation(for paper: Paper, format: CitationFormat) -> String {
        switch format {
        case .bibTeX:
            return bibTeX(for: paper)
        case .apa:
            return apa(for: paper)
        case .mla:
            return mla(for: paper)
        case .chicago:
            return chicago(for: paper)
        case .ieee:
            return ieee(for: paper)
        case .ris:
            return ris(for: paper)
        }
    }

    private nonisolated static func apa(for paper: Paper) -> String {
        let authors = citationAuthors(for: paper, separator: ", ")
        let year = paper.year.map(String.init) ?? "n.d."
        let venue = trimmedOrNil(paper.publicationTitle ?? paper.venue)
        let suffix = citationLocator(for: paper)
        return [authors, "(\(year)).", "\(paper.displayTitle).", venue, suffix]
            .compactMap(trimmedOrNil)
            .joined(separator: " ")
    }

    private nonisolated static func mla(for paper: Paper) -> String {
        let authors = citationAuthors(for: paper, separator: ", ")
        let venue = trimmedOrNil(paper.publicationTitle ?? paper.venue)
        let year = paper.year.map(String.init)
        return [authors, "\"\(paper.displayTitle).\"", venue, year, citationLocator(for: paper)]
            .compactMap(trimmedOrNil)
            .joined(separator: " ")
    }

    private nonisolated static func chicago(for paper: Paper) -> String {
        let authors = citationAuthors(for: paper, separator: ", ")
        let year = paper.year.map(String.init)
        let venue = trimmedOrNil(paper.publicationTitle ?? paper.venue)
        return [authors, "\"\(paper.displayTitle).\"", venue, year, citationLocator(for: paper)]
            .compactMap(trimmedOrNil)
            .joined(separator: " ")
    }

    private nonisolated static func ieee(for paper: Paper) -> String {
        let authors = citationAuthors(for: paper, separator: ", ")
        let venue = trimmedOrNil(paper.publicationTitle ?? paper.venue)
        let year = paper.year.map(String.init)
        return [authors, "\"\(paper.displayTitle),\"", venue, year, citationLocator(for: paper)]
            .compactMap(trimmedOrNil)
            .joined(separator: " ")
    }

    private nonisolated static func ris(for paper: Paper) -> String {
        var lines: [String] = []
        lines.append("TY  - JOUR")
        lines.append("TI  - \(paper.displayTitle)")
        for author in paper.authors {
            lines.append("AU  - \(author)")
        }
        if let year = paper.year {
            lines.append("PY  - \(year)")
        }
        if let venue = trimmedOrNil(paper.publicationTitle ?? paper.venue) {
            lines.append("JO  - \(venue)")
        }
        if let doi = trimmedOrNil(paper.doi) {
            lines.append("DO  - \(doi)")
        }
        if let url = trimmedOrNil(paper.url ?? paper.pdfURL) {
            lines.append("UR  - \(url)")
        }
        if let abstract = trimmedOrNil(paper.abstract) {
            lines.append("AB  - \(abstract)")
        }
        lines.append("ER  -")
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated static func entryType(for paper: Paper) -> String {
        let itemType = paper.itemType?.lowercased() ?? ""
        if itemType.contains("book") {
            return "book"
        }
        if itemType.contains("proceedings") || itemType.contains("conference") {
            return "inproceedings"
        }
        if itemType.contains("thesis") {
            return "phdthesis"
        }
        if itemType.contains("article") || paper.publicationTitle != nil || paper.venue != nil {
            return "article"
        }
        return "misc"
    }

    private nonisolated static func appendOptionalField(_ key: String, _ value: String?, to fields: inout [(String, String)]) {
        guard let value = trimmedOrNil(value) else {
            return
        }

        fields.append((key, value))
    }

    private nonisolated static func citationAuthors(for paper: Paper, separator: String) -> String {
        if !paper.authors.isEmpty {
            return paper.authors.joined(separator: separator)
        }
        return paper.authorsDisplay
    }

    private nonisolated static func citationLocator(for paper: Paper) -> String? {
        if let doi = trimmedOrNil(paper.doi) {
            return "https://doi.org/\(doi)"
        }
        if let arxiv = trimmedOrNil(paper.arxiv) {
            return "https://arxiv.org/abs/\(arxiv)"
        }
        return trimmedOrNil(paper.url ?? paper.pdfURL)
    }

    private nonisolated static func escaped(_ value: String) -> String {
        // BibTeX special characters that must be escaped.
        // `{` / `}` are the field brace tokens themselves, so they have to be
        // preserved carefully — our encoded fields are `{value}`, and unescaped
        // braces inside `value` would close the field prematurely. We escape them
        // with the standard LaTeX `\{` / `\}` form.
        //
        // Order matters: we replace the backslash first so we do not double-
        // escape the replacements we add in subsequent steps.
        return value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "^", with: "\\^{}")
            .replacingOccurrences(of: "~", with: "\\~{}")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}