import Foundation

public actor AgentRunLogger {
    private let fileManager: FileManager
    private let writerRegistry: JSONLWriterRegistry

    public init(
        fileManager: FileManager = .default,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.writerRegistry = writerRegistry
    }

    public func append(_ run: AgentRun, in workspace: ResearchWorkspace) async throws {
        try await append(run, logURL: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"))
    }

    public func append(_ run: AgentRun, in root: ResearchRoot) async throws {
        try await append(run, logURL: root.fileURL(for: ".sci-station/agent/runs.jsonl"))
    }

    public func recentRuns(in workspace: ResearchWorkspace, limit: Int = 5) throws -> [AgentRun] {
        try recentRuns(logURL: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"), limit: limit)
    }

    public func recentRuns(in root: ResearchRoot, limit: Int = 5) throws -> [AgentRun] {
        try recentRuns(logURL: root.fileURL(for: ".sci-station/agent/runs.jsonl"), limit: limit)
    }

    public func recentRuns(in root: ResearchRoot, projectID: String?, limit: Int = 20) throws -> [AgentRun] {
        try recentRuns(in: root, limit: max(limit * 4, limit))
            .filter { $0.currentProjectID == projectID }
            .prefix(limit)
            .map { $0 }
    }

    private func append(_ run: AgentRun, logURL: URL) async throws {
        let writer = await writerRegistry.writer(for: logURL)
        try await writer.append(run, encoder: JSONLWriter.defaultEncoder())
    }

    private func recentRuns(logURL: URL, limit: Int) throws -> [AgentRun] {
        guard limit > 0, fileManager.fileExists(atPath: logURL.path) else {
            return []
        }

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let validRuns = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentRun? in
                try? decoder.decode(AgentRun.self, from: Data(line.utf8))
            }

        return Array(validRuns.suffix(limit).reversed())
    }
}

public actor AgentSessionEventLogger {
    public static let relativePath = ".sci-station/agent/session_events.jsonl"

    private let fileManager: FileManager
    private let writerRegistry: JSONLWriterRegistry

    public init(
        fileManager: FileManager = .default,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.writerRegistry = writerRegistry
    }

    public func append(_ event: AgentSessionEvent, in workspace: ResearchWorkspace) async throws {
        try await append(event, logURL: workspace.fileURL(for: Self.relativePath))
    }

    public func append(_ event: AgentSessionEvent, in root: ResearchRoot) async throws {
        try await append(event, logURL: root.fileURL(for: Self.relativePath))
    }

    public func events(in workspace: ResearchWorkspace, sessionID: String? = nil, limit: Int? = nil) throws -> [AgentSessionEvent] {
        try events(logURL: workspace.fileURL(for: Self.relativePath), sessionID: sessionID, limit: limit)
    }

    public func events(in root: ResearchRoot, sessionID: String? = nil, limit: Int? = nil) throws -> [AgentSessionEvent] {
        try events(logURL: root.fileURL(for: Self.relativePath), sessionID: sessionID, limit: limit)
    }

    private func append(_ event: AgentSessionEvent, logURL: URL) async throws {
        // Redact sensitive content before persisting. Session events may
        // contain workspace paths, paper titles, or wiki body previews that
        // should not leak into debug bundles.
        var redactedEvent = event
        if let payload = redactedEvent.payloadJSON,
           payload.count > 1024 {
            redactedEvent.payloadJSON = String(payload.prefix(1024)) + "\n[truncated by Sci-Station]"
        }
        if let payload = redactedEvent.payloadJSON {
            redactedEvent.payloadJSON = AgentRunDirectoryStore.redactSensitiveTextPublic(payload)
        }
        let writer = await writerRegistry.writer(for: logURL)
        try await writer.append(redactedEvent, encoder: JSONLWriter.defaultEncoder())
    }

    private func events(logURL: URL, sessionID: String?, limit: Int?) throws -> [AgentSessionEvent] {
        if let limit, limit <= 0 {
            return []
        }
        guard fileManager.fileExists(atPath: logURL.path) else {
            return []
        }

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let validEvents = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentSessionEvent? in
                try? decoder.decode(AgentSessionEvent.self, from: Data(line.utf8))
            }
            .filter { event in
                sessionID.map { event.sessionID == $0 } ?? true
            }

        guard let limit else {
            return validEvents
        }
        return Array(validEvents.suffix(limit))
    }
}

public nonisolated struct AppDebugEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var event: String
    public var workspaceID: String?
    public var projectID: String?
    public var threadID: String?
    public var runID: String?
    public var payload: JSONValue

    public init(
        id: String = "debug-event-\(UUID().uuidString.lowercased())",
        timestamp: Date = Date(),
        event: String,
        workspaceID: String? = nil,
        projectID: String? = nil,
        threadID: String? = nil,
        runID: String? = nil,
        payload: JSONValue = .object([:])
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        // Top-level identifier fields are written verbatim into
        // `app_events.jsonl`; several call sites pass `workspace.rootURL.path`,
        // so redact them through the same path-aware scrubber as the payload to
        // keep absolute user paths out of the debug log.
        self.workspaceID = workspaceID.map(AgentRunDirectoryStore.redactPathLikeTextPublic)
        self.projectID = projectID.map(AgentRunDirectoryStore.redactPathLikeTextPublic)
        self.threadID = threadID.map(AgentRunDirectoryStore.redactPathLikeTextPublic)
        self.runID = runID.map(AgentRunDirectoryStore.redactPathLikeTextPublic)
        self.payload = AgentRunDirectoryStore.redactedDebugPayload(payload)
    }
}

public actor AppDebugEventLogger {
    public static let relativePath = ".sci-station/debug/app_events.jsonl"

    private let fileManager: FileManager
    private let writerRegistry: JSONLWriterRegistry

    public init(
        fileManager: FileManager = .default,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.writerRegistry = writerRegistry
    }

    public func append(_ event: AppDebugEvent, in root: ResearchRoot) async throws {
        let logURL = root.fileURL(for: Self.relativePath)
        let writer = await writerRegistry.writer(for: logURL)
        try await writer.append(event, encoder: AgentRunDirectoryStore.encoder())
    }

    public func events(in root: ResearchRoot, limit: Int = 200) throws -> [AppDebugEvent] {
        guard limit > 0 else {
            return []
        }
        let logURL = root.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: logURL.path) else {
            return []
        }
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = AgentRunDirectoryStore.decoder()
        let events = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { try? decoder.decode(AppDebugEvent.self, from: Data($0.utf8)) }
        return Array(events.suffix(limit))
    }
}
