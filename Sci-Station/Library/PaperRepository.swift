import Foundation

public actor PaperRepository {
    private let fileManager: FileManager
    private let metadataCodec: PaperMetadataCodec

    public init(
        fileManager: FileManager = .default,
        metadataCodec: PaperMetadataCodec? = nil
    ) {
        self.fileManager = fileManager
        self.metadataCodec = metadataCodec ?? PaperMetadataCodec()
    }

    public func loadPapers(in workspace: ResearchWorkspace) throws -> [Paper] {
        guard fileManager.fileExists(atPath: workspace.rawPapersURL.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: workspace.rawPapersURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return []
        }

        var papers: [Paper] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "meta.yaml" else {
                continue
            }

            let directoryURL = fileURL.deletingLastPathComponent()
            let metadataContents = try String(contentsOf: fileURL, encoding: .utf8)
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            var paper = metadataCodec.decode(
                metadataContents,
                directoryRelativePath: workspace.relativePath(to: directoryURL),
                fallbackTitle: directoryURL.lastPathComponent,
                createdAt: attributes[FileAttributeKey.creationDate] as? Date,
                updatedAt: attributes[FileAttributeKey.modificationDate] as? Date
            )
            paper.collectionPath = Paper.collectionPath(for: paper.paperDirectoryRelativePath)
            papers.append(paper)
        }

        return papers.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    public func save(_ paper: Paper, in workspace: ResearchWorkspace) throws -> Paper {
        let directoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var updatedPaper = paper
        updatedPaper.updatedAt = Date()
        updatedPaper.collectionPath = Paper.collectionPath(for: updatedPaper.paperDirectoryRelativePath)
        if updatedPaper.notesSummaryRelativePath == nil {
            updatedPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
                for: updatedPaper.citekey,
                paperDirectoryRelativePath: updatedPaper.paperDirectoryRelativePath
            )
        }

        let metadataURL = directoryURL.appendingPathComponent("meta.yaml", isDirectory: false)
        let metadataContents = metadataCodec.encode(updatedPaper)
        try metadataContents.write(to: metadataURL, atomically: true, encoding: .utf8)

        let annotationsRelativePath = updatedPaper.annotationsRelativePath ?? "annotations.md"
        let annotationsURL = workspace.resolve(relativePath: annotationsRelativePath, from: directoryURL, isDirectory: false)
        if !fileManager.fileExists(atPath: annotationsURL.path) {
            try "# Annotations\n\n".write(to: annotationsURL, atomically: true, encoding: .utf8)
        }

        return updatedPaper
    }

    public func delete(_ paper: Paper, in workspace: ResearchWorkspace) throws {
        let directoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath).standardizedFileURL
        let papersRootURL = workspace.rawPapersURL.standardizedFileURL
        let directoryPath = directoryURL.path
        let papersRootPath = papersRootURL.path

        guard directoryPath == papersRootPath || directoryPath.hasPrefix(papersRootPath + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }

        guard fileManager.fileExists(atPath: directoryPath) else {
            return
        }

        try fileManager.removeItem(at: directoryURL)
    }

    public func appendBibliographyStub(for paper: Paper, in workspace: ResearchWorkspace) throws {
        let bibliographyURL = workspace.libraryBibURL
        let existingContents = (try? String(contentsOf: bibliographyURL, encoding: .utf8)) ?? ""
        guard !existingContents.contains("{\(paper.citekey),") else {
            return
        }

        let entry = "\n\(BibTeXFormatter.bibTeX(for: paper))"

        try (existingContents + entry).write(to: bibliographyURL, atomically: true, encoding: .utf8)
    }
}