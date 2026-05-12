import Foundation

public struct BacklinkIndex: Sendable {
    private let backlinksByRelativePath: [String: [MarkdownDocumentReference]]

    public nonisolated init(documents: [MarkdownDocument]) {
        var documentsByPageKey: [String: [MarkdownDocument]] = [:]
        for document in documents {
            for pageKey in document.pageKeys {
                documentsByPageKey[pageKey, default: []].append(document)
            }
        }

        var backlinks: [String: [MarkdownDocumentReference]] = [:]
        for sourceDocument in documents {
            let reference = MarkdownDocumentReference(
                relativePath: sourceDocument.relativePath,
                title: sourceDocument.title
            )

            for link in sourceDocument.outgoingLinks {
                // Resolution strategy (most specific first):
                // 1. Fully-qualified namespace key (`concept/dark matter`)
                // 2. `wiki/<key>` default namespace
                // 3. Bare legacy key (`<key>`) — this is the backwards-compat
                //    path that keeps pre-namespace documents discoverable.
                var resolved: [MarkdownDocument] = []
                var seenPaths: Set<String> = []

                let orderedCandidates: [String]
                if link.namespace != nil {
                    orderedCandidates = [link.normalizedTarget, "wiki/" + link.legacyNormalizedTarget, link.legacyNormalizedTarget]
                } else {
                    orderedCandidates = [link.normalizedTarget, link.legacyNormalizedTarget]
                }

                for candidate in orderedCandidates {
                    guard let matches = documentsByPageKey[candidate] else { continue }
                    for match in matches where seenPaths.insert(match.relativePath).inserted {
                        resolved.append(match)
                    }
                }

                for targetDocument in resolved where targetDocument.relativePath != sourceDocument.relativePath {
                    if backlinks[targetDocument.relativePath, default: []].contains(where: { $0.relativePath == reference.relativePath }) {
                        continue
                    }

                    backlinks[targetDocument.relativePath, default: []].append(reference)
                }
            }
        }

        self.backlinksByRelativePath = backlinks.mapValues { references in
            references.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    public nonisolated func backlinks(for document: MarkdownDocument) -> [MarkdownDocumentReference] {
        backlinksByRelativePath[document.relativePath] ?? []
    }
}
