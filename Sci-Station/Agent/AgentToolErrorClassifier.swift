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
    // P47-enabling additions. See docs/development/comment.md §1.6.
    case timeout = "timeout"
    case cancelled = "cancelled"
    case network = "network"
    case rateLimited = "rate_limited"
    case toolNotFound = "tool_not_found"
    case moduleDisabled = "module_disabled"
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
            "schema_version": .number("2"),
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
        // Phase 1: type-based classification. These dominate substring checks
        // because they behave the same across locales.
        if let typed = classifyByType(error, toolName: toolName) {
            return typed
        }

        // Phase 2: tool-name specific hints.
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
        if lowercased.contains("module is disabled") || lowercased.contains("module not enabled") {
            return AgentToolErrorClassification(
                code: .moduleDisabled,
                userMessage: message,
                suggestion: "Enable the required module in workspace settings and retry."
            )
        }
        if lowercased.contains("rate limit") || lowercased.contains("too many requests") || lowercased.contains("429") {
            return AgentToolErrorClassification(
                code: .rateLimited,
                userMessage: message,
                suggestion: "Wait briefly and retry; reduce concurrency if this repeats."
            )
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") {
            return AgentToolErrorClassification(
                code: .timeout,
                userMessage: message,
                suggestion: "Retry the tool; if this persists, narrow the query or increase the tool timeout."
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

    private nonisolated func classifyByType(_ error: Error, toolName: String) -> AgentToolErrorClassification? {
        if error is CancellationError {
            return AgentToolErrorClassification(
                code: .cancelled,
                userMessage: "The tool run was cancelled.",
                suggestion: "Re-send the question or approve the pending call to continue."
            )
        }
        if let agentError = error as? AgentError, case let .unknownTool(name) = agentError {
            return AgentToolErrorClassification(
                code: .toolNotFound,
                userMessage: "Tool is not registered: \(name).",
                suggestion: "Ask the model to choose another tool, or enable the module that provides it."
            )
        }
        if let agentError = error as? AgentError, case let .invalidArguments(message) = agentError {
            return AgentToolErrorClassification(
                code: .invalidArguments,
                userMessage: message,
                suggestion: "Edit the tool arguments into a valid JSON object and retry."
            )
        }
        if let timeoutError = error as? AgentTimeoutError {
            return AgentToolErrorClassification(
                code: .timeout,
                userMessage: timeoutError.localizedDescription,
                suggestion: "Retry the tool; if this persists, narrow the query or increase the tool timeout."
            )
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return AgentToolErrorClassification(
                    code: .timeout,
                    userMessage: urlError.localizedDescription,
                    suggestion: "Retry after a moment; check network connectivity and provider status."
                )
            case .cancelled:
                return AgentToolErrorClassification(
                    code: .cancelled,
                    userMessage: urlError.localizedDescription,
                    suggestion: "Re-send the question or approve the pending call to continue."
                )
            default:
                return AgentToolErrorClassification(
                    code: .network,
                    userMessage: urlError.localizedDescription,
                    suggestion: "Check network connectivity or provider availability, then retry."
                )
            }
        }
        _ = toolName // reserved for future tool-specific type hints
        return nil
    }
}

/// Error thrown by `AgentLoopRunner` when a provider or tool invocation
/// exceeds its configured soft budget.
public nonisolated struct AgentTimeoutError: LocalizedError, Sendable {
    public var operation: String
    public var timeoutSeconds: Double
    public var toolName: String?

    public nonisolated init(operation: String, timeoutSeconds: Double, toolName: String? = nil) {
        self.operation = operation
        self.timeoutSeconds = timeoutSeconds
        self.toolName = toolName
    }

    public var errorDescription: String? {
        if let toolName {
            return "\(operation) for tool \(toolName) timed out after \(formattedSeconds)s."
        }
        return "\(operation) timed out after \(formattedSeconds)s."
    }

    private var formattedSeconds: String {
        if timeoutSeconds == timeoutSeconds.rounded() {
            return String(Int(timeoutSeconds))
        }
        return String(format: "%.1f", timeoutSeconds)
    }
}

/// Generic hard timeout helper. Uses a `TaskGroup` rather than sleeping tasks
/// so that when the timeout fires the in-flight operation Task is cancelled
/// explicitly, giving cooperative cancellation a chance to unwind network
/// reads and file handles cleanly.
public func withAgentTimeout<T: Sendable>(
    _ seconds: Double,
    operation name: String,
    toolName: String? = nil,
    _ body: @Sendable @escaping () async throws -> T
) async throws -> T {
    guard seconds > 0 else {
        return try await body()
    }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            let nanoseconds = UInt64((seconds * 1_000_000_000).rounded())
            try await Task.sleep(nanoseconds: nanoseconds)
            throw AgentTimeoutError(operation: name, timeoutSeconds: seconds, toolName: toolName)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AgentTimeoutError(operation: name, timeoutSeconds: seconds, toolName: toolName)
        }
        return result
    }
}
