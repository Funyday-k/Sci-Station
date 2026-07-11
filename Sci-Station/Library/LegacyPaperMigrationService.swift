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

public nonisolated enum LegacyPaperMigrationExecutionStatus: String, Codable, Hashable, Sendable {
    case copied
    case skippedConflict = "skipped_conflict"
    case failed

    public nonisolated var label: String {
        switch self {
        case .copied:
            return "Copied"
        case .skippedConflict:
            return "Skipped conflict"
        case .failed:
            return "Failed"
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

public nonisolated struct LegacyPaperMigrationReportItem: Identifiable, Codable, Hashable, Sendable {
    public var paperID: String
    public var title: String
    public var sourceRelativePath: String
    public var targetRelativePath: String
    public var status: LegacyPaperMigrationExecutionStatus
    public var conflicts: [LegacyPaperMigrationConflict]
    public var errorMessage: String?

    public nonisolated var id: String {
        sourceRelativePath
    }

    public nonisolated init(
        paperID: String,
        title: String,
        sourceRelativePath: String,
        targetRelativePath: String,
        status: LegacyPaperMigrationExecutionStatus,
        conflicts: [LegacyPaperMigrationConflict] = [],
        errorMessage: String? = nil
    ) {
        self.paperID = paperID
        self.title = title
        self.sourceRelativePath = sourceRelativePath
        self.targetRelativePath = targetRelativePath
        self.status = status
        self.conflicts = conflicts
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case title
        case sourceRelativePath = "source_relative_path"
        case targetRelativePath = "target_relative_path"
        case status
        case conflicts
        case errorMessage = "error_message"
    }
}

public nonisolated struct LegacyPaperMigrationReport: Codable, Hashable, Sendable {
    public var id: String
    public var createdAt: Date
    public var mode: String
    public var reportRelativePath: String?
    public var items: [LegacyPaperMigrationReportItem]

    public nonisolated init(
        id: String,
        createdAt: Date = Date(),
        mode: String = "copy",
        reportRelativePath: String? = nil,
        items: [LegacyPaperMigrationReportItem] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.reportRelativePath = reportRelativePath
        self.items = items
    }

    public nonisolated var copiedCount: Int {
        items.filter { $0.status == .copied }.count
    }

    public nonisolated var skippedCount: Int {
        items.filter { $0.status == .skippedConflict }.count
    }

    public nonisolated var failedCount: Int {
        items.filter { $0.status == .failed }.count
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case mode
        case reportRelativePath = "report_relative_path"
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

        let items = try legacyPapers.map { paper in
            try makePlanItem(
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

    public func copyReadyItems(in workspace: ResearchWorkspace) throws -> LegacyPaperMigrationReport {
        let plan = try makePlan(in: workspace)
        let reportID = "legacy-paper-migration-\(timestampSlug(from: Date()))"
        var report = LegacyPaperMigrationReport(id: reportID)

        for item in plan.items {
            if item.hasConflicts {
                report.items.append(
                    LegacyPaperMigrationReportItem(
                        paperID: item.paperID,
                        title: item.title,
                        sourceRelativePath: item.sourceRelativePath,
                        targetRelativePath: item.targetRelativePath,
                        status: .skippedConflict,
                        conflicts: item.conflicts
                    )
                )
                continue
            }

            do {
                try copy(item, in: workspace)
                report.items.append(
                    LegacyPaperMigrationReportItem(
                        paperID: item.paperID,
                        title: item.title,
                        sourceRelativePath: item.sourceRelativePath,
                        targetRelativePath: item.targetRelativePath,
                        status: .copied
                    )
                )
            } catch {
                report.items.append(
                    LegacyPaperMigrationReportItem(
                        paperID: item.paperID,
                        title: item.title,
                        sourceRelativePath: item.sourceRelativePath,
                        targetRelativePath: item.targetRelativePath,
                        status: .failed,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }

        let reportRelativePath = ".sci-station/migrations/\(reportID).json"
        report.reportRelativePath = reportRelativePath
        try write(report, relativePath: reportRelativePath, in: workspace)
        return report
    }

    private func makePlanItem(
        for paper: Paper,
        workspace: ResearchWorkspace,
        globalPaperIDs: Set<Paper.ID>,
        legacyPaperIDCounts: [Paper.ID: Int]
    ) throws -> LegacyPaperMigrationItem {
        let targetRelativePath = try Paper.directoryRelativePath(
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

    private func copy(_ item: LegacyPaperMigrationItem, in workspace: ResearchWorkspace) throws {
        let sourceURL = workspace.directoryURL(for: item.sourceRelativePath)
        let targetURL = workspace.directoryURL(for: item.targetRelativePath)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }

        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        try normalizeCopiedMetadata(at: targetURL, relativePath: item.targetRelativePath, fallbackTitle: item.title)
    }

    private func normalizeCopiedMetadata(at targetURL: URL, relativePath: String, fallbackTitle: String) throws {
        let metadataURL = targetURL.appendingPathComponent("meta.yaml", isDirectory: false)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        let metadataContents = try String(contentsOf: metadataURL, encoding: .utf8)
        let attributes = try fileManager.attributesOfItem(atPath: metadataURL.path)
        var paper = metadataCodec.decode(
            metadataContents,
            directoryRelativePath: relativePath,
            fallbackTitle: fallbackTitle,
            createdAt: attributes[FileAttributeKey.creationDate] as? Date,
            updatedAt: attributes[FileAttributeKey.modificationDate] as? Date
        )
        paper.collectionPath = Paper.collectionPath(for: relativePath)
        paper.folderPath = paper.folderPath ?? paper.collectionPath
        paper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: paper.citekey,
            paperDirectoryRelativePath: relativePath
        )
        paper.annotationsRelativePath = paper.annotationsRelativePath ?? "annotations.md"
        try metadataCodec.encode(paper).write(to: metadataURL, atomically: true, encoding: .utf8)
    }

    private func write(_ report: LegacyPaperMigrationReport, relativePath: String, in workspace: ResearchWorkspace) throws {
        let reportURL = workspace.fileURL(for: relativePath)
        try fileManager.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
    }

    private func timestampSlug(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
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
