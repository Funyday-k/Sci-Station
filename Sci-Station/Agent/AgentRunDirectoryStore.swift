import Foundation

public nonisolated enum AgentRunState: String, Codable, Sendable {
    case created
    case running
    case waitingForApproval = "waiting_for_approval"
    case resuming
    case completed
    case failed
    case cancelled
}

public nonisolated enum AgentToolExecutionStatus: String, Codable, Sendable {
    case requested
    case completed
    case failed
    case skipped
}

public nonisolated struct AgentToolExecutionLedgerRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var schemaVersion: Int
    public var runID: String
    public var toolCallID: String
    public var approvalID: String
    public var fingerprint: String
    public var tool: String
    public var risk: AgentToolRisk
    public var targetPaths: [String]
    public var status: AgentToolExecutionStatus
    public var resultRef: String?
    public var createdAt: Date

    public nonisolated init(
        id: String = "tool-ledger-\(UUID().uuidString.lowercased())",
        schemaVersion: Int = 1,
        runID: String,
        toolCallID: String,
        approvalID: String,
        fingerprint: String,
        tool: String,
        risk: AgentToolRisk,
        targetPaths: [String],
        status: AgentToolExecutionStatus,
        resultRef: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.toolCallID = toolCallID
        self.approvalID = approvalID
        self.fingerprint = fingerprint
        self.tool = tool
        self.risk = risk
        self.targetPaths = targetPaths
        self.status = status
        self.resultRef = resultRef
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case toolCallID = "tool_call_id"
        case approvalID = "approval_id"
        case fingerprint
        case tool
        case risk
        case targetPaths = "target_paths"
        case status
        case resultRef = "result_ref"
        case createdAt = "created_at"
    }
}

