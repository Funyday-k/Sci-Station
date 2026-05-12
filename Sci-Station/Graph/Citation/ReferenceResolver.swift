import CryptoKit
import Foundation

// MARK: - Data Models

public nonisolated enum EvidenceSource: String, Codable, Sendable {
    case bibtex
    case paperMarkdown = "paper_md"
    case metaYaml = "meta_yaml"
}

public nonisolated struct CitationReference: Hashable, Sendable {
    public let sourcePaperID: String
    public let evidenceSource: EvidenceSource
    public let bibtexKey: String?
    public let rawText: String
    public let doi: String?
    public let arxivID: String?
    public let normalizedTitle: String?
    public let firstAuthorLastName: String?
    public let year: Int?

    public nonisolated init(
        sourcePaperID: String,
        evidenceSource: EvidenceSource,
        bibtexKey: String? = nil,
        rawText: String,
        doi: String? = nil,
        arxivID: String? = nil,
        normalizedTitle: String? = nil,
        firstAuthorLastName: String? = nil,
        year: Int? = nil
    ) {
        self.sourcePaperID = sourcePaperID
        self.evidenceSource = evidenceSource
        self.bibtexKey = bibtexKey
        self.rawText = rawText
        self.doi = doi
        self.arxivID = arxivID
        self.normalizedTitle = normalizedTitle
        self.firstAuthorLastName = firstAuthorLastName
        self.year = year
    }

    public nonisolated func computeHash() -> String {
        GraphIdentifier.sourceHash(from: [
            sourcePaperID, evidenceSource.rawValue,
            doi ?? "", arxivID ?? "", normalizedTitle ?? "",
            firstAuthorLastName ?? "", year.map(String.init) ?? ""
        ])
    }
}

public nonisolated enum ExternalSource: String, Sendable {
    case doi
    case arxiv
    case titleHash = "title_hash"
}

public nonisolated enum ResolutionOutcome: Hashable, Sendable {
    case matchedLocal(paperGraphNodeID: String)
    case matchedExternal(externalNodeID: String, source: ExternalSource)
    case unresolved(reason: String)
}

public nonisolated struct ResolvedReference: Hashable, Sendable {
    public let reference: CitationReference
    public let outcome: ResolutionOutcome

    public nonisolated init(reference: CitationReference, outcome: ResolutionOutcome) {
        self.reference = reference
        self.outcome = outcome
    }
}

// MARK: - Local Paper Index

public nonisolated struct LocalPaperIndexEntry: Hashable, Sendable {
    public let paperGraphNodeID: String
    public let firstAuthorLastName: String?
    public let year: Int?
}

/// In-memory index of local papers keyed by DOI, arXiv, and normalized title.
/// Built once per indexer run and used by `ReferenceResolver` for O(1) lookups.
public nonisolated struct LocalPaperIndex: Sendable {
    public let byDOI: [String: String]
    public let byArxiv: [String: String]
    public let byNormalizedTitle: [String: [LocalPaperIndexEntry]]

    public nonisolated init(papers: [Paper]) {
        var doiMap: [String: String] = [:]
        var arxivMap: [String: String] = [:]
        var titleMap: [String: [LocalPaperIndexEntry]] = [:]

        for paper in papers {
            let graphNodeID = paper.resolvedGraphNodeID
            if let doi = PaperIdentityGenerator.normalizedDOI(paper.doi) {
                doiMap[doi] = graphNodeID
            }
            if let arxiv = PaperIdentityGenerator.normalizedArxiv(paper.arxiv) {
                arxivMap[arxiv] = graphNodeID
            }
            let normalizedTitle = TitleNormalizer.normalize(paper.title)
            if !normalizedTitle.isEmpty {
                let entry = LocalPaperIndexEntry(
                    paperGraphNodeID: graphNodeID,
                    firstAuthorLastName: paper.authors.first.flatMap { author in
                        if let comma = author.firstIndex(of: ",") {
                            return String(author[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return author.split(separator: " ").last.map(String.init)
                    }?.lowercased(),
                    year: paper.year
                )
                titleMap[normalizedTitle, default: []].append(entry)
            }
        }

        self.byDOI = doiMap
        self.byArxiv = arxivMap
        self.byNormalizedTitle = titleMap
    }

    public nonisolated func fuzzyMatch(title: String, firstAuthor: String?) -> LocalPaperIndexEntry? {
        let normalizedAuthor = firstAuthor?.lowercased()

        // 1. Exact normalized title match.
        if let candidates = byNormalizedTitle[title] {
            if let normalizedAuthor,
               let exact = candidates.first(where: { $0.firstAuthorLastName == normalizedAuthor }) {
                return exact
            }
            return candidates.first
        }

        // 2. Levenshtein ≤ 2 (only for titles of similar length to avoid
        //    false positives on very short titles).
        guard title.count > 15 else { return nil }
        for (key, candidates) in byNormalizedTitle {
            guard abs(key.count - title.count) <= 3 else { continue }
            guard Levenshtein.distance(key, title) <= 2 else { continue }
            if let normalizedAuthor,
               let exact = candidates.first(where: { $0.firstAuthorLastName == normalizedAuthor }) {
                return exact
            }
            return candidates.first
        }

        return nil
    }
}

// MARK: - Resolver

/// Resolves citation references to local papers or external placeholders.
/// Priority: DOI → arXiv → title fuzzy match → external/unresolved.
public struct ReferenceResolver {
    public nonisolated init() {}

    public nonisolated func resolve(
        _ reference: CitationReference,
        localIndex: LocalPaperIndex
    ) -> ResolvedReference {
        // 1. DOI match.
        if let doi = reference.doi.flatMap(PaperIdentityGenerator.normalizedDOI) {
            if let localID = localIndex.byDOI[doi] {
                return ResolvedReference(reference: reference, outcome: .matchedLocal(paperGraphNodeID: localID))
            }
            return ResolvedReference(
                reference: reference,
                outcome: .matchedExternal(
                    externalNodeID: "paper:external:doi:\(doi)",
                    source: .doi
                )
            )
        }

        // 2. arXiv match.
        if let arxiv = reference.arxivID.flatMap(PaperIdentityGenerator.normalizedArxiv) {
            if let localID = localIndex.byArxiv[arxiv] {
                return ResolvedReference(reference: reference, outcome: .matchedLocal(paperGraphNodeID: localID))
            }
            return ResolvedReference(
                reference: reference,
                outcome: .matchedExternal(
                    externalNodeID: "paper:external:arxiv:\(arxiv)",
                    source: .arxiv
                )
            )
        }

        // 3. Title fuzzy match.
        if let title = reference.normalizedTitle, !title.isEmpty {
            if let match = localIndex.fuzzyMatch(title: title, firstAuthor: reference.firstAuthorLastName) {
                return ResolvedReference(reference: reference, outcome: .matchedLocal(paperGraphNodeID: match.paperGraphNodeID))
            }
            let hashInput = title + (reference.firstAuthorLastName?.lowercased() ?? "")
            let hash = SHA256.hash(data: Data(hashInput.utf8))
                .prefix(8)
                .map { String(format: "%02x", $0) }
                .joined()
            return ResolvedReference(
                reference: reference,
                outcome: .matchedExternal(
                    externalNodeID: "paper:external:title-hash:\(hash)",
                    source: .titleHash
                )
            )
        }

        // 4. Unresolved.
        return ResolvedReference(
            reference: reference,
            outcome: .unresolved(reason: "no_doi_arxiv_or_title")
        )
    }
}

// MARK: - Levenshtein

public enum Levenshtein {
    public nonisolated static func distance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
