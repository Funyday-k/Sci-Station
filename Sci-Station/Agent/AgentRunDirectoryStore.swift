import Foundation
import CryptoKit

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
    public var provenance: AgentRunProvenance?

    public nonisolated init(
        schemaVersion: Int = 1,
        runID: String,
        events: [AgentRuntimeEventEnvelope],
        checkpoint: AgentCheckpointSummary? = nil,
        generatedAt: Date = Date(),
        debugPromptResponse: JSONValue? = nil,
        provenance: AgentRunProvenance? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.events = events
        self.checkpoint = checkpoint
        self.generatedAt = generatedAt
        self.debugPromptResponse = debugPromptResponse
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case events
        case checkpoint
        case generatedAt = "generated_at"
        case debugPromptResponse = "debug_prompt_response"
        case provenance
    }
}

public nonisolated struct AgentRunProvenance: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var requestedRuntime: String?
    public var effectiveRuntime: String?
    public var runtime: String?
    public var workflow: String?
    public var fallbackReason: String?
    public var evidenceProvenance: JSONValue?
    public var metadata: [String: String]

    public nonisolated init(
        schemaVersion: Int = 1,
        requestedRuntime: String? = nil,
        effectiveRuntime: String? = nil,
        runtime: String? = nil,
        workflow: String? = nil,
        fallbackReason: String? = nil,
        evidenceProvenance: JSONValue? = nil,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.requestedRuntime = requestedRuntime
        self.effectiveRuntime = effectiveRuntime
        self.runtime = runtime
        self.workflow = workflow
        self.fallbackReason = fallbackReason
        self.evidenceProvenance = evidenceProvenance
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestedRuntime = "requested_runtime"
        case effectiveRuntime = "effective_runtime"
        case runtime
        case workflow
        case fallbackReason = "fallback_reason"
        case evidenceProvenance = "evidence_provenance"
        case metadata
    }
}

public nonisolated struct AgentDebugBundleManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var runID: String
    public var includedFiles: [String]
    public var excludedPatterns: [String]
    public var redactionPolicy: String
    public var runMetadata: [String: String]
    public var provenance: AgentRunProvenance?
    public var privacyNotice: String
    public var generatedAt: Date

    public nonisolated init(
        schemaVersion: Int = 1,
        runID: String,
        includedFiles: [String],
        excludedPatterns: [String] = ["*.env", "*key*", "*token*", "Keychain", "private paths", ".sci-station/index/embeddings/**", "prompt/response plaintext"],
        redactionPolicy: String = "Default bundle includes only run metadata, events, checkpoints, critic reports, retrieval traces, and redacted replay data; embedding index files and prompt/response plaintext are excluded unless explicitly saved redacted.",
        runMetadata: [String: String] = [:],
        provenance: AgentRunProvenance? = nil,
        privacyNotice: String = "Debug bundle excludes API keys, private path inventories, environment files, Keychain content, embedding index files, and prompt/response plaintext.",
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.includedFiles = includedFiles
        self.excludedPatterns = excludedPatterns
        self.redactionPolicy = redactionPolicy
        self.runMetadata = runMetadata
        self.provenance = provenance
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
        case provenance
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

public nonisolated struct AgentRunPromptSnapshot: Codable, Hashable, Sendable {
    public var runID: String
    public var snapshots: [AgentPromptSnapshot]
    public var provenance: AgentRunProvenance?
    public var generatedAt: Date

    public nonisolated init(
        runID: String,
        snapshots: [AgentPromptSnapshot],
        provenance: AgentRunProvenance? = nil,
        generatedAt: Date = Date()
    ) {
        self.runID = runID
        self.snapshots = snapshots
        self.provenance = provenance
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case snapshots
        case provenance
        case generatedAt = "generated_at"
    }
}

public nonisolated struct AgentRunProviderSnapshot: Codable, Hashable, Sendable {
    public var provider: LLMProviderKind
    public var model: String
    public var baseURLString: String
    public var temperature: Double
    public var maxTokens: Int?

    public nonisolated init(configuration: LLMConfiguration) {
        self.provider = configuration.provider
        self.model = configuration.model
        self.baseURLString = configuration.baseURLString
        self.temperature = configuration.temperature
        self.maxTokens = configuration.maxTokens
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case model
        case baseURLString = "base_url"
        case temperature
        case maxTokens = "max_tokens"
    }
}

public nonisolated struct AgentRunPromptManifestSnapshot: Codable, Hashable, Sendable {
    public var snapshotRef: String
    public var surface: AgentPromptSurface?
    public var templateID: String?
    public var templateVersion: String?
    public var templateHash: String?

    public nonisolated init(
        snapshotRef: String = "prompt_snapshot.json",
        surface: AgentPromptSurface?,
        templateID: String?,
        templateVersion: String?,
        templateHash: String?
    ) {
        self.snapshotRef = snapshotRef
        self.surface = surface
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.templateHash = templateHash
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotRef = "snapshot_ref"
        case surface
        case templateID = "template_id"
        case templateVersion = "template_version"
        case templateHash = "template_hash"
    }
}

public nonisolated struct AgentRunSkillSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { skillID }
    public var skillID: String
    public var version: String?
    public var source: AgentSkillSource?
    public var trustLevel: AgentSkillTrustLevel?
    public var risk: AgentToolRisk?
    public var allowedTools: [String]
    public var selected: Bool
    public var blockedReason: String?

    public nonisolated init(
        skillID: String,
        version: String? = nil,
        source: AgentSkillSource? = nil,
        trustLevel: AgentSkillTrustLevel? = nil,
        risk: AgentToolRisk? = nil,
        allowedTools: [String] = [],
        selected: Bool = false,
        blockedReason: String? = nil
    ) {
        self.skillID = skillID
        self.version = version
        self.source = source
        self.trustLevel = trustLevel
        self.risk = risk
        self.allowedTools = allowedTools
        self.selected = selected
        self.blockedReason = blockedReason
    }

    private enum CodingKeys: String, CodingKey {
        case skillID = "skill_id"
        case version
        case source
        case trustLevel = "trust_level"
        case risk
        case allowedTools = "allowed_tools"
        case selected
        case blockedReason = "blocked_reason"
    }
}

