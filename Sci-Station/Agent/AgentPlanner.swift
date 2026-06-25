import Foundation

public actor AgentPlanner {
    private let provider: any LLMProvider
    private let promptBuilder: AgentPromptBuilder
    private let planParser: AgentPlanParser
    private let promptLibraryResolver: AgentPromptLibraryResolver

    public init(
        provider: any LLMProvider,
        promptBuilder: AgentPromptBuilder = AgentPromptBuilder(),
        planParser: AgentPlanParser = AgentPlanParser(),
        promptLibraryResolver: AgentPromptLibraryResolver = AgentPromptLibraryResolver()
    ) {
        self.provider = provider
        self.promptBuilder = promptBuilder
        self.planParser = planParser
        self.promptLibraryResolver = promptLibraryResolver
    }

    public func plan(
        goal: String,
        workspaceSnapshot: AgentWorkspaceSnapshot,
        tools: [AgentToolDefinition],
        configuration: LLMConfiguration,
        apiKey: String,
        modeInstructions: String? = nil,
        conversationHistory: [LLMChatMessage] = [],
        allowsPlainTextResponse: Bool = false,
        workspaceProfile: AgentWorkspaceProfile = AgentWorkspaceProfile(),
        skillContext: String? = nil,
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AgentPlan {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            throw AgentError.emptyGoal
        }

        let basePrompt = allowsPlainTextResponse ? trimmedGoal : trimmedGoal
        let plannerPrompt = promptLibraryResolver.resolve(
            surface: .planner,
            profile: workspaceProfile,
            basePrompt: basePrompt
        ).appendingContext(skillContext)

        if let chatProvider = provider as? any LLMChatProvider {
            let messages = try promptBuilder.buildChatMessages(
                goal: plannerPrompt.promptText,
                workspaceSnapshot: workspaceSnapshot,
                tools: tools,
                modeInstructions: modeInstructions,
                conversationHistory: conversationHistory,
                allowsPlainTextResponse: allowsPlainTextResponse
            )
            let request = LLMProviderRequest(
                messages: messages,
                tools: allowsPlainTextResponse ? [] : tools.map(LLMToolSpecification.init(agentTool:))
            )

            if let streamingProvider = provider as? any LLMStreamingChatProvider,
               let responseDeltaHandler {
                let streamedMessage = try await streamedResponse(
                    from: streamingProvider,
                    request: request,
                    configuration: configuration,
                    apiKey: apiKey,
                    responseDeltaHandler: responseDeltaHandler
                )
                return try parsedPlan(from: streamedMessage, goal: trimmedGoal, allowsPlainTextResponse: allowsPlainTextResponse)
            }

            let response = try await chatProvider.respond(to: request, configuration: configuration, apiKey: apiKey)
            return try parsedPlan(from: response.message, goal: plannerPrompt.promptText, allowsPlainTextResponse: allowsPlainTextResponse)
        }

        let prompt = try promptBuilder.buildPrompt(
            goal: plannerPrompt.promptText,
            workspaceSnapshot: workspaceSnapshot,
            tools: tools,
            modeInstructions: modeInstructions,
            conversationHistory: conversationHistory,
            allowsPlainTextResponse: allowsPlainTextResponse
        )
        let response = try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
        return try parsedPlan(from: response, goal: plannerPrompt.promptText, allowsPlainTextResponse: allowsPlainTextResponse)
    }

    private func streamedResponse(
        from provider: any LLMStreamingChatProvider,
        request: LLMProviderRequest,
        configuration: LLMConfiguration,
        apiKey: String,
        responseDeltaHandler: @escaping @Sendable (String) async -> Void
    ) async throws -> LLMChatMessage {
        var accumulated = ""
        var completedMessage: LLMChatMessage?

        for try await event in provider.streamResponse(to: request, configuration: configuration, apiKey: apiKey) {
            try Task.checkCancellation()
            switch event {
            case let .messageDelta(delta):
                accumulated += delta
                await responseDeltaHandler(delta)
            case .toolCallDelta:
                break
            case let .completed(response):
                completedMessage = response.message
            }
        }

        if let completedMessage,
           !completedMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !completedMessage.toolCalls.isEmpty {
            return completedMessage
        }
        return LLMChatMessage(role: .assistant, content: accumulated)
    }

    private func parsedPlan(from message: LLMChatMessage, goal: String, allowsPlainTextResponse: Bool) throws -> AgentPlan {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.toolCalls.isEmpty {
            if var parsed = try? planParser.parse(content), parsed.toolCalls.isEmpty {
                parsed.toolCalls = message.toolCalls
                return parsed
            }

            let visibleResponse = AgentVisibleResponseExtractor.visibleText(from: content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let toolNames = message.toolCalls.map(\.toolName).joined(separator: ", ")
            return AgentPlan(
                title: "待审批工具调用",
                summary: visibleResponse ?? "模型请求工具：\(toolNames)",
                risk: "工具调用将在用户审批后执行。",
                steps: ["审查模型请求的工具调用", "批准后由 Sci-Station 执行工具"],
                toolCalls: message.toolCalls,
                finalResponseDraft: visibleResponse
            )
        }

        return try parsedPlan(from: content, goal: goal, allowsPlainTextResponse: allowsPlainTextResponse)
    }

    private func parsedPlan(from response: String, goal: String, allowsPlainTextResponse: Bool) throws -> AgentPlan {
        do {
            return try planParser.parse(response)
        } catch let error as AgentPlanParserError {
            if let fallbackPlan = planParser.writebackFallbackPlan(response: response, goal: goal) {
                return fallbackPlan
            }
            let visibleResponse = AgentVisibleResponseExtractor.visibleText(from: response)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visibleResponse.isEmpty else {
                throw error
            }

            return AgentPlan(
                title: allowsPlainTextResponse ? "对话回复" : "AI 回复",
                summary: visibleResponse,
                risk: nil,
                steps: [],
                toolCalls: [],
                finalResponseDraft: visibleResponse
            )
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
