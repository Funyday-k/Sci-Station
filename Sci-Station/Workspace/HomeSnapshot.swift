import Foundation

public nonisolated struct HomeSnapshot: Codable, Hashable, Sendable {
    public var today: TodayPanelData
    public var activeProjects: [ActiveProjectData]
    public var aiReview: AIReviewPanelData
    public var builtAt: Date
    public var generationDuration: TimeInterval
    public var moduleAvailability: HomeModuleAvailability

    public init(
        today: TodayPanelData,
        activeProjects: [ActiveProjectData],
        aiReview: AIReviewPanelData,
        builtAt: Date,
        generationDuration: TimeInterval,
        moduleAvailability: HomeModuleAvailability = HomeModuleAvailability()
    ) {
        self.today = today
        self.activeProjects = activeProjects
        self.aiReview = aiReview
        self.builtAt = builtAt
        self.generationDuration = generationDuration
        self.moduleAvailability = moduleAvailability
    }

    public var debugPayload: JSONValue {
        .object([
            "duration_ms": .number(String(Int((generationDuration * 1000).rounded()))),
            "today_due": .number(String(today.dueTodos.count)),
            "today_drafts": .number(String(today.pendingDrafts.count)),
            "active_projects": .number(String(activeProjects.count)),
            "ai_unsupported_claims": .number(String(aiReview.unsupportedClaims.count)),
            "ai_stale_evidence": .number(String(aiReview.staleEvidenceWarnings.count))
        ])
    }
}

public nonisolated struct HomeModuleAvailability: Codable, Hashable, Sendable {
    public var tasksEnabled: Bool
    public var libraryEnabled: Bool
    public var projectsEnabled: Bool
    public var draftInboxEnabled: Bool
    public var aiLabEnabled: Bool

    public init(
        tasksEnabled: Bool = true,
        libraryEnabled: Bool = true,
        projectsEnabled: Bool = true,
        draftInboxEnabled: Bool = true,
        aiLabEnabled: Bool = true
    ) {
        self.tasksEnabled = tasksEnabled
        self.libraryEnabled = libraryEnabled
        self.projectsEnabled = projectsEnabled
        self.draftInboxEnabled = draftInboxEnabled
        self.aiLabEnabled = aiLabEnabled
    }
}

public nonisolated struct TodayPanelData: Codable, Hashable, Sendable {
    public var dueTodos: [TodoSummary]
    /// P42 heuristic list of recently-prioritised papers, kept as a fallback
    /// when the P48 queue is empty so the Today panel never goes blank.
    public var readingQueue: [PaperSummary]
    public var upcomingDeadlines: [DeadlineSummary]
    public var pendingDrafts: [DraftSummary]

    public init(
        dueTodos: [TodoSummary] = [],
        readingQueue: [PaperSummary] = [],
        upcomingDeadlines: [DeadlineSummary] = [],
        pendingDrafts: [DraftSummary] = []
    ) {
        self.dueTodos = dueTodos
        self.readingQueue = readingQueue
        self.upcomingDeadlines = upcomingDeadlines
        self.pendingDrafts = pendingDrafts
    }

    private enum CodingKeys: String, CodingKey {
        case dueTodos
        case readingQueue
        case upcomingDeadlines
        case pendingDrafts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dueTodos = try container.decodeIfPresent([TodoSummary].self, forKey: .dueTodos) ?? []
        self.readingQueue = try container.decodeIfPresent([PaperSummary].self, forKey: .readingQueue) ?? []
        self.upcomingDeadlines = try container.decodeIfPresent([DeadlineSummary].self, forKey: .upcomingDeadlines) ?? []
        self.pendingDrafts = try container.decodeIfPresent([DraftSummary].self, forKey: .pendingDrafts) ?? []
    }
}

public nonisolated struct TodoSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var dueDate: Date?
    public var priority: Priority
    public var projectIDs: [String]
    public var status: TodoStatus

    public init(
        id: String,
        title: String,
        dueDate: Date?,
        priority: Priority,
        projectIDs: [String],
        status: TodoStatus
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.projectIDs = projectIDs
        self.status = status
    }

    public init(todo: TodoItem) {
        self.init(
            id: todo.id,
            title: todo.title,
            dueDate: todo.dueDate,
            priority: todo.priority,
            projectIDs: todo.projectIDs,
            status: todo.status
        )
    }
}

