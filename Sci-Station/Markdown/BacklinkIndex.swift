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
                let targets = documentsByPageKey[link.normalizedTarget] ?? []
                for targetDocument in targets where targetDocument.relativePath != sourceDocument.relativePath {
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