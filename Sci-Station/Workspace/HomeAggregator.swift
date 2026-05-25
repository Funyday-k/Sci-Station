import Foundation

public nonisolated struct HomeAggregationInput: Sendable {
    public var workspaceID: String
    public var currentProjectID: String?
    public var projects: [ResearchProject]
    public var papers: [Paper]
    public var todos: [TodoItem]
    public var markdownDocuments: [MarkdownDocument]
    public var agentRuns: [AgentRun]
    public var sessionEvents: [AgentSessionEvent]
    public var retrievalIndexStatus: AgentEmbeddingIndexStatusSnapshot
    public var moduleConfiguration: WorkspaceModuleConfiguration
    public var failureReason: String?
    /// P48 — Real queue entries the AppViewModel has loaded for the active
    /// workspace and project. Optional; default empty for callers that have
    /// not yet wired the queue store.
    public var queueEntries: [ResearchQueueEntry]
    public var activeReadingPlan: ReadingPlanSummary?

    public init(
        workspaceID: String,
        currentProjectID: String? = nil,
        projects: [ResearchProject] = [],
        papers: [Paper] = [],
        todos: [TodoItem] = [],
        markdownDocuments: [MarkdownDocument] = [],
        agentRuns: [AgentRun] = [],
        sessionEvents: [AgentSessionEvent] = [],
        retrievalIndexStatus: AgentEmbeddingIndexStatusSnapshot = AgentEmbeddingIndexStatusSnapshot.disabled(),
        moduleConfiguration: WorkspaceModuleConfiguration = WorkspaceModuleRegistry.defaultConfiguration(),
        failureReason: String? = nil,
        queueEntries: [ResearchQueueEntry] = [],
        activeReadingPlan: ReadingPlanSummary? = nil
    ) {
        self.workspaceID = workspaceID
        self.currentProjectID = currentProjectID
        self.projects = projects
        self.papers = papers
        self.todos = todos
        self.markdownDocuments = markdownDocuments
        self.agentRuns = agentRuns
        self.sessionEvents = sessionEvents
        self.retrievalIndexStatus = retrievalIndexStatus
        self.moduleConfiguration = moduleConfiguration
        self.failureReason = failureReason
        self.queueEntries = queueEntries
        self.activeReadingPlan = activeReadingPlan
    }

    public var signature: Int {
        var hasher = Hasher()
        hasher.combine(workspaceID)
        hasher.combine(currentProjectID)
        for project in projects.sorted(by: { $0.id < $1.id }) {
            hasher.combine(project.id)
            hasher.combine(project.name)
            hasher.combine(project.relativePath)
            hasher.combine(project.isArchived)
            hasher.combine(project.updatedAt)
        }
        for paper in papers.sorted(by: { $0.id < $1.id }) {
            hasher.combine(paper.id)
            hasher.combine(paper.projectIDs.sorted())
            hasher.combine(paper.coreProjectIDs.sorted())
            hasher.combine(paper.status.rawValue)
            hasher.combine(paper.priority.rawValue)
            hasher.combine(paper.createdAt)
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
            hasher.combine(run.plan.title)
            hasher.combine(run.plan.summary)
            for result in run.toolResults {
                hasher.combine(result.callID)
                hasher.combine(result.toolName)
                hasher.combine(result.succeeded)
                hasher.combine(result.requiresConfirmation)
                hasher.combine(result.modifiedPaths.sorted())
                hasher.combine(result.payload?.canonicalJSON)
            }
        }
        for event in sessionEvents.sorted(by: { $0.id < $1.id }) {
            hasher.combine(event.id)
            hasher.combine(event.sessionID)
            hasher.combine(event.createdAt)
            hasher.combine(event.kind.rawValue)
        }
        hasher.combine(retrievalIndexStatus)
        hasher.combine(moduleConfiguration)
        hasher.combine(failureReason)
        for entry in queueEntries.sorted(by: { $0.id < $1.id }) {
            hasher.combine(entry.id)
            hasher.combine(entry.status.rawValue)
            hasher.combine(entry.source.rawValue)
            hasher.combine(entry.order)
            hasher.combine(entry.lastTouchedAt)
            hasher.combine(entry.scope.identifier)
        }
        hasher.combine(activeReadingPlan)
        return hasher.finalize()
    }
}

