import Foundation

public nonisolated struct ProjectDashboardAggregationInput: Sendable {
    public var workspaceID: String
    public var project: ResearchProject?
    public var papers: [Paper]
    public var todos: [TodoItem]
    public var markdownDocuments: [MarkdownDocument]
    public var agentRuns: [AgentRun]
    public var unsupportedClaims: [ClaimSummary]

    public init(
        workspaceID: String,
        project: ResearchProject?,
        papers: [Paper] = [],
        todos: [TodoItem] = [],
        markdownDocuments: [MarkdownDocument] = [],
        agentRuns: [AgentRun] = [],
        unsupportedClaims: [ClaimSummary] = []
    ) {
        self.workspaceID = workspaceID
        self.project = project
        self.papers = papers
        self.todos = todos
        self.markdownDocuments = markdownDocuments
        self.agentRuns = agentRuns
        self.unsupportedClaims = unsupportedClaims
    }

    public var signature: Int {
        var hasher = Hasher()
        hasher.combine(workspaceID)
        hasher.combine(project?.id)
        hasher.combine(project?.name)
        hasher.combine(project?.relativePath)
        hasher.combine(project?.updatedAt)
        for paper in papers.sorted(by: { $0.id < $1.id }) {
            hasher.combine(paper.id)
            hasher.combine(paper.projectIDs.sorted())
            hasher.combine(paper.coreProjectIDs.sorted())
            hasher.combine(paper.status.rawValue)
            hasher.combine(paper.priority.rawValue)
            hasher.combine(paper.updatedAt)
            hasher.combine(paper.lastReadAt)
        }
        for todo in todos.sorted(by: { $0.id < $1.id }) {
            hasher.combine(todo.id)
            hasher.combine(todo.status.rawValue)
            hasher.combine(todo.dueDate)
            hasher.combine(todo.priority.rawValue)
            hasher.combine(todo.projectIDs.sorted())
            hasher.combine(todo.updatedAt)
        }
        for document in markdownDocuments.sorted(by: { $0.relativePath < $1.relativePath }) {
            hasher.combine(document.relativePath)
            hasher.combine(document.title)
            hasher.combine(document.rawContents)
        }
        for run in agentRuns.sorted(by: { $0.id < $1.id }) {
            hasher.combine(run.id)
            hasher.combine(run.createdAt)
            hasher.combine(run.completedAt)
            hasher.combine(run.lifecycleState.rawValue)
            hasher.combine(run.failureCategory?.rawValue)
            hasher.combine(run.currentProjectID)
            hasher.combine(run.projectID)
            for result in run.toolResults {
                hasher.combine(result.callID)
                hasher.combine(result.toolName)
                hasher.combine(result.succeeded)
                hasher.combine(result.requiresConfirmation)
                hasher.combine(result.modifiedPaths.sorted())
                hasher.combine(result.payload?.canonicalJSON)
            }
        }
        hasher.combine(unsupportedClaims)
        return hasher.finalize()
    }
}

public actor ProjectDashboardAggregator {
    private struct CachedSnapshot: Sendable {
        var signature: Int
        var projectID: String
        var snapshot: ProjectDashboardSnapshot
    }

    private var cached: CachedSnapshot?
    private let cacheTTL: TimeInterval
    private let debugLogger: AppDebugEventLogger?
    private let debugRoot: ResearchRoot?

    public init(cacheTTL: TimeInterval = 60, debugLogger: AppDebugEventLogger? = nil, debugRoot: ResearchRoot? = nil) {
        self.cacheTTL = cacheTTL
        self.debugLogger = debugLogger
        self.debugRoot = debugRoot
    }

    public func snapshot(input: ProjectDashboardAggregationInput, now: Date = Date()) async throws -> ProjectDashboardSnapshot? {
        guard let project = input.project else {
            return nil
        }

        let signature = input.signature
        if let cached,
           cached.projectID == project.id,
           cached.signature == signature,
           now.timeIntervalSince(cached.snapshot.builtAt) < cacheTTL {
            return cached.snapshot
        }

        let snapshot = ProjectDashboardSnapshotBuilder().build(input: input, now: now)
        if let snapshot {
            cached = CachedSnapshot(signature: signature, projectID: project.id, snapshot: snapshot)
            await appendDebugEvent("project_dashboard.render", payload: snapshot.debugPayload)
            await appendDebugEvent("project_dashboard.stage_inferred", payload: .object([
                "project_id": .string(snapshot.projectID),
                "stage": .string(snapshot.stage.rawValue),
                "rule": .string(snapshot.stageRule)
            ]))
        }
        return snapshot
    }

    public func invalidate(reason: String? = nil) async {
        cached = nil
    }

    private func appendDebugEvent(_ event: String, payload: JSONValue) async {
        guard let debugLogger, let debugRoot else {
            return
        }
        try? await debugLogger.append(AppDebugEvent(event: event, payload: payload), in: debugRoot)
    }
}

public nonisolated struct ProjectDashboardSnapshotBuilder: Sendable {
    private let homeBuilder: HomeSnapshotBuilder

    public init(homeBuilder: HomeSnapshotBuilder = HomeSnapshotBuilder()) {
        self.homeBuilder = homeBuilder
    }

    public func build(input: ProjectDashboardAggregationInput, now: Date = Date()) -> ProjectDashboardSnapshot? {
        guard let project = input.project else {
            return nil
        }

        let start = Date()
        let projectPapers = input.papers.filter { $0.projectIDs.contains(project.id) }
        let corePapers = projectPapers
            .filter { $0.coreProjectIDs.contains(project.id) }
            .sorted { first, second in
                if first.priority != second.priority {
                    return prioritySortValue(first.priority) < prioritySortValue(second.priority)
                }
                return first.updatedAt > second.updatedAt
            }
            .prefix(6)
            .map(PaperSummary.init(paper:))
        let projectTodos = input.todos.filter { $0.projectIDs.contains(project.id) }
        let openProjectTodos = projectTodos.filter { $0.status != .done && $0.status != .cancelled }
        let openTodoCount = openProjectTodos.count
        let openTodos = openProjectTodos
            .sorted(by: TodoQueries.dueThenPriority)
            .prefix(5)
            .map(TodoSummary.init(todo:))
        let gaps = homeBuilder.gapSummaries(for: project.id, documents: input.markdownDocuments)
        let artifacts = homeBuilder.artifactSummaries(from: input.agentRuns)
            .filter { $0.projectID == project.id }
        let unsupportedClaimCount = input.unsupportedClaims
            .filter { $0.projectID == project.id }
            .reduce(0) { $0 + $1.count }
        let stageDecision = homeBuilder.stageDecision(
            for: project,
            papers: projectPapers,
            documents: input.markdownDocuments,
            gaps: gaps,
            todos: projectTodos,
            artifacts: artifacts,
            unsupportedClaimCount: unsupportedClaimCount,
            now: now
        )

        return ProjectDashboardSnapshot(
            projectID: project.id,
            projectTitle: project.name,
            stage: stageDecision.stage,
            stageRule: stageDecision.rule,
            corePapers: Array(corePapers),
            openGaps: Array(gaps.prefix(5)),
            recentArtifacts: Array(artifacts.prefix(3)),
            nextDeadline: homeBuilder.nextDeadline(from: projectTodos, after: now),
            currentReadingSummary: nil,
            openTodoCount: openTodoCount,
            openTodos: Array(openTodos),
            builtAt: now,
            generationDuration: Date().timeIntervalSince(start)
        )
    }

    private func prioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}
