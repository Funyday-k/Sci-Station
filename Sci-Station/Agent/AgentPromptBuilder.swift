import Foundation

public nonisolated struct AgentPromptBuilder {
    public nonisolated init() {}

    public nonisolated func buildPrompt(
        goal: String,
        workspaceSnapshot: AgentWorkspaceSnapshot,
        tools: [AgentToolDefinition],
      modeInstructions: String? = nil,
      conversationHistory: [LLMChatMessage] = [],
      allowsPlainTextResponse: Bool = false
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
          modeInstructions: modeInstructions,
          allowsPlainTextResponse: allowsPlainTextResponse
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
      conversationHistory: [LLMChatMessage] = [],
      allowsPlainTextResponse: Bool = false
    ) throws -> [LLMChatMessage] {
      let systemPrompt = try buildSystemPrompt(
        workspaceSnapshot: workspaceSnapshot,
        tools: tools,
        modeInstructions: modeInstructions,
        allowsPlainTextResponse: allowsPlainTextResponse
      )
      let safeHistory = conversationHistory
        .filter { $0.role == .user || $0.role == .assistant }
        .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(12)

      return [LLMChatMessage(role: .system, content: systemPrompt)]
        + safeHistory
        + [LLMChatMessage(role: .user, content: "user_goal:\n\(goal)")]
    }

    public nonisolated func buildToolLoopChatMessages(
      goal: String,
      workspaceSnapshot: AgentWorkspaceSnapshot,
      tools: [AgentToolDefinition],
      conversationHistory: [LLMChatMessage] = []
    ) throws -> [LLMChatMessage] {
      let snapshotJSON = try encoded(workspaceSnapshot)
      let toolsJSON = try encoded(tools)
      let safeHistory = conversationHistory
        .filter { $0.role == .user || $0.role == .assistant }
        .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(12)

      let systemPrompt = """
      You are the Sci-Station in-app research assistant running in a Swift-native tool loop.

      Operating rules:
      - Answer using only workspace_context, conversation history, and tool results returned in this loop.
      - Use provider-native tool calls when paper body details, equations, methods, claims, section summaries, quotations, or exact evidence are needed.
      - If the user refers to "the first paper", "第一篇", or an ordinal paper without a stable paper id, call `list_papers` first to resolve the target paper before reading body content.
      - For equation/formula questions, especially evaporation-rate questions, follow `list_papers -> search_papers -> read_paper_section -> final answer` unless a stable paper id and exact section are already known.
      - Prefer `search_papers` for keywords, symbols, formula names, or concepts; then use `read_paper_section` when a focused section is needed.
      - Prefer `read_paper_section` when the user names a section or heading. Use `read_paper` only for overview/page-based reading or when the target section is unknown.
      - Read-only tools may run automatically. Workspace writes, network actions, and external side effects require approval and may pause the loop.
      - Do not invent papers, file paths, todo items, equations, citations, or tool results.
      - Respond in the same language as the latest user_goal unless the user explicitly asks for another language.
      - If the latest user_goal contains Chinese, answer in Simplified Chinese.
      - Return final user-facing content as natural GitHub-flavored Markdown, not JSON.
      - Render inline math as `$...$` and display math as `$$...$$`. Never wrap math in backticks.
      - When citing a paper or section, include the paper title, paper id, or relative file path so the user can re-locate it.
      - Final answers to paper formula questions must include the formula, the local context explaining what the symbols mean when available, and the source paper title/id/path. If no formula is found, say which tools and queries were used and which papers or sections did not match.

      workspace_context:
      \(snapshotJSON)

      available_tools:
      \(toolsJSON)
      """

      return [LLMChatMessage(role: .system, content: systemPrompt)]
        + safeHistory
        + [LLMChatMessage(role: .user, content: "user_goal:\n\(goal)")]
    }

    private nonisolated func buildSystemPrompt(
      workspaceSnapshot: AgentWorkspaceSnapshot,
      tools: [AgentToolDefinition],
      modeInstructions: String?,
      allowsPlainTextResponse: Bool
    ) throws -> String {
        let snapshotJSON = try encoded(workspaceSnapshot)
        let toolsJSON = try encoded(tools)
        let resolvedModeInstructions = modeInstructions?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Mode: Assistant. Use available tools only when they help and respect approval requirements."

        if allowsPlainTextResponse {
            return """
            You are the Sci-Station in-app research assistant. Answer the user's question using only the workspace_context and conversation history.

            Operating mode:
            \(resolvedModeInstructions)

            Operating rules:
            - Do not call tools.
            - Do not invent papers, file paths, todo items, or citations that are not present in workspace_context.
            - Respond in the same language as the latest user_goal unless the user explicitly asks for another language.
            - If the latest user_goal contains Chinese, answer in Simplified Chinese.
            - Paper snapshots are metadata-first. When `source_excerpt` is absent, you do not have the paper body; say what is known from metadata and what content would need a paper tool read.
            - Tool access is disabled in this mode. Do not guess equations, methods, claims, or section details from metadata-only paper snapshots.
            - Return only the user-facing answer as natural GitHub-flavored Markdown.
            - Do not return JSON, schema fields, tool_calls, summaries, or envelope metadata.

            Formatting rules:
            - Always separate ideas into short paragraphs with a blank line between them. Do not produce one giant paragraph.
            - Use `##` / `###` headings, bullet lists, numbered lists, blockquotes, and triple-backtick code fences when they help the reader.
            - Render inline math as `$...$` and display math as `$$...$$`. Never use Unicode pseudo-math, never wrap math in backticks. Example inline: `the rate $E_{\\odot}$`. Example display:
              $$
              E_{\\odot} = \\sum_{i} \\int_{0}^{R_{\\odot}} s(r)\\, n_{\\chi}(r)\\, 4\\pi r^{2}\\, dr.
              $$
            - Inside math, prefer `\\mathrm{rel}`, `\\boldsymbol{w}`, `\\dot{m}`, `\\hat{n}` for upright/bold/derivative/hat semantics rather than ad-hoc Unicode.
            - When citing a paper or section, include the paper title, paper id, or relative file path so the user can re-locate it.

            workspace_context:
            \(snapshotJSON)

            available_tools:
            \(toolsJSON)
            """
        }

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
        - Paper snapshots are metadata-first. Treat `source_excerpt` as paper body content only when it is present; otherwise use metadata only for identification and routing.
        - When the user asks for paper body content such as equations, methods, claims, comparisons, section summaries, quotations, or detailed evidence, plan paper tool calls before answering.
        - If the user refers to "the first paper", "第一篇", or an ordinal paper without a stable paper id, plan `list_papers` first to resolve the target paper before reading body content.
        - For equation/formula questions, especially evaporation-rate questions, plan `list_papers -> search_papers -> read_paper_section -> final_response_draft` unless a stable paper id and exact section are already known.
        - Prefer `search_papers` when the user gives keywords, symbols, formula names, or concepts; then use `read_paper_section` with the matched heading/path when a focused section is needed.
        - Prefer `read_paper_section` when the user names a section or heading. Use `read_paper` only for overview/page-based reading or when the target section is unknown.
        - Always pass a stable `paper_id` or relative path from workspace_context into paper tools, and cite the resulting paper id/title/path in user-facing text.
        - Return only one JSON object. Do not wrap it in Markdown.
        - In Conversation mode, `tool_calls` must be empty. `final_response_draft` may contain Markdown for readable answers.
        - When `final_response_draft` is populated, format it as GitHub-flavored Markdown with blank-line paragraph breaks, bullet/numbered lists when helpful, and math written as `$...$` (inline) or `$$...$$` (display). Never wrap math in backticks.
        - Final answers to paper formula questions must include the formula, the local context explaining what the symbols mean when available, and the source paper title/id/path. If no formula is found, state the search path and misses.

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
