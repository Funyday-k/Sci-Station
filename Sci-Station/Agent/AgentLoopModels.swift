import Foundation

public nonisolated struct AgentLoopOptions: Codable, Hashable, Sendable {
    public var maxSteps: Int
    public var maxToolCalls: Int
    public var maxContextCharacters: Int
    public var maxToolResultCharactersPerCall: Int
    public var maxAccumulatedToolResultCharacters: Int
    public var autoApproveReadOnly: Bool
    public var allowProviderNativeTools: Bool

    public nonisolated init(
        maxSteps: Int = 8,
        maxToolCalls: Int = 16,
        maxContextCharacters: Int = 80_000,
        maxToolResultCharactersPerCall: Int = 12_000,
        maxAccumulatedToolResultCharacters: Int = 40_000,
        autoApproveReadOnly: Bool = true,
        allowProviderNativeTools: Bool = true
    ) {
        self.maxSteps = max(1, maxSteps)
        self.maxToolCalls = max(1, maxToolCalls)
        self.maxContextCharacters = max(1_000, maxContextCharacters)
        self.maxToolResultCharactersPerCall = max(1_000, maxToolResultCharactersPerCall)
        self.maxAccumulatedToolResultCharacters = max(1_000, maxAccumulatedToolResultCharacters)
        self.autoApproveReadOnly = autoApproveReadOnly
        self.allowProviderNativeTools = allowProviderNativeTools
    }

    private enum CodingKeys: String, CodingKey {
        case maxSteps = "max_steps"
        case maxToolCalls = "max_tool_calls"
        case maxContextCharacters = "max_context_characters"
        case maxToolResultCharactersPerCall = "max_tool_result_characters_per_call"
        case maxAccumulatedToolResultCharacters = "max_accumulated_tool_result_characters"
        case autoApproveReadOnly = "auto_approve_read_only"
        case allowProviderNativeTools = "allow_provider_native_tools"
    }
}

public nonisolated enum AgentHumanDecisionAction: String, Codable, Sendable {
    case allowOnce
    case denyAndContinue
    case denyAndStop
    case reviseWithFeedback
    case editArguments
}

public nonisolated struct AgentApprovalRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var toolName: String
    public var permissionKey: String
    public var risk: AgentToolRisk
    public var argumentsJSON: String
    public var reason: String?
    public var createdAt: Date

    public nonisolated init(
        id: String = "approval-\(UUID().uuidString.lowercased())",
        toolName: String,
        permissionKey: String,
        risk: AgentToolRisk,
        argumentsJSON: String,
        reason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.permissionKey = permissionKey
        self.risk = risk
        self.argumentsJSON = argumentsJSON
        self.reason = reason
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolName = "tool_name"
        case permissionKey = "permission_key"
        case risk
        case argumentsJSON = "arguments_json"
        case reason
        case createdAt = "created_at"
    }
}

