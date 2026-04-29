import Foundation

public nonisolated struct AgentPromptBuilder {
    public nonisolated init() {}

    public nonisolated func buildPrompt(
        goal: String,
        workspaceSnapshot: AgentWorkspaceSnapshot,
        tools: [AgentToolDefinition]
    ) throws -> String {
        let snapshotJSON = try encoded(workspaceSnapshot)
        let toolsJSON = try encoded(tools)

        return """
        You are the Sci-Station in-app research agent. Plan actions that can be executed by Sci-Station tools.

        Operating rules:
        - Only use tools listed in the available_tools JSON.
        - Do not invent papers, file paths, or todo items that are not present in workspace_context.
        - Prefer a plan-only answer when the user's intent is ambiguous or requires confirmation.
        - Any tool with requires_confirmation=true must be shown to the user before execution.
        - Return only one JSON object. Do not wrap it in Markdown.

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

        user_goal:
        \(goal)

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