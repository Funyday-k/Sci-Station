import Foundation

public nonisolated struct AgentThreadMigrationResult: Hashable, Sendable {
    public var migratedCount: Int
    public var archivedLegacyFileURL: URL?

    public nonisolated init(migratedCount: Int, archivedLegacyFileURL: URL? = nil) {
        self.migratedCount = migratedCount
        self.archivedLegacyFileURL = archivedLegacyFileURL
    }
}

public actor AgentThreadRepository {
    private let fileManager: FileManager
    public nonisolated static let legacyRelativePath = ".sci-station/agent/threads.jsonl"
    public nonisolated static let legacyArchiveFileName = "threads.legacy.jsonl"
    public nonisolated static let globalFileName = "threads.jsonl"
    private let storeFileURL: URL

    public init(fileManager: FileManager = .default, storeDirectory: URL? = nil) {
        self.fileManager = fileManager
        let resolvedStoreDirectory = storeDirectory ?? Self.defaultStoreDirectory(fileManager: fileManager)
        self.storeFileURL = Self.threadsFileURL(in: resolvedStoreDirectory)
    }

    public nonisolated static func defaultStoreDirectory(fileManager: FileManager = .default) -> URL {
        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupportURL
                .appendingPathComponent("Sci-Station", isDirectory: true)
                .appendingPathComponent("agent", isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Sci-Station", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
    }

    public nonisolated static var defaultThreadsFileURL: URL {
        threadsFileURL(in: defaultStoreDirectory())
    }

    public nonisolated static func threadsFileURL(in storeDirectory: URL) -> URL {
        storeDirectory.appendingPathComponent(globalFileName, isDirectory: false)
    }

    public nonisolated static func workspaceID(for root: ResearchRoot) -> String {
        root.rootURL.standardizedFileURL.path
    }

    public func upsert(_ thread: AgentThread, in root: ResearchRoot) throws {
        _ = try migrateLegacyThreads(from: root)
        var taggedThread = thread
        taggedThread.assignWorkspace(id: Self.workspaceID(for: root), name: root.displayName)
        try upsert(taggedThread, fileURL: storeFileURL)
    }

    public func threads(in root: ResearchRoot, projectID: String?, workspaceID: String? = nil, includeArchived: Bool = false) throws -> [AgentThread] {
        _ = try migrateLegacyThreads(from: root)
        return try threads(fileURL: storeFileURL)
            .filter { $0.projectID == projectID }
            .filter { workspaceID == nil || $0.belongsToWorkspace(id: workspaceID) }
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func allThreads(in root: ResearchRoot, workspaceID: String? = nil, includeArchived: Bool = true) throws -> [AgentThread] {
        _ = try migrateLegacyThreads(from: root)
        return try threads(fileURL: storeFileURL)
            .filter { workspaceID == nil || $0.belongsToWorkspace(id: workspaceID) }
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func thread(id: String, in root: ResearchRoot) throws -> AgentThread? {
        _ = try migrateLegacyThreads(from: root)
        return try threads(fileURL: storeFileURL)
            .first { $0.id == id }
    }

    public func migrateLegacyThreads(from root: ResearchRoot) throws -> AgentThreadMigrationResult {
        let legacyURL = root.fileURL(for: Self.legacyRelativePath)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return AgentThreadMigrationResult(migratedCount: 0)
        }

        let workspaceID = Self.workspaceID(for: root)
        let workspaceName = root.displayName
        let legacyThreads = try threads(fileURL: legacyURL).map { thread -> AgentThread in
            var taggedThread = thread
            taggedThread.assignWorkspace(id: workspaceID, name: workspaceName)
            return taggedThread
        }

        if !legacyThreads.isEmpty {
            let mergedThreads = merge(legacyThreads, into: try threads(fileURL: storeFileURL))
            try write(sortedThreads(mergedThreads), fileURL: storeFileURL)
        }

        let archiveURL = try archiveLegacyFile(at: legacyURL)
        return AgentThreadMigrationResult(migratedCount: legacyThreads.count, archivedLegacyFileURL: archiveURL)
    }

    private func upsert(_ thread: AgentThread, fileURL: URL) throws {
        var currentThreads = try threads(fileURL: fileURL)
        if let existingIndex = currentThreads.firstIndex(where: { $0.id == thread.id }) {
            currentThreads[existingIndex] = thread
        } else {
            currentThreads.append(thread)
        }

        try write(sortedThreads(currentThreads), fileURL: fileURL)
    }

    private func merge(_ importedThreads: [AgentThread], into existingThreads: [AgentThread]) -> [AgentThread] {
        var mergedThreads = existingThreads
        for importedThread in importedThreads {
            if let existingIndex = mergedThreads.firstIndex(where: { $0.id == importedThread.id }) {
                var existingThread = mergedThreads[existingIndex]
                if importedThread.updatedAt >= existingThread.updatedAt {
                    mergedThreads[existingIndex] = importedThread
                } else {
                    existingThread.assignWorkspace(id: importedThread.workspaceID, name: importedThread.workspaceName)
                    mergedThreads[existingIndex] = existingThread
                }
            } else {
                mergedThreads.append(importedThread)
            }
        }
        return mergedThreads
    }

    private func sortedThreads(_ threads: [AgentThread]) -> [AgentThread] {
        threads.sorted { first, second in
            if first.updatedAt == second.updatedAt {
                return first.id < second.id
            }
            return first.updatedAt > second.updatedAt
        }
    }

    private func write(_ threads: [AgentThread], fileURL: URL) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try threads.map { thread -> String in
            let data = try encoder.encode(thread)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }

        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func threads(fileURL: URL) throws -> [AgentThread] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentThread? in
                try? decoder.decode(AgentThread.self, from: Data(line.utf8))
            }
    }

    private func archiveLegacyFile(at legacyURL: URL) throws -> URL {
        let archiveURL = legacyURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.legacyArchiveFileName, isDirectory: false)

        if fileManager.fileExists(atPath: archiveURL.path) {
            let existingContents = (try? String(contentsOf: archiveURL, encoding: .utf8)) ?? ""
            let legacyContents = (try? String(contentsOf: legacyURL, encoding: .utf8)) ?? ""
            let separator = existingContents.isEmpty || existingContents.hasSuffix("\n") ? "" : "\n"
            let trailingNewline = legacyContents.isEmpty || legacyContents.hasSuffix("\n") ? "" : "\n"
            try (existingContents + separator + legacyContents + trailingNewline).write(to: archiveURL, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: legacyURL)
        } else {
            try fileManager.moveItem(at: legacyURL, to: archiveURL)
        }

        return archiveURL
    }
}

