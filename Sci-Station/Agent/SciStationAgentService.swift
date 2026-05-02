import Foundation

public actor SciStationAgentService {
    private let contextBuilder: AgentWorkspaceContextBuilder
    private let planner: AgentPlanner
    private let toolRegistry: AgentToolRegistry
    private let toolExecutor: AgentToolExecutor
    private let runLogger: AgentRunLogger
    private let sessionEventLogger: AgentSessionEventLogger
    private let threadRepository: AgentThreadRepository
    private let draftRepository: AgentPromptDraftRepository
    private let hookDefinitions: [AgentHookDefinition]

    public init(
        provider: any LLMProvider,
        paperRepository: PaperRepository = PaperRepository(),
        todoRepository: TodoRepository = TodoRepository(),
        markdownRepository: MarkdownRepository = MarkdownRepository(),
        contextBuilder: AgentWorkspaceContextBuilder? = nil,
        toolRegistry: AgentToolRegistry? = nil,
        toolExecutor: AgentToolExecutor? = nil,
        runLogger: AgentRunLogger = AgentRunLogger(),
        sessionEventLogger: AgentSessionEventLogger = AgentSessionEventLogger(),
        threadRepository: AgentThreadRepository = AgentThreadRepository(),
        draftRepository: AgentPromptDraftRepository = AgentPromptDraftRepository(),
        hookDefinitions: [AgentHookDefinition] = AgentSafetyPreset.defaultHooks()
    ) {
        let resolvedContextBuilder = contextBuilder ?? AgentWorkspaceContextBuilder(
            paperRepository: paperRepository,
            todoRepository: todoRepository
        )
        let resolvedToolRegistry = toolRegistry ?? AgentToolRegistry(tools: [
            ListPapersAgentTool(paperRepository: paperRepository),
            ReadPaperAgentTool(paperRepository: paperRepository),
            ReadPaperSectionAgentTool(paperRepository: paperRepository),
            SearchPapersAgentTool(paperRepository: paperRepository),
            CreateTodoAgentTool(todoRepository: todoRepository),
            UpdatePaperClassificationAgentTool(paperRepository: paperRepository),
            WriteMarkdownPlanAgentTool(markdownRepository: markdownRepository)
        ])

        self.contextBuilder = resolvedContextBuilder
        self.planner = AgentPlanner(provider: provider)
        self.toolRegistry = resolvedToolRegistry
        self.toolExecutor = toolExecutor ?? AgentToolExecutor(registry: resolvedToolRegistry)
        self.runLogger = runLogger
        self.sessionEventLogger = sessionEventLogger
        self.threadRepository = threadRepository
        self.draftRepository = draftRepository
        self.hookDefinitions = hookDefinitions
    }

    public func snapshot(
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        projects: [ResearchProject] = [],
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        includedPaperIDs: Set<String>? = nil,
        paperContextPolicy: AgentPaperContextPolicy = .metadataOnly
    ) async throws -> AgentWorkspaceSnapshot {
        try await contextBuilder.snapshot(
            in: workspace,
            root: root ?? ResearchRoot(rootURL: workspace.rootURL),
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID,
            includedPaperIDs: includedPaperIDs,
            paperContextPolicy: paperContextPolicy
        )
    }

    public func toolDefinitions() async -> [AgentToolDefinition] {
        await toolRegistry.definitions()
    }

    public func run(
        goal: String,
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        projects: [ResearchProject] = [],
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        includedPaperIDs: Set<String>? = nil,
        conversationHistory: [LLMChatMessage] = [],
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentExecutionOptions = AgentExecutionOptions(),
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AgentRun {
        let createdAt = Date()
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        let hookEngine = hookEngine(disabledHookIDs: options.disabledHookIDs)
        var hookResults = hookEngine.evaluate(
            AgentHookEvent(name: .sessionStart, prompt: goal)
        )
        hookResults.append(contentsOf: hookEngine.evaluate(
            AgentHookEvent(name: .userPromptSubmit, prompt: goal)
        ))
        let snapshot = try await contextBuilder.snapshot(
            in: workspace,
            root: resolvedRoot,
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID,
            includedPaperIDs: includedPaperIDs
        )
        let toolDefinitions = await filteredToolDefinitions(allowedToolNames: options.allowedToolNames)
        var plan = try await planner.plan(
            goal: goal,
            workspaceSnapshot: snapshot,
            tools: toolDefinitions,
            configuration: configuration,
            apiKey: apiKey,
            modeInstructions: options.plannerInstructions,
            conversationHistory: conversationHistory,
            allowsPlainTextResponse: options.allowsPlainTextResponse,
            responseDeltaHandler: responseDeltaHandler
        )
        if let allowedToolNames = options.allowedToolNames {
            plan.toolCalls = plan.toolCalls.filter { allowedToolNames.contains($0.toolName) }
        }
        let context = AgentToolContext(
            workspace: workspace,
            selectedPaperID: selectedPaperID,
            researchRoot: resolvedRoot,
            currentProjectID: currentProjectID,
            allowedPaperIDs: includedPaperIDs
        )
        for call in plan.toolCalls {
            hookResults.append(contentsOf: hookEngine.evaluate(
                AgentHookEvent(
                    name: .preToolUse,
                    toolName: call.toolName,
                    command: call.argumentsJSON,
                    prompt: goal
                )
            ))
        }
        let toolResults: [AgentToolResult]

        switch options.mode {
        case .planOnly:
            toolResults = []
        case .executeApproved:
            toolResults = await toolExecutor.execute(
                plan: plan,
                context: context,
                approvedToolCallIDs: options.approvedToolCallIDs
            )
        }

        let runID = "agent-run-\(UUID().uuidString.lowercased())"
        let run = AgentRun(
            id: runID,
            goal: goal,
            createdAt: createdAt,
            completedAt: Date(),
            mode: options.mode,
            plan: plan,
            toolResults: toolResults,
            currentProjectID: currentProjectID
        )
        try await runLogger.append(run, in: resolvedRoot)
        try await appendPlanningEvents(for: run, toolDefinitions: toolDefinitions, hookResults: hookResults, in: resolvedRoot)
        return run
    }

    public func executeApprovedPlan(
        goal: String,
        plan: AgentPlan,
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        includedPaperIDs: Set<String>? = nil,
        allowedToolNames: Set<String>? = nil,
        approvedToolCallIDs: Set<String>,
        deniedToolCallIDs: Set<String> = [],
        correctionFeedbackByCallID: [String: String] = [:],
        disabledHookIDs: Set<String> = []
    ) async throws -> AgentRun {
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        var executablePlan = plan
        if let allowedToolNames {
            executablePlan.toolCalls = executablePlan.toolCalls.filter { allowedToolNames.contains($0.toolName) }
        }
        let hookEngine = hookEngine(disabledHookIDs: disabledHookIDs)
        var hookResults: [AgentHookResult] = []
        for call in executablePlan.toolCalls {
            hookResults.append(contentsOf: hookEngine.evaluate(
                AgentHookEvent(
                    name: .preToolUse,
                    toolName: call.toolName,
                    command: call.argumentsJSON,
                    prompt: goal
                )
            ))
        }
        let context = AgentToolContext(
            workspace: workspace,
            selectedPaperID: selectedPaperID,
            researchRoot: resolvedRoot,
            currentProjectID: currentProjectID,
            allowedPaperIDs: includedPaperIDs
        )
        let toolResults = await toolExecutor.execute(
            plan: executablePlan,
            context: context,
            approvedToolCallIDs: approvedToolCallIDs
        )
        for result in toolResults {
            hookResults.append(contentsOf: hookEngine.evaluate(
                AgentHookEvent(
                    name: .postToolUse,
                    toolName: result.toolName,
                    modifiedPaths: result.modifiedPaths,
                    validationRecorded: result.succeeded
                )
            ))
        }
        hookResults.append(contentsOf: hookEngine.evaluate(
            AgentHookEvent(
                name: .stop,
                prompt: goal,
                modifiedPaths: toolResults.flatMap(\.modifiedPaths),
                validationRecorded: toolResults.allSatisfy(\.succeeded)
            )
        ))
        let runID = "agent-run-\(UUID().uuidString.lowercased())"
        let run = AgentRun(
            id: runID,
            goal: goal,
            createdAt: Date(),
            completedAt: Date(),
            mode: .executeApproved,
            plan: executablePlan,
            toolResults: toolResults,
            currentProjectID: currentProjectID
        )
        try await runLogger.append(run, in: resolvedRoot)
        try await appendExecutionEvents(
            for: run,
            approvedToolCallIDs: approvedToolCallIDs,
            deniedToolCallIDs: deniedToolCallIDs,
            correctionFeedbackByCallID: correctionFeedbackByCallID,
            hookResults: hookResults,
            in: resolvedRoot
        )
        return run
    }

    public func recentRuns(in root: ResearchRoot, limit: Int = 5) async throws -> [AgentRun] {
        try await runLogger.recentRuns(in: root, limit: limit)
    }

    public func recentRuns(in root: ResearchRoot, projectID: String?, limit: Int = 20) async throws -> [AgentRun] {
        try await runLogger.recentRuns(in: root, projectID: projectID, limit: limit)
    }

    public func threads(in root: ResearchRoot, projectID: ResearchProject.ID?) async throws -> [AgentThread] {
        try await threadRepository.threads(in: root, projectID: projectID)
    }

    public func allThreads(in root: ResearchRoot) async throws -> [AgentThread] {
        try await threadRepository.allThreads(in: root)
    }

    public func thread(id: AgentThread.ID, in root: ResearchRoot) async throws -> AgentThread? {
        try await threadRepository.thread(id: id, in: root)
    }

    public func upsertThread(_ thread: AgentThread, in root: ResearchRoot) async throws {
        try await threadRepository.upsert(thread, in: root)
    }

    public func draft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?, in root: ResearchRoot) async throws -> String? {
        try await draftRepository.draft(projectID: projectID, threadID: threadID, in: root)
    }

    public func saveDraft(_ text: String, projectID: ResearchProject.ID?, threadID: AgentThread.ID?, in root: ResearchRoot) async throws {
        try await draftRepository.saveDraft(text, projectID: projectID, threadID: threadID, in: root)
    }

    public func removeDraft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?, in root: ResearchRoot) async throws {
        try await draftRepository.removeDraft(projectID: projectID, threadID: threadID, in: root)
    }

    public func sessionEvents(in root: ResearchRoot, sessionID: String? = nil, limit: Int = 100) async throws -> [AgentSessionEvent] {
        try await sessionEventLogger.events(in: root, sessionID: sessionID, limit: limit)
    }

    private func appendPlanningEvents(
        for run: AgentRun,
        toolDefinitions: [AgentToolDefinition],
        hookResults: [AgentHookResult],
        in root: ResearchRoot
    ) async throws {
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.createdAt,
                kind: .userMessage,
                summary: run.goal
            ),
            in: root
        )
        if let reasoningSummary = reasoningSummary(for: run.plan, toolDefinitions: toolDefinitions) {
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    createdAt: run.createdAt.addingTimeInterval(0.001),
                    kind: .reasoningSummary,
                    summary: reasoningSummary.summary,
                    payloadJSON: reasoningSummary.payload
                ),
                in: root
            )
        }
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.completedAt ?? Date(),
                kind: .assistantMessage,
                summary: run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? run.plan.summary
            ),
            in: root
        )
        try await appendHookResults(hookResults, sessionID: run.id, in: root)

        let evaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
        for call in run.plan.toolCalls {
            let definition = toolDefinitions.first { $0.name == call.toolName }
            let risk = definition?.risk ?? .externalSideEffect
            let permissionKey = definition?.permissionKey ?? risk.defaultPermissionKey
            let decision = evaluator.evaluate(
                AgentPermissionRequest(
                    toolName: call.toolName,
                    permissionKey: permissionKey,
                    command: call.argumentsJSON,
                    risk: risk
                )
            )
            let eventKind: AgentSessionEventKind = decision.action == .ask ? .permissionRequested : .permissionResolved
            let decisionSummary: String
            switch decision.action {
            case .allow:
                decisionSummary = "Tool call \(call.toolName) is auto-allowed by \(decision.ruleID ?? "default policy")."
            case .ask:
                decisionSummary = "Tool call \(call.toolName) is waiting for explicit approval."
            case .deny:
                decisionSummary = "Tool call \(call.toolName) is denied by \(decision.ruleID ?? "default policy")."
            }
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    kind: eventKind,
                    summary: decisionSummary,
                    payloadJSON: call.argumentsJSON
                ),
                in: root
            )
        }
    }

    private func appendExecutionEvents(
        for run: AgentRun,
        approvedToolCallIDs: Set<String>,
        deniedToolCallIDs: Set<String>,
        correctionFeedbackByCallID: [String: String],
        hookResults: [AgentHookResult],
        in root: ResearchRoot
    ) async throws {
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.createdAt,
                kind: .userMessage,
                summary: run.goal
            ),
            in: root
        )
        for call in run.plan.toolCalls {
            if approvedToolCallIDs.contains(call.id) {
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        kind: .permissionResolved,
                        summary: "Allowed \(call.toolName) once for this execution.",
                        payloadJSON: call.argumentsJSON
                    ),
                    in: root
                )
            } else if deniedToolCallIDs.contains(call.id) {
                let feedback = correctionFeedbackByCallID[call.id]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        kind: .permissionResolved,
                        summary: ["Denied \(call.toolName).", feedback].compactMap { $0 }.joined(separator: " "),
                        payloadJSON: feedback
                    ),
                    in: root
                )
            }
        }
        try await appendHookResults(hookResults, sessionID: run.id, in: root)

        for call in run.plan.toolCalls where run.toolResults.contains(where: { $0.callID == call.id }) {
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    kind: .toolCallStarted,
                    summary: "Running \(call.toolName).",
                    payloadJSON: call.argumentsJSON
                ),
                in: root
            )
        }

        for result in run.toolResults {
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    kind: result.succeeded ? .toolCallCompleted : .toolCallFailed,
                    summary: result.message,
                    payloadJSON: result.modifiedPaths.joined(separator: "\n").nilIfEmpty
                ),
                in: root
            )
        }
    }

    private func reasoningSummary(
        for plan: AgentPlan,
        toolDefinitions: [AgentToolDefinition]
    ) -> (summary: String, payload: String?)? {
        let plannedTools = plan.toolCalls.map { call in
            let displayName = toolDefinitions.first { $0.name == call.toolName }?.displayName ?? call.toolName
            return "\(displayName) (`\(call.toolName)`)"
        }
        let summaryParts = [
            plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { "计划判断：\($0)" },
            plan.steps.isEmpty ? nil : "步骤：\(plan.steps.joined(separator: "；"))",
            plannedTools.isEmpty ? "未计划调用工具。" : "计划工具：\(plannedTools.joined(separator: "、"))。"
        ].compactMap { $0 }
        guard !summaryParts.isEmpty else {
            return nil
        }
        let payload = plan.toolCalls.isEmpty
            ? plan.steps.joined(separator: "\n").nilIfEmpty
            : plan.toolCalls.map { call in
                "tool: \(call.toolName)\narguments:\n\(call.argumentsJSON)"
            }.joined(separator: "\n\n")
        return (summaryParts.joined(separator: "\n"), payload)
    }

    private func appendHookResults(_ results: [AgentHookResult], sessionID: String, in root: ResearchRoot) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for result in results {
            let payloadData = try encoder.encode(result)
            let payload = String(data: payloadData, encoding: .utf8)
            let decisionSummary = result.permissionDecision.map { "Decision: \($0.rawValue)." }
            let summary = [
                "\(result.eventName.rawValue) hook \(result.hookID).",
                decisionSummary,
                result.message,
                result.additionalContext
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " ")

            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: sessionID,
                    kind: .hookResult,
                    summary: summary,
                    payloadJSON: payload
                ),
                in: root
            )
        }
    }

    private func hookEngine(disabledHookIDs: Set<String>) -> AgentHookEngine {
        AgentHookEngine(
            hooks: hookDefinitions.map { hook in
                var updatedHook = hook
                if disabledHookIDs.contains(hook.id) {
                    updatedHook.isEnabled = false
                }
                return updatedHook
            }
        )
    }

    private func filteredToolDefinitions(allowedToolNames: Set<String>?) async -> [AgentToolDefinition] {
        let definitions = await toolRegistry.definitions()
        guard let allowedToolNames else {
            return definitions
        }

        return definitions.filter { allowedToolNames.contains($0.name) }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}