import Foundation

public nonisolated struct AgentPromptBuilder {
    public nonisolated init() {}

    public nonisolated func buildPrompt(
        goal: String,
        workspaceSnapshot: AgentWorkspaceSnapshot,
        tools: [AgentToolDefinition],
      modeInstructions: String? = nil,
      conversationHistory: [LLMChatMessage] = []
    ) throws -> String {
      let history = conversationHistory
        .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(12)
        .map { "\($0.role.rawValue): \($0.content)" }
        .joined(separator: "\n\n")

      return try [
        buildSystemPrompt(
          workspaceSnapshot: workspaceSnapshot,
          tools: tools,
          modeInstructions: modeInstructions
        ),
        history.isEmpty ? nil : "conversation_history:\n\(history)",
        "user_goal:\n\(goal)"
      ]
      .compactMap { $0 }
      .joined(separator: "\n\n")
    }

    public nonisolated func buildChatMessages(
      goal: String,
      workspaceSnapshot: AgentWorkspaceSnapshot,
      tools: [AgentToolDefinition],
      modeInstructions: String? = nil,
      conversationHistory: [LLMChatMessage] = []
    ) throws -> [LLMChatMessage] {
      let systemPrompt = try buildSystemPrompt(
        workspaceSnapshot: workspaceSnapshot,
        tools: tools,
        modeInstructions: modeInstructions
      )
      let safeHistory = conversationHistory
        .filter { $0.role == .user || $0.role == .assistant }
        .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(12)

      return [LLMChatMessage(role: .system, content: systemPrompt)]
        + safeHistory
        + [LLMChatMessage(role: .user, content: "user_goal:\n\(goal)")]
    }

    private nonisolated func buildSystemPrompt(
      workspaceSnapshot: AgentWorkspaceSnapshot,
      tools: [AgentToolDefinition],
      modeInstructions: String?
    ) throws -> String {
        let snapshotJSON = try encoded(workspaceSnapshot)
        let toolsJSON = try encoded(tools)
        let resolvedModeInstructions = modeInstructions?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Mode: Assistant. Use available tools only when they help and respect approval requirements."

        return """
        You are the Sci-Station in-app research agent. Plan actions that can be executed by Sci-Station tools.

        Operating mode:
        \(resolvedModeInstructions)

        Operating rules:
        - Only use tools listed in the available_tools JSON.
        - Do not invent papers, file paths, or todo items that are not present in workspace_context.
        - Prefer a plan-only answer when the user's intent is ambiguous or requires confirmation.
        - Any tool with requires_confirmation=true must be shown to the user before execution.
        - Respond in the same language as the latest user_goal unless the user explicitly asks for another language.
        - If the latest user_goal contains Chinese, all user-facing fields (`summary`, `steps`, `risk`, `final_response_draft`) must be Simplified Chinese.
        - Use conversation history to preserve context, but let the latest user_goal take priority.
        - When paper markdown excerpts are present, use them as the primary paper content. When only metadata is present, say what is known and what is missing.
        - Return only one JSON object. Do not wrap it in Markdown.
        - In Conversation mode, `tool_calls` must be empty. `final_response_draft` may contain Markdown for readable answers.

        Output JSON schema:
        {
          "title": "short title for the plan",
          "summary": "short plan summary",
          "risk": "short risk note, especially for workspace writes",
          "steps": [
            "concrete step 1",
            "concrete step 2"
          ],
          "tool_calls": [
            {
              "id": "call-1",
              "tool_name": "tool name from available_tools",
              "arguments_json": "JSON object encoded as a string"
            }
          ],
          "final_response_draft": "optional user-facing response after these actions"
        }

        workspace_context:
        \(snapshotJSON)

        available_tools:
        \(toolsJSON)
        """
    }

    private nonisolated func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