public actor AgentRunDirectoryStore {
    public static let runsRelativePath = ".sci-station/agent/runs"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func runDirectoryURL(runID: String, in root: ResearchRoot) -> URL {
        root.directoryURL(for: Self.runsRelativePath + "/" + runID)
    }

    public func ensureRunDirectory(runID: String, in root: ResearchRoot) throws -> URL {
        let runDirectory = runDirectoryURL(runID: runID, in: root)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory.appendingPathComponent("tool_results", isDirectory: true), withIntermediateDirectories: true)
        return runDirectory
    }

    public func saveCheckpoint(_ pending: AgentPendingToolCall, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: pending.runID, in: root)
        let checkpointURL = runDirectory.appendingPathComponent("checkpoint.json", isDirectory: false)
        let encoder = Self.encoder()
        try encoder.encode(pending).write(to: checkpointURL, options: .atomic)
        try appendJSONLine(pending.approvalRequest, to: runDirectory.appendingPathComponent("approvals.jsonl", isDirectory: false), encoder: encoder)
    }

    public func pending(runID: String, in root: ResearchRoot) throws -> AgentPendingToolCall? {
        let checkpointURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("checkpoint.json", isDirectory: false)
        guard fileManager.fileExists(atPath: checkpointURL.path) else {
            return nil
        }
        return try Self.decoder().decode(AgentPendingToolCall.self, from: Data(contentsOf: checkpointURL))
    }

    public func pending(callID: String, in root: ResearchRoot) throws -> AgentPendingToolCall? {
        let runsDirectory = root.directoryURL(for: Self.runsRelativePath)
        guard let runIDs = try? fileManager.contentsOfDirectory(atPath: runsDirectory.path) else {
            return nil
        }
        for runID in runIDs.sorted().reversed() {
            if let pending = try pending(runID: runID, in: root), pending.toolCall.id == callID, !pending.isExpiredForRunDirectory {
                return pending
            }
        }
        return nil
    }

    public func appendEvent(_ envelope: AgentRuntimeEventEnvelope, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: envelope.runID, in: root)
        let eventsURL = runDirectory.appendingPathComponent("events.jsonl", isDirectory: false)
        if fileManager.fileExists(atPath: eventsURL.path), try eventEnvelopes(runID: envelope.runID, in: root).contains(where: { $0.id == envelope.id }) {
            return
        }
        try appendJSONLine(envelope, to: eventsURL, encoder: Self.encoder())
    }

    public func nextSequence(runID: String, in root: ResearchRoot) throws -> Int {
        let events = try eventEnvelopes(runID: runID, in: root)
        return (events.map(\.sequence).max() ?? 0) + 1
    }

    public func eventEnvelopes(runID: String, in root: ResearchRoot) throws -> [AgentRuntimeEventEnvelope] {
        let eventsURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("events.jsonl", isDirectory: false)
        guard fileManager.fileExists(atPath: eventsURL.path) else {
            return []
        }
        return try readJSONLines(AgentRuntimeEventEnvelope.self, from: eventsURL)
    }

    public func saveToolResult(_ result: AgentToolResultWireFormat, runID: String, in root: ResearchRoot) throws -> String {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let relativePath = "tool_results/\(result.toolCallID).json"
        let resultURL = runDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try Self.encoder().encode(result).write(to: resultURL, options: .atomic)
        return relativePath
    }

    public func toolResult(runID: String, resultRef: String, in root: ResearchRoot) throws -> AgentToolResultWireFormat? {
        let resultURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent(resultRef, isDirectory: false)
        guard fileManager.fileExists(atPath: resultURL.path) else {
            return nil
        }
        return try Self.decoder().decode(AgentToolResultWireFormat.self, from: Data(contentsOf: resultURL))
    }

    public func appendToolCallRecord(_ record: AgentToolExecutionLedgerRecord, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: record.runID, in: root)
        try appendJSONLine(record, to: runDirectory.appendingPathComponent("tool_calls.jsonl", isDirectory: false), encoder: Self.encoder())
    }

    public func toolCallRecords(runID: String, in root: ResearchRoot) throws -> [AgentToolExecutionLedgerRecord] {
        let recordsURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("tool_calls.jsonl", isDirectory: false)
        guard fileManager.fileExists(atPath: recordsURL.path) else {
            return []
        }
        return try readJSONLines(AgentToolExecutionLedgerRecord.self, from: recordsURL)
    }

    public func checkpointSummary(runID: String, in root: ResearchRoot) throws -> AgentCheckpointSummary? {
        guard let pending = try pending(runID: runID, in: root) else {
            return nil
        }
        return AgentCheckpointSummary(
            runID: pending.runID,
            state: .waitingForApproval,
            pendingApprovalID: pending.approvalRequest.id,
            pendingToolCallID: pending.toolCall.id,
            targetPaths: pending.approvalRequest.targetPaths,
            lastSequence: (try? eventEnvelopes(runID: runID, in: root).map(\.sequence).max()) ?? 0,
            updatedAt: pending.createdAt
        )
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = Self.decoder()
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
    }

    public nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public actor AgentToolExecutionLedger {
    private let runDirectoryStore: AgentRunDirectoryStore

    public init(runDirectoryStore: AgentRunDirectoryStore = AgentRunDirectoryStore()) {
        self.runDirectoryStore = runDirectoryStore
    }

    public func completedResult(
        runID: String,
        approvalID: String,
        toolCallID: String,
        fingerprint: String,
        in root: ResearchRoot
    ) async throws -> AgentToolResult? {
        let records = try await runDirectoryStore.toolCallRecords(runID: runID, in: root)
        guard let record = records.last(where: { record in
            record.approvalID == approvalID
                && record.toolCallID == toolCallID
                && record.fingerprint == fingerprint
                && record.status == .completed
        }), let resultRef = record.resultRef else {
            return nil
        }
        return try await runDirectoryStore.toolResult(runID: runID, resultRef: resultRef, in: root)?.agentToolResult()
    }

    public func record(
        result: AgentToolResult,
        runID: String,
        approvalID: String,
        fingerprint: String,
        risk: AgentToolRisk,
        targetPaths: [String],
        in root: ResearchRoot
    ) async throws {
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: result.callID)
        let resultRef = try await runDirectoryStore.saveToolResult(wireResult, runID: runID, in: root)
        let record = AgentToolExecutionLedgerRecord(
            runID: runID,
            toolCallID: result.callID,
            approvalID: approvalID,
            fingerprint: fingerprint,
            tool: result.toolName,
            risk: risk,
            targetPaths: targetPaths,
            status: result.succeeded ? .completed : .failed,
            resultRef: resultRef
        )
        try await runDirectoryStore.appendToolCallRecord(record, in: root)
    }
}

private extension AgentPendingToolCall {
    nonisolated var isExpiredForRunDirectory: Bool {
        expiresAt.map { $0 < Date() } ?? false
    }
}