public enum HomeAggregationError: LocalizedError, Sendable {
    case buildFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .buildFailed(reason):
            return reason
        }
    }
}

public actor HomeAggregator {
    private struct CachedSnapshot: Sendable {
        var signature: Int
        var snapshot: HomeSnapshot
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

    public func snapshot(input: HomeAggregationInput, now: Date = Date()) async throws -> HomeSnapshot {
        let signature = input.signature
        if let cached,
           cached.signature == signature,
           now.timeIntervalSince(cached.snapshot.builtAt) < cacheTTL {
            return cached.snapshot
        }

        do {
            let snapshot = try HomeSnapshotBuilder().build(input: input, now: now)
            cached = CachedSnapshot(signature: signature, snapshot: snapshot)
            await appendDebugEvent("home.aggregate", payload: snapshot.debugPayload)
            return snapshot
        } catch {
            await appendDebugEvent("home.aggregate.error", payload: .object([
                "panel": .string("home"),
                "reason": .string(error.localizedDescription)
            ]))
            throw error
        }
    }

    public func invalidate(reason: String? = nil) async {
        cached = nil
        if let reason {
            await appendDebugEvent("home.cache.invalidate", payload: .object([
                "reason": .string(reason)
            ]))
        }
    }

    private func appendDebugEvent(_ event: String, payload: JSONValue) async {
        guard let debugLogger, let debugRoot else {
            return
        }
        try? await debugLogger.append(AppDebugEvent(event: event, payload: payload), in: debugRoot)
    }
}

public nonisolated struct HomeSnapshotBuilder: Sendable {
    private let calendar: Calendar
    private let stageProvider: ProjectStageProvider

    public init(calendar: Calendar = .current, stageProvider: ProjectStageProvider = ProjectStageProvider()) {
        self.calendar = calendar
        self.stageProvider = stageProvider
    }

    public func build(input: HomeAggregationInput, now: Date = Date()) throws -> HomeSnapshot {
        if let reason = input.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            throw HomeAggregationError.buildFailed(reason)
        }

        let start = Date()
        let moduleAvailability = moduleAvailability(in: input.moduleConfiguration)
        let today = buildToday(input: input, now: now, moduleAvailability: moduleAvailability)
        let artifacts = artifactSummaries(from: input.agentRuns)
        let aiReview = buildAIReview(input: input, artifacts: artifacts, now: now, moduleAvailability: moduleAvailability)
        let activeProjects = buildActiveProjects(input: input, artifacts: artifacts, aiReview: aiReview, now: now, moduleAvailability: moduleAvailability)

        return HomeSnapshot(
            today: today,
            activeProjects: activeProjects,
            aiReview: aiReview,
            builtAt: now,
            generationDuration: Date().timeIntervalSince(start),
            moduleAvailability: moduleAvailability
        )
    }

    private func buildToday(
        input: HomeAggregationInput,
        now: Date,
        moduleAvailability: HomeModuleAvailability
    ) -> TodayPanelData {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let horizon = calendar.date(byAdding: .day, value: 14, to: startOfToday) ?? now

        let openTodos = input.todos.filter(isOpen)
        let dueTodos = moduleAvailability.tasksEnabled ? openTodos
            .filter { todo in
                guard let dueDate = todo.dueDate else { return false }
                return dueDate < endOfToday
            }
            .sorted(by: todoSort)
            .prefix(8)
            .map(TodoSummary.init(todo:)) : []

        let upcomingDeadlines = moduleAvailability.tasksEnabled ? openTodos
            .compactMap { todo -> DeadlineSummary? in
                guard let dueDate = todo.dueDate,
                      dueDate >= endOfToday,
                      dueDate < horizon else {
                    return nil
                }
                return DeadlineSummary(
                    id: "todo-\(todo.id)",
                    title: todo.title,
                    dueDate: dueDate,
                    projectIDs: todo.projectIDs,
                    source: "todo",
                    priority: todo.priority
                )
            }
            .sorted(by: deadlineSort)
            .prefix(8)
            .map { $0 } : []

        let readingQueue = moduleAvailability.libraryEnabled ? readingQueue(from: input.papers) : []
        let readingQueueEntries: [ReadingQueueEntrySummary] = moduleAvailability.libraryEnabled
            ? input.queueEntries
                .filter { $0.status == .queued || $0.status == .reading }
                .sorted { lhs, rhs in
                    if lhs.lastTouchedAt != rhs.lastTouchedAt {
                        return lhs.lastTouchedAt > rhs.lastTouchedAt
                    }
                    return lhs.order < rhs.order
                }
                .prefix(10)
                .map(ReadingQueueEntrySummary.init(entry:))
            : []
        let pendingDrafts = moduleAvailability.aiLabEnabled ? draftSummaries(from: input.agentRuns, projectID: input.currentProjectID)
            .prefix(6)
            .map { $0 } : []

        return TodayPanelData(
            dueTodos: dueTodos,
            readingQueue: readingQueue,
            upcomingDeadlines: upcomingDeadlines,
            pendingDrafts: pendingDrafts,
            readingQueueEntries: readingQueueEntries,
            activeReadingPlan: input.activeReadingPlan
        )
    }

    private func buildActiveProjects(
        input: HomeAggregationInput,
        artifacts: [ArtifactSummary],
        aiReview: AIReviewPanelData,
        now: Date,
        moduleAvailability: HomeModuleAvailability
    ) -> [ActiveProjectData] {
        guard moduleAvailability.projectsEnabled else {
            return []
        }

        let activeProjects = input.projects.filter { !$0.isArchived }
        return activeProjects.map { project in
            let projectPapers = input.papers.filter { $0.projectIDs.contains(project.id) }
            let coreCount = projectPapers.filter { $0.coreProjectIDs.contains(project.id) }.count
            let recentPaperCount = projectPapers.filter { paper in
                let activityDate = paper.lastReadAt ?? paper.updatedAt
                return now.timeIntervalSince(activityDate) <= 14 * 86_400
            }.count
            let gaps = gapSummaries(for: project.id, documents: input.markdownDocuments)
            let projectTodos = input.todos.filter { $0.projectIDs.contains(project.id) }
            let openTodoCount = projectTodos.filter(isOpen).count
            let projectArtifacts = artifacts.filter { $0.projectID == project.id }
            let nextDeadline = nextDeadline(from: projectTodos)
            let unsupportedCount = aiReview.unsupportedClaims
                .filter { $0.projectID == project.id }
                .reduce(0) { $0 + $1.count }
            let stageDecision = stageDecision(
                for: project,
                papers: projectPapers,
                documents: input.markdownDocuments,
                gaps: gaps,
                todos: projectTodos,
                artifacts: projectArtifacts,
                unsupportedClaimCount: unsupportedCount,
                now: now
            )

            return ActiveProjectData(
                projectID: project.id,
                title: project.name,
                stage: stageDecision.stage,
                stageRule: stageDecision.rule,
                coreCount: coreCount,
                recentPaperCount: recentPaperCount,
                openGapsCount: gaps.count,
                openTodoCount: openTodoCount,
                latestArtifact: projectArtifacts.first,
                nextDeadline: nextDeadline
            )
        }
        .sorted { first, second in
            if first.nextDeadline?.dueDate != second.nextDeadline?.dueDate {
                return (first.nextDeadline?.dueDate ?? .distantFuture) < (second.nextDeadline?.dueDate ?? .distantFuture)
            }
            return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }

    private func buildAIReview(
        input: HomeAggregationInput,
        artifacts: [ArtifactSummary],
        now: Date,
        moduleAvailability: HomeModuleAvailability
    ) -> AIReviewPanelData {
        guard moduleAvailability.aiLabEnabled || moduleAvailability.draftInboxEnabled else {
            return AIReviewPanelData()
        }

        let needsApproval = draftSummaries(from: input.agentRuns, projectID: nil)
        let unsupportedClaims = claimSummaries(from: input.agentRuns)
        var staleWarnings = staleEvidenceSummaries(from: input.agentRuns)

        if input.retrievalIndexStatus.staleCount > 0 {
            staleWarnings.insert(EvidenceWarningSummary(
                id: "retrieval-index-stale",
                runID: nil,
                projectID: input.currentProjectID,
                title: "Retrieval index has stale source chunks",
                count: input.retrievalIndexStatus.staleCount,
                createdAt: now,
                routeID: "settings/retrieval-index"
            ), at: 0)
        }

        let artifactWarnings = artifacts
            .filter { $0.status == "needs_review" && $0.evidenceCount == 0 }
            .map { artifact in
                EvidenceWarningSummary(
                    id: "artifact-weak-evidence-\(artifact.id)",
                    runID: artifact.runID,
                    projectID: artifact.projectID,
                    title: "Artifact draft has no evidence references",
                    count: 1,
                    createdAt: artifact.savedAt,
                    routeID: "draft-inbox/\(artifact.id)?tab=evidence"
                )
            }

        staleWarnings.append(contentsOf: artifactWarnings)

        return AIReviewPanelData(
            needsApproval: Array(needsApproval.prefix(8)),
            unsupportedClaims: Array(unsupportedClaims.prefix(8)),
            staleEvidenceWarnings: Array(staleWarnings.sorted { $0.createdAt > $1.createdAt }.prefix(8))
        )
    }

    public func stageDecision(
        for project: ResearchProject,
        papers: [Paper],
        documents: [MarkdownDocument],
        gaps: [GapSummary],
        todos: [TodoItem],
        artifacts: [ArtifactSummary],
        unsupportedClaimCount: Int,
        now: Date = Date()
    ) -> ProjectStageDecision {
        let projectWikiPrefix = project.relativePath + "/wiki/"
        let wikiPageCount = documents.filter { $0.relativePath.hasPrefix(projectWikiPrefix) }.count
        let lastActivityAt = ([project.updatedAt] + papers.map { $0.lastReadAt ?? $0.updatedAt } + todos.map(\.updatedAt) + artifacts.map(\.savedAt)).max()

        return stageProvider.stage(for: ProjectStageSignal(
            projectID: project.id,
            papersCount: papers.count,
            wikiPageCount: wikiPageCount,
            openGapsCount: gaps.count,
            artifactKinds: artifacts.map(\.kind),
            unsupportedClaimCount: unsupportedClaimCount,
            lastActivityAt: lastActivityAt
        ), today: now)
    }

    public func artifactSummaries(from runs: [AgentRun]) -> [ArtifactSummary] {
        runs.flatMap { run in
            run.toolResults.compactMap { result -> ArtifactSummary? in
                     if let payload = result.payload,
                         let draft = artifactDraft(from: payload) {
                    return ArtifactSummary(
                        id: draft.id,
                        runID: run.id,
                        projectID: run.projectID ?? run.currentProjectID,
                        title: draft.title,
                        kind: draft.kind,
                        status: result.requiresConfirmation ? "needs_review" : (result.succeeded ? "saved" : "failed"),
                        savedAt: run.completedAt ?? run.createdAt,
                        targetPath: draft.proposedPath,
                        evidenceCount: draft.evidenceRefs.count
                    )
                }

                guard !result.modifiedPaths.isEmpty else {
                    return nil
                }

                let kind = artifactKind(from: result)
                return ArtifactSummary(
                    id: "\(run.id)-\(result.callID)-\(kind)",
                    runID: run.id,
                    projectID: run.projectID ?? run.currentProjectID,
                    title: nonEmpty(result.message) ?? kind.replacingOccurrences(of: "_", with: " ").capitalized,
                    kind: kind,
                    status: result.succeeded ? "saved" : "failed",
                    savedAt: run.completedAt ?? run.createdAt,
                    targetPath: result.modifiedPaths.first,
                    evidenceCount: 0
                )
            }
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    public func gapSummaries(for projectID: String, documents: [MarkdownDocument]) -> [GapSummary] {
        documents
            .filter { document in
                document.relativePath.contains("/wiki/gaps/") || document.relativePath.hasPrefix("wiki/gaps/")
            }
            .filter { document in
                document.relativePath.contains(projectID) || !document.relativePath.hasPrefix("projects/")
            }
            .map { document in
                GapSummary(id: document.relativePath, title: document.title, relativePath: document.relativePath)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func nextDeadline(from todos: [TodoItem], after now: Date = Date()) -> DeadlineSummary? {
        todos
            .filter(isOpen)
            .compactMap { todo -> DeadlineSummary? in
                guard let dueDate = todo.dueDate, dueDate >= calendar.startOfDay(for: now) else {
                    return nil
                }
                return DeadlineSummary(
                    id: "todo-\(todo.id)",
                    title: todo.title,
                    dueDate: dueDate,
                    projectIDs: todo.projectIDs,
                    source: "todo",
                    priority: todo.priority
                )
            }
            .sorted(by: deadlineSort)
            .first
    }

    private func moduleAvailability(in configuration: WorkspaceModuleConfiguration) -> HomeModuleAvailability {
        let catalog = PluginWorkspaceContributionCatalog(configuration: configuration)
        let routeIDs = Set(catalog.availableRoutes().map(\.id))
        let tabIDs = Set(catalog.availableProjectTabs().map(\.id))
        return HomeModuleAvailability(
            tasksEnabled: routeIDs.contains("tasks") || tabIDs.contains("tasks"),
            libraryEnabled: routeIDs.contains("library") || tabIDs.contains("papers"),
            projectsEnabled: routeIDs.contains("projects") || tabIDs.contains("overview"),
            draftInboxEnabled: routeIDs.contains("draft-inbox"),
            aiLabEnabled: routeIDs.contains("ai-lab") || tabIDs.contains("ai-drafts")
        )
    }

    private func readingQueue(from papers: [Paper]) -> [PaperSummary] {
        let prioritizedStatuses: Set<ReadingStatus> = [.unread, .skimmed, .deepRead]
        return Array(papers
            .filter { paper in
                paper.status != .rejected && (prioritizedStatuses.contains(paper.status) || paper.priority == .urgent || paper.priority == .high)
            }
            .sorted { first, second in
                let firstPriority = paperPrioritySortValue(first)
                let secondPriority = paperPrioritySortValue(second)
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }
                return first.updatedAt > second.updatedAt
            }
            .prefix(10)
            .map(PaperSummary.init(paper:)))
    }

    private func draftSummaries(from runs: [AgentRun], projectID: String?) -> [DraftSummary] {
        runs
            .filter { run in
                if let projectID, (run.projectID ?? run.currentProjectID) != projectID {
                    return false
                }
                if run.lifecycleState == .waitingForApproval || run.failureCategory == .approvalRequired {
                    return true
                }
                return run.toolResults.contains { $0.requiresConfirmation }
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { run in
                DraftSummary(
                    id: "draft-\(run.id)",
                    title: nonEmpty(run.plan.title) ?? nonEmpty(run.plan.summary) ?? run.goal,
                    projectID: run.projectID ?? run.currentProjectID,
                    runID: run.id,
                    createdAt: run.createdAt,
                    status: run.lifecycleState == .waitingForApproval ? "needs_review" : "approval_required",
                    routeID: "draft-inbox/\(run.id)?tab=evidence"
                )
            }
    }

    private func claimSummaries(from runs: [AgentRun]) -> [ClaimSummary] {
        runs.flatMap { run in
            run.toolResults.compactMap { result -> ClaimSummary? in
                guard let payload = result.payload,
                      let report = decode(AgentCitationCriticReport.self, from: payload),
                      !report.unsupportedClaims.isEmpty else {
                    return nil
                }
                return ClaimSummary(
                    id: "unsupported-\(run.id)-\(result.callID)",
                    runID: run.id,
                    projectID: run.projectID ?? run.currentProjectID,
                    title: nonEmpty(run.plan.title) ?? run.goal,
                    count: report.unsupportedClaims.count,
                    createdAt: run.completedAt ?? run.createdAt,
                    routeID: "draft-inbox/\(run.id)?tab=evidence"
                )
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func staleEvidenceSummaries(from runs: [AgentRun]) -> [EvidenceWarningSummary] {
        runs.flatMap { run in
            run.toolResults.compactMap { result -> EvidenceWarningSummary? in
                guard let payload = result.payload,
                      let report = decode(AgentCitationCriticReport.self, from: payload),
                      !report.staleEvidence.isEmpty else {
                    return nil
                }
                return EvidenceWarningSummary(
                    id: "stale-\(run.id)-\(result.callID)",
                    runID: run.id,
                    projectID: run.projectID ?? run.currentProjectID,
                    title: nonEmpty(run.plan.title) ?? run.goal,
                    count: report.staleEvidence.count,
                    createdAt: run.completedAt ?? run.createdAt,
                    routeID: "draft-inbox/\(run.id)?tab=evidence"
                )
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
        guard let data = try? AgentRunDirectoryStore.encoder().encode(value) else {
            return nil
        }
        return try? AgentRunDirectoryStore.decoder().decode(T.self, from: data)
    }

    private func artifactDraft(from value: JSONValue) -> AgentArtifactDraft? {
        if let draft = decode(AgentArtifactDraft.self, from: value) {
            return draft
        }
        guard let nested = value.objectValue?["graph_insight_draft"] else {
            return nil
        }
        return decode(AgentArtifactDraft.self, from: nested)
    }

    private func artifactKind(from result: AgentToolResult) -> String {
        let normalizedTool = result.toolName.lowercased()
        if normalizedTool.contains("related") {
            return "related_work"
        }
        if normalizedTool.contains("plan") {
            return "research_plan"
        }
        if normalizedTool.contains("revision") {
            return "writing_revision"
        }
        return normalizedTool.isEmpty ? "workspace_artifact" : normalizedTool
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func isOpen(_ todo: TodoItem) -> Bool {
        todo.status != .done && todo.status != .cancelled
    }

    private func todoSort(_ first: TodoItem, _ second: TodoItem) -> Bool {
        if first.dueDate != second.dueDate {
            return (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }
        let firstPriority = todoPrioritySortValue(first.priority)
        let secondPriority = todoPrioritySortValue(second.priority)
        if firstPriority != secondPriority {
            return firstPriority < secondPriority
        }
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }

    private func deadlineSort(_ first: DeadlineSummary, _ second: DeadlineSummary) -> Bool {
        if first.dueDate != second.dueDate {
            return first.dueDate < second.dueDate
        }
        return (first.priority.map(todoPrioritySortValue) ?? 99) < (second.priority.map(todoPrioritySortValue) ?? 99)
    }

    private func todoPrioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    private func paperPrioritySortValue(_ paper: Paper) -> Int {
        let priorityScore = todoPrioritySortValue(paper.priority)
        let statusScore: Int
        switch paper.status {
        case .deepRead: statusScore = 0
        case .skimmed: statusScore = 1
        case .unread: statusScore = 2
        case .summarized: statusScore = 3
        case .used: statusScore = 4
        case .rejected: statusScore = 9
        }
        return priorityScore * 10 + statusScore
    }
}