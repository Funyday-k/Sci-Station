import Foundation

public nonisolated protocol ExternalAgentRuntime: Sendable {
    func startRun(_ request: AgentRuntimeRequest) async throws -> AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>
    func resumeRun(runID: String, decision: AgentHumanDecision) async throws
    func cancelRun(runID: String) async throws
    func loadCheckpoint(runID: String) async throws -> AgentCheckpointSummary?
}

public nonisolated struct AgentRuntimeRequest: Sendable {
    public var runID: String
    public var threadID: String?
    public var goal: String
    public var initialMessages: [LLMChatMessage]
    public var provider: any LLMChatProvider
    public var toolDefinitions: [AgentToolDefinition]
    public var toolRegistry: AgentToolRegistry
    public var toolHost: SciStationToolHost
    public var toolContext: AgentToolContext
    public var root: ResearchRoot
    public var configuration: LLMConfiguration
    public var apiKey: String
    public var options: AgentLoopOptions
    public var hookEngine: AgentHookEngine
    public var permissionEvaluator: AgentPermissionEvaluator
    public var enabledWorkflowIDs: Set<String>?
    public var responseDeltaHandler: (@Sendable (String) async -> Void)?

    public nonisolated init(
        runID: String = "agent-run-\(UUID().uuidString.lowercased())",
        threadID: String? = nil,
        goal: String,
        initialMessages: [LLMChatMessage],
        provider: any LLMChatProvider,
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost? = nil,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: AgentSafetyPreset.defaultHooks()),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
        enabledWorkflowIDs: Set<String>? = nil,
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) {
        self.runID = runID
        self.threadID = threadID
        self.goal = goal
        self.initialMessages = initialMessages
        self.provider = provider
        self.toolDefinitions = toolDefinitions
        self.toolRegistry = toolRegistry
        self.toolHost = toolHost ?? SciStationToolHost(legacyRegistry: toolRegistry)
        self.toolContext = toolContext
        self.root = root
        self.configuration = configuration
        self.apiKey = apiKey
        self.options = options
        self.hookEngine = hookEngine
        self.permissionEvaluator = permissionEvaluator
        self.enabledWorkflowIDs = enabledWorkflowIDs
        self.responseDeltaHandler = responseDeltaHandler
    }

    public nonisolated func asLoopRequest() -> AgentLoopRequest {
        AgentLoopRequest(
            runID: runID,
            goal: goal,
            initialMessages: initialMessages,
            provider: provider,
            toolDefinitions: toolDefinitions,
            toolRegistry: toolRegistry,
            toolHost: toolHost,
            toolContext: toolContext,
            root: root,
            configuration: configuration,
            apiKey: apiKey,
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: permissionEvaluator,
            responseDeltaHandler: responseDeltaHandler
        )
    }
}

public nonisolated struct AgentHumanDecision: Codable, Hashable, Sendable {
    public var action: AgentHumanDecisionAction
    public var feedback: String?
    public var editedArguments: AgentToolArguments?

    public nonisolated init(action: AgentHumanDecisionAction, feedback: String? = nil, editedArguments: AgentToolArguments? = nil) {
        self.action = action
        self.feedback = feedback
        self.editedArguments = editedArguments
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case feedback
        case editedArguments = "edited_arguments"
    }
}

public nonisolated enum AgentRuntimeErrorCode: String, Codable, Sendable {
    case invalidRequest
    case providerUnavailable
    case toolNotFound
    case toolSchemaInvalid
    case permissionDenied
    case approvalRequired
    case checkpointNotFound
    case sidecarUnavailable
    case sidecarCrashed
    case maxStepsExceeded
    case maxToolCallsExceeded
    case contextLimitExceeded
    case safetyPolicyBlocked
    case internalError
}