public nonisolated struct AgentRunMCPToolSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { exposedName }
    public var exposedName: String
    public var serverID: String
    public var remoteToolName: String?
    public var approvalRequired: Bool
    public var permissionKey: String

    public nonisolated init(
        exposedName: String,
        serverID: String,
        remoteToolName: String? = nil,
        approvalRequired: Bool,
        permissionKey: String
    ) {
        self.exposedName = exposedName
        self.serverID = serverID
        self.remoteToolName = remoteToolName
        self.approvalRequired = approvalRequired
        self.permissionKey = permissionKey
    }

    private enum CodingKeys: String, CodingKey {
        case exposedName = "exposed_name"
        case serverID = "server_id"
        case remoteToolName = "remote_tool_name"
        case approvalRequired = "approval_required"
        case permissionKey = "permission_key"
    }
}

public nonisolated struct AgentRunMCPServerSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { serverID }
    public var serverID: String
    public var displayName: String
    public var source: AgentMCPServerSource
    public var transport: MCPServerTransport
    public var endpointSummary: String
    public var state: AgentMCPRuntimeState
    public var serverVersion: String?
    public var discoveredToolCount: Int
    public var errorMessage: String?
    public var lastSuccessAt: Date?
    public var lastErrorAt: Date?
    public var exitCode: Int?
    public var retryCount: Int
    public var freshness: String

    public nonisolated init(status: AgentMCPRuntimeStatus) {
        self.serverID = status.serverID
        self.displayName = status.displayName
        self.source = status.source
        self.transport = status.transport
        self.endpointSummary = status.endpointSummary
        self.state = status.state
        self.serverVersion = status.serverVersion
        self.discoveredToolCount = status.discoveredToolCount
        self.errorMessage = status.errorMessage
        self.lastSuccessAt = status.lastSuccessAt
        self.lastErrorAt = status.lastErrorAt
        self.exitCode = status.exitCode
        self.retryCount = status.retryCount
        self.freshness = status.freshness
    }

    private enum CodingKeys: String, CodingKey {
        case serverID = "server_id"
        case displayName = "display_name"
        case source
        case transport
        case endpointSummary = "endpoint_summary"
        case state
        case serverVersion = "server_version"
        case discoveredToolCount = "discovered_tool_count"
        case errorMessage = "error_message"
        case lastSuccessAt = "last_success_at"
        case lastErrorAt = "last_error_at"
        case exitCode = "exit_code"
        case retryCount = "retry_count"
        case freshness
    }
}

