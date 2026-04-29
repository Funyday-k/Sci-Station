import Foundation

public nonisolated enum LegacyPaperMigrationConflict: String, Codable, Hashable, Sendable {
    case targetDirectoryExists = "target_directory_exists"
    case duplicatePaperIDInGlobalLibrary = "duplicate_paper_id_in_global_library"
    case duplicatePaperIDInLegacyLibrary = "duplicate_paper_id_in_legacy_library"

    public nonisolated var label: String {
        switch self {
        case .targetDirectoryExists:
            return "Target exists"
        case .duplicatePaperIDInGlobalLibrary:
            return "Global duplicate"
        case .duplicatePaperIDInLegacyLibrary:
            return "Legacy duplicate"
        }
    }
}

public nonisolated enum LegacyPaperMigrationItemStatus: String, Codable, Hashable, Sendable {
    case readyToCopy = "ready_to_copy"
    case conflict

    public nonisolated var label: String {
        switch self {
        case .readyToCopy:
            return "Ready to copy"
        case .conflict:
            return "Conflict"
        }
    }
}

public nonisolated struct LegacyPaperMigrationItem: Identifiable, Codable, Hashable, Sendable {
    public var paperID: String
    public var title: String
    public var sourceRelativePath: String
    public var targetRelativePath: String
    public var status: LegacyPaperMigrationItemStatus
    public var conflicts: [LegacyPaperMigrationConflict]

    public nonisolated var id: String {
        sourceRelativePath
    }

    public nonisolated var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    public nonisolated init(
        paperID: String,
        title: String,
        sourceRelativePath: String,
        targetRelativePath: String,
        status: LegacyPaperMigrationItemStatus,
        conflicts: [LegacyPaperMigrationConflict]
    ) {
        self.paperID = paperID
        self.title = title
        self.sourceRelativePath = sourceRelativePath
        self.targetRelativePath = targetRelativePath
        self.status = status
        self.conflicts = conflicts
    }

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case title
        case sourceRelativePath = "source_relative_path"
        case targetRelativePath = "target_relative_path"
        case status
        case conflicts
    }
}

public nonisolated struct LegacyPaperMigrationPlan: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var items: [LegacyPaperMigrationItem]

    public nonisolated init(generatedAt: Date = Date(), items: [LegacyPaperMigrationItem] = []) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public nonisolated var legacyPaperCount: Int {
        items.count
    }

    public nonisolated var readyCount: Int {
        items.filter { $0.status == .readyToCopy }.count
    }

    public nonisolated var conflictCount: Int {
        items.filter(\.hasConflicts).count
    }

    public nonisolated var hasLegacyPapers: Bool {
        !items.isEmpty
    }

    public nonisolated static var empty: LegacyPaperMigrationPlan {
        LegacyPaperMigrationPlan()
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case items
    }
}

public actor LegacyPaperMigrationService {
    private let fileManager: FileManager
    private let metadataCodec: PaperMetadataCodec

    public init(
        fileManager: FileManager = .default,
        metadataCodec: PaperMetadataCodec = PaperMetadataCodec()
    ) {
        self.fileManager = fileManager
        self.metadataCodec = metadataCodec
    }

    public func makePlan(in workspace: ResearchWorkspace) throws -> LegacyPaperMigrationPlan {
        let legacyPapers = try scanPapers(at: workspace.rawPapersURL, in: workspace)
        let globalPapers = try scanPapers(at: workspace.globalPapersURL, in: workspace)
        let globalPaperIDs = Set(globalPapers.map(\.id))
        let legacyPaperIDCounts = Dictionary(grouping: legacyPapers, by: \.id).mapValues(\.count)

        let items = legacyPapers.map { paper in
            makePlanItem(
                for: paper,
                workspace: workspace,
                globalPaperIDs: globalPaperIDs,
                legacyPaperIDCounts: legacyPaperIDCounts
            )
        }
        .sorted { lhs, rhs in
            lhs.sourceRelativePath.localizedStandardCompare(rhs.sourceRelativePath) == .orderedAscending
        }

        return LegacyPaperMigrationPlan(items: items)
    }

    private func makePlanItem(
        for paper: Paper,
        workspace: ResearchWorkspace,
        globalPaperIDs: Set<Paper.ID>,
        legacyPaperIDCounts: [Paper.ID: Int]
    ) -> LegacyPaperMigrationItem {
        let targetRelativePath = Paper.directoryRelativePath(
            for: paper.id,
            collectionPath: paper.collectionPath
        )
        let targetURL = workspace.directoryURL(for: targetRelativePath)
        var conflicts: [LegacyPaperMigrationConflict] = []

        if fileManager.fileExists(atPath: targetURL.path) {
            conflicts.append(.targetDirectoryExists)
        }
        if globalPaperIDs.contains(paper.id) {
            conflicts.append(.duplicatePaperIDInGlobalLibrary)
        }
        if (legacyPaperIDCounts[paper.id] ?? 0) > 1 {
            conflicts.append(.duplicatePaperIDInLegacyLibrary)
        }

        return LegacyPaperMigrationItem(
            paperID: paper.id,
            title: paper.displayTitle,
            sourceRelativePath: paper.paperDirectoryRelativePath,
            targetRelativePath: targetRelativePath,
            status: conflicts.isEmpty ? .readyToCopy : .conflict,
            conflicts: conflicts
        )
    }

    private func scanPapers(at papersRootURL: URL, in workspace: ResearchWorkspace) throws -> [Paper] {
        guard fileManager.fileExists(atPath: papersRootURL.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: papersRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var papers: [Paper] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "meta.yaml" {
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

        return papers
    }
}