public nonisolated struct AgentRuntimeError: Codable, Hashable, Sendable {
    public var code: AgentRuntimeErrorCode
    public var message: String

    public nonisolated init(code: AgentRuntimeErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public nonisolated struct AgentCheckpointSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String { runID }
    public var runID: String
    public var state: AgentRunState
    public var pendingApprovalID: String?
    public var pendingToolCallID: String?
    public var targetPaths: [String]
    public var lastSequence: Int
    public var updatedAt: Date

    public nonisolated init(
        runID: String,
        state: AgentRunState,
        pendingApprovalID: String? = nil,
        pendingToolCallID: String? = nil,
        targetPaths: [String] = [],
        lastSequence: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.runID = runID
        self.state = state
        self.pendingApprovalID = pendingApprovalID
        self.pendingToolCallID = pendingToolCallID
        self.targetPaths = targetPaths
        self.lastSequence = lastSequence
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case state
        case pendingApprovalID = "pending_approval_id"
        case pendingToolCallID = "pending_tool_call_id"
        case targetPaths = "target_paths"
        case lastSequence = "last_sequence"
        case updatedAt = "updated_at"
    }
}

public nonisolated struct AgentRuntimeEventEnvelope: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var schemaVersion: Int
    public var runID: String
    public var threadID: String?
    public var sequence: Int
    public var timestamp: Date
    public var event: AgentRuntimeEvent

    public nonisolated init(
        id: String = "evt-\(UUID().uuidString.lowercased())",
        schemaVersion: Int = 1,
        runID: String,
        threadID: String? = nil,
        sequence: Int,
        timestamp: Date = Date(),
        event: AgentRuntimeEvent
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.threadID = threadID
        self.sequence = sequence
        self.timestamp = timestamp
        self.event = event
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case threadID = "thread_id"
        case sequence
        case timestamp
        case event
    }
}

public nonisolated struct AgentRunStarted: Codable, Hashable, Sendable {
    public var goal: String
    public nonisolated init(goal: String) { self.goal = goal }
}

public nonisolated struct AgentNodeStarted: Codable, Hashable, Sendable {
    public var name: String
    public nonisolated init(name: String) { self.name = name }
}

public nonisolated struct AgentAssistantDelta: Codable, Hashable, Sendable {
    public var text: String
    public nonisolated init(text: String) { self.text = text }
}

public nonisolated struct AgentAssistantMessage: Codable, Hashable, Sendable {
    public var content: String
    public nonisolated init(content: String) { self.content = content }
}

public nonisolated struct AgentToolCallRequested: Codable, Hashable, Sendable {
    public var tool: String
    public var toolCallID: String
    public var arguments: AgentToolArguments
    public var risk: AgentToolRisk
    public var targetPaths: [String]

    public nonisolated init(tool: String, toolCallID: String, arguments: AgentToolArguments, risk: AgentToolRisk, targetPaths: [String] = []) {
        self.tool = tool
        self.toolCallID = toolCallID
        self.arguments = arguments
        self.risk = risk
        self.targetPaths = targetPaths
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case toolCallID = "tool_call_id"
        case arguments
        case risk
        case targetPaths = "target_paths"
    }
}

public nonisolated struct AgentToolCallCompleted: Codable, Hashable, Sendable {
    public var tool: String
    public var toolCallID: String
    public var result: AgentToolResultWireFormat

    public nonisolated init(tool: String, toolCallID: String, result: AgentToolResultWireFormat) {
        self.tool = tool
        self.toolCallID = toolCallID
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case toolCallID = "tool_call_id"
        case result
    }
}

