import Foundation

public nonisolated enum AgentPlanParserError: LocalizedError, Sendable {
    case missingJSONObject
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingJSONObject:
            return "AI 返回的内容不是结构化 JSON。聊天模式会自动接受自然语言；计划/执行模式请重新生成。"
        case let .invalidJSON(message):
            return "AI 返回的 JSON 无法解析：\(message)"
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