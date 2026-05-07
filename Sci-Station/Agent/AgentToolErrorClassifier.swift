import Foundation

public nonisolated enum AgentToolErrorCode: String, Codable, Sendable {
    case paperNotFound = "paper_not_found"
    case markdownNotConverted = "markdown_not_converted"
    case sectionNotFound = "section_not_found"
    case emptySearch = "empty_search"
    case permissionDenied = "permission_denied"
    case writeFailed = "write_failed"
    case providerFailed = "provider_failed"
    case invalidArguments = "invalid_arguments"
    case toolFailed = "tool_failed"
}

public nonisolated struct AgentToolErrorClassification: Hashable, Sendable {
    public var code: AgentToolErrorCode
    public var userMessage: String
    public var suggestion: String

    public nonisolated init(code: AgentToolErrorCode, userMessage: String, suggestion: String) {
        self.code = code
        self.userMessage = userMessage
        self.suggestion = suggestion
    }

    public nonisolated var payload: JSONValue {
        .object([
            "schema_version": .number("1"),
            "kind": .string("tool_error"),
            "error_code": .string(code.rawValue),
            "message": .string(userMessage),
            "suggestion": .string(suggestion)
        ])
    }
}

public nonisolated struct AgentToolErrorClassifier {
    public nonisolated init() {}

    public nonisolated func classify(_ error: Error, toolName: String) -> AgentToolErrorClassification {
        let message = error.localizedDescription
        let lowercased = message.lowercased()

        if lowercased.contains("no paper found") {
            return AgentToolErrorClassification(
                code: .paperNotFound,
                userMessage: message,
                suggestion: "Choose a paper from list_papers or pass a stable paper_id/path."
            )
        }
        if lowercased.contains("paper.md is not available") || lowercased.contains("convert or import markdown") {
            return AgentToolErrorClassification(
                code: .markdownNotConverted,
                userMessage: message,
                suggestion: "Convert/import Markdown for this paper, then retry the read or search."
            )
        }
        if lowercased.contains("no markdown heading matched") || lowercased.contains("heading or start_line/end_line is required") {
            return AgentToolErrorClassification(
                code: .sectionNotFound,
                userMessage: message,
                suggestion: "Use search_papers first, then retry read_paper_section with a matched heading or line range."
            )
        }
        if lowercased.contains("denied") || lowercased.contains("permission") {
            return AgentToolErrorClassification(
                code: .permissionDenied,
                userMessage: message,
                suggestion: "Approve the tool call, edit the target, or deny and keep the draft for revision."
            )
        }
        if toolName.hasPrefix("write_") || toolName == "create_todo" || toolName == "update_paper_classification" {
            return AgentToolErrorClassification(
                code: .writeFailed,
                userMessage: message,
                suggestion: "Keep the draft, verify the target path, then retry after fixing the workspace write error."
            )
        }
        if lowercased.contains("invalid agent tool arguments") || lowercased.contains("arguments") {
            return AgentToolErrorClassification(
                code: .invalidArguments,
                userMessage: message,
                suggestion: "Edit the tool arguments into a valid JSON object and retry."
            )
        }
        return AgentToolErrorClassification(
            code: .toolFailed,
            userMessage: message,
            suggestion: "Review the tool details, adjust the paper/path/query, and retry."
        )
    }
}
