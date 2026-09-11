import Combine
import Foundation

@MainActor
struct LoadedWorkspaceState<State> {
    let workspace: ResearchWorkspace
    let state: State
}

@MainActor
enum WorkspaceStateLoader {
    static func load<State>(
        workspace: ResearchWorkspace,
        operation: () async throws -> State
    ) async throws -> LoadedWorkspaceState<State> {
        try Task.checkCancellation()
        let state = try await operation()
        try Task.checkCancellation()
        return LoadedWorkspaceState(workspace: workspace, state: state)
    }
}

/// Focused application state stores that keep domain observers from depending
/// on the full AppViewModel surface. They live in the Core target so state
/// transitions can be exercised by standard Swift Testing suites.
@MainActor
final class WorkspaceStore: ObservableObject {
    struct State {
        let workspace: ResearchWorkspace?
        let root: ResearchRoot?
        let projects: [ResearchProject]
        let currentProjectID: ResearchProject.ID?
    }

    @Published private(set) var workspace: ResearchWorkspace?
    @Published private(set) var root: ResearchRoot?
    @Published private(set) var projects: [ResearchProject] = []
    @Published private(set) var currentProjectID: ResearchProject.ID?

    func setWorkspace(_ workspace: ResearchWorkspace?) { self.workspace = workspace }
    func setRoot(_ root: ResearchRoot?) { self.root = root }
    func setProjects(_ projects: [ResearchProject]) { self.projects = projects }
    func setCurrentProjectID(_ projectID: ResearchProject.ID?) { currentProjectID = projectID }

    func snapshot() -> State {
        State(workspace: workspace, root: root, projects: projects, currentProjectID: currentProjectID)
    }

    func restore(_ state: State) {
        workspace = state.workspace
        root = state.root
        projects = state.projects
        currentProjectID = state.currentProjectID
    }

    func reset() {
        workspace = nil
        root = nil
        projects = []
        currentProjectID = nil
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    struct State {
        let papers: [Paper]
        let projectLinks: [ProjectPaperLink]
        let collections: [PaperCollection]
        let tags: [TagDefinition]
        let selectedPaperIDs: Set<Paper.ID>
    }

    @Published private(set) var papers: [Paper] = []
    @Published private(set) var projectLinks: [ProjectPaperLink] = []
    @Published private(set) var collections: [PaperCollection] = []
    @Published private(set) var tags: [TagDefinition] = []
    @Published private(set) var selectedPaperIDs: Set<Paper.ID> = []

    func setPapers(_ papers: [Paper]) { self.papers = papers }
    func setProjectLinks(_ links: [ProjectPaperLink]) { projectLinks = links }
    func setCollections(_ collections: [PaperCollection]) { self.collections = collections }
    func setTags(_ tags: [TagDefinition]) { self.tags = tags }
    func setSelectedPaperIDs(_ ids: Set<Paper.ID>) { selectedPaperIDs = ids }

    func snapshot() -> State {
        State(
            papers: papers,
            projectLinks: projectLinks,
            collections: collections,
            tags: tags,
            selectedPaperIDs: selectedPaperIDs
        )
    }

    func restore(_ state: State) {
        papers = state.papers
        projectLinks = state.projectLinks
        collections = state.collections
        tags = state.tags
        selectedPaperIDs = state.selectedPaperIDs
    }

    func reset() {
        papers = []
        projectLinks = []
        collections = []
        tags = []
        selectedPaperIDs = []
    }
}

@MainActor
final class KnowledgeStore: ObservableObject {
    struct State {
        let documents: [MarkdownDocument]
        let selectedDocumentID: String?
        let selectedDraft: MarkdownDocument?
        let saveState: MarkdownSaveState
        let saveErrorMessage: String?
    }

    @Published private(set) var documents: [MarkdownDocument] = []
    @Published private(set) var selectedDocumentID: String?
    @Published private(set) var selectedDraft: MarkdownDocument?
    @Published private(set) var saveState = MarkdownSaveState.clean
    @Published private(set) var saveErrorMessage: String?

    func setDocuments(_ documents: [MarkdownDocument]) { self.documents = documents }
    func setSelection(id: String?, draft: MarkdownDocument?) {
        selectedDocumentID = id
        selectedDraft = draft
    }
    func setSaveState(_ state: MarkdownSaveState, errorMessage: String?) {
        saveState = state
        saveErrorMessage = errorMessage
    }

    func snapshot() -> State {
        State(
            documents: documents,
            selectedDocumentID: selectedDocumentID,
            selectedDraft: selectedDraft,
            saveState: saveState,
            saveErrorMessage: saveErrorMessage
        )
    }

