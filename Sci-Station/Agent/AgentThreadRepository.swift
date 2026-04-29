import Foundation

public actor AgentThreadRepository {
    private let fileManager: FileManager
    private static let relativePath = ".sci-station/agent/threads.jsonl"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func upsert(_ thread: AgentThread, in root: ResearchRoot) throws {
        try upsert(thread, fileURL: root.fileURL(for: Self.relativePath))
    }

    public func threads(in root: ResearchRoot, projectID: String?, includeArchived: Bool = false) throws -> [AgentThread] {
        try threads(fileURL: root.fileURL(for: Self.relativePath))
            .filter { $0.projectID == projectID }
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func allThreads(in root: ResearchRoot, includeArchived: Bool = true) throws -> [AgentThread] {
        try threads(fileURL: root.fileURL(for: Self.relativePath))
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func thread(id: String, in root: ResearchRoot) throws -> AgentThread? {
        try threads(fileURL: root.fileURL(for: Self.relativePath))
            .first { $0.id == id }
    }

    private func upsert(_ thread: AgentThread, fileURL: URL) throws {
        var currentThreads = try threads(fileURL: fileURL)
        if let existingIndex = currentThreads.firstIndex(where: { $0.id == thread.id }) {
            currentThreads[existingIndex] = thread
        } else {
            currentThreads.append(thread)
        }

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try currentThreads.map { thread -> String in
            let data = try encoder.encode(thread)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }

        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
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
