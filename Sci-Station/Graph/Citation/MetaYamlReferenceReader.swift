import Foundation

/// A single reference entry from `meta.yaml`'s `references:` array.
public nonisolated struct MetaYamlReference: Hashable, Sendable {
    public var doi: String?
    public var arxiv: String?
    public var title: String?
    public var authors: [String]?
    public var year: Int?

    public nonisolated init(doi: String? = nil, arxiv: String? = nil, title: String? = nil, authors: [String]? = nil, year: Int? = nil) {
        self.doi = doi
        self.arxiv = arxiv
        self.title = title
        self.authors = authors
        self.year = year
    }
}

/// Reads the optional `references:` array from a paper's standards-compliant
/// `meta.yaml` document. Invalid YAML remains non-fatal for indexing callers;
/// validation and migration paths can use `readThrowing` for diagnostics.
public nonisolated enum MetaYamlReferenceReader {
    public static func read(from yamlContents: String) -> [MetaYamlReference] {
        (try? readThrowing(from: yamlContents)) ?? []
    }

    public static func readThrowing(from yamlContents: String) throws -> [MetaYamlReference] {
        let mapping = try StandardsYAMLDecoder.decodeMapping(yamlContents)
        guard let entries = mapping["references"]?.arrayElements else {
            return []
        }

        return entries.compactMap { entry in
            guard let fields = entry.objectValue else {
                return nil
            }
            return makeReference(from: fields)
        }
    }

    private static func makeReference(from fields: [String: FrontmatterValue]) -> MetaYamlReference {
        let authors: [String]? = {
            if let values = fields["authors"]?.arrayValue {
                return values.compactMap(\.nilIfEmptyMeta).nilIfEmptyMeta
            }
            return fields["authors"]?.stringValue?
                .split(separator: ",")
                .compactMap { String($0).nilIfEmptyMeta }
                .nilIfEmptyMeta
        }()

        return MetaYamlReference(
            doi: fields["doi"]?.stringValue?.nilIfEmptyMeta,
            arxiv: (fields["arxiv"] ?? fields["arxiv_id"])?.stringValue?.nilIfEmptyMeta,
            title: fields["title"]?.stringValue?.nilIfEmptyMeta,
            authors: authors,
            year: fields["year"]?.stringValue.flatMap(Int.init)
        )
    }
}

private extension String {
    var nilIfEmptyMeta: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    var nilIfEmptyMeta: Self? {
        isEmpty ? nil : self
    }
}
