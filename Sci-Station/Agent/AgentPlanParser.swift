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

public nonisolated struct AgentVisibleResponseExtractor {
    public nonisolated init() {}

    public nonisolated static func visibleText(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksStructured(trimmed) else {
            return response
        }

        guard let json = balancedJSONObject(in: trimmed),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        for key in ["final_response_draft", "finalResponseDraft", "answer", "content", "summary"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        return ""
    }

    private nonisolated static func looksStructured(_ value: String) -> Bool {
        value.hasPrefix("{")
            || value.hasPrefix("```json")
            || value.hasPrefix("```JSON")
            || value.contains("\"tool_calls\"")
            || value.contains("\"final_response_draft\"")
    }

    private nonisolated static func balancedJSONObject(in value: String) -> String? {
        guard let startIndex = value.firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = startIndex

        while index < value.endIndex {
            let character = value[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(value[startIndex...index])
                    }
                }
            }
            index = value.index(after: index)
        }

        return nil
    }
}