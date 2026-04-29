import Foundation

public actor SciStationAgentService {
    private let contextBuilder: AgentWorkspaceContextBuilder
    private let planner: AgentPlanner
    private let toolRegistry: AgentToolRegistry
    private let toolExecutor: AgentToolExecutor
    private let runLogger: AgentRunLogger
    private let bridgeExporter: AgentCopilotBridgeExporter

    public init(
        provider: any LLMProvider,
        paperRepository: PaperRepository = PaperRepository(),
        todoRepository: TodoRepository = TodoRepository(),
        contextBuilder: AgentWorkspaceContextBuilder? = nil,
        toolRegistry: AgentToolRegistry? = nil,
        toolExecutor: AgentToolExecutor? = nil,
        runLogger: AgentRunLogger = AgentRunLogger(),
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

        let run = AgentRun(
            id: "agent-run-\(UUID().uuidString.lowercased())",
            goal: goal,
            createdAt: createdAt,
            completedAt: Date(),
            mode: options.mode,
            plan: plan,
            toolResults: toolResults,
            currentProjectID: currentProjectID
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
        let run = AgentRun(
            id: "agent-run-\(UUID().uuidString.lowercased())",
            goal: goal,
            createdAt: Date(),
            completedAt: Date(),
            mode: .executeApproved,
            plan: plan,
            toolResults: toolResults,
            currentProjectID: currentProjectID
        )
        try await runLogger.append(run, in: resolvedRoot)
        return run
    }

    public func recentRuns(in root: ResearchRoot, limit: Int = 5) async throws -> [AgentRun] {
        try await runLogger.recentRuns(in: root, limit: limit)
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
}