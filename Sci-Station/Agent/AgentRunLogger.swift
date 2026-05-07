import Foundation

public actor AgentRunLogger {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func append(_ run: AgentRun, in workspace: ResearchWorkspace) throws {
        try append(run, logURL: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"))
    }

    public func append(_ run: AgentRun, in root: ResearchRoot) throws {
        try append(run, logURL: root.fileURL(for: ".sci-station/agent/runs.jsonl"))
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

    private func append(_ run: AgentRun, logURL: URL) throws {
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(run)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func append(_ event: AgentSessionEvent, in workspace: ResearchWorkspace) throws {
        try append(event, logURL: workspace.fileURL(for: Self.relativePath))
    }

    public func append(_ event: AgentSessionEvent, in root: ResearchRoot) throws {
        try append(event, logURL: root.fileURL(for: Self.relativePath))
    }

    public func events(in workspace: ResearchWorkspace, sessionID: String? = nil, limit: Int = 200) throws -> [AgentSessionEvent] {
        try events(logURL: workspace.fileURL(for: Self.relativePath), sessionID: sessionID, limit: limit)
    }

    public func events(in root: ResearchRoot, sessionID: String? = nil, limit: Int = 200) throws -> [AgentSessionEvent] {
        try events(logURL: root.fileURL(for: Self.relativePath), sessionID: sessionID, limit: limit)
    }

    private func append(_ event: AgentSessionEvent, logURL: URL) throws {
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func events(logURL: URL, sessionID: String?, limit: Int) throws -> [AgentSessionEvent] {
        guard limit > 0, fileManager.fileExists(atPath: logURL.path) else {
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
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.threadID = threadID
        self.runID = runID
        self.payload = AgentRunDirectoryStore.redactedDebugPayload(payload)
    }
}

public actor AppDebugEventLogger {
    public static let relativePath = ".sci-station/debug/app_events.jsonl"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func append(_ event: AppDebugEvent, in root: ResearchRoot) throws {
        let logURL = root.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = AgentRunDirectoryStore.encoder()
        let data = try encoder.encode(event)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
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