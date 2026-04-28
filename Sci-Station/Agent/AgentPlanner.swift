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
        apiKey: String
    ) async throws -> AgentPlan {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            throw AgentError.emptyGoal
        }

        let prompt = try promptBuilder.buildPrompt(
            goal: trimmedGoal,
            workspaceSnapshot: workspaceSnapshot,
            tools: tools
        )
        let response = try await provider.complete(prompt: prompt, configuration: configuration, apiKey: apiKey)
        return try planParser.parse(response)
    }
}