public nonisolated struct AgentArtifactDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var runID: String
    public var kind: String
    public var proposedPath: String?
    public var title: String
    public var content: String
    public var diffPreview: String?
    public var evidenceRefs: [AgentEvidenceRef]
    public var risk: AgentToolRisk

    public nonisolated init(
        id: String = "artifact-\(UUID().uuidString.lowercased())",
        runID: String,
        kind: String,
        proposedPath: String? = nil,
        title: String,
        content: String,
        diffPreview: String? = nil,
        evidenceRefs: [AgentEvidenceRef] = [],
        risk: AgentToolRisk = .readOnly
    ) {
        self.id = id
        self.runID = runID
        self.kind = kind
        self.proposedPath = proposedPath
        self.title = title
        self.content = content
        self.diffPreview = diffPreview
        self.evidenceRefs = evidenceRefs
        self.risk = risk
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case kind
        case proposedPath = "proposed_path"
        case title
        case content
        case diffPreview = "diff_preview"
        case evidenceRefs = "evidence_refs"
        case risk
    }
}

public nonisolated struct AgentCitationCriticReport: Codable, Hashable, Sendable {
    public var unsupportedClaims: [JSONValue]
    public var staleEvidence: [JSONValue]
    public var weakEvidence: [JSONValue]
    public var overclaims: [JSONValue]
    public var requiredRevisions: [String]
    public var canRequestApproval: Bool

    public nonisolated init(
        unsupportedClaims: [JSONValue] = [],
        staleEvidence: [JSONValue] = [],
        weakEvidence: [JSONValue] = [],
        overclaims: [JSONValue] = [],
        requiredRevisions: [String] = [],
        canRequestApproval: Bool = true
    ) {
        self.unsupportedClaims = unsupportedClaims
        self.staleEvidence = staleEvidence
        self.weakEvidence = weakEvidence
        self.overclaims = overclaims
        self.requiredRevisions = requiredRevisions
        self.canRequestApproval = canRequestApproval
    }

    public nonisolated var blocksFinalApproval: Bool {
        !canRequestApproval || !unsupportedClaims.isEmpty || !requiredRevisions.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case unsupportedClaims = "unsupported_claims"
        case staleEvidence = "stale_evidence"
        case weakEvidence = "weak_evidence"
        case overclaims
        case requiredRevisions = "required_revisions"
        case canRequestApproval = "can_request_approval"
    }
}

public nonisolated struct AgentEmbeddingRetrievalConfiguration: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var provider: String
    public var model: String
    public var modelVersion: String?
    public var dimension: Int
    public var store: String

    public nonisolated init(
        enabled: Bool = false,
        provider: String = "swift-proxy",
        model: String = "",
        modelVersion: String? = nil,
        dimension: Int = 0,
        store: String = "sqlite-vec"
    ) {
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.modelVersion = modelVersion
        self.dimension = dimension
        self.store = store
    }

    public nonisolated var modelID: String {
        model
    }

    public nonisolated var usesFTSFallback: Bool {
        !enabled
    }
}

public nonisolated struct AgentFinalResponse: Codable, Hashable, Sendable {
    public var markdown: String
    public nonisolated init(markdown: String) { self.markdown = markdown }
}

public nonisolated struct AgentRunCancelled: Codable, Hashable, Sendable {
    public var reason: String?
    public nonisolated init(reason: String? = nil) { self.reason = reason }
}

public nonisolated struct AgentRunFailed: Codable, Hashable, Sendable {
    public var error: AgentRuntimeError
    public nonisolated init(error: AgentRuntimeError) { self.error = error }
}

