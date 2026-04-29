import Foundation

public actor PaperRepository {
    private let fileManager: FileManager
    private let metadataCodec: PaperMetadataCodec
    private let projectPaperLinkRepository: ProjectPaperLinkRepository

    public init(
        fileManager: FileManager = .default,
        metadataCodec: PaperMetadataCodec? = nil,
        projectPaperLinkRepository: ProjectPaperLinkRepository? = nil
    ) {
        self.fileManager = fileManager
        self.metadataCodec = metadataCodec ?? PaperMetadataCodec()
        self.projectPaperLinkRepository = projectPaperLinkRepository ?? ProjectPaperLinkRepository(fileManager: fileManager)
    }

    public func loadPapers(in workspace: ResearchWorkspace) async throws -> [Paper] {
        let scannedPapers = try scanPapers(at: workspace.globalPapersURL, in: workspace)
            + scanPapers(at: workspace.rawPapersURL, in: workspace)
        let deduplicatedPapers = deduplicated(scannedPapers)
        let linkedPapers = try await applyingProjectLinks(to: deduplicatedPapers, in: workspace)

        return linkedPapers.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func scanPapers(at papersRootURL: URL, in workspace: ResearchWorkspace) throws -> [Paper] {
        guard fileManager.fileExists(atPath: papersRootURL.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: papersRootURL,
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
            if paper.folderPath == nil {
                paper.folderPath = paper.collectionPath
            }
            papers.append(paper)
        }

        return papers
    }

    public func save(_ paper: Paper, in workspace: ResearchWorkspace) async throws -> Paper {
        let directoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var updatedPaper = paper
        updatedPaper.updatedAt = Date()
        updatedPaper.collectionPath = Paper.collectionPath(for: updatedPaper.paperDirectoryRelativePath)
        if updatedPaper.folderPath == nil {
            updatedPaper.folderPath = updatedPaper.collectionPath
        }
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

        try await projectPaperLinkRepository.replaceLinks(for: updatedPaper, in: workspace)

        return updatedPaper
    }

    public func delete(_ paper: Paper, in workspace: ResearchWorkspace) async throws {
        let directoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath).standardizedFileURL
        let directoryPath = directoryURL.path
        let allowedRootPaths = [workspace.globalPapersURL, workspace.rawPapersURL]
            .map { $0.standardizedFileURL.path }

        guard allowedRootPaths.contains(where: { rootPath in
            directoryPath == rootPath || directoryPath.hasPrefix(rootPath + "/")
        }) else {
            throw CocoaError(.fileWriteNoPermission)
        }

        guard fileManager.fileExists(atPath: directoryPath) else {
            return
        }

        try fileManager.removeItem(at: directoryURL)
        try await projectPaperLinkRepository.removeLinks(forPaperID: paper.id, in: workspace)
    }

    public func appendBibliographyStub(for paper: Paper, in workspace: ResearchWorkspace) throws {
        let bibliographyURL = workspace.globalLibraryBibURL
        try fileManager.createDirectory(at: bibliographyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existingContents = (try? String(contentsOf: bibliographyURL, encoding: .utf8)) ?? ""
        guard !existingContents.contains("{\(paper.citekey),") else {
            return
        }

        let entry = "\n\(BibTeXFormatter.bibTeX(for: paper))"

        try (existingContents + entry).write(to: bibliographyURL, atomically: true, encoding: .utf8)
    }

    private func deduplicated(_ papers: [Paper]) -> [Paper] {
        var papersByID: [String: Paper] = [:]
        for paper in papers {
            guard let existingPaper = papersByID[paper.id] else {
                papersByID[paper.id] = paper
                continue
            }

            if shouldPrefer(paper, over: existingPaper) {
                papersByID[paper.id] = paper
            }
        }
        return Array(papersByID.values)
    }

    private func shouldPrefer(_ candidate: Paper, over existing: Paper) -> Bool {
        if candidate.isStoredInGlobalLibrary != existing.isStoredInGlobalLibrary {
            return candidate.isStoredInGlobalLibrary
        }
        return candidate.updatedAt > existing.updatedAt
    }

    private func applyingProjectLinks(to papers: [Paper], in workspace: ResearchWorkspace) async throws -> [Paper] {
        let links = try await projectPaperLinkRepository.load(in: workspace)
        guard !links.isEmpty else {
            return papers
        }

        let linksByPaperID = Dictionary(grouping: links, by: \.paperID)
        return papers.map { paper in
            guard let paperLinks = linksByPaperID[paper.id], !paperLinks.isEmpty else {
                return paper
            }

            var linkedPaper = paper
            linkedPaper.projectIDs = uniqueOrdered(paperLinks.map(\.projectID))
            linkedPaper.coreProjectIDs = uniqueOrdered(paperLinks.filter(\.isCore).map(\.projectID))
            linkedPaper.folderPath = paperLinks.compactMap(\.folderPath).first ?? linkedPaper.folderPath
            linkedPaper.useFor = uniqueOrdered(linkedPaper.useFor + paperLinks.flatMap(\.useFor))
            return linkedPaper
        }
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}