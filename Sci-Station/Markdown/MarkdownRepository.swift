import Foundation

public actor MarkdownRepository {
    private let fileManager: FileManager
    private let frontmatterParser: FrontmatterParser
    private let wikiLinkParser: WikiLinkParser

    public init(
        fileManager: FileManager = .default,
        frontmatterParser: FrontmatterParser = FrontmatterParser(),
        wikiLinkParser: WikiLinkParser = WikiLinkParser()
    ) {
        self.fileManager = fileManager
        self.frontmatterParser = frontmatterParser
        self.wikiLinkParser = wikiLinkParser
    }

    public func loadDocuments(in workspace: ResearchWorkspace) throws -> [MarkdownDocument] {
        let wikiRootURL = workspace.directoryURL(for: "wiki")
        guard fileManager.fileExists(atPath: wikiRootURL.path) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: wikiRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var documents: [MarkdownDocument] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else {
                continue
            }

            documents.append(try loadDocument(at: fileURL, in: workspace))
        }

        return documents.sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    public func saveContents(
        _ contents: String,
        relativePath: String,
        in workspace: ResearchWorkspace
    ) throws -> MarkdownDocument {
        let fileURL = workspace.fileURL(for: relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try loadDocument(at: fileURL, in: workspace)
    }

    private func loadDocument(at fileURL: URL, in workspace: ResearchWorkspace) throws -> MarkdownDocument {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let parsedDocument = frontmatterParser.parse(contents)
        let relativePath = workspace.relativePath(to: fileURL)
        let category = categoryName(from: relativePath)
        let title = resolvedTitle(
            frontmatter: parsedDocument.frontmatter,
            body: parsedDocument.body,
            fallback: fileURL.deletingPathExtension().lastPathComponent
        )
        let outgoingLinks = wikiLinkParser.parse(parsedDocument.body)
        let pageKeys = uniquePageKeys(for: fileURL, title: title)

        return MarkdownDocument(
            fileURL: fileURL,
            relativePath: relativePath,
            category: category,
            title: title,
            frontmatter: parsedDocument.frontmatter,
            body: parsedDocument.body,
            rawContents: contents,
            outgoingLinks: outgoingLinks,
            pageKeys: pageKeys
        )
    }

    private func categoryName(from relativePath: String) -> String {
        let components = relativePath.split(separator: "/")
        guard components.count >= 2 else {
            return "wiki"
        }

        return String(components[1])
    }

    private func resolvedTitle(
        frontmatter: [String: FrontmatterValue],
        body: String,
        fallback: String
    ) -> String {
        if let title = frontmatter["title"]?.stringValue,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        if let heading = body.components(separatedBy: .newlines).first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fallback
    }

    private func uniquePageKeys(for fileURL: URL, title: String) -> [String] {
        let candidates = [
            WikiLink.normalizePageKey(title),
            WikiLink.normalizePageKey(fileURL.deletingPathExtension().lastPathComponent)
        ]

        var pageKeys: [String] = []
        for candidate in candidates where !candidate.isEmpty && !pageKeys.contains(candidate) {
            pageKeys.append(candidate)
        }
        return pageKeys
    }
}