public nonisolated struct AgentPendingToolCall: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var runID: String
    public var stepIndex: Int
    public var toolCall: AgentToolCall
    public var approvalRequest: AgentApprovalRequest
    public var messagesBeforePause: [LLMChatMessage]
    public var createdAt: Date
    public var expiresAt: Date?

    public nonisolated init(
        id: String = "pending-tool-\(UUID().uuidString.lowercased())",
        runID: String,
        stepIndex: Int,
        toolCall: AgentToolCall,
        approvalRequest: AgentApprovalRequest,
        messagesBeforePause: [LLMChatMessage],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.stepIndex = stepIndex
        self.toolCall = toolCall
        self.approvalRequest = approvalRequest
        self.messagesBeforePause = messagesBeforePause
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public nonisolated func replacing(
        toolCall: AgentToolCall,
        approvalRequest: AgentApprovalRequest
    ) -> AgentPendingToolCall {
        AgentPendingToolCall(
            id: id,
            runID: runID,
            stepIndex: stepIndex,
            toolCall: toolCall,
            approvalRequest: approvalRequest,
            messagesBeforePause: messagesBeforePause,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case stepIndex = "step_index"
        case toolCall = "tool_call"
        case approvalRequest = "approval_request"
        case messagesBeforePause = "messages_before_pause"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

public nonisolated struct AgentToolCallFingerprint: Codable, Hashable, Sendable {
    public var toolName: String
    public var normalizedArgumentsHash: String
    public var targetPathsHash: String?

    public nonisolated init(toolName: String, normalizedArgumentsHash: String, targetPathsHash: String? = nil) {
        self.toolName = toolName
        self.normalizedArgumentsHash = normalizedArgumentsHash
        self.targetPathsHash = targetPathsHash
    }

    public nonisolated init(call: AgentToolCall, targetPaths: [String] = []) {
        let normalizedArguments = Self.normalizedJSON(call.argumentsJSON)
        let normalizedPaths = targetPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
        self.init(
            toolName: call.toolName,
            normalizedArgumentsHash: Self.stableHash(normalizedArguments),
            targetPathsHash: normalizedPaths.isEmpty ? nil : Self.stableHash(normalizedPaths)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case normalizedArgumentsHash = "normalized_arguments_hash"
        case targetPathsHash = "target_paths_hash"
    }

    public nonisolated static func normalizedJSON(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalizedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let normalized = String(data: normalizedData, encoding: .utf8) else {
            return trimmed
        }
        return normalized
    }

    private nonisolated static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

public nonisolated enum AgentLoopPauseKind: String, Codable, Sendable {
    case approvalRequired = "approval_required"
    case contextLimitExceeded = "context_limit_exceeded"
    case maxStepsExceeded = "max_steps_exceeded"
    case maxToolCallsExceeded = "max_tool_calls_exceeded"
    case safetyPolicyBlocked = "safety_policy_blocked"
    case deniedAndStopped = "denied_and_stopped"
    case providerUnavailable = "provider_unavailable"
}

public nonisolated struct AgentLoopPauseReason: Codable, Hashable, Sendable {
    public var kind: AgentLoopPauseKind
    public var message: String
    public var toolCallID: String?
    public var approvalRequest: AgentApprovalRequest?

    public nonisolated init(
        kind: AgentLoopPauseKind,
        message: String,
        toolCallID: String? = nil,
        approvalRequest: AgentApprovalRequest? = nil
    ) {
        self.kind = kind
        self.message = message
        self.toolCallID = toolCallID
        self.approvalRequest = approvalRequest
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case toolCallID = "tool_call_id"
        case approvalRequest = "approval_request"
    }
}

public nonisolated struct AgentLoopStep: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var stepIndex: Int
    public var assistantMessage: LLMChatMessage?
    public var toolCalls: [AgentToolCall]
    public var toolResults: [AgentToolResult]
    public var cachedToolCallIDs: [String]
    public var pauseReason: AgentLoopPauseReason?

    public nonisolated init(
        id: String = "loop-step-\(UUID().uuidString.lowercased())",
        stepIndex: Int,
        assistantMessage: LLMChatMessage? = nil,
        toolCalls: [AgentToolCall] = [],
        toolResults: [AgentToolResult] = [],
        cachedToolCallIDs: [String] = [],
        pauseReason: AgentLoopPauseReason? = nil
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.assistantMessage = assistantMessage
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.cachedToolCallIDs = cachedToolCallIDs
        self.pauseReason = pauseReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stepIndex = "step_index"
        case assistantMessage = "assistant_message"
        case toolCalls = "tool_calls"
        case toolResults = "tool_results"
        case cachedToolCallIDs = "cached_tool_call_ids"
        case pauseReason = "pause_reason"
    }
}

public nonisolated struct AgentLoopResult: Codable, Hashable, Sendable {
    public var runID: String
    public var sessionID: String
    public var finalResponseMarkdown: String?
    public var messages: [LLMChatMessage]
    public var toolResults: [AgentToolResult]
    public var pauseReason: AgentLoopPauseReason?
    public var pendingToolCall: AgentPendingToolCall?
    public var steps: [AgentLoopStep]

    public nonisolated init(
        runID: String,
        sessionID: String? = nil,
        finalResponseMarkdown: String? = nil,
        messages: [LLMChatMessage],
        toolResults: [AgentToolResult] = [],
        pauseReason: AgentLoopPauseReason? = nil,
        pendingToolCall: AgentPendingToolCall? = nil,
        steps: [AgentLoopStep] = []
    ) {
        self.runID = runID
        self.sessionID = sessionID ?? runID
        self.finalResponseMarkdown = finalResponseMarkdown
        self.messages = messages
        self.toolResults = toolResults
        self.pauseReason = pauseReason
        self.pendingToolCall = pendingToolCall
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case sessionID = "session_id"
        case finalResponseMarkdown = "final_response_markdown"
        case messages
        case toolResults = "tool_results"
        case pauseReason = "pause_reason"
        case pendingToolCall = "pending_tool_call"
        case steps
    }
}