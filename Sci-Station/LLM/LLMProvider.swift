import Foundation

public protocol LLMProvider: Sendable {
    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String
}

public nonisolated enum LLMChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public nonisolated struct LLMChatMessage: Codable, Hashable, Sendable {
    public var role: LLMChatRole
    public var content: String
    public var reasoningContent: String?
    public var name: String?
    public var toolCallID: String?
    public var toolCalls: [AgentToolCall]

    public nonisolated init(
        role: LLMChatRole,
        content: String,
        reasoningContent: String? = nil,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [AgentToolCall] = []
    ) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case name
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(LLMChatRole.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        self.toolCalls = try container.decodeIfPresent([AgentToolCall].self, forKey: .toolCalls) ?? []
    }
}

public nonisolated struct LLMToolSpecification: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var inputSchemaJSON: String
    public var permissionKey: String?

    public nonisolated init(
        name: String,
        description: String,
        inputSchemaJSON: String,
        permissionKey: String? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
        self.permissionKey = permissionKey
    }

    public nonisolated init(agentTool definition: AgentToolDefinition) {
        self.name = definition.name
        self.description = definition.summary
        self.inputSchemaJSON = definition.inputSchema
        self.permissionKey = definition.permissionKey
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchemaJSON = "input_schema_json"
        case permissionKey = "permission_key"
    }
}

public nonisolated struct LLMProviderOptions: Codable, Hashable, Sendable {
    public var model: String?
    public var temperature: Double?
    public var maxTokens: Int?
    public var providerOptions: [String: String]

    public nonisolated init(
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        providerOptions: [String: String] = [:]
    ) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case maxTokens = "max_tokens"
        case providerOptions = "provider_options"
    }
}

public nonisolated struct LLMProviderRequest: Codable, Hashable, Sendable {
    public var messages: [LLMChatMessage]
    public var tools: [LLMToolSpecification]
    public var options: LLMProviderOptions

    public nonisolated init(
        messages: [LLMChatMessage],
        tools: [LLMToolSpecification] = [],
        options: LLMProviderOptions = LLMProviderOptions()
    ) {
        self.messages = messages
        self.tools = tools
        self.options = options
    }
}

public nonisolated struct LLMProviderV2AdapterFlow: Codable, Hashable, Sendable {
    public var request: LLMProviderRequest
    public var preservesLegacyCompletePath: Bool
    public var supportsTaskCancellation: Bool

    public nonisolated init(
        messages: [LLMChatMessage],
        toolDefinitions: [AgentToolDefinition] = [],
        options: LLMProviderOptions = LLMProviderOptions(),
        preservesLegacyCompletePath: Bool = true,
        supportsTaskCancellation: Bool = true
    ) {
        self.request = LLMProviderRequest(
            messages: messages,
            tools: toolDefinitions.map(LLMToolSpecification.init(agentTool:)),
            options: options
        )
        self.preservesLegacyCompletePath = preservesLegacyCompletePath
        self.supportsTaskCancellation = supportsTaskCancellation
    }

    private enum CodingKeys: String, CodingKey {
        case request
        case preservesLegacyCompletePath = "preserves_legacy_complete_path"
        case supportsTaskCancellation = "supports_task_cancellation"
    }
}

public nonisolated struct LLMProviderResponse: Codable, Hashable, Sendable {
    public var message: LLMChatMessage
    public var toolCalls: [AgentToolCall]
    public var rawResponse: String?

    public nonisolated init(message: LLMChatMessage, toolCalls: [AgentToolCall] = [], rawResponse: String? = nil) {
        self.message = message
        self.toolCalls = toolCalls
        self.rawResponse = rawResponse
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case toolCalls = "tool_calls"
        case rawResponse = "raw_response"
    }
}

public nonisolated enum LLMProviderStreamEvent: Sendable {
    case messageDelta(String)
    case toolCallDelta(AgentToolCall)
    case completed(LLMProviderResponse)
}

public protocol LLMChatProvider: Sendable {
    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse
}

public protocol LLMStreamingChatProvider: LLMChatProvider {
    nonisolated func streamResponse(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) -> AsyncThrowingStream<LLMProviderStreamEvent, Error>
}

public enum LLMProviderError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case httpError(statusCode: Int, message: String)
    case malformedResponse
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid LLM endpoint: \(endpoint)."
        case let .httpError(statusCode, message):
            return "LLM request failed with HTTP \(statusCode): \(message)"
        case .malformedResponse:
            return "LLM provider returned a malformed response."
        case .emptyResponse:
            return "LLM provider returned an empty response."
        }
    }
}