public nonisolated struct AgentRunFileRef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var sha256: String?
    public var lineCount: Int?
    public var lastSequence: Int?

    public nonisolated init(path: String, sha256: String? = nil, lineCount: Int? = nil, lastSequence: Int? = nil) {
        self.path = path
        self.sha256 = sha256
        self.lineCount = lineCount
        self.lastSequence = lastSequence
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case sha256
        case lineCount = "line_count"
        case lastSequence = "last_sequence"
    }
}

public nonisolated struct AgentRunEvidenceSummary: Codable, Hashable, Sendable {
    public var sourceTypes: [String]
    public var containsSyntheticEvidence: Bool
    public var evidenceProvenance: JSONValue?

    public nonisolated init(
        sourceTypes: [String] = [],
        containsSyntheticEvidence: Bool = false,
        evidenceProvenance: JSONValue? = nil
    ) {
        self.sourceTypes = sourceTypes
        self.containsSyntheticEvidence = containsSyntheticEvidence
        self.evidenceProvenance = evidenceProvenance
    }

    private enum CodingKeys: String, CodingKey {
        case sourceTypes = "source_types"
        case containsSyntheticEvidence = "contains_synthetic_evidence"
        case evidenceProvenance = "evidence_provenance"
    }
}

public nonisolated struct AgentRunApprovalSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { toolCallID }
    public var toolCallID: String
    public var toolName: String
    public var decision: String
    public var risk: AgentToolRisk
    public var targetPaths: [String]
    public var approvalRef: String?

    public nonisolated init(
        toolCallID: String,
        toolName: String,
        decision: String,
        risk: AgentToolRisk,
        targetPaths: [String] = [],
        approvalRef: String? = nil
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.decision = decision
        self.risk = risk
        self.targetPaths = targetPaths
        self.approvalRef = approvalRef
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case decision
        case risk
        case targetPaths = "target_paths"
        case approvalRef = "approval_ref"
    }
}

public nonisolated struct AgentRunManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var runID: String
    public var provider: AgentRunProviderSnapshot?
    public var runtime: AgentRunProvenance?
    public var prompt: AgentRunPromptManifestSnapshot
    public var skills: [AgentRunSkillSnapshot]
    public var mcpServers: [AgentRunMCPServerSnapshot]
    public var mcpTools: [AgentRunMCPToolSnapshot]
    public var enabledToolNames: [String]
    public var approvals: [AgentRunApprovalSnapshot]
    public var approvalRefs: [String]
    public var toolLedgerRef: String?
    public var evidence: AgentRunEvidenceSummary
    public var files: [AgentRunFileRef]
    public var generatedAt: Date

    public nonisolated init(
        schemaVersion: Int = 1,
        runID: String,
        provider: AgentRunProviderSnapshot? = nil,
        runtime: AgentRunProvenance? = nil,
        prompt: AgentRunPromptManifestSnapshot,
        skills: [AgentRunSkillSnapshot] = [],
        mcpServers: [AgentRunMCPServerSnapshot] = [],
        mcpTools: [AgentRunMCPToolSnapshot] = [],
        enabledToolNames: [String] = [],
        approvals: [AgentRunApprovalSnapshot] = [],
        approvalRefs: [String] = [],
        toolLedgerRef: String? = nil,
        evidence: AgentRunEvidenceSummary = AgentRunEvidenceSummary(),
        files: [AgentRunFileRef] = [],
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.provider = provider
        self.runtime = runtime
        self.prompt = prompt
        self.skills = skills
        self.mcpServers = mcpServers
        self.mcpTools = mcpTools
        self.enabledToolNames = enabledToolNames
        self.approvals = approvals
        self.approvalRefs = approvalRefs
        self.toolLedgerRef = toolLedgerRef
        self.evidence = evidence
        self.files = files
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case provider
        case runtime
        case prompt
        case skills
        case mcpServers = "mcp_servers"
        case mcpTools = "mcp_tools"
        case enabledToolNames = "enabled_tool_names"
        case approvals
        case approvalRefs = "approval_refs"
        case toolLedgerRef = "tool_ledger_ref"
        case evidence
        case files
        case generatedAt = "generated_at"
    }
}

