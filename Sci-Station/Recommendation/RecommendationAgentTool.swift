import Foundation

public nonisolated struct RequestRecommendationRefreshAgentTool: AgentTool {
    public nonisolated init() {}

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "request_recommendation_refresh",
            displayName: "Request Recommendation Refresh",
            summary: "Request a local recommendation refresh and return only the generated candidate count.",
            inputSchema: #"{"scope":"workspace|active_project optional","top_k":10}"#,
            risk: .readOnly,
            requiresConfirmation: false,
            permissionKey: "recommendation.read",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 2000),
            examples: [#"{"scope":"active_project","top_k":8}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let papers = try await PaperRepository().loadPapers(in: context.workspace)
        let config = (try? RecommendationConfigStore().load(in: context.workspace)) ?? RecommendationConfig()
        let scopedPapers = context.currentProjectID.map { projectID in
            papers.filter { $0.projectIDs.contains(projectID) || $0.coreProjectIDs.contains(projectID) }
        } ?? papers
        let candidateCount = min(scopedPapers.count, config.topK)
        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: true,
            message: "Recommendation refresh prepared \(candidateCount) local candidate(s). Review Recommendations to approve queue additions.",
            payload: .object([
                "schema_version": .number("1"),
                "kind": .string("recommendation_refresh_requested"),
                "candidate_count": .number(String(candidateCount)),
                "scope": .string(context.currentProjectID.map { "project:\($0)" } ?? "workspace")
            ])
        )
    }
}
