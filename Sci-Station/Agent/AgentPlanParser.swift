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

    public nonisolated func writebackFallbackPlan(response: String, goal: String) -> AgentPlan? {
        guard AgentWritebackFallbackIntent.matches(goal: goal) else {
            return nil
        }
        let visibleResponse = AgentVisibleResponseExtractor.visibleText(from: response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleResponse.isEmpty else {
            return nil
        }
        return AgentPlan(
            title: "未确认的写回草稿",
            summary: visibleResponse,
            risk: "模型返回了非 JSON Markdown；已保留为待审批写回草稿。",
            steps: ["保留模型生成的 Markdown 草稿", "如需写入 wiki，请审查目标路径后批准写回工具"],
            toolCalls: [],
            finalResponseDraft: visibleResponse
        )
    }

    private nonisolated func extractJSONObject(from response: String) throws -> String {
        guard let json = balancedJSONObject(in: response) else {
            throw AgentPlanParserError.missingJSONObject
        }

        return json
    }

    private nonisolated func balancedJSONObject(in value: String) -> String? {
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

public nonisolated enum AgentWritebackFallbackIntent {
    public nonisolated static func matches(goal: String) -> Bool {
        let lowercased = goal.lowercased()
        let keywords = [
            "写进", "写到", "写入", "放进", "保存到", "存到", "加入 wiki", "放到 wiki",
            "save to", "save into", "write to", "write into", "add to", "put into"
        ]
        guard keywords.contains(where: { lowercased.contains($0) }) else {
            return false
        }
        return lowercased.contains("wiki")
            || lowercased.contains("维基")
            || lowercased.contains("笔记")
            || lowercased.contains("note")
            || lowercased.contains("paper")
            || lowercased.contains("论文")
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