public actor AgentRunDirectoryStore {
    public static let runsRelativePath = ".sci-station/agent/runs"

    private let fileManager: FileManager
    private let writerRegistry: JSONLWriterRegistry

    public init(
        fileManager: FileManager = .default,
        writerRegistry: JSONLWriterRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.writerRegistry = writerRegistry
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

    public func saveCheckpoint(_ pending: AgentPendingToolCall, in root: ResearchRoot) async throws {
        let runDirectory = try ensureRunDirectory(runID: pending.runID, in: root)
        let checkpointURL = runDirectory.appendingPathComponent("checkpoint.json", isDirectory: false)
        let encoder = Self.encoder()
        try encoder.encode(pending).write(to: checkpointURL, options: .atomic)
        try await appendJSONLine(
            pending.approvalRequest,
            to: runDirectory.appendingPathComponent("approvals.jsonl", isDirectory: false),
            encoder: encoder
        )
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

    public func appendEvent(_ envelope: AgentRuntimeEventEnvelope, in root: ResearchRoot) async throws {
        let runDirectory = try ensureRunDirectory(runID: envelope.runID, in: root)
        let eventsURL = runDirectory.appendingPathComponent("events.jsonl", isDirectory: false)
        // Use a shared JSONLWriter keyed by the file URL. This is both crash-safe
        // (each write is fsync'd) and dedup-aware (constant time) — the previous
        // implementation re-decoded every line in the file on each call, which
        // grew O(N²) over long runs.
        let writer = await writerRegistry.writer(
            for: eventsURL,
            idExtractor: { data in
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = object["id"] as? String else {
                    return nil
                }
                return id
            }
        )
        try await writer.append(envelope, encoder: Self.encoder(), id: envelope.id)
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

    public func appendToolCallRecord(_ record: AgentToolExecutionLedgerRecord, in root: ResearchRoot) async throws {
        let runDirectory = try ensureRunDirectory(runID: record.runID, in: root)
        try await appendJSONLine(
            record,
            to: runDirectory.appendingPathComponent("tool_calls.jsonl", isDirectory: false),
            encoder: Self.encoder()
        )
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

    public func savePromptSnapshot(_ snapshot: AgentRunPromptSnapshot, in root: ResearchRoot) throws {
        let runDirectory = try ensureRunDirectory(runID: snapshot.runID, in: root)
        try Self.encoder().encode(snapshot).write(to: runDirectory.appendingPathComponent("prompt_snapshot.json", isDirectory: false), options: .atomic)
    }

    public func promptSnapshot(runID: String, in root: ResearchRoot) throws -> AgentRunPromptSnapshot? {
        let snapshotURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("prompt_snapshot.json", isDirectory: false)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        return try Self.decoder().decode(AgentRunPromptSnapshot.self, from: Data(contentsOf: snapshotURL))
    }

    public func saveManifest(_ manifest: AgentRunManifest, in root: ResearchRoot) throws -> AgentRunManifest {
        let runDirectory = try ensureRunDirectory(runID: manifest.runID, in: root)
        let manifestWithRefs = manifestWithFileRefs(manifest, runDirectory: runDirectory)
        try Self.encoder().encode(manifestWithRefs).write(to: runDirectory.appendingPathComponent("manifest.json", isDirectory: false), options: .atomic)
        return manifestWithRefs
    }

    public func manifest(runID: String, in root: ResearchRoot) throws -> AgentRunManifest? {
        let manifestURL = runDirectoryURL(runID: runID, in: root).appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        return try Self.decoder().decode(AgentRunManifest.self, from: Data(contentsOf: manifestURL))
    }

    public func saveReplay(runID: String, in root: ResearchRoot, debugPromptResponse: JSONValue? = nil) throws -> AgentRunReplay {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let replay = AgentRunReplay(
            runID: runID,
            events: try eventEnvelopes(runID: runID, in: root),
            checkpoint: try checkpointSummary(runID: runID, in: root),
            debugPromptResponse: debugPromptResponse.map(Self.redactedDebugPayload),
            provenance: try runProvenance(runID: runID, in: root)
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
        let candidateFiles = [
            "manifest.json",
            "events.jsonl",
            "checkpoint.json",
            "approvals.jsonl",
            "tool_calls.jsonl",
            "replay.json",
            "critic_report.json",
            "retrieval_trace.json",
            "evidence.json",
            "prompt_snapshot.json"
        ]
        let included = candidateFiles.filter { fileManager.fileExists(atPath: runDirectory.appendingPathComponent($0, isDirectory: false).path) }
        let events = try? eventEnvelopes(runID: runID, in: root)
        let metadata: [String: String] = [
            "run_id": runID,
            "event_count": String(events?.count ?? 0),
            "last_sequence": String(events?.map(\.sequence).max() ?? 0)
        ]
        let provenance = try runProvenance(runID: runID, in: root)
        let provenanceMetadata: [String: String] = [
            "requested_runtime": provenance?.requestedRuntime ?? "",
            "effective_runtime": provenance?.effectiveRuntime ?? provenance?.runtime ?? "",
            "fallback_reason": provenance?.fallbackReason ?? ""
        ].filter { !$0.value.isEmpty }
        let manifest = AgentDebugBundleManifest(runID: runID, includedFiles: included, runMetadata: metadata.merging(provenanceMetadata) { current, _ in current }, provenance: provenance)
        try Self.encoder().encode(manifest).write(to: runDirectory.appendingPathComponent("debug_bundle_manifest.json", isDirectory: false), options: .atomic)
        return manifest
    }

    public func runProvenance(runID: String, in root: ResearchRoot) throws -> AgentRunProvenance? {
        let runDirectory = runDirectoryURL(runID: runID, in: root)
        if let provenance = try provenanceFromRetrievalTrace(at: runDirectory.appendingPathComponent("retrieval_trace.json", isDirectory: false)) {
            return provenance
        }
        let events = try eventEnvelopes(runID: runID, in: root)
        return provenanceFromEvents(events)
    }

    public func debugBundlePreview(runID: String, in root: ResearchRoot) throws -> AgentDebugBundlePreview {
        let runDirectory = try ensureRunDirectory(runID: runID, in: root)
        let candidateFiles = [
            "manifest.json",
            "events.jsonl",
            "checkpoint.json",
            "approvals.jsonl",
            "tool_calls.jsonl",
            "replay.json",
            "critic_report.json",
            "retrieval_trace.json",
            "evidence.json",
            "prompt_snapshot.json",
            "debug_bundle_manifest.json"
        ]
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

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) async throws {
        let writer = await writerRegistry.writer(for: url)
        try await writer.append(value, encoder: encoder)
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = Self.decoder()
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
    }

    private func manifestWithFileRefs(_ manifest: AgentRunManifest, runDirectory: URL) -> AgentRunManifest {
        var updated = manifest
        let candidates = [
            "events.jsonl",
            "checkpoint.json",
            "approvals.jsonl",
            "tool_calls.jsonl",
            "replay.json",
            "critic_report.json",
            "retrieval_trace.json",
            "evidence.json",
            "prompt_snapshot.json"
        ]
        var refs = manifest.files
        let existingPaths = Set(refs.map(\.path))
        for name in candidates where !existingPaths.contains(name) {
            let url = runDirectory.appendingPathComponent(name, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path),
                  let ref = fileRef(path: name, url: url) else {
                continue
            }
            refs.append(ref)
        }
        updated.files = refs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return updated
    }

    private func fileRef(path: String, url: URL) -> AgentRunFileRef? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let text = String(data: data, encoding: .utf8)
        let lineCount = text?.split(whereSeparator: \.isNewline).count
        let lastSequence = lastSequence(in: text)
        return AgentRunFileRef(
            path: path,
            sha256: Self.sha256(data),
            lineCount: lineCount,
            lastSequence: lastSequence
        )
    }

    private func lastSequence(in text: String?) -> Int? {
        guard let text else { return nil }
        let decoder = Self.decoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int? in
                (try? decoder.decode(AgentRuntimeEventEnvelope.self, from: Data(line.utf8)))?.sequence
            }
            .max()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func provenanceFromRetrievalTrace(at url: URL) throws -> AgentRunProvenance? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let value = try Self.decoder().decode(JSONValue.self, from: Data(contentsOf: url))
        guard case let .object(trace) = value else {
            return nil
        }
        if let provenanceValue = trace["provenance"],
           let provenance = try? decodeProvenance(from: provenanceValue) {
            return provenance
        }
        let fallbackMetadata = objectValue(trace["fallback_metadata"])
        let evidenceProvenance = trace["evidence_provenance"]
        return AgentRunProvenance(
            requestedRuntime: stringValue(trace["requested_runtime"]),
            effectiveRuntime: stringValue(trace["effective_runtime"]) ?? stringValue(fallbackMetadata?["effective_runtime"]),
            runtime: stringValue(trace["runtime"]),
            workflow: stringValue(trace["workflow"]),
            fallbackReason: stringValue(trace["fallback_reason"]) ?? stringValue(fallbackMetadata?["reason"]),
            evidenceProvenance: evidenceProvenance,
            metadata: stringMetadata(from: trace)
        )
    }

    private nonisolated func provenanceFromEvents(_ events: [AgentRuntimeEventEnvelope]) -> AgentRunProvenance? {
        for envelope in events {
            switch envelope.event {
            case let .runStarted(started):
                let metadata = started.metadata
                let requestedRuntime = metadata["requested_runtime"]?.stringValue ?? metadata["runtime_selector"]?.stringValue
                let effectiveRuntime = metadata["effective_runtime"]?.stringValue
                let runtime = metadata["runtime"]?.stringValue
                let fallbackReason = metadata["fallback_reason"]?.stringValue
                let evidenceProvenance = metadata["evidence_provenance"]
                if requestedRuntime != nil || effectiveRuntime != nil || runtime != nil || fallbackReason != nil || evidenceProvenance != nil {
                    return AgentRunProvenance(
                        requestedRuntime: requestedRuntime,
                        effectiveRuntime: effectiveRuntime,
                        runtime: runtime,
                        fallbackReason: fallbackReason,
                        evidenceProvenance: evidenceProvenance,
                        metadata: metadata.compactMapValues(\.stringValue)
                    )
                }
            default:
                continue
            }
        }
        return nil
    }

    private nonisolated func decodeProvenance(from value: JSONValue) throws -> AgentRunProvenance {
        let data = try Self.encoder().encode(value)
        return try Self.decoder().decode(AgentRunProvenance.self, from: data)
    }

    private nonisolated func objectValue(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case let .object(object) = value else {
            return nil
        }
        return object
    }

    private nonisolated func stringValue(_ value: JSONValue?) -> String? {
        value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private nonisolated func stringMetadata(from object: [String: JSONValue]) -> [String: String] {
        object.compactMapValues { value in
            switch value {
            case let .string(string):
                return string
            case let .number(number):
                return number
            case let .bool(bool):
                return bool ? "true" : "false"
            default:
                return nil
            }
        }
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
        return redactSensitiveTextInternal(homeRedacted.replacingOccurrences(of: pattern, with: "[PATH]", options: .regularExpression))
    }

    /// Public entry point for redacting sensitive text. Used by
    /// `AgentSessionEventLogger` to sanitise payloads before persisting.
    public nonisolated static func redactSensitiveTextPublic(_ text: String) -> String {
        redactSensitiveTextInternal(text)
    }

    /// Public path-aware redactor. Collapses the home directory to `~`, strips
    /// absolute paths, and removes secret-looking tokens. Used to sanitise the
    /// top-level identifier fields of `AppDebugEvent` so the user's absolute
    /// workspace path never reaches `app_events.jsonl`.
    public nonisolated static func redactPathLikeTextPublic(_ text: String) -> String {
        redactPathLikeText(text)
    }

    private nonisolated static func redactSensitiveTextInternal(_ text: String) -> String {
        var redacted = text.replacingOccurrences(of: #"sk-[A-Za-z0-9_\-]+"#, with: "[REDACTED]", options: .regularExpression)
        redacted = redacted.replacingOccurrences(of: #"(?i)(api[_-]?key|token|secret|password|bearer|authorization|cookie|session|jwt)\s*[:=]\s*[^\s,}\]]+"#, with: "$1=[REDACTED]", options: .regularExpression)
        redacted = redacted.replacingOccurrences(of: #"eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, with: "[REDACTED_JWT]", options: .regularExpression)
        redacted = redacted.replacingOccurrences(of: #"AIza[A-Za-z0-9_\-]{30,}"#, with: "[REDACTED_GCLOUD]", options: .regularExpression)
        redacted = redacted.replacingOccurrences(of: #"Bearer\s+[A-Za-z0-9_\-\.]+"#, with: "Bearer [REDACTED]", options: .regularExpression)
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
        return [
            "manifest.json",
            "events.jsonl",
            "checkpoint.json",
            "approvals.jsonl",
            "tool_calls.jsonl",
            "replay.json",
            "critic_report.json",
            "retrieval_trace.json",
            "evidence.json",
            "prompt_snapshot.json"
        ].contains(name)
    }

    private func redactedDebugFileData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }
        return Data(Self.redactSensitiveTextInternal(text).utf8)
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

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
