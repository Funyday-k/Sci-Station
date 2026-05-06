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

public nonisolated struct AgentRunReplay: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var runID: String
    public var events: [AgentRuntimeEventEnvelope]
    public var checkpoint: AgentCheckpointSummary?
    public var generatedAt: Date
    public var debugPromptResponse: JSONValue?

    public nonisolated init(
        schemaVersion: Int = 1,
        runID: String,
        events: [AgentRuntimeEventEnvelope],
        checkpoint: AgentCheckpointSummary? = nil,
        generatedAt: Date = Date(),
        debugPromptResponse: JSONValue? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.events = events
        self.checkpoint = checkpoint
        self.generatedAt = generatedAt
        self.debugPromptResponse = debugPromptResponse
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case events
        case checkpoint
        case generatedAt = "generated_at"
        case debugPromptResponse = "debug_prompt_response"
    }
}

public nonisolated struct AgentDebugBundleManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var runID: String
    public var includedFiles: [String]
    public var excludedPatterns: [String]
    public var redactionPolicy: String
    public var runMetadata: [String: String]
    public var privacyNotice: String
    public var generatedAt: Date

    public nonisolated init(
        schemaVersion: Int = 1,
        runID: String,
        includedFiles: [String],
        excludedPatterns: [String] = ["*.env", "*key*", "*token*", "Keychain", "private paths", ".sci-station/index/embeddings/**", "prompt/response plaintext"],
        redactionPolicy: String = "Default bundle includes only run metadata, events, checkpoints, critic reports, retrieval traces, and redacted replay data; embedding index files and prompt/response plaintext are excluded unless explicitly saved redacted.",
        runMetadata: [String: String] = [:],
        privacyNotice: String = "Debug bundle excludes API keys, private path inventories, environment files, Keychain content, embedding index files, and prompt/response plaintext.",
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.includedFiles = includedFiles
        self.excludedPatterns = excludedPatterns
        self.redactionPolicy = redactionPolicy
        self.runMetadata = runMetadata
        self.privacyNotice = privacyNotice
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case includedFiles = "included_files"
        case excludedPatterns = "excluded_patterns"
        case redactionPolicy = "redaction_policy"
        case runMetadata = "run_metadata"
        case privacyNotice = "privacy_notice"
        case generatedAt = "generated_at"
    }
}