public actor AgentPromptDraftRepository {
    private let fileManager: FileManager
    private static let relativePath = ".sci-station/agent/drafts.json"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func drafts(in root: ResearchRoot) throws -> [AgentPromptDraft] {
        try store(fileURL: root.fileURL(for: Self.relativePath)).drafts
    }

    public func draft(projectID: String?, threadID: String?, in root: ResearchRoot) throws -> String? {
        let key = AgentPromptDraft.key(projectID: projectID, threadID: threadID)
        return try drafts(in: root).first { $0.key == key }?.text
    }

    public func saveDraft(_ text: String, projectID: String?, threadID: String?, in root: ResearchRoot) throws {
        let fileURL = root.fileURL(for: Self.relativePath)
        let key = AgentPromptDraft.key(projectID: projectID, threadID: threadID)
        var currentDrafts = try drafts(in: root)
        let draft = AgentPromptDraft(projectID: projectID, threadID: threadID, text: text, updatedAt: Date())

        if let existingIndex = currentDrafts.firstIndex(where: { $0.key == key }) {
            currentDrafts[existingIndex] = draft
        } else {
            currentDrafts.append(draft)
        }

        try write(AgentPromptDraftStore(drafts: currentDrafts), fileURL: fileURL)
    }

    public func removeDraft(projectID: String?, threadID: String?, in root: ResearchRoot) throws {
        let fileURL = root.fileURL(for: Self.relativePath)
        let key = AgentPromptDraft.key(projectID: projectID, threadID: threadID)
        let currentDrafts = try drafts(in: root).filter { $0.key != key }

        try write(AgentPromptDraftStore(drafts: currentDrafts), fileURL: fileURL)
    }

    private func store(fileURL: URL) throws -> AgentPromptDraftStore {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AgentPromptDraftStore()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentPromptDraftStore.self, from: data)
    }

    private func write(_ store: AgentPromptDraftStore, fileURL: URL) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: .atomic)
    }
}
