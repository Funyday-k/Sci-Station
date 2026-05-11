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
            return partialVisibleText(from: trimmed)
        }

        for key in ["final_response_draft", "finalResponseDraft", "answer", "response", "message", "markdown", "content", "summary"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        let fallback = object.values.compactMap { value -> String? in
            guard let text = value as? String else {
                return nil
            }
            return nonEmpty(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.first

        return fallback ?? stripMarkdownFence(from: trimmed)
    }

    private nonisolated static func looksStructured(_ value: String) -> Bool {
        value.hasPrefix("{")
            || value.hasPrefix("```json")
            || value.hasPrefix("```JSON")
            || value.contains("\"tool_calls\"")
            || value.contains("\"final_response_draft\"")
    }

    private nonisolated static func partialVisibleText(from value: String) -> String {
        for key in ["final_response_draft", "finalResponseDraft", "answer", "response", "message", "markdown", "content", "summary"] {
            if let partial = partialJSONStringValue(for: key, in: value) {
                return partial
            }
        }
        return stripMarkdownFence(from: value)
    }

    private nonisolated static func partialJSONStringValue(for key: String, in value: String) -> String? {
        let quotedKey = "\"\(key)\""
        guard let keyRange = value.range(of: quotedKey),
              let colonRange = value[keyRange.upperBound...].range(of: ":") else {
            return nil
        }
        var index = colonRange.upperBound
        while index < value.endIndex, value[index].isWhitespace || value[index].isNewline {
            index = value.index(after: index)
        }
        guard index < value.endIndex, value[index] == "\"" else {
            return nil
        }
        index = value.index(after: index)

        var output = ""
        var isEscaped = false
        while index < value.endIndex {
            let character = value[index]
            if isEscaped {
                output.append(unescaped(character))
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                break
            } else {
                output.append(character)
            }
            index = value.index(after: index)
        }

        return nonEmpty(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private nonisolated static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private nonisolated static func unescaped(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        default: return character
        }
    }

    private nonisolated static func stripMarkdownFence(from value: String) -> String {
        var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["```json", "```JSON", "```"] {
            if output.hasPrefix(marker) {
                output = String(output.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if output.hasSuffix("```") {
            output = String(output.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
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