public nonisolated enum AgentRuntimeEvent: Codable, Hashable, Sendable {
    case runStarted(AgentRunStarted)
    case nodeStarted(AgentNodeStarted)
    case assistantDelta(AgentAssistantDelta)
    case assistantMessage(AgentAssistantMessage)
    case toolCallRequested(AgentToolCallRequested)
    case toolCallCompleted(AgentToolCallCompleted)
    case approvalRequired(AgentApprovalRequest)
    case artifactDraft(AgentArtifactDraft)
    case checkpointSaved(AgentCheckpointSummary)
    case finalResponse(AgentFinalResponse)
    case runCancelled(AgentRunCancelled)
    case runFailed(AgentRunFailed)
    case sidecarStarting
    case sidecarReady
    case sidecarUnavailable(AgentRuntimeError)
    case sidecarCrashed(AgentRuntimeError)
    case fallbackToLegacyRuntime(AgentRuntimeError)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "run_started": self = .runStarted(try container.decode(AgentRunStarted.self, forKey: .payload))
        case "node_started": self = .nodeStarted(try container.decode(AgentNodeStarted.self, forKey: .payload))
        case "assistant_delta": self = .assistantDelta(try container.decode(AgentAssistantDelta.self, forKey: .payload))
        case "assistant_message": self = .assistantMessage(try container.decode(AgentAssistantMessage.self, forKey: .payload))
        case "tool_call_requested": self = .toolCallRequested(try container.decode(AgentToolCallRequested.self, forKey: .payload))
        case "tool_call_completed": self = .toolCallCompleted(try container.decode(AgentToolCallCompleted.self, forKey: .payload))
        case "approval_required": self = .approvalRequired(try container.decode(AgentApprovalRequest.self, forKey: .payload))
        case "artifact_draft": self = .artifactDraft(try container.decode(AgentArtifactDraft.self, forKey: .payload))
        case "checkpoint_saved": self = .checkpointSaved(try container.decode(AgentCheckpointSummary.self, forKey: .payload))
        case "final_response": self = .finalResponse(try container.decode(AgentFinalResponse.self, forKey: .payload))
        case "run_cancelled": self = .runCancelled(try container.decode(AgentRunCancelled.self, forKey: .payload))
        case "run_failed": self = .runFailed(try container.decode(AgentRunFailed.self, forKey: .payload))
        case "sidecar_starting": self = .sidecarStarting
        case "sidecar_ready": self = .sidecarReady
        case "sidecar_unavailable": self = .sidecarUnavailable(try container.decode(AgentRuntimeError.self, forKey: .payload))
        case "sidecar_crashed": self = .sidecarCrashed(try container.decode(AgentRuntimeError.self, forKey: .payload))
        case "fallback_to_legacy_runtime": self = .fallbackToLegacyRuntime(try container.decode(AgentRuntimeError.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported runtime event type: \(type)")
        }
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .runStarted(payload): try encode("run_started", payload, into: &container)
        case let .nodeStarted(payload): try encode("node_started", payload, into: &container)
        case let .assistantDelta(payload): try encode("assistant_delta", payload, into: &container)
        case let .assistantMessage(payload): try encode("assistant_message", payload, into: &container)
        case let .toolCallRequested(payload): try encode("tool_call_requested", payload, into: &container)
        case let .toolCallCompleted(payload): try encode("tool_call_completed", payload, into: &container)
        case let .approvalRequired(payload): try encode("approval_required", payload, into: &container)
        case let .artifactDraft(payload): try encode("artifact_draft", payload, into: &container)
        case let .checkpointSaved(payload): try encode("checkpoint_saved", payload, into: &container)
        case let .finalResponse(payload): try encode("final_response", payload, into: &container)
        case let .runCancelled(payload): try encode("run_cancelled", payload, into: &container)
        case let .runFailed(payload): try encode("run_failed", payload, into: &container)
        case .sidecarStarting:
            try container.encode("sidecar_starting", forKey: .type)
            try container.encode(JSONValue.object([:]), forKey: .payload)
        case .sidecarReady:
            try container.encode("sidecar_ready", forKey: .type)
            try container.encode(JSONValue.object([:]), forKey: .payload)
        case let .sidecarUnavailable(payload): try encode("sidecar_unavailable", payload, into: &container)
        case let .sidecarCrashed(payload): try encode("sidecar_crashed", payload, into: &container)
        case let .fallbackToLegacyRuntime(payload): try encode("fallback_to_legacy_runtime", payload, into: &container)
        }
    }

    private nonisolated func encode<T: Encodable>(_ type: String, _ payload: T, into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
    }
}