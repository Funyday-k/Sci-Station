import Foundation

public nonisolated struct RequestRecommendationRefreshAgentTool: AgentTool {
    public nonisolated init() {}

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "request_recommendation_refresh",
            displayName: "Request Recommendation Refresh",
            summary: "Fetch arXiv-only paper recommendations and return candidates for the recommendation workflow.",
            inputSchema: #"{"query":"optional keywords","categories":["cs.AI","cs.CL"],"scope":"workspace|active_project optional","top_k":10}"#,
            risk: .network,
            permissionKey: "recommendation.network",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 12000),
            examples: [#"{"query":"scientific agents","categories":["cs.AI","cs.CL"],"scope":"active_project","top_k":8}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let config = (try? RecommendationConfigStore().load(in: context.workspace)) ?? RecommendationConfig()
        let arguments = (try? JSONDecoder().decode(RecommendationRefreshArguments.self, from: Data(argumentsJSON.utf8))) ?? RecommendationRefreshArguments()
        let topK = min(max(arguments.topK ?? config.topK, 1), 100)
        let configuredCategories = config.dailySources.first { $0.kind == .arxiv }?.categories ?? []
        let categories = arguments.categories?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? configuredCategories
        let request = ArxivRecommendationRequest(
            query: arguments.query ?? "",
            categories: categories.isEmpty ? ["cs.AI", "cs.CL", "cs.CV", "cs.LG"] : categories,
            maxResults: min(max(topK * 3, config.maxDailyCandidates), 100)
        )
        let candidates = try await ArxivRecommendationClient().fetch(request)
        let selectedCandidates = Array(candidates.prefix(topK))
        let scope = arguments.scope == "active_project"
            ? context.currentProjectID.map { "project:\($0)" } ?? "workspace"
            : "workspace"
        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: true,
            message: "Fetched \(selectedCandidates.count) arXiv candidate(s). Review them in the recommendation view after approval.",
            payload: .object([
                "schema_version": .number("1"),
                "kind": .string("recommendation_note"),
                "artifact_kind": .string("recommendation_note"),
                "candidate_count": .number(String(selectedCandidates.count)),
                "scope": .string(scope),
                "source": .string("arxiv"),
                "candidates": .array(selectedCandidates.map(candidatePayload(_:)))
            ])
        )
    }

    private nonisolated func candidatePayload(_ candidate: RecommendationCandidate) -> JSONValue {
        var payload: [String: JSONValue] = [
            "display_title": .string(candidate.displayTitle),
            "reason": .string("arXiv-only recommendation"),
            "source": .string("arxiv")
        ]
        if let paperID = candidate.paperID {
            payload["paper_id"] = .string(paperID)
        }
        if let externalKey = candidate.externalKey {
            payload["external_key"] = .string(externalKey)
        }
        return .object(payload)
    }
}

private nonisolated struct RecommendationRefreshArguments: Decodable {
    var query: String?
    var categories: [String]?
    var scope: String?
    var topK: Int?

    init(query: String? = nil, categories: [String]? = nil, scope: String? = nil, topK: Int? = nil) {
        self.query = query
        self.categories = categories
        self.scope = scope
        self.topK = topK
    }

    private enum CodingKeys: String, CodingKey {
        case query
        case categories
        case scope
        case topK = "top_k"
    }
}