public nonisolated struct PaperSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var authors: String
    public var status: ReadingStatus
    public var priority: Priority
    public var projectIDs: [String]
    public var updatedAt: Date
    public var lastReadAt: Date?

    public init(
        id: String,
        title: String,
        authors: String,
        status: ReadingStatus,
        priority: Priority,
        projectIDs: [String],
        updatedAt: Date,
        lastReadAt: Date?
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.status = status
        self.priority = priority
        self.projectIDs = projectIDs
        self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
    }

    public init(paper: Paper) {
        self.init(
            id: paper.id,
            title: paper.displayTitle,
            authors: paper.authorsDisplay,
            status: paper.status,
            priority: paper.priority,
            projectIDs: paper.projectIDs,
            updatedAt: paper.updatedAt,
            lastReadAt: paper.lastReadAt
        )
    }
}

public nonisolated struct DeadlineSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var dueDate: Date
    public var projectIDs: [String]
    public var source: String
    public var priority: Priority?

    public init(
        id: String,
        title: String,
        dueDate: Date,
        projectIDs: [String],
        source: String,
        priority: Priority? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.projectIDs = projectIDs
        self.source = source
        self.priority = priority
    }
}

public nonisolated struct DraftSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var projectID: String?
    public var runID: String
    public var createdAt: Date
    public var status: String
    public var routeID: String

    public init(
        id: String,
        title: String,
        projectID: String?,
        runID: String,
        createdAt: Date,
        status: String,
        routeID: String
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.runID = runID
        self.createdAt = createdAt
        self.status = status
        self.routeID = routeID
    }
}

public nonisolated struct ActiveProjectData: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var projectID: String
    public var stage: ProjectStage
    public var stageRule: String
    public var coreCount: Int
    public var recentPaperCount: Int
    public var openGapsCount: Int
    public var openTodoCount: Int
    public var latestArtifact: ArtifactSummary?
    public var nextDeadline: DeadlineSummary?

    public init(
        projectID: String,
        title: String,
        stage: ProjectStage,
        stageRule: String,
        coreCount: Int,
        recentPaperCount: Int,
        openGapsCount: Int,
        openTodoCount: Int,
        latestArtifact: ArtifactSummary? = nil,
        nextDeadline: DeadlineSummary? = nil
    ) {
        self.id = projectID
        self.projectID = projectID
        self.title = title
        self.stage = stage
        self.stageRule = stageRule
        self.coreCount = coreCount
        self.recentPaperCount = recentPaperCount
        self.openGapsCount = openGapsCount
        self.openTodoCount = openTodoCount
        self.latestArtifact = latestArtifact
        self.nextDeadline = nextDeadline
    }
}

public nonisolated struct AIReviewPanelData: Codable, Hashable, Sendable {
    public var needsApproval: [DraftSummary]
    public var unsupportedClaims: [ClaimSummary]
    public var staleEvidenceWarnings: [EvidenceWarningSummary]

    public init(
        needsApproval: [DraftSummary] = [],
        unsupportedClaims: [ClaimSummary] = [],
        staleEvidenceWarnings: [EvidenceWarningSummary] = []
    ) {
        self.needsApproval = needsApproval
        self.unsupportedClaims = unsupportedClaims
        self.staleEvidenceWarnings = staleEvidenceWarnings
    }
}

public nonisolated struct ClaimSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var runID: String
    public var projectID: String?
    public var title: String
    public var count: Int
    public var createdAt: Date
    public var routeID: String

    public init(id: String, runID: String, projectID: String?, title: String, count: Int, createdAt: Date, routeID: String) {
        self.id = id
        self.runID = runID
        self.projectID = projectID
        self.title = title
        self.count = count
        self.createdAt = createdAt
        self.routeID = routeID
    }
}

public nonisolated struct EvidenceWarningSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var runID: String?
    public var projectID: String?
    public var title: String
    public var count: Int
    public var createdAt: Date
    public var routeID: String

    public init(id: String, runID: String?, projectID: String?, title: String, count: Int, createdAt: Date, routeID: String) {
        self.id = id
        self.runID = runID
        self.projectID = projectID
        self.title = title
        self.count = count
        self.createdAt = createdAt
        self.routeID = routeID
    }
}

public nonisolated struct ArtifactSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var runID: String
    public var projectID: String?
    public var title: String
    public var kind: String
    public var status: String
    public var savedAt: Date
    public var targetPath: String?
    public var evidenceCount: Int

    public init(
        id: String,
        runID: String,
        projectID: String?,
        title: String,
        kind: String,
        status: String,
        savedAt: Date,
        targetPath: String? = nil,
        evidenceCount: Int = 0
    ) {
        self.id = id
        self.runID = runID
        self.projectID = projectID
        self.title = title
        self.kind = kind
        self.status = status
        self.savedAt = savedAt
        self.targetPath = targetPath
        self.evidenceCount = evidenceCount
    }
}

public nonisolated struct GapSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var relativePath: String?

    public init(id: String, title: String, relativePath: String? = nil) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
    }
}

public nonisolated struct ProjectDashboardSnapshot: Codable, Hashable, Sendable {
    public var projectID: String
    public var projectTitle: String
    public var stage: ProjectStage
    public var stageRule: String
    public var corePapers: [PaperSummary]
    public var openGaps: [GapSummary]
    public var recentArtifacts: [ArtifactSummary]
    public var nextDeadline: DeadlineSummary?
    /// Persisted from `projects/<id>/wiki/research_plan.md` (P50 surfaces it).
    /// Kept untouched so the existing "Current Reading Plan" card still works.
    public var currentReadingPlan: String?
    public var openTodoCount: Int
    public var builtAt: Date
    public var generationDuration: TimeInterval

    public init(
        projectID: String,
        projectTitle: String,
        stage: ProjectStage,
        stageRule: String,
        corePapers: [PaperSummary],
        openGaps: [GapSummary],
        recentArtifacts: [ArtifactSummary],
        nextDeadline: DeadlineSummary?,
        currentReadingPlan: String?,
        openTodoCount: Int,
        builtAt: Date,
        generationDuration: TimeInterval
    ) {
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.stage = stage
        self.stageRule = stageRule
        self.corePapers = corePapers
        self.openGaps = openGaps
        self.recentArtifacts = recentArtifacts
        self.nextDeadline = nextDeadline
        self.currentReadingPlan = currentReadingPlan
        self.openTodoCount = openTodoCount
        self.builtAt = builtAt
        self.generationDuration = generationDuration
    }

    private enum CodingKeys: String, CodingKey {
        case projectID
        case projectTitle
        case stage
        case stageRule
        case corePapers
        case openGaps
        case recentArtifacts
        case nextDeadline
        case currentReadingPlan
        case openTodoCount
        case builtAt
        case generationDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectID = try container.decode(String.self, forKey: .projectID)
        self.projectTitle = try container.decode(String.self, forKey: .projectTitle)
        self.stage = try container.decode(ProjectStage.self, forKey: .stage)
        self.stageRule = try container.decode(String.self, forKey: .stageRule)
        self.corePapers = try container.decodeIfPresent([PaperSummary].self, forKey: .corePapers) ?? []
        self.openGaps = try container.decodeIfPresent([GapSummary].self, forKey: .openGaps) ?? []
        self.recentArtifacts = try container.decodeIfPresent([ArtifactSummary].self, forKey: .recentArtifacts) ?? []
        self.nextDeadline = try container.decodeIfPresent(DeadlineSummary.self, forKey: .nextDeadline)
        self.currentReadingPlan = try container.decodeIfPresent(String.self, forKey: .currentReadingPlan)
        self.openTodoCount = try container.decodeIfPresent(Int.self, forKey: .openTodoCount) ?? 0
        self.builtAt = try container.decode(Date.self, forKey: .builtAt)
        self.generationDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .generationDuration) ?? 0
    }

    public var debugPayload: JSONValue {
        .object([
            "project_id": .string(projectID),
            "duration_ms": .number(String(Int((generationDuration * 1000).rounded()))),
            "stage": .string(stage.rawValue),
            "recent_artifacts_count": .number(String(recentArtifacts.count))
        ])
    }
}