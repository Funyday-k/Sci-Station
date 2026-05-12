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

/// Reads the optional `references:` list-of-object field from a paper's
/// `meta.yaml` content. Each item may contain `doi`, `arxiv`, `title`,
/// `authors`, and `year`.
///
/// This reader works directly on the raw YAML text using the same lightweight
/// parser as `PaperMetadataCodec`. It does NOT require the field to be
/// declared in the `Paper` struct — the codec's unknown-field preservation
/// (Week 1 §1.2) keeps it alive across round-trips.
public enum MetaYamlReferenceReader {
    public nonisolated static func read(from yamlContents: String) -> [MetaYamlReference] {
        let lines = yamlContents.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("references:")
        }) else {
            return []
        }

        let parentIndent = indentation(of: lines[startIndex])
        var results: [MetaYamlReference] = []
        var cursor = startIndex + 1
        var currentRef: [String: String] = [:]

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineIndent = indentation(of: line)

            if trimmed.isEmpty {
                cursor += 1
                continue
            }

            // Stop if we've returned to the parent indent level or above.
            guard lineIndent > parentIndent else { break }

            if trimmed.hasPrefix("- ") {
                // New list item. Flush the previous one.
                if !currentRef.isEmpty {
                    results.append(makeReference(from: currentRef))
                }
                currentRef = [:]
                // Parse inline key: value on the same line as `-`.
                let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let (key, value) = splitKeyValue(afterDash) {
                    currentRef[key] = value
                }
            } else if let (key, value) = splitKeyValue(trimmed) {
                // Continuation key under the current list item.
                currentRef[key] = value
            }

            cursor += 1
        }

        // Flush last item.
        if !currentRef.isEmpty {
            results.append(makeReference(from: currentRef))
        }

        return results
    }

    private nonisolated static func makeReference(from fields: [String: String]) -> MetaYamlReference {
        MetaYamlReference(
            doi: fields["doi"]?.nilIfEmptyMeta,
            arxiv: (fields["arxiv"] ?? fields["arxiv_id"])?.nilIfEmptyMeta,
            title: fields["title"]?.nilIfEmptyMeta,
            authors: fields["authors"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            year: fields["year"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private nonisolated static func splitKeyValue(_ line: String) -> (String, String)? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        let unquoted = value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2
            ? String(value.dropFirst().dropLast())
            : value
        return (key, unquoted)
    }

    private nonisolated static func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }
}

private extension String {
    var nilIfEmptyMeta: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
