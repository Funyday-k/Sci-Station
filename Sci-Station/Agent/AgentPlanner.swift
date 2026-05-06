import Foundation

public actor AgentPlanner {
    private let provider: any LLMProvider
    private let promptBuilder: AgentPromptBuilder
    private let planParser: AgentPlanParser

    public init(
        provider: any LLMProvider,
        promptBuilder: AgentPromptBuilder = AgentPromptBuilder(),
        planParser: AgentPlanParser = AgentPlanParser()
    ) {
        self.provider = provider
        self.promptBuilder = promptBuilder
        self.planParser = planParser
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
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AgentPlan {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            throw AgentError.emptyGoal
        }

        if let chatProvider = provider as? any LLMChatProvider {
            let messages = try promptBuilder.buildChatMessages(
                goal: trimmedGoal,
                workspaceSnapshot: workspaceSnapshot,
                tools: tools,
                modeInstructions: modeInstructions,
                conversationHistory: conversationHistory,
                allowsPlainTextResponse: allowsPlainTextResponse
            )
            let request = LLMProviderRequest(messages: messages)

            if let streamingProvider = provider as? any LLMStreamingChatProvider,
               let responseDeltaHandler {
                let streamedContent = try await streamedResponse(
                    from: streamingProvider,
                    request: request,
                    configuration: configuration,
                    apiKey: apiKey,
                    responseDeltaHandler: responseDeltaHandler
                )
                return try parsedPlan(from: streamedContent, allowsPlainTextResponse: allowsPlainTextResponse)
            }

            let response = try await chatProvider.respond(to: request, configuration: configuration, apiKey: apiKey)
            return try parsedPlan(from: response.message.content, allowsPlainTextResponse: allowsPlainTextResponse)
        }

        let prompt = try promptBuilder.buildPrompt(
            goal: trimmedGoal,
            workspaceSnapshot: workspaceSnapshot,
            tools: tools,
            modeInstructions: modeInstructions,
            conversationHistory: conversationHistory,
            allowsPlainTextResponse: allowsPlainTextResponse
        )
        let response = try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
        return try parsedPlan(from: response, allowsPlainTextResponse: allowsPlainTextResponse)
    }

    private func streamedResponse(
        from provider: any LLMStreamingChatProvider,
        request: LLMProviderRequest,
        configuration: LLMConfiguration,
        apiKey: String,
        responseDeltaHandler: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        var accumulated = ""
        var completedContent: String?

        for try await event in provider.streamResponse(to: request, configuration: configuration, apiKey: apiKey) {
            try Task.checkCancellation()
            switch event {
            case let .messageDelta(delta):
                accumulated += delta
                await responseDeltaHandler(delta)
            case .toolCallDelta:
                break
            case let .completed(response):
                completedContent = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }

        return completedContent ?? accumulated
    }

    private func parsedPlan(from response: String, allowsPlainTextResponse: Bool) throws -> AgentPlan {
        do {
            return try planParser.parse(response)
        } catch let error as AgentPlanParserError {
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