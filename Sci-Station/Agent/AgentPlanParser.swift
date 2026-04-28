import Foundation

public nonisolated enum AgentPlanParserError: LocalizedError, Sendable {
    case missingJSONObject
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingJSONObject:
            return "Agent response did not contain a JSON object."
        case let .invalidJSON(message):
            return "Agent response JSON could not be decoded: \(message)"
        }
    }
}

public nonisolated struct AgentPlanParser {
    public nonisolated init() {}

    public nonisolated func parse(_ response: String) throws -> AgentPlan {
        let json = try extractJSONObject(from: response)
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        do {
            return try decoder.decode(AgentPlan.self, from: data)
        } catch {
            throw AgentPlanParserError.invalidJSON(error.localizedDescription)
        }
    }

    private nonisolated func extractJSONObject(from response: String) throws -> String {
        guard let startIndex = response.firstIndex(of: "{"),
              let endIndex = response.lastIndex(of: "}"),
              startIndex <= endIndex else {
            throw AgentPlanParserError.missingJSONObject
        }

        return String(response[startIndex...endIndex])
    }
}