public nonisolated struct AgentDebugBundlePreview: Codable, Hashable, Sendable {
    public var runID: String
    public var includedFiles: [String]
    public var excludedPatterns: [String]
    public var privacyNotice: String

    public nonisolated init(
        runID: String,
        includedFiles: [String],
        excludedPatterns: [String],
        privacyNotice: String
    ) {
        self.runID = runID
        self.includedFiles = includedFiles
        self.excludedPatterns = excludedPatterns
        self.privacyNotice = privacyNotice
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

    public func saveCriticReport(_ report: JSONValue, runID: String, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        try Self.encoder().encode(report).write(to: runDirectory.appendingPathComponent("critic_report.json", isDirectory: false), options: .atomic)
    }

    public func saveRetrievalTrace(_ trace: JSONValue, runID: String, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        try Self.encoder().encode(trace).write(to: runDirectory.appendingPathComponent("retrieval_trace.json", isDirectory: false), options: .atomic)
    }

    public func saveReplay(runID: String, in root: ResearchRoot, debugPromptResponse: JSONValue? = nil) throws -> AgentRunReplay {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let replay = AgentRunReplay(
            runID: runID,
            events: try eventEnvelopes(runID: runID, in: root),
            checkpoint: try checkpointSummary(runID: runID, in: root),
            debugPromptResponse: debugPromptResponse.map(Self.redactedDebugPayload)
        )
        try Self.encoder().encode(replay).write(to: runDirectory.appendingPathComponent("replay.json", isDirectory: false), options: .atomic)
        return replay
    }

    public func runReplay(runID: String, in root: ResearchRoot) throws -> AgentRunReplay {
        let replayURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("replay.json", isDirectory: false)
        guard fileManager.fileExists(atPath: replayURL.path) else {
            return try saveReplay(runID: runID, in: root)
        }
        return try Self.decoder().decode(AgentRunReplay.self, from: Data(contentsOf: replayURL))
    }

    public func saveDebugBundleManifest(runID: String, in root: ResearchRoot) throws -> AgentDebugBundleManifest {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let candidateFiles = ["events.jsonl", "checkpoint.json", "replay.json", "critic_report.json", "retrieval_trace.json"]
        let included = candidateFiles.filter { fileManager.fileExists(atPath: runDirectory.appendingPathComponent($0, isDirectory: false).path) }
        let events = try? eventEnvelopes(runID: runID, in: root)
        let metadata: [String: String] = [
            "run_id": runID,
            "event_count": String(events?.count ?? 0),
            "last_sequence": String(events?.map(\.sequence).max() ?? 0)
        ]
        let manifest = AgentDebugBundleManifest(runID: runID, includedFiles: included, runMetadata: metadata)
        try Self.encoder().encode(manifest).write(to: runDirectory.appendingPathComponent("debug_bundle_manifest.json", isDirectory: false), options: .atomic)
        return manifest
    }

    public func debugBundlePreview(runID: String, in root: ResearchRoot) throws -> AgentDebugBundlePreview {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let candidateFiles = ["events.jsonl", "checkpoint.json", "replay.json", "critic_report.json", "retrieval_trace.json", "debug_bundle_manifest.json"]
        let included = candidateFiles.filter { fileManager.fileExists(atPath: runDirectory.appendingPathComponent($0, isDirectory: false).path) }
        return AgentDebugBundlePreview(
            runID: runID,
            includedFiles: included,
            excludedPatterns: AgentDebugBundleManifest(runID: runID, includedFiles: included).excludedPatterns,
            privacyNotice: AgentDebugBundleManifest(runID: runID, includedFiles: included).privacyNotice
        )
    }

    public func saveDebugBundle(runID: String, in root: ResearchRoot) throws -> URL {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let manifest = try saveDebugBundleManifest(runID: runID, in: root)
        var files: [(name: String, data: Data)] = []
        let manifestURL = runDirectory.appendingPathComponent("debug_bundle_manifest.json", isDirectory: false)
        files.append(("debug_bundle_manifest.json", try Data(contentsOf: manifestURL)))
        for name in manifest.includedFiles where isAllowedDebugBundleFile(name) {
            let url = runDirectory.appendingPathComponent(name, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let data = try redactedDebugFileData(at: url)
            files.append((name, data))
        }
        let bundleURL = runDirectory.appendingPathComponent("debug_bundle.zip", isDirectory: false)
        try SimpleZipWriter.write(files: files, to: bundleURL)
        return bundleURL
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

    public nonisolated static func redactedDebugPayload(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .object(object):
            var redacted: [String: JSONValue] = [:]
            for (key, item) in object {
                let lowered = key.lowercased()
                if lowered.contains("api") || lowered.contains("key") || lowered.contains("token") || lowered.contains("secret") || lowered.contains("password") {
                    redacted[key] = .string("[REDACTED]")
                } else {
                    redacted[key] = redactedDebugPayload(item)
                }
            }
            return .object(redacted)
        case let .array(array):
            return .array(array.map(redactedDebugPayload))
        case let .string(string):
            return .string(redactPathLikeText(string))
        default:
            return value
        }
    }

    private nonisolated static func redactPathLikeText(_ string: String) -> String {
        let homeRedacted = string.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let pattern = #"(?<![\w:])/(?:[^\s]+/)*[^\s]+"#
        return redactSensitiveText(homeRedacted.replacingOccurrences(of: pattern, with: "[PATH]", options: .regularExpression))
    }

    private nonisolated static func redactSensitiveText(_ text: String) -> String {
        var redacted = text.replacingOccurrences(of: #"sk-[A-Za-z0-9_\-]+"#, with: "[REDACTED]", options: .regularExpression)
        redacted = redacted.replacingOccurrences(of: #"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,}\]]+"#, with: "$1=[REDACTED]", options: .regularExpression)
        return redacted
    }

    private nonisolated func isAllowedDebugBundleFile(_ name: String) -> Bool {
        guard !name.contains(".."), !name.hasPrefix("/"), !name.contains("/") else {
            return false
        }
        let lowered = name.lowercased()
        if lowered.contains(".env") || lowered.contains("key") || lowered.contains("token") || lowered.contains("secret") {
            return false
        }
        return ["events.jsonl", "checkpoint.json", "replay.json", "critic_report.json", "retrieval_trace.json"].contains(name)
    }

    private func redactedDebugFileData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }
        return Data(Self.redactSensitiveText(text).utf8)
    }
}

private nonisolated enum SimpleZipWriter {
    struct Entry {
        var name: String
        var data: Data
        var crc32: UInt32
        var localHeaderOffset: UInt32
    }

    static func write(files: [(name: String, data: Data)], to url: URL) throws {
        var archive = Data()
        var entries: [Entry] = []
        for file in files {
            let nameData = Data(file.name.utf8)
            let offset = UInt32(archive.count)
            let crc = CRC32.checksum(file.data)
            appendUInt32(0x04034b50, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(crc, to: &archive)
            appendUInt32(UInt32(file.data.count), to: &archive)
            appendUInt32(UInt32(file.data.count), to: &archive)
            appendUInt16(UInt16(nameData.count), to: &archive)
            appendUInt16(0, to: &archive)
            archive.append(nameData)
            archive.append(file.data)
            entries.append(Entry(name: file.name, data: file.data, crc32: crc, localHeaderOffset: offset))
        }

        let centralDirectoryOffset = UInt32(archive.count)
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            appendUInt32(0x02014b50, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(entry.crc32, to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt16(UInt16(nameData.count), to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(0, to: &archive)
            appendUInt32(entry.localHeaderOffset, to: &archive)
            archive.append(nameData)
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        appendUInt32(0x06054b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt32(centralDirectorySize, to: &archive)
        appendUInt32(centralDirectoryOffset, to: &archive)
        appendUInt16(0, to: &archive)
        try archive.write(to: url, options: .atomic)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}

private nonisolated enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xedb88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
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