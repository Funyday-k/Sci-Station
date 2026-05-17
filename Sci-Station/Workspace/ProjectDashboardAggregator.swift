import Foundation

public nonisolated struct ProjectDashboardAggregationInput: Sendable {
    public var workspaceID: String
    public var project: ResearchProject?
    public var papers: [Paper]
    public var todos: [TodoItem]
    public var markdownDocuments: [MarkdownDocument]
    public var agentRuns: [AgentRun]
    public var unsupportedClaims: [ClaimSummary]
    /// P48 — Queue entries the AppViewModel exposes for the workspace plus all
    /// active projects. The snapshot builder filters down to the project of
    /// interest before rendering. Default empty for callers that have not yet
    /// wired the queue store.
    public var queueEntries: [ResearchQueueEntry]

    public init(
        workspaceID: String,
        project: ResearchProject?,
        papers: [Paper] = [],
        todos: [TodoItem] = [],
        markdownDocuments: [MarkdownDocument] = [],
        agentRuns: [AgentRun] = [],
        unsupportedClaims: [ClaimSummary] = [],
        queueEntries: [ResearchQueueEntry] = []
    ) {
        self.workspaceID = workspaceID
        self.project = project
        self.papers = papers
        self.todos = todos
        self.markdownDocuments = markdownDocuments
        self.agentRuns = agentRuns
        self.unsupportedClaims = unsupportedClaims
        self.queueEntries = queueEntries
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
        for entry in queueEntries.sorted(by: { $0.id < $1.id }) {
            hasher.combine(entry.id)
            hasher.combine(entry.status.rawValue)
            hasher.combine(entry.source.rawValue)
            hasher.combine(entry.order)
            hasher.combine(entry.lastTouchedAt)
            hasher.combine(entry.scope.identifier)
        }
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
        let openTodoCount = projectTodos.filter { $0.status != .done && $0.status != .cancelled }.count
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

        let projectPaperIDs = Set(projectPapers.map(\.id))
        let readingQueuePreview = readingQueuePreview(
            from: input.queueEntries,
            projectID: project.id,
            projectPaperIDs: projectPaperIDs
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
            currentReadingPlan: nil,
            openTodoCount: openTodoCount,
            builtAt: now,
            generationDuration: Date().timeIntervalSince(start),
            readingQueuePreview: readingQueuePreview
        )
    }

    private func readingQueuePreview(
        from entries: [ResearchQueueEntry],
        projectID: String,
        projectPaperIDs: Set<String>
    ) -> [ReadingQueueEntrySummary] {
        let projectScope = QueueScope.project(projectID).identifier
        let candidates = entries.filter { entry in
            guard entry.status == .queued || entry.status == .reading else {
                return false
            }
            if entry.scope.identifier == projectScope {
                return true
            }
            // Surface workspace-queue rows whose paper is linked to the
            // project so the project dashboard does not appear empty just
            // because the user added the paper at the workspace level.
            if entry.scope == .workspace, let paperID = entry.paperID {
                return projectPaperIDs.contains(paperID)
            }
            return false
        }
        return candidates
            .sorted { lhs, rhs in
                if lhs.lastTouchedAt != rhs.lastTouchedAt {
                    return lhs.lastTouchedAt > rhs.lastTouchedAt
                }
                return lhs.order < rhs.order
            }
            .prefix(3)
            .map(ReadingQueueEntrySummary.init(entry:))
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