    func restore(_ state: State) {
        documents = state.documents
        selectedDocumentID = state.selectedDocumentID
        selectedDraft = state.selectedDraft
        saveState = state.saveState
        saveErrorMessage = state.saveErrorMessage
    }

    func reset() {
        documents = []
        selectedDocumentID = nil
        selectedDraft = nil
        saveState = .clean
        saveErrorMessage = nil
    }
}

@MainActor
final class RecommendationStore: ObservableObject {
    struct State {
        let runResult: RecommendationRunResult?
        let history: [RecommendationRunResult]
        let feedbackByScoreID: [String: RecommendationFeedbackType]
        let candidateCount: Int
        let isRefreshing: Bool
        let isEvaluatingWithAI: Bool
        let errorMessage: String?
        let aiEvaluationStatusMessage: String?
    }

    @Published private(set) var runResult: RecommendationRunResult?
    @Published private(set) var history: [RecommendationRunResult] = []
    @Published private(set) var feedbackByScoreID: [String: RecommendationFeedbackType] = [:]
    @Published private(set) var candidateCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isEvaluatingWithAI = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var aiEvaluationStatusMessage: String?

    func setRunResult(_ result: RecommendationRunResult?) { runResult = result }
    func setHistory(_ history: [RecommendationRunResult]) { self.history = history }
    func setFeedback(_ feedback: [String: RecommendationFeedbackType]) { feedbackByScoreID = feedback }
    func setCandidateCount(_ count: Int) { candidateCount = count }
    func setRefreshing(_ value: Bool) { isRefreshing = value }
    func setEvaluatingWithAI(_ value: Bool) { isEvaluatingWithAI = value }
    func setErrorMessage(_ message: String?) { errorMessage = message }
    func setAIEvaluationStatusMessage(_ message: String?) { aiEvaluationStatusMessage = message }

    func snapshot() -> State {
        State(
            runResult: runResult,
            history: history,
            feedbackByScoreID: feedbackByScoreID,
            candidateCount: candidateCount,
            isRefreshing: isRefreshing,
            isEvaluatingWithAI: isEvaluatingWithAI,
            errorMessage: errorMessage,
            aiEvaluationStatusMessage: aiEvaluationStatusMessage
        )
    }

    func restore(_ state: State) {
        runResult = state.runResult
        history = state.history
        feedbackByScoreID = state.feedbackByScoreID
        candidateCount = state.candidateCount
        isRefreshing = state.isRefreshing
        isEvaluatingWithAI = state.isEvaluatingWithAI
        errorMessage = state.errorMessage
        aiEvaluationStatusMessage = state.aiEvaluationStatusMessage
    }

    func reset() {
        runResult = nil
        history = []
        feedbackByScoreID = [:]
        candidateCount = 0
        isRefreshing = false
        isEvaluatingWithAI = false
        errorMessage = nil
        aiEvaluationStatusMessage = nil
    }
}

@MainActor
final class AgentStore: ObservableObject {
    struct State {
        let currentRun: AgentRun?
        let runHistory: [AgentRun]
        let threads: [AgentThread]
        let toolDefinitions: [AgentToolDefinition]
        let statusMessage: String?
        let errorMessage: String?
    }

    @Published private(set) var currentRun: AgentRun?
    @Published private(set) var runHistory: [AgentRun] = []
    @Published private(set) var threads: [AgentThread] = []
    @Published private(set) var toolDefinitions: [AgentToolDefinition] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    func setCurrentRun(_ run: AgentRun?) { currentRun = run }
    func setRunHistory(_ history: [AgentRun]) { runHistory = history }
    func setThreads(_ threads: [AgentThread]) { self.threads = threads }
    func setToolDefinitions(_ definitions: [AgentToolDefinition]) { toolDefinitions = definitions }
    func setStatusMessage(_ message: String?) { statusMessage = message }
    func setErrorMessage(_ message: String?) { errorMessage = message }

    func snapshot() -> State {
        State(
            currentRun: currentRun,
            runHistory: runHistory,
            threads: threads,
            toolDefinitions: toolDefinitions,
            statusMessage: statusMessage,
            errorMessage: errorMessage
        )
    }

    func restore(_ state: State) {
        currentRun = state.currentRun
        runHistory = state.runHistory
        threads = state.threads
        toolDefinitions = state.toolDefinitions
        statusMessage = state.statusMessage
        errorMessage = state.errorMessage
    }

    func reset() {
        currentRun = nil
        runHistory = []
        threads = []
        toolDefinitions = []
        statusMessage = nil
        errorMessage = nil
    }
}

@MainActor
final class NavigationStore: ObservableObject {
    struct State {
        let selectedSection: WorkspaceSection?
        let selectedProjectID: ResearchProject.ID?
        let selectedProjectTabID: String
        let isViewingGlobalTodos: Bool
        let selectedSettingsCategory: SettingsCategory
        let shellWindowWidth: Double
        let isShellNarrowWidth: Bool
    }

