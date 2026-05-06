import Foundation

public actor SciStationAgentService {
    private let provider: any LLMProvider
    private let contextBuilder: AgentWorkspaceContextBuilder
    private let planner: AgentPlanner
    private let toolRegistry: AgentToolRegistry
    private let toolHost: SciStationToolHost
    private let toolExecutor: AgentToolExecutor
    private let runLogger: AgentRunLogger
    private let sessionEventLogger: AgentSessionEventLogger
    private let loopRunner: AgentLoopRunner
    private let loopCheckpointStore: AgentLoopCheckpointStore
    private let legacyRuntime: LegacySwiftAgentRuntime
    private let sidecarCoordinator: SidecarRuntimeCoordinator
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
        sidecarCoordinator: SidecarRuntimeCoordinator = SidecarRuntimeCoordinator(),
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
            SearchWikiAgentTool(markdownRepository: markdownRepository),
            ReadWikiPageAgentTool(markdownRepository: markdownRepository),
            ListTasksAgentTool(todoRepository: todoRepository),
            ListMaterialsAgentTool(),
            CreateTodoAgentTool(todoRepository: todoRepository),
            UpdatePaperClassificationAgentTool(paperRepository: paperRepository),
            WriteMarkdownPlanAgentTool(markdownRepository: markdownRepository)
        ])
        let resolvedLoopCheckpointStore = AgentLoopCheckpointStore()
        let resolvedToolHost = SciStationToolHost(legacyRegistry: resolvedToolRegistry)
        let resolvedLoopRunner = AgentLoopRunner(sessionEventLogger: sessionEventLogger, checkpointStore: resolvedLoopCheckpointStore)

        self.provider = provider
        self.contextBuilder = resolvedContextBuilder
        self.planner = AgentPlanner(provider: provider)
        self.toolRegistry = resolvedToolRegistry
        self.toolHost = resolvedToolHost
        self.toolExecutor = toolExecutor ?? AgentToolExecutor(registry: resolvedToolRegistry)
        self.runLogger = runLogger
        self.sessionEventLogger = sessionEventLogger
        self.loopCheckpointStore = resolvedLoopCheckpointStore
        self.loopRunner = resolvedLoopRunner
        self.legacyRuntime = LegacySwiftAgentRuntime(loopRunner: resolvedLoopRunner)
        self.sidecarCoordinator = sidecarCoordinator
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
        await toolHost.definitions()
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
        if let denial = AgentDeterministicSafetyPolicy().evaluatePrompt(goal), denial.action == .deny {
            throw AgentError.invalidArguments(denial.message ?? "Prompt was blocked by the deterministic safety policy.")
        }
        let hookEngine = hookEngine(disabledHookIDs: options.disabledHookIDs)
        var hookResults = hookEngine.evaluate(
            AgentHookEvent(name: .sessionStart, prompt: goal)
        )
        hookResults.append(contentsOf: hookEngine.evaluate(
            AgentHookEvent(name: .userPromptSubmit, prompt: goal)
        ))
        if let deniedHook = hookResults.first(where: { $0.permissionDecision == .deny }) {
            throw AgentError.invalidArguments(deniedHook.message ?? "Prompt was blocked by an agent hook.")
        }
        let snapshot = try await contextBuilder.snapshot(
            in: workspace,
            root: resolvedRoot,
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID,
            includedPaperIDs: includedPaperIDs
        )
        let toolDefinitions = await filteredToolDefinitions(allowedToolNames: options.allowedToolNames)

        if options.loopPolicy == .readOnlyAutoApproveWritesRequireApproval,
           let chatProvider = provider as? any LLMChatProvider {
            let runID = "agent-run-\(UUID().uuidString.lowercased())"
            try await appendHookResults(hookResults, sessionID: runID, in: resolvedRoot)
            let context = AgentToolContext(
                workspace: workspace,
                selectedPaperID: selectedPaperID,
                researchRoot: resolvedRoot,
                currentProjectID: currentProjectID,
                allowedPaperIDs: includedPaperIDs
            )
            let messages = try AgentPromptBuilder().buildToolLoopChatMessages(
                goal: goal,
                workspaceSnapshot: snapshot,
                tools: toolDefinitions,
                conversationHistory: conversationHistory
            )
            let runtimeRequest = AgentRuntimeRequest(
                runID: runID,
                goal: goal,
                initialMessages: messages,
                provider: chatProvider,
                toolDefinitions: toolDefinitions,
                toolRegistry: toolRegistry,
                toolHost: toolHost,
                toolContext: context,
                root: resolvedRoot,
                configuration: configuration,
                apiKey: apiKey,
                options: AgentLoopOptions(),
                hookEngine: hookEngine,
                permissionEvaluator: AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
                enabledWorkflowIDs: options.enabledWorkflowIDs,
                responseDeltaHandler: responseDeltaHandler
            )
            let decision = await sidecarCoordinator.resolve(
                selection: options.runtimeSelection,
                sidecarDisabled: options.isSidecarDisabledForWorkspace,
                root: resolvedRoot
            )
            let runtime: any ExternalAgentRuntime = decision.shouldAttemptSidecar
                ? await sidecarCoordinator.langGraphRuntime(fallbackRuntime: legacyRuntime)
                : legacyRuntime
            let stream = try await runtime.startRun(runtimeRequest)
            var runtimeEvents: [AgentRuntimeEventEnvelope] = []
            for try await envelope in stream {
                runtimeEvents.append(envelope)
            }
            if let loopResult = await legacyRuntime.completedLoopResult(runID: runID) {
                let run = run(
                    from: loopResult,
                    goal: goal,
                    createdAt: createdAt,
                    currentProjectID: currentProjectID,
                    runtimeSelector: options.runtimeSelection.rawValue,
                    enabledToolNames: enabledToolNamesSnapshot(options.allowedToolNames, toolDefinitions: toolDefinitions),
                    retryOfRunID: options.retryOfRunID
                )
                try await runLogger.append(run, in: resolvedRoot)
                return run
            }
            let run = run(
                from: runtimeEvents,
                goal: goal,
                createdAt: createdAt,
                currentProjectID: currentProjectID,
                runtimeSelector: options.runtimeSelection.rawValue,
                enabledToolNames: enabledToolNamesSnapshot(options.allowedToolNames, toolDefinitions: toolDefinitions),
                retryOfRunID: options.retryOfRunID
            )
            try await runLogger.append(run, in: resolvedRoot)
            try await appendRuntimeSessionEvents(for: runtimeEvents, run: run, in: resolvedRoot)
            return run
        }

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
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            runtimeSelector: options.runtimeSelection.rawValue,
            createdFromRoute: "ai_lab",
            enabledToolNames: enabledToolNamesSnapshot(options.allowedToolNames, toolDefinitions: toolDefinitions),
            retryOfRunID: options.retryOfRunID
        )
        try await runLogger.append(run, in: resolvedRoot)
        try await appendPlanningEvents(for: run, toolDefinitions: toolDefinitions, hookResults: hookResults, in: resolvedRoot)
        return run
    }

    public func resumePendingToolCall(
        runID: String,
        action: AgentHumanDecisionAction,
        feedback: String? = nil,
        editedArgumentsJSON: String? = nil,
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        includedPaperIDs: Set<String>? = nil,
        allowedToolNames: Set<String>? = nil,
        disabledHookIDs: Set<String> = [],
        configuration: LLMConfiguration,
        apiKey: String,
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AgentRun {
        guard let chatProvider = provider as? any LLMChatProvider else {
            throw AgentError.invalidArguments("The configured provider does not support chat tool-loop resume.")
        }
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        guard let pending = try await loopCheckpointStore.pending(runID: runID, in: resolvedRoot) else {
            throw AgentError.invalidArguments("No pending tool call checkpoint was found for this run.")
        }
        let toolDefinitions = await filteredToolDefinitions(allowedToolNames: allowedToolNames)
        let context = AgentToolContext(
            workspace: workspace,
            selectedPaperID: selectedPaperID,
            researchRoot: resolvedRoot,
            currentProjectID: currentProjectID,
            allowedPaperIDs: includedPaperIDs
        )
        let loopResult = try await loopRunner.resume(
            AgentLoopResumeRequest(
                pending: pending,
                action: action,
                feedback: feedback,
                editedArgumentsJSON: editedArgumentsJSON,
                provider: chatProvider,
                toolDefinitions: toolDefinitions,
                toolRegistry: toolRegistry,
                toolHost: toolHost,
                toolContext: context,
                root: resolvedRoot,
                configuration: configuration,
                apiKey: apiKey,
                options: AgentLoopOptions(),
                hookEngine: hookEngine(disabledHookIDs: disabledHookIDs),
                permissionEvaluator: AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
                responseDeltaHandler: responseDeltaHandler
            )
        )
        let run = run(
            from: loopResult,
            goal: "Resume pending tool call",
            createdAt: Date(),
            currentProjectID: currentProjectID,
            runtimeSelector: nil,
            enabledToolNames: enabledToolNamesSnapshot(allowedToolNames, toolDefinitions: toolDefinitions)
        )
        try await runLogger.append(run, in: resolvedRoot)
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
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            createdFromRoute: "ai_lab",
            enabledToolNames: allowedToolNames?.sorted()
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

    public func recordFailedRun(
        goal: String,
        message: String,
        partialAssistantResponse: String? = nil,
        in root: ResearchRoot,
        currentProjectID: ResearchProject.ID? = nil,
        runtimeSelector: String? = nil,
        enabledToolNames: [String]? = nil,
        failureCategory: AgentRunFailureCategory = .unknown,
        retryOfRunID: String? = nil
    ) async throws -> AgentRun {
        let createdAt = Date()
        let trimmedPartial = partialAssistantResponse?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let summary = trimmedPartial ?? "Run failed: \(message)"
        let run = AgentRun(
            id: "agent-run-\(UUID().uuidString.lowercased())",
            goal: goal,
            createdAt: createdAt,
            completedAt: Date(),
            mode: .planOnly,
            plan: AgentPlan(
                title: "运行失败",
                summary: summary,
                risk: message,
                steps: ["Inline failure: \(message)"],
                toolCalls: [],
                finalResponseDraft: trimmedPartial
            ),
            toolResults: [],
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            runtimeSelector: runtimeSelector,
            createdFromRoute: "ai_lab",
            enabledToolNames: enabledToolNames,
            lifecycleState: .failed,
            failureCategory: failureCategory,
            retryOfRunID: retryOfRunID
        )
        try await runLogger.append(run, in: root)
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: createdAt,
                kind: .userMessage,
                summary: goal
            ),
            in: root
        )
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: createdAt.addingTimeInterval(0.001),
                kind: .toolCallFailed,
                summary: message,
                payloadJSON: trimmedPartial
            ),
            in: root
        )
        return run
    }

    public func recordCancelledRun(
        goal: String,
        message: String,
        partialAssistantResponse: String? = nil,
        in root: ResearchRoot,
        currentProjectID: ResearchProject.ID? = nil,
        runtimeSelector: String? = nil,
        enabledToolNames: [String]? = nil,
        retryOfRunID: String? = nil
    ) async throws -> AgentRun {
        let createdAt = Date()
        let trimmedPartial = partialAssistantResponse?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let run = AgentRun(
            id: "agent-run-\(UUID().uuidString.lowercased())",
            goal: goal,
            createdAt: createdAt,
            completedAt: Date(),
            mode: .planOnly,
            plan: AgentPlan(
                title: "已停止",
                summary: trimmedPartial ?? message,
                risk: message,
                steps: ["Cancelled: \(message)"],
                toolCalls: [],
                finalResponseDraft: trimmedPartial
            ),
            toolResults: [],
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            runtimeSelector: runtimeSelector,
            createdFromRoute: "ai_lab",
            enabledToolNames: enabledToolNames,
            lifecycleState: .cancelled,
            failureCategory: .cancelledByUser,
            retryOfRunID: retryOfRunID
        )
        try await runLogger.append(run, in: root)
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: createdAt,
                kind: .userMessage,
                summary: goal
            ),
            in: root
        )
        if let trimmedPartial {
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    createdAt: createdAt.addingTimeInterval(0.001),
                    kind: .assistantMessage,
                    summary: trimmedPartial
                ),
                in: root
            )
        }
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: createdAt.addingTimeInterval(0.002),
                kind: .runCancelled,
                summary: message
            ),
            in: root
        )
        return run
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
            guard decision.action != .allow else {
                continue
            }
            let eventKind: AgentSessionEventKind = decision.action == .ask ? .permissionRequested : .permissionResolved
            let decisionSummary: String
            switch decision.action {
            case .allow:
                continue
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
        let definitions = await toolHost.definitions()
        guard let allowedToolNames else {
            return definitions
        }

        return definitions.filter { allowedToolNames.contains($0.name) }
    }

    private nonisolated func enabledToolNamesSnapshot(_ allowedToolNames: Set<String>?, toolDefinitions: [AgentToolDefinition]) -> [String] {
        let names = allowedToolNames ?? Set(toolDefinitions.map(\.name))
        return names.sorted()
    }

    private func run(
        from loopResult: AgentLoopResult,
        goal: String,
        createdAt: Date,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String]?,
        retryOfRunID: String? = nil
    ) -> AgentRun {
        let toolCalls = loopResult.steps.flatMap(\.toolCalls)
        let finalResponse = loopResult.finalResponseMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let pauseSummary = loopResult.pauseReason?.message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let summary = finalResponse ?? pauseSummary ?? "Agent loop completed without a visible response."
        let steps = loopResult.steps.map { step in
            if let pause = step.pauseReason {
                return "Step \(step.stepIndex): \(pause.message)"
            }
            if step.toolCalls.isEmpty {
                return "Step \(step.stepIndex): assistant response"
            }
            return "Step \(step.stepIndex): tools \(step.toolCalls.map(\.toolName).joined(separator: ", "))"
        }
        let title: String
        if loopResult.pauseReason?.kind == .approvalRequired {
            title = "等待工具审批"
        } else if loopResult.pauseReason != nil && finalResponse == nil {
            title = "运行失败"
        } else {
            title = "对话回复"
        }
        let lifecycleState: AgentRunState
        let failureCategory: AgentRunFailureCategory?
        if loopResult.pauseReason?.kind == .approvalRequired {
            lifecycleState = .waitingForApproval
            failureCategory = nil
        } else if let pause = loopResult.pauseReason, finalResponse == nil {
            lifecycleState = .failed
            failureCategory = self.failureCategory(for: pause)
        } else {
            lifecycleState = .completed
            failureCategory = nil
        }
        return AgentRun(
            id: loopResult.runID,
            goal: goal,
            createdAt: createdAt,
            completedAt: loopResult.pauseReason?.kind == .approvalRequired ? nil : Date(),
            mode: .planOnly,
            plan: AgentPlan(
                title: title,
                summary: summary,
                risk: pauseSummary,
                steps: steps,
                toolCalls: toolCalls,
                finalResponseDraft: finalResponse
            ),
            toolResults: loopResult.toolResults,
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            runtimeSelector: runtimeSelector,
            createdFromRoute: "ai_lab",
            enabledToolNames: enabledToolNames,
            lifecycleState: lifecycleState,
            failureCategory: failureCategory,
            retryOfRunID: retryOfRunID
        )
    }

    private func run(
        from envelopes: [AgentRuntimeEventEnvelope],
        goal: String,
        createdAt: Date,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String]?,
        retryOfRunID: String? = nil
    ) -> AgentRun {
        let events = envelopes.map(\.event)
        let toolCalls = events.compactMap { event -> AgentToolCall? in
            if case let .toolCallRequested(payload) = event {
                return AgentToolCall(id: payload.toolCallID, toolName: payload.tool, argumentsJSON: payload.arguments.canonicalJSON)
            }
            if case let .approvalRequired(payload) = event {
                return AgentToolCall(id: payload.toolCallID, toolName: payload.tool, argumentsJSON: payload.arguments.canonicalJSON)
            }
            return nil
        }
        let toolResults = events.compactMap { event -> AgentToolResult? in
            if case let .toolCallCompleted(payload) = event {
                return payload.result.agentToolResult()
            }
            return nil
        }
        let finalResponse = events.compactMap { event -> String? in
            if case let .finalResponse(payload) = event {
                return payload.markdown.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            return nil
        }.last
        let pendingApproval = events.compactMap { event -> AgentApprovalRequest? in
            if case let .approvalRequired(payload) = event { return payload }
            return nil
        }.last
        let failure = events.compactMap { event -> AgentRuntimeError? in
            if case let .runFailed(payload) = event { return payload.error }
            if case let .sidecarUnavailable(payload) = event { return payload }
            if case let .sidecarCrashed(payload) = event { return payload }
            return nil
        }.last
        let artifactCount = events.filter { event in
            if case .artifactDraft = event { return true }
            return false
        }.count
        let steps = envelopes.map { envelope in
            "#\(envelope.sequence): \(runtimeEventSummary(envelope.event))"
        }
        let summary = finalResponse
            ?? pendingApproval.map { "Waiting for approval: \($0.tool)." }
            ?? failure.map { "Runtime fallback/error: \($0.message)" }
            ?? (artifactCount > 0 ? "Sidecar produced \(artifactCount) artifact draft(s)." : "Sidecar run completed without a visible response.")
        let lifecycleState: AgentRunState
        let failureCategory: AgentRunFailureCategory?
        if pendingApproval != nil {
            lifecycleState = .waitingForApproval
            failureCategory = nil
        } else if let failure, finalResponse == nil {
            lifecycleState = .failed
            failureCategory = self.failureCategory(for: failure)
        } else {
            lifecycleState = .completed
            failureCategory = nil
        }

        return AgentRun(
            id: envelopes.first?.runID ?? "agent-run-\(UUID().uuidString.lowercased())",
            goal: goal,
            createdAt: createdAt,
            completedAt: pendingApproval == nil && failure?.code != .approvalRequired ? Date() : nil,
            mode: .planOnly,
            plan: AgentPlan(
                title: pendingApproval == nil ? "LangGraph Sidecar" : "等待工具审批",
                summary: summary,
                risk: failure?.message,
                steps: steps,
                toolCalls: toolCalls,
                finalResponseDraft: finalResponse
            ),
            toolResults: toolResults,
            currentProjectID: currentProjectID,
            contextScope: AgentContextScope.inferred(projectID: currentProjectID),
            projectID: currentProjectID,
            runtimeSelector: runtimeSelector,
            createdFromRoute: "ai_lab",
            enabledToolNames: enabledToolNames,
            lifecycleState: lifecycleState,
            failureCategory: failureCategory,
            retryOfRunID: retryOfRunID
        )
    }

    private nonisolated func failureCategory(for pause: AgentLoopPauseReason) -> AgentRunFailureCategory {
        switch pause.kind {
        case .approvalRequired:
            return .approvalRequired
        case .providerUnavailable:
            return .providerUnavailable
        case .safetyPolicyBlocked:
            return .safetyBlocked
        case .deniedAndStopped:
            return .toolFailure
        case .contextLimitExceeded, .maxStepsExceeded, .maxToolCallsExceeded:
            return .providerError
        }
    }

    private nonisolated func failureCategory(for error: AgentRuntimeError) -> AgentRunFailureCategory {
        switch error.code {
        case .approvalRequired:
            return .approvalRequired
        case .providerUnavailable:
            return .providerUnavailable
        case .sidecarUnavailable, .sidecarCrashed:
            return .runtimeUnavailable
        case .toolNotFound, .toolSchemaInvalid, .permissionDenied, .checkpointNotFound:
            return .toolFailure
        case .safetyPolicyBlocked:
            return .safetyBlocked
        case .maxStepsExceeded, .maxToolCallsExceeded, .contextLimitExceeded:
            return .providerError
        case .invalidRequest, .internalError:
            return .providerError
        }
    }

    private func appendRuntimeSessionEvents(
        for envelopes: [AgentRuntimeEventEnvelope],
        run: AgentRun,
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

        for envelope in envelopes {
            let event = envelope.event
            switch event {
            case let .artifactDraft(artifact):
                let payloadData = try SidecarJSONCodec.encoder.encode(artifact)
                let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .reasoningSummary,
                        summary: "Artifact draft: \(artifact.title)",
                        payloadJSON: payload
                    ),
                    in: root
                )
            case let .approvalRequired(approval):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .permissionRequested,
                        summary: "Sidecar requested approval for \(approval.tool).",
                        payloadJSON: approval.arguments.canonicalJSON
                    ),
                    in: root
                )
            case let .toolCallRequested(call):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .toolCallStarted,
                        summary: "Sidecar requested \(call.tool).",
                        payloadJSON: call.arguments.canonicalJSON
                    ),
                    in: root
                )
            case let .toolCallCompleted(call):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: call.result.succeeded ? .toolCallCompleted : .toolCallFailed,
                        summary: runtimeToolEventSummary(tool: call.tool, result: call.result),
                        payloadJSON: call.result.content
                    ),
                    in: root
                )
            case let .finalResponse(response):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .assistantMessage,
                        summary: response.markdown
                    ),
                    in: root
                )
            case let .runFailed(failure):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .assistantMessage,
                        summary: "Run failed: \(failure.error.message)"
                    ),
                    in: root
                )
            case let .sidecarUnavailable(error), let .sidecarCrashed(error), let .fallbackToLegacyRuntime(error):
                try await sessionEventLogger.append(
                    AgentSessionEvent(
                        sessionID: run.id,
                        createdAt: envelope.timestamp,
                        kind: .reasoningSummary,
                        summary: runtimeEventSummary(event),
                        payloadJSON: error.message
                    ),
                    in: root
                )
            default:
                break
            }
        }
    }

    private nonisolated func runtimeEventSummary(_ event: AgentRuntimeEvent) -> String {
        switch event {
        case let .runStarted(payload): return "run started: \(payload.goal)"
        case let .nodeStarted(payload): return "node started: \(payload.name)"
        case .assistantDelta: return "assistant delta"
        case let .assistantMessage(payload): return "assistant message: \(payload.content.prefix(80))"
        case let .toolCallRequested(payload): return "tool requested: \(payload.tool)"
        case let .toolCallCompleted(payload): return "tool completed: \(payload.tool)"
        case let .approvalRequired(payload): return "approval required: \(payload.tool)"
        case let .artifactDraft(payload): return "artifact draft: \(payload.kind)"
        case let .checkpointSaved(payload): return "checkpoint saved: \(payload.state.rawValue)"
        case .finalResponse: return "final response"
        case let .runCancelled(payload): return "run cancelled: \(payload.reason ?? "cancelled")"
        case let .runFailed(payload): return "run failed: \(payload.error.message)"
        case .sidecarStarting: return "sidecar starting"
        case .sidecarReady: return "sidecar ready"
        case let .sidecarUnavailable(payload): return "sidecar unavailable: \(payload.message)"
        case let .sidecarCrashed(payload): return "sidecar crashed: \(payload.message)"
        case let .fallbackToLegacyRuntime(payload): return "fallback to Swift Loop: \(payload.message)"
        }
    }

    private nonisolated func runtimeToolEventSummary(tool: String, result: AgentToolResultWireFormat) -> String {
        if result.succeeded {
            return "已使用工具：\(tool)"
        }
        return "工具 \(tool) 失败：\(result.error ?? result.summary)"
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
