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
    private let bridgeExporter: AgentCopilotBridgeExporter

    public init(
        provider: any LLMProvider,
        paperRepository: PaperRepository = PaperRepository(),
        todoRepository: TodoRepository = TodoRepository(),
        contextBuilder: AgentWorkspaceContextBuilder? = nil,
        toolRegistry: AgentToolRegistry? = nil,
        toolExecutor: AgentToolExecutor? = nil,
        runLogger: AgentRunLogger = AgentRunLogger(),
        sessionEventLogger: AgentSessionEventLogger = AgentSessionEventLogger(),
        threadRepository: AgentThreadRepository = AgentThreadRepository(),
        draftRepository: AgentPromptDraftRepository = AgentPromptDraftRepository(),
        bridgeExporter: AgentCopilotBridgeExporter = AgentCopilotBridgeExporter()
    ) {
        let resolvedContextBuilder = contextBuilder ?? AgentWorkspaceContextBuilder(
            paperRepository: paperRepository,
            todoRepository: todoRepository
        )
        let resolvedToolRegistry = toolRegistry ?? AgentToolRegistry(tools: [
            CreateTodoAgentTool(todoRepository: todoRepository),
            UpdatePaperClassificationAgentTool(paperRepository: paperRepository)
        ])

        self.contextBuilder = resolvedContextBuilder
        self.planner = AgentPlanner(provider: provider)
        self.toolRegistry = resolvedToolRegistry
        self.toolExecutor = toolExecutor ?? AgentToolExecutor(registry: resolvedToolRegistry)
        self.runLogger = runLogger
        self.sessionEventLogger = sessionEventLogger
        self.threadRepository = threadRepository
        self.draftRepository = draftRepository
        self.bridgeExporter = bridgeExporter
    }

    public func snapshot(
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        projects: [ResearchProject] = [],
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil
    ) async throws -> AgentWorkspaceSnapshot {
        try await contextBuilder.snapshot(
            in: workspace,
            root: root ?? ResearchRoot(rootURL: workspace.rootURL),
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID
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
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentExecutionOptions = AgentExecutionOptions()
    ) async throws -> AgentRun {
        let createdAt = Date()
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        let snapshot = try await contextBuilder.snapshot(
            in: workspace,
            root: resolvedRoot,
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID
        )
        let toolDefinitions = await toolRegistry.definitions()
        let plan = try await planner.plan(
            goal: goal,
            workspaceSnapshot: snapshot,
            tools: toolDefinitions,
            configuration: configuration,
            apiKey: apiKey
        )
        let context = AgentToolContext(
            workspace: workspace,
            selectedPaperID: selectedPaperID,
            researchRoot: resolvedRoot,
            currentProjectID: currentProjectID
        )
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
        try await appendPlanningEvents(for: run, in: resolvedRoot)
        return run
    }

    public func executeApprovedPlan(
        goal: String,
        plan: AgentPlan,
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        approvedToolCallIDs: Set<String>
    ) async throws -> AgentRun {
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        let context = AgentToolContext(
            workspace: workspace,
            selectedPaperID: selectedPaperID,
            researchRoot: resolvedRoot,
            currentProjectID: currentProjectID
        )
        let toolResults = await toolExecutor.execute(
            plan: plan,
            context: context,
            approvedToolCallIDs: approvedToolCallIDs
        )
        let runID = "agent-run-\(UUID().uuidString.lowercased())"
        let run = AgentRun(
            id: runID,
            goal: goal,
            createdAt: Date(),
            completedAt: Date(),
            mode: .executeApproved,
            plan: plan,
            toolResults: toolResults,
            currentProjectID: currentProjectID
        )
        try await runLogger.append(run, in: resolvedRoot)
        try await appendExecutionEvents(for: run, in: resolvedRoot)
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

    public func exportCopilotBridge(
        goal: String,
        in workspace: ResearchWorkspace,
        root: ResearchRoot? = nil,
        projects: [ResearchProject] = [],
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil
    ) async throws -> AgentCopilotBridgeExport {
        let resolvedRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        let workspaceSnapshot = try await snapshot(
            in: workspace,
            root: resolvedRoot,
            projects: projects,
            currentProjectID: currentProjectID,
            selectedPaperID: selectedPaperID
        )
        let tools = await toolDefinitions()
        return try await bridgeExporter.export(
            goal: goal,
            workspaceSnapshot: workspaceSnapshot,
            tools: tools,
            in: resolvedRoot
        )
    }

    public func sessionEvents(in root: ResearchRoot, sessionID: String? = nil, limit: Int = 100) async throws -> [AgentSessionEvent] {
        try await sessionEventLogger.events(in: root, sessionID: sessionID, limit: limit)
    }

    private func appendPlanningEvents(for run: AgentRun, in root: ResearchRoot) async throws {
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.createdAt,
                kind: .userMessage,
                summary: run.goal
            ),
            in: root
        )
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.completedAt ?? Date(),
                kind: .assistantMessage,
                summary: run.plan.summary
            ),
            in: root
        )

        for call in run.plan.toolCalls {
            try await sessionEventLogger.append(
                AgentSessionEvent(
                    sessionID: run.id,
                    kind: .permissionRequested,
                    summary: "Tool call \(call.toolName) is waiting for explicit approval.",
                    payloadJSON: call.argumentsJSON
                ),
                in: root
            )
        }
    }

    private func appendExecutionEvents(for run: AgentRun, in root: ResearchRoot) async throws {
        try await sessionEventLogger.append(
            AgentSessionEvent(
                sessionID: run.id,
                createdAt: run.createdAt,
                kind: .userMessage,
                summary: run.goal
            ),
            in: root
        )

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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}