    @Published var selectedSection: WorkspaceSection? = .projects
    @Published var selectedProjectID: ResearchProject.ID?
    @Published var selectedProjectTabID = ProjectSpaceTabsBuilder.overviewTabID
    @Published var isViewingGlobalTodos = false
    @Published var selectedSettingsCategory: SettingsCategory = .workspace
    @Published private(set) var shellWindowWidth: Double = 1_440
    @Published private(set) var isShellNarrowWidth = false

    func updateWindow(width: Double, isNarrow: Bool) {
        shellWindowWidth = width
        isShellNarrowWidth = isNarrow
    }

    func snapshot() -> State {
        State(
            selectedSection: selectedSection,
            selectedProjectID: selectedProjectID,
            selectedProjectTabID: selectedProjectTabID,
            isViewingGlobalTodos: isViewingGlobalTodos,
            selectedSettingsCategory: selectedSettingsCategory,
            shellWindowWidth: shellWindowWidth,
            isShellNarrowWidth: isShellNarrowWidth
        )
    }

    func restore(_ state: State) {
        selectedSection = state.selectedSection
        selectedProjectID = state.selectedProjectID
        selectedProjectTabID = state.selectedProjectTabID
        isViewingGlobalTodos = state.isViewingGlobalTodos
        selectedSettingsCategory = state.selectedSettingsCategory
        shellWindowWidth = state.shellWindowWidth
        isShellNarrowWidth = state.isShellNarrowWidth
    }

    func resetProjectRoute() {
        selectedProjectID = nil
        selectedProjectTabID = ProjectSpaceTabsBuilder.overviewTabID
        isViewingGlobalTodos = false
    }

    func reset() {
        selectedSection = .projects
        resetProjectRoute()
        selectedSettingsCategory = .workspace
        shellWindowWidth = 1_440
        isShellNarrowWidth = false
    }
}

@MainActor
struct AppDomainStoresSnapshot {
    let workspace: WorkspaceStore.State
    let library: LibraryStore.State
    let knowledge: KnowledgeStore.State
    let recommendation: RecommendationStore.State
    let agent: AgentStore.State
    let navigation: NavigationStore.State

    init(
        workspaceStore: WorkspaceStore,
        libraryStore: LibraryStore,
        knowledgeStore: KnowledgeStore,
        recommendationStore: RecommendationStore,
        agentStore: AgentStore,
        navigationStore: NavigationStore
    ) {
        workspace = workspaceStore.snapshot()
        library = libraryStore.snapshot()
        knowledge = knowledgeStore.snapshot()
        recommendation = recommendationStore.snapshot()
        agent = agentStore.snapshot()
        navigation = navigationStore.snapshot()
    }

    func restore(
        workspaceStore: WorkspaceStore,
        libraryStore: LibraryStore,
        knowledgeStore: KnowledgeStore,
        recommendationStore: RecommendationStore,
        agentStore: AgentStore,
        navigationStore: NavigationStore
    ) {
        workspaceStore.restore(workspace)
        libraryStore.restore(library)
        knowledgeStore.restore(knowledge)
        recommendationStore.restore(recommendation)
        agentStore.restore(agent)
        navigationStore.restore(navigation)
    }
}

/// Pure route mapping shared by the app facade and focused navigation views.
/// Keeping this policy in the Core target makes route behavior testable without
/// constructing the full AppViewModel and its host-service graph.
enum WorkspaceNavigationPolicy {
    static func route(
        selectedSection: WorkspaceSection?,
        selectedProjectID: ResearchProject.ID?,
        selectedProjectTabID: String,
        currentProjectID: ResearchProject.ID?,
        librarySecondarySelection: String?,
        isViewingGlobalTodos: Bool,
        agentProjectID: ResearchProject.ID?
    ) -> WorkspaceRoute {
        switch selectedSection {
        case .some(.dashboard):
            return .home
        case .some(.projects):
            return WorkspaceRoute(
                top: .projects,
                projectID: selectedProjectID,
                projectTabID: selectedProjectID == nil ? nil : selectedProjectTabID
            )
        case .some(.library):
            return WorkspaceRoute(top: .library, secondarySelection: librarySecondarySelection)
        case .some(.calendar), .some(.tasks):
            return WorkspaceRoute(
                top: .calendar,
                secondarySelection: isViewingGlobalTodos ? "global_todos" : nil
            )
        case .some(.llmLab):
            return WorkspaceRoute(top: .aiLab, projectID: agentProjectID)
        case .some(.settings):
            return WorkspaceRoute(top: .settings)
        case .some(.pdfReader), .some(.wiki), .some(.materials), .some(.graph),
             .some(.inbox), .some(.papers), .some(.concepts), .some(.methods), .some(.gaps):
            let section = selectedSection ?? .projects
            return WorkspaceRoute(
                top: .projects,
                projectID: selectedProjectID ?? currentProjectID,
                projectTabID: projectTabID(for: section)
            )
        case .none:
            return .home
        }
    }

    static func topRoute(for section: WorkspaceSection) -> WorkspaceRoute.Top {
        switch section {
        case .dashboard:
            return .home
        case .projects:
            return .projects
        case .library:
            return .library
        case .calendar, .tasks:
            return .calendar
        case .llmLab:
            return .aiLab
        case .settings:
            return .settings
        case .pdfReader, .inbox, .wiki, .papers, .concepts, .methods, .gaps, .materials, .graph:
            return .projects
        }
    }

    static func section(for top: WorkspaceRoute.Top) -> WorkspaceSection {
        switch top {
        case .home:
            return .dashboard
        case .projects:
            return .projects
        case .library:
            return .library
        case .calendar:
            return .calendar
        case .aiLab:
            return .llmLab
        case .settings:
            return .settings
        }
    }

    static func projectTabID(for section: WorkspaceSection) -> String {
        section.moduleProjectTabID ?? ProjectSpaceTabsBuilder.overviewTabID
    }

    static func recentSectionValue(for route: WorkspaceRoute) -> String {
        section(for: route.top).rawValue
    }

    static func legacyRoute(recentSection rawValue: String?, currentProjectID: ResearchProject.ID?) -> WorkspaceRoute {
        guard let rawValue, let section = WorkspaceSection(rawValue: rawValue) else {
            return .home
        }
        if section.inProjectSpaceOnly, let currentProjectID {
            return WorkspaceRoute(
                top: .projects,
                projectID: currentProjectID,
                projectTabID: projectTabID(for: section)
            )
        }
        return WorkspaceRoute(top: topRoute(for: section))
    }
}

enum LibraryDomainUseCases {
    static func papers(_ papers: [Paper], for projectID: ResearchProject.ID) -> [Paper] {
        papers.filter { $0.projectIDs.contains(projectID) }
    }

    static func corePapers(_ papers: [Paper], for projectID: ResearchProject.ID) -> [Paper] {
        self.papers(papers, for: projectID).filter { $0.coreProjectIDs.contains(projectID) }
    }

    static func projectLink(
        paper: Paper,
        projectID: ResearchProject.ID,
        links: [ProjectPaperLink]
    ) -> ProjectPaperLink? {
        if let link = links.first(where: { $0.paperID == paper.id && $0.projectID == projectID }) {
            return link
        }
        guard paper.projectIDs.contains(projectID) else {
            return nil
        }
        return ProjectPaperLink(
            projectID: projectID,
            paperID: paper.id,
            isCore: paper.coreProjectIDs.contains(projectID),
            folderPath: paper.folderPath,
            useFor: paper.useFor,
            createdAt: paper.createdAt,
            updatedAt: paper.updatedAt
        )
    }

    static func projectLinkSortPrecedes(
        _ first: Paper,
        _ second: Paper,
        projectID: ResearchProject.ID,
        links: [ProjectPaperLink]
    ) -> Bool {
        let firstLink = projectLink(paper: first, projectID: projectID, links: links)
        let secondLink = projectLink(paper: second, projectID: projectID, links: links)
        if firstLink?.isPinned != secondLink?.isPinned {
            return firstLink?.isPinned == true
        }
        if firstLink?.sortOrder != secondLink?.sortOrder {
            switch (firstLink?.sortOrder, secondLink?.sortOrder) {
            case let (firstOrder?, secondOrder?):
                return firstOrder < secondOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
        }
        return false
    }
}

enum WorkspaceDomainUseCases {
    static func projectName(_ projectID: ResearchProject.ID, projects: [ResearchProject]) -> String {
        projects.first(where: { $0.id == projectID })?.name ?? projectID
    }

    static func projectNames(for paper: Paper, projects: [ResearchProject]) -> [String] {
        paper.projectIDs.map { projectName($0, projects: projects) }
    }

    static func coreProjectNames(for paper: Paper, projects: [ResearchProject]) -> [String] {
        paper.coreProjectIDs.map { projectName($0, projects: projects) }
    }

    static func todos(_ todos: [TodoItem], for projectID: ResearchProject.ID) -> [TodoItem] {
        TodoQueries.forProject(todos, projectID: projectID)
    }

    static func openTodos(_ todos: [TodoItem], for projectID: ResearchProject.ID) -> [TodoItem] {
        self.todos(todos, for: projectID).filter(TodoQueries.isOpen)
    }
}
