import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ResearchProjectEditorDraft {
    var id: ResearchProject.ID?
    var name = ""
    var description = ""
    var colorHex = "#4F7CAC"
    var iconName = "folder"

    init() {}

    init(project: ResearchProject) {
        self.id = project.id
        self.name = project.name
        self.description = project.description
        self.colorHex = project.colorHex
        self.iconName = project.iconName
    }

    var isNew: Bool {
        id == nil
    }
}

private enum AgentPanelValidationError: LocalizedError {
    case missingWorkspace
    case emptyGoal
    case missingAPIKey
    case missingPlan

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "请先打开工作区，再运行 AI Lab。"
        case .emptyGoal:
            return "请先输入要发送给 AI 的内容。"
        case .missingAPIKey:
            return "请先在设置中填写 LLM API Key。"
        case .missingPlan:
            return "请先生成计划，再运行已审批的工具。"
        }
    }
}

private enum MarkdownConversionStatusSurface {
    case agent
    case workspace
}

private struct PendingMarkdownConversionRequest {
    var papers: [Paper]
    var workspace: ResearchWorkspace
    var statusSurface: MarkdownConversionStatusSurface
    var existingMarkdownCount: Int
}

private struct PaperMarkdownConversionMetadata {
    var extractionEngine: String?
    var fallbackReason: String?
}

struct DeepSeekModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    static let presets: [DeepSeekModelOption] = [
        DeepSeekModelOption(id: "deepseek-chat", title: "DeepSeek Chat", detail: "General conversation and paper reading."),
        DeepSeekModelOption(id: "deepseek-reasoner", title: "DeepSeek Reasoner", detail: "Reasoning-heavy planning and analysis."),
        DeepSeekModelOption(id: "deepseek-v4-flash", title: "DeepSeek V4 Flash", detail: "Fast cached responses, useful for interactive runs."),
        DeepSeekModelOption(id: "deepseek-v4-pro", title: "DeepSeek V4 Pro", detail: "Higher quality planning and tool-call drafting.")
    ]

    static func option(for model: String) -> DeepSeekModelOption? {
        presets.first { $0.id == model }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var currentWorkspace: ResearchWorkspace?
    @Published private(set) var currentResearchRoot: ResearchRoot?
    @Published private(set) var researchProjects: [ResearchProject] = []
    @Published private(set) var currentProjectID: ResearchProject.ID?
    @Published private(set) var isViewingGlobalTodos = false
    @Published private(set) var rootCompatibilityMessage: String?
    @Published var isShowingResearchProjectEditor = false
    @Published var researchProjectEditorDraft = ResearchProjectEditorDraft()
    @Published private(set) var isSavingResearchProject = false
    @Published var selectedSection: WorkspaceSection? = .projects
    @Published var isShowingError = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var papers: [Paper] = []
    @Published private(set) var projectPaperLinks: [ProjectPaperLink] = []
    @Published private(set) var legacyPaperMigrationPlan = LegacyPaperMigrationPlan.empty
    @Published private(set) var legacyPaperMigrationReport: LegacyPaperMigrationReport?
    @Published private(set) var isLoadingLegacyPaperMigrationPlan = false
    @Published private(set) var isRunningLegacyPaperMigration = false
    @Published private(set) var collections: [PaperCollection] = []
    @Published private(set) var tagDefinitions: [TagDefinition] = []
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var calendarEvents: [CalendarEvent] = []
    @Published private(set) var systemScheduleItems: [SystemScheduleItem] = []
    @Published private(set) var systemCalendarAccessState: SystemCalendarAccessState = .notDetermined
    @Published private(set) var isLoadingSystemSchedule = false
    @Published var addTodosToAppleReminders = true
    @Published private(set) var workspacePreferences = WorkspacePreferences()
    @Published private(set) var workspaceSettingsStatusMessage: String?
    @Published var selectedSettingsCategory: SettingsCategory = .workspace
    @Published private(set) var selectedPaperID: Paper.ID?
    @Published private(set) var selectedLibraryPaperIDs: Set<Paper.ID> = []
    @Published private(set) var selectedPaperDraft: Paper?
    @Published var selectedPaperAnnotationsDraft = ""
    @Published private(set) var isSavingSelectedPaperAnnotations = false
    @Published var libraryBatchTagText = ""
    @Published private(set) var libraryBatchStatusMessage: String?
    @Published var isShowingPaperDeleteConfirmation = false
    @Published private(set) var paperPendingDeletion: Paper?
    @Published var isShowingBibTeXExport = false
    @Published private(set) var bibTeXExportText = ""
    @Published private(set) var bibTeXExportFileName = "reference.bib"
    @Published private(set) var selectedCollectionPath: String?
    @Published private(set) var selectedTagName: String?
    @Published private(set) var selectedLibraryProjectID: ResearchProject.ID?
    @Published private(set) var collapsedCollectionPaths: Set<String> = []
    @Published var selectedDashboardDate = Calendar.current.startOfDay(for: Date())
    @Published var librarySearchText = ""
    @Published private(set) var librarySearchFocusRequest = 0
    @Published private(set) var pdfReaderSearchFocusRequest = 0
    @Published private(set) var pdfReaderFindNextRequest = 0
    @Published private(set) var pdfReaderFindPreviousRequest = 0
    @Published private(set) var inspectorFocusRequest = 0
    @Published private(set) var isImportingPDF = false
    @Published var isShowingIdentifierImport = false
    @Published var identifierImportInput = ""
    @Published var identifierImportCollectionPath = "Uncategorized"
    @Published var identifierImportTagsText = ""
    @Published private(set) var identifierImportPreview: PaperMetadataDraft?
    @Published private(set) var identifierImportStatusMessage: String?
    @Published private(set) var isResolvingIdentifierImport = false
    @Published private(set) var isPerformingIdentifierImport = false
    @Published private(set) var isSavingSelectedPaper = false
    @Published private(set) var llmConfiguration = LLMConfiguration()
    @Published var llmAPIKey = ""
    @Published var minerUAPIToken = ""
    @Published private(set) var isTestingLLMConnection = false
    @Published private(set) var llmConnectionStatusMessage: String?
    @Published private(set) var isGeneratingSummary = false
    @Published private(set) var summaryPreviewText: String?
    @Published var isShowingSummaryPreview = false
    @Published var agentGoal = "" {
        didSet {
            saveAgentDraftForCurrentConversation()
            scheduleAgentDraftPersistence()
        }
    }
    @Published private(set) var agentWorkspaceSnapshot: AgentWorkspaceSnapshot?
    @Published private(set) var agentToolDefinitions: [AgentToolDefinition] = []
    @Published private(set) var agentDisabledToolNames: Set<String> = []
    @Published private(set) var agentCurrentRun: AgentRun?
    @Published private(set) var agentToolApprovals: Set<String> = []
    @Published private(set) var agentToolDenials: Set<String> = []
    @Published private(set) var agentToolSessionApprovalDrafts: Set<String> = []
    @Published private(set) var agentToolCorrectionFeedback: [String: String] = [:]
    @Published private(set) var agentRunHistory: [AgentRun] = []
    @Published private(set) var agentSessionEvents: [AgentSessionEvent] = []
    @Published private(set) var agentThreads: [AgentThread] = []
    @Published private(set) var allAgentThreads: [AgentThread] = []
    @Published var isAgentThreadWorkspaceFilterEnabled = false {
        didSet { applyAgentThreadFilterForCurrentScope() }
    }
    @Published private(set) var activeAgentThreadID: AgentThread.ID?
    @Published private(set) var pendingAgentThread: AgentThread?
    @Published private(set) var pinnedAgentThreadIDs: Set<AgentThread.ID> = []
    @Published private(set) var agentPresetDetails: AgentPresetSummary?
    @Published private(set) var agentProductMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published private(set) var agentLocalMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published private(set) var agentHookActivitySummary = AgentHookActivitySummary()
    @Published private(set) var agentSidecarHealth = SidecarHealth(status: "unavailable")
    @Published private(set) var agentDisabledHookIDs: Set<String> = []
    @Published var isShowingAgentThreadRename = false
    @Published var isShowingAgentThreadArchiveConfirmation = false
    @Published var agentThreadRenameDraft = ""
    @Published private(set) var agentThreadPendingArchive: AgentThread?
    @Published private(set) var agentStatusMessage: String?
    @Published private(set) var agentErrorMessage: String?
    @Published private(set) var selectedAgentKnowledgePaperIDs: Set<Paper.ID> = []
    @Published var isShowingAgentKnowledgeLibrary = false
    @Published var agentInteractionMode: AgentInteractionMode = .conversation
    @Published private(set) var agentPendingUserPrompt: String?
    @Published private(set) var agentStreamingResponseText: String?
    @Published private(set) var isRefreshingAgentContext = false
    @Published private(set) var isPlanningAgentRun = false
    @Published private(set) var isExecutingAgentTools = false
    @Published private(set) var isConvertingAgentKnowledgeMarkdown = false
    @Published private(set) var paperMarkdownConversionStates: [Paper.ID: PaperMarkdownConversionState] = [:]
    @Published private(set) var paperMarkdownConversionMessages: [Paper.ID: String] = [:]
    @Published var isShowingMarkdownOverwriteConfirmation = false
    @Published private(set) var isGeneratingWikiPage = false
    @Published private(set) var markdownDocuments: [MarkdownDocument] = []
    @Published private(set) var selectedMarkdownID: String?
    @Published private(set) var selectedMarkdownDraft: MarkdownDocument?
    @Published var isShowingUnsavedMarkdownConfirmation = false
    @Published private(set) var markdownSnippets: [MarkdownSnippet] = MarkdownSnippetRepository.defaultSnippets
    @Published private(set) var isSavingSelectedMarkdown = false

    private let workspaceService: WorkspaceService
    private let projectRegistryRepository: ProjectRegistryRepository
    private let paperRepository: PaperRepository
    private let projectPaperLinkRepository: ProjectPaperLinkRepository
    private let legacyPaperMigrationService: LegacyPaperMigrationService
    private let collectionRepository: CollectionRepository
    private let movePaperToCollectionService: MovePaperToCollectionService
    private let tagRepository: TagRepository
    private let todoRepository: TodoRepository
    private let calendarRepository: CalendarRepository
    private let workspacePreferencesRepository: WorkspacePreferencesRepository
    private let paperAnnotationsRepository: PaperAnnotationsRepository
    private let libraryBulkEditService: LibraryBulkEditService
    private let systemCalendarService: SystemCalendarService
    private let pdfReadingStateService: PDFReadingStateService
    private let remoteImportService: RemoteImportService
    private let llmConfigurationStore: LLMConfigurationStore
    private let apiKeyStore: KeychainAPIKeyStore
    private let openAIProvider: OpenAICompatibleProvider
    private let paperSummaryService: PaperSummaryService
    private let llmWritebackService: LLMWritebackService
    private let agentService: SciStationAgentService
    private let sidecarCoordinator: SidecarRuntimeCoordinator
    private let pdfImportService: PDFImportService
    private let markdownRepository: MarkdownRepository
    private let markdownSnippetRepository: MarkdownSnippetRepository
    private let wikiPageGenerator: WikiPageGenerator
    private var pendingMarkdownConversionRequest: PendingMarkdownConversionRequest?
    private let pdfOpeningService: any PDFOpeningService
    private let librarySearchService: LibrarySearchService
    private let batchImportInputParser = BatchImportInputParser()
    private var backlinkIndex = BacklinkIndex(documents: [])
    private var pendingMarkdownSelectionID: String?
    private var agentGoalDrafts: [String: String] = [:]
    private var pendingAgentThreadsByProject: [String: AgentThread] = [:]
    private var agentThreadPendingRename: AgentThread?
    private var agentDraftSaveTask: Task<Void, Never>?
    private var agentPlanningTask: Task<Void, Never>?
    private var agentStreamingRawResponseText = ""

    var identifierImportInputs: [String] {
        batchImportInputParser.parse(identifierImportInput)
    }

    var agentKnowledgePaperTotalCount: Int {
        papers.count
    }

    var agentKnowledgePaperSelectedCount: Int {
        selectedAgentKnowledgePaperIDs.intersection(Set(papers.map(\.id))).count
    }

    var selectedAgentKnowledgePapers: [Paper] {
        papers.filter { selectedAgentKnowledgePaperIDs.contains($0.id) }
    }

    var agentEnabledToolNames: Set<String> {
        Set(agentToolDefinitions.map(\.name)).subtracting(agentDisabledToolNames)
    }

    var agentEnabledToolSummary: String {
        let count = agentEnabledToolNames.count
        return "\(count) 工具"
    }

    var agentKnowledgePaperIDsForContext: Set<Paper.ID> {
        selectedAgentKnowledgePaperIDs.intersection(Set(papers.map(\.id)))
    }

    var agentModeStatusText: String {
        agentInteractionMode.summary
    }

    var workspaceTemplateOptions: [WorkspaceTemplate] {
        WorkspaceTemplateRegistry.builtInTemplates
    }

    var markdownOverwriteConfirmationTitle: String {
        localized("覆盖已有 Markdown？", "Overwrite existing Markdown?")
    }

    var markdownOverwriteConfirmationMessage: String {
        let count = pendingMarkdownConversionRequest?.existingMarkdownCount ?? 0
        return localized(
            "已有 \(count) 篇论文生成过 paper.md。再次转换会覆盖现有 Markdown，并重新写入转换结果。",
            "\(count) paper(s) already have generated paper.md files. Converting again will overwrite the existing Markdown with fresh results."
        )
    }

    private var effectiveAgentAllowedToolNames: Set<String>? {
        let enabledNames = agentEnabledToolNames
        if let modeAllowedNames = agentInteractionMode.allowedToolNames {
            return modeAllowedNames.intersection(enabledNames)
        }

        return enabledNames
    }

    init(
        workspaceService: WorkspaceService? = nil,
        projectRegistryRepository: ProjectRegistryRepository? = nil,
        projectPaperLinkRepository: ProjectPaperLinkRepository? = nil,
        paperRepository: PaperRepository? = nil,
        legacyPaperMigrationService: LegacyPaperMigrationService? = nil,
        collectionRepository: CollectionRepository? = nil,
        tagRepository: TagRepository? = nil,
        todoRepository: TodoRepository? = nil,
        calendarRepository: CalendarRepository? = nil,
        workspacePreferencesRepository: WorkspacePreferencesRepository? = nil,
        paperAnnotationsRepository: PaperAnnotationsRepository? = nil,
        libraryBulkEditService: LibraryBulkEditService? = nil,
        systemCalendarService: SystemCalendarService? = nil,
        pdfReadingStateService: PDFReadingStateService? = nil,
        remoteImportService: RemoteImportService? = nil,
        llmConfigurationStore: LLMConfigurationStore? = nil,
        apiKeyStore: KeychainAPIKeyStore? = nil,
        openAIProvider: OpenAICompatibleProvider? = nil,
        paperSummaryService: PaperSummaryService? = nil,
        llmWritebackService: LLMWritebackService? = nil,
        agentService: SciStationAgentService? = nil,
        sidecarCoordinator: SidecarRuntimeCoordinator? = nil,
        markdownRepository: MarkdownRepository? = nil,
        markdownSnippetRepository: MarkdownSnippetRepository? = nil,
        pdfOpeningService: (any PDFOpeningService)? = nil
    ) {
        let resolvedWorkspaceService = workspaceService ?? WorkspaceService()
        let resolvedProjectRegistryRepository = projectRegistryRepository ?? ProjectRegistryRepository()
        let resolvedProjectPaperLinkRepository = projectPaperLinkRepository ?? ProjectPaperLinkRepository()
        let resolvedPaperRepository = paperRepository ?? PaperRepository(projectPaperLinkRepository: resolvedProjectPaperLinkRepository)
        let resolvedLegacyPaperMigrationService = legacyPaperMigrationService ?? LegacyPaperMigrationService()
        let resolvedCollectionRepository = collectionRepository ?? CollectionRepository()
        let resolvedTagRepository = tagRepository ?? TagRepository()
        let resolvedTodoRepository = todoRepository ?? TodoRepository()
        let resolvedCalendarRepository = calendarRepository ?? CalendarRepository()
        let resolvedWorkspacePreferencesRepository = workspacePreferencesRepository ?? WorkspacePreferencesRepository()
        let resolvedPaperAnnotationsRepository = paperAnnotationsRepository ?? PaperAnnotationsRepository()
        let resolvedSystemCalendarService = systemCalendarService ?? SystemCalendarService()
        let resolvedPDFReadingStateService = pdfReadingStateService ?? PDFReadingStateService(paperRepository: resolvedPaperRepository)
        let resolvedMovePaperToCollectionService = MovePaperToCollectionService(paperRepository: resolvedPaperRepository)
        let resolvedLibraryBulkEditService = libraryBulkEditService ?? LibraryBulkEditService(
            paperRepository: resolvedPaperRepository,
            movePaperToCollectionService: resolvedMovePaperToCollectionService
        )
        let resolvedRemoteImportService = remoteImportService ?? RemoteImportService(
            pdfImportService: PDFImportService(repository: resolvedPaperRepository),
            linkOnlyImportService: LinkOnlyImportService(repository: resolvedPaperRepository)
        )
        let resolvedLLMConfigurationStore = llmConfigurationStore ?? LLMConfigurationStore()
        let resolvedAPIKeyStore = apiKeyStore ?? KeychainAPIKeyStore()
        let resolvedOpenAIProvider = openAIProvider ?? OpenAICompatibleProvider()
        let resolvedPaperSummaryService = paperSummaryService ?? PaperSummaryService(provider: resolvedOpenAIProvider)
        let resolvedLLMWritebackService = llmWritebackService ?? LLMWritebackService()
        let resolvedSidecarCoordinator = sidecarCoordinator ?? SidecarRuntimeCoordinator()
        let resolvedAgentService = agentService ?? SciStationAgentService(
            provider: resolvedOpenAIProvider,
            paperRepository: resolvedPaperRepository,
            todoRepository: resolvedTodoRepository,
            sidecarCoordinator: resolvedSidecarCoordinator
        )
        let resolvedMarkdownRepository = markdownRepository ?? MarkdownRepository()
        let resolvedMarkdownSnippetRepository = markdownSnippetRepository ?? MarkdownSnippetRepository()

        self.workspaceService = resolvedWorkspaceService
        self.projectRegistryRepository = resolvedProjectRegistryRepository
        self.paperRepository = resolvedPaperRepository
        self.projectPaperLinkRepository = resolvedProjectPaperLinkRepository
        self.legacyPaperMigrationService = resolvedLegacyPaperMigrationService
        self.collectionRepository = resolvedCollectionRepository
        self.movePaperToCollectionService = resolvedMovePaperToCollectionService
        self.tagRepository = resolvedTagRepository
        self.todoRepository = resolvedTodoRepository
        self.calendarRepository = resolvedCalendarRepository
        self.workspacePreferencesRepository = resolvedWorkspacePreferencesRepository
        self.paperAnnotationsRepository = resolvedPaperAnnotationsRepository
        self.libraryBulkEditService = resolvedLibraryBulkEditService
        self.systemCalendarService = resolvedSystemCalendarService
        self.systemCalendarAccessState = resolvedSystemCalendarService.accessState
        self.pdfReadingStateService = resolvedPDFReadingStateService
        self.remoteImportService = resolvedRemoteImportService
        self.llmConfigurationStore = resolvedLLMConfigurationStore
        self.apiKeyStore = resolvedAPIKeyStore
        self.openAIProvider = resolvedOpenAIProvider
        self.paperSummaryService = resolvedPaperSummaryService
        self.llmWritebackService = resolvedLLMWritebackService
        self.agentService = resolvedAgentService
        self.sidecarCoordinator = resolvedSidecarCoordinator
        self.pdfImportService = PDFImportService(repository: resolvedPaperRepository)
        self.markdownRepository = resolvedMarkdownRepository
        self.markdownSnippetRepository = resolvedMarkdownSnippetRepository
        self.wikiPageGenerator = WikiPageGenerator(paperRepository: resolvedPaperRepository)
        self.pdfOpeningService = pdfOpeningService ?? SystemPDFOpeningService()
        self.librarySearchService = LibrarySearchService()
    }

    var filteredPapers: [Paper] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matchingPapers = papers.filter { paper in
            let matchesProject = selectedLibraryProjectID.map { projectID in
                paper.projectIDs.contains(projectID)
            } ?? true
            let matchesCollection = selectedCollectionPath.map { selectedPath in
                guard let collectionPath = paper.collectionPath else {
                    return false
                }

                return collectionPath == selectedPath || collectionPath.hasPrefix(selectedPath + "/")
            } ?? true
            let matchesTag = selectedTagName.map { paper.tags.contains($0) } ?? true
            let matchesQuery = librarySearchService.matches(paper, query: query)

            return matchesProject && matchesCollection && matchesTag && matchesQuery
        }

        return workspacePreferences.librarySortState.sorted(matchingPapers)
    }

    var libraryVisibleColumnStorage: String {
        workspacePreferences.libraryVisibleColumnsStorageValue
    }

    var librarySortState: LibrarySortState {
        workspacePreferences.librarySortState
    }

    var selectedLibraryPapers: [Paper] {
        let selectedIDs = selectedLibraryPaperIDs
        return filteredPapers.filter { selectedIDs.contains($0.id) }
    }

    var selectedLibraryPaperCount: Int {
        selectedLibraryPaperIDs.count
    }

    var hasMultipleLibraryPaperSelection: Bool {
        selectedLibraryPaperIDs.count > 1
    }

    var availableTagDefinitions: [TagDefinition] {
        let existingNames = Set(tagDefinitions.map(\.name))
        let inferredDefinitions = Set(papers.flatMap(\.tags))
            .subtracting(existingNames)
            .sorted()
            .map { Self.inferredTagDefinition(named: $0) }

        return (tagDefinitions + inferredDefinitions)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedDateTodos: [TodoItem] {
        let calendar = Calendar.current
        return todos.filter { todo in
            guard let dueDate = todo.dueDate else {
                return false
            }

            return calendar.isDate(dueDate, inSameDayAs: selectedDashboardDate)
        }
        .sorted { first, second in
            if first.dueDate == second.dueDate {
                return prioritySortValue(first.priority) < prioritySortValue(second.priority)
            }
            return (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }
    }

    var currentProjectTodos: [TodoItem] {
        guard let currentProjectID else {
            return todos
        }

        return todos(for: currentProjectID)
    }

    var currentProjectOpenTodos: [TodoItem] {
        currentProjectTodos.filter { $0.status != .done && $0.status != .cancelled }
    }

    private func prioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent:
            return 0
        case .high:
            return 1
        case .medium:
            return 2
        case .low:
            return 3
        }
    }

    var selectedDateWorkspaceEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return calendarEvents
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDashboardDate) }
            .sorted { $0.date < $1.date }
    }

    var activeResearchProjects: [ResearchProject] {
        researchProjects.filter { !$0.isArchived }
    }

    var agentConversationRuns: [AgentRun] {
        guard let thread = activeAgentThread else {
            return agentRunHistory.filter { $0.currentProjectID == agentConversationProjectID }
        }

        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        return thread.runIDs.compactMap { runsByID[$0] }
    }

    var agentTimelineItems: [AgentSessionTimelineItem] {
        let sessionIDs = agentRelevantSessionIDs
        guard !sessionIDs.isEmpty else {
            return []
        }
        return AgentSessionTimelineItem.items(
            from: agentSessionEvents,
            sessionIDs: sessionIDs
        )
    }

    private var agentRelevantSessionIDs: Set<String> {
        var ids = Set(agentConversationRuns.map(\.id))
        if let currentRunID = agentCurrentRun?.id {
            ids.insert(currentRunID)
        }
        return ids
    }

    var agentOrphanRuns: [AgentRun] {
        let threadedRunIDs = Set(allAgentThreads.flatMap(\.runIDs))
        return agentRunHistory.filter { run in
            run.currentProjectID == agentConversationProjectID && !threadedRunIDs.contains(run.id)
        }
    }

    var activeAgentThread: AgentThread? {
        guard let activeAgentThreadID else {
            return agentThreads.first
        }

        return allAgentThreads.first { $0.id == activeAgentThreadID && !$0.isArchived }
            ?? (pendingAgentThread?.id == activeAgentThreadID ? pendingAgentThread : nil)
    }

    var agentThreadFilterLabel: String {
        isAgentThreadWorkspaceFilterEnabled ? "当前工作区" : "全部工作区"
    }

    var agentCurrentWorkspaceThreadCount: Int {
        allAgentThreads.filter { !$0.isArchived && isAgentThreadInCurrentWorkspace($0) }.count
    }

    func isAgentThreadInCurrentWorkspace(_ thread: AgentThread) -> Bool {
        thread.belongsToWorkspace(id: currentAgentWorkspaceID)
    }

    func agentThreadSubtitle(for thread: AgentThread) -> String {
        let runLabel = "\(thread.runIDs.count) runs"
        guard let workspaceName = thread.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspaceName.isEmpty else {
            return runLabel
        }
        return "\(runLabel) - \(workspaceName)"
    }

    var agentConversationTitle: String {
        guard let agentConversationProjectID else {
            return "全局"
        }

        return projectName(for: agentConversationProjectID)
    }

    var agentConversationProjectID: ResearchProject.ID? {
        currentProjectID
    }

    var currentResearchProject: ResearchProject? {
        guard let currentProjectID else {
            return activeResearchProjects.first
        }
        return activeResearchProjects.first { $0.id == currentProjectID } ?? activeResearchProjects.first
    }

    var selectedDateSystemScheduleItems: [SystemScheduleItem] {
        let calendar = Calendar.current
        return systemScheduleItems
            .filter { calendar.isDate($0.displayDate, inSameDayAs: selectedDashboardDate) }
            .sorted { first, second in
                if first.displayDate == second.displayDate {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.displayDate < second.displayDate
            }
    }

    var recentPapers: [Paper] {
        Array(papers.prefix(5))
    }

    func papers(for projectID: ResearchProject.ID) -> [Paper] {
        papers.filter { $0.projectIDs.contains(projectID) }
    }

    func corePapers(for projectID: ResearchProject.ID) -> [Paper] {
        papers(for: projectID).filter { $0.coreProjectIDs.contains(projectID) }
    }

    func projectPaperLink(for paperID: Paper.ID, projectID: ResearchProject.ID) -> ProjectPaperLink? {
        projectPaperLinks.first { $0.paperID == paperID && $0.projectID == projectID }
    }

    func projectPaperLink(for paper: Paper, projectID: ResearchProject.ID) -> ProjectPaperLink? {
        if let link = projectPaperLink(for: paper.id, projectID: projectID) {
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

    func projectPaperLinkSortPrecedes(_ first: Paper, _ second: Paper, projectID: ResearchProject.ID) -> Bool {
        let firstLink = projectPaperLink(for: first, projectID: projectID)
        let secondLink = projectPaperLink(for: second, projectID: projectID)

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

    func projectName(for projectID: ResearchProject.ID) -> String {
        researchProjects.first(where: { $0.id == projectID })?.name ?? projectID
    }

    func projectNames(for paper: Paper) -> [String] {
        paper.projectIDs.map(projectName(for:))
    }

    func todos(for projectID: ResearchProject.ID) -> [TodoItem] {
        todos.filter { todo in
            todo.projectIDs.contains(projectID) || (todo.projectIDs.isEmpty && activeResearchProjects.count <= 1)
        }
    }

    func openTodos(for projectID: ResearchProject.ID) -> [TodoItem] {
        todos(for: projectID).filter { $0.status != .done && $0.status != .cancelled }
    }

    func coreProjectNames(for paper: Paper) -> [String] {
        paper.coreProjectIDs.map(projectName(for:))
    }

    var recentlyReadPapers: [Paper] {
        Array(
            papers
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
    }

    var libraryScopeSummary: String {
        var components: [String] = []

        if let selectedLibraryProjectID {
            components.append("Project: \(projectName(for: selectedLibraryProjectID))")
        }

        if let selectedCollectionPath {
            components.append("Folder: \(selectedCollectionPath)")
        }

        if let selectedTagName {
            components.append("Tag: \(selectedTagName)")
        }

        return components.isEmpty ? "All Papers" : components.joined(separator: " / ")
    }

    var canOpenSelectedPaperPDF: Bool {
        guard let currentWorkspace, let selectedPaperDraft, let pdfURL = selectedPaperDraft.pdfURL(in: currentWorkspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    var canEnterSelectedPaperReader: Bool {
        canOpenSelectedPaperPDF
    }

    var canPreviewLibrarySelection: Bool {
        previewPaperForLibrarySelection() != nil
    }

    var agentProviderSummary: String {
        return "OpenAI-compatible / \(llmConfiguration.model)"
    }

    var agentProviderV2Summary: String {
        "Provider V2 wrapper is available for OpenAI-compatible chat requests; plan generation still uses the stable complete path."
    }

    var usesEnglishInterface: Bool {
        switch workspacePreferences.appLanguage {
        case .english:
            return true
        case .simplifiedChinese:
            return false
        case .system:
            return !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
        }
    }

    func localized(_ simplifiedChinese: String, _ english: String) -> String {
        usesEnglishInterface ? english : simplifiedChinese
    }

    func appLanguageLabel(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            return localized("跟随系统", "Follow System")
        case .simplifiedChinese:
            return localized("中文", "Chinese")
        case .english:
            return localized("English", "English")
        }
    }

    var agentPlatformSummary: String {
        "ExternalAgentRuntime + Swift ToolHost/MCP gateway core"
    }

    var agentPresetSummary: String {
        if let agentPresetDetails {
            let issueSummary = agentPresetDetails.validationIssues.isEmpty ? "valid" : "\(agentPresetDetails.validationIssues.count) issues"
            return "\(agentPresetDetails.name) \(agentPresetDetails.version); \(agentPresetDetails.commands.count) commands; \(agentPresetDetails.skills.count) skills; \(issueSummary)"
        }

        return "research-core preset not found in the current root"
    }

    var agentPermissionSummary: String {
        let writingTools = agentToolDefinitions.filter(\.requiresConfirmation).count
        let dockItems = agentCurrentRun.map { agentPermissionDockItems(for: $0) } ?? []
        let waitingCount = dockItems.filter { $0.approvalState == .waitingForApproval }.count
        let autoAllowedCount = dockItems.filter { $0.approvalState == .autoAllowed }.count
        return "allow / ask / deny rules active; \(writingTools) tools require approval; \(waitingCount) waiting; \(agentToolApprovals.count) allow once; \(agentToolDenials.count) denied; \(autoAllowedCount) auto-allowed"
    }

    var agentHookSummary: String {
        let enabledNames = agentHookActivitySummary.enabledEventNames.map(\.rawValue)
        let resultsCount = agentHookActivitySummary.results.count
        return "\(enabledNames.joined(separator: ", ").nilIfEmpty ?? "No hooks enabled"); \(resultsCount) results in current timeline"
    }

    var agentMCPStatusSummary: String {
        let productCount = agentProductMCPServerStatuses.count
        let localCount = agentLocalMCPServerStatuses.count
        return ".sci-ai/sci-station: \(productCount) templates; .sci-ai/workspace.local: \(localCount) local configs; local gateway tools/list+tools/call; side-effect tools require permissions"
    }

    var agentRuntimeSelectionSummary: String {
        workspacePreferences.agentRuntimeSelection.label
    }

    var agentRuntimeEffectiveSummary: String {
        workspacePreferences.agentRuntimeSelection.effectiveRuntime(
            sidecarAvailable: agentSidecarHealthIsAvailable,
            sidecarDisabled: workspacePreferences.isSidecarDisabledForWorkspace
        ).label
    }

    var agentSidecarHealthSummary: String {
        if workspacePreferences.isSidecarDisabledForWorkspace {
            return "disabled for workspace"
        }
        let dependencySummary = agentSidecarHealth.dependencies
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value ? "ok" : "missing")" }
            .joined(separator: ", ")
        return [
            agentSidecarHealth.status,
            agentSidecarHealth.pythonVersion.map { "python \($0)" },
            agentSidecarHealth.sidecarVersion.map { "sidecar \($0)" },
            dependencySummary.nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    var agentRuntimeFallbackSummary: String {
        workspacePreferences.agentRuntimeSelection.fallbackReason(
            sidecarAvailable: agentSidecarHealthIsAvailable,
            sidecarDisabled: workspacePreferences.isSidecarDisabledForWorkspace
        ) ?? agentSidecarHealth.fallbackReason ?? agentSidecarHealth.lastCrash ?? "No fallback active."
    }

    private var agentSidecarHealthIsAvailable: Bool {
        agentSidecarHealth.status == "ready"
    }

    var agentMCPServerStatuses: [AgentMCPServerStatus] {
        agentProductMCPServerStatuses + agentLocalMCPServerStatuses
    }

    func agentPermissionDockItems(for run: AgentRun) -> [AgentPermissionDockItem] {
        var filteredRun = run
        if let allowedToolNames = effectiveAgentAllowedToolNames {
            filteredRun.plan.toolCalls = filteredRun.plan.toolCalls.filter { allowedToolNames.contains($0.toolName) }
        }

        return AgentPermissionDockItem.items(
            for: filteredRun,
            toolDefinitions: agentToolDefinitions,
            state: AgentPermissionDockState(
                approvedCallIDs: agentToolApprovals,
                deniedCallIDs: agentToolDenials,
                sessionScopedApprovalDraftCallIDs: agentToolSessionApprovalDrafts,
                correctionFeedbackByCallID: agentToolCorrectionFeedback
            )
        )
    }

    var selectedPaperPDFURL: URL? {
        guard let currentWorkspace, let selectedPaperDraft else {
            return nil
        }

        return selectedPaperDraft.pdfURL(in: currentWorkspace)
    }

    var selectedPaperHasUnsavedChanges: Bool {
        guard let selectedPaperDraft,
              let originalPaper = papers.first(where: { $0.id == selectedPaperDraft.id }) else {
            return false
        }

        return selectedPaperDraft != originalPaper
    }

    var deletePendingPaperTitle: String {
        paperPendingDeletion?.displayTitle ?? "the selected paper"
    }

    var deletePendingPaperRelativePath: String {
        paperPendingDeletion?.paperDirectoryRelativePath ?? "the selected paper directory"
    }

    var selectedPaperHasWikiPage: Bool {
        guard let currentWorkspace, let selectedPaperDraft else {
            return false
        }

        return paperHasWikiPage(selectedPaperDraft, in: currentWorkspace)
    }

    var selectedPaperWikiButtonTitle: String {
        selectedPaperHasWikiPage ? "Open Wiki Page" : "Generate Wiki Page"
    }

    var canSaveSelectedMarkdown: Bool {
        currentWorkspace != nil && selectedMarkdownDraft != nil
    }

    var selectedMarkdownHasUnsavedChanges: Bool {
        guard let selectedMarkdownDraft,
              let savedDocument = markdownDocuments.first(where: { $0.id == selectedMarkdownDraft.id }) else {
            return false
        }

        return selectedMarkdownDraft.rawContents != savedDocument.rawContents
    }

    var selectedMarkdownBacklinks: [MarkdownDocumentReference] {
        guard let selectedMarkdownDraft else {
            return []
        }

        return backlinkIndex.backlinks(for: selectedMarkdownDraft)
    }

    func tagDefinition(named name: String) -> TagDefinition? {
        availableTagDefinitions.first(where: { $0.name == name })
    }

    private static func inferredTagDefinition(named name: String) -> TagDefinition {
        let palette = [
            ("#A7D8F0", "#17465F"),
            ("#BEE7C8", "#1F5130"),
            ("#F7C8D0", "#6B2637"),
            ("#F9D99A", "#62440E"),
            ("#CDBFF5", "#3D2F73"),
            ("#BFE7E2", "#1E5550"),
            ("#F4C7A1", "#6A3A14"),
            ("#D6E3A3", "#48551A")
        ]
        let index = name.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult + Int(scalar.value)) % palette.count
        }
        let colors = palette[index]
        return TagDefinition(name: name, colorHex: colors.0, textColorHex: colors.1)
    }

    func selectSection(_ section: WorkspaceSection) {
        selectedSection = section
        isViewingGlobalTodos = false
        updateWorkspacePreferences { preferences in
            preferences.recentSection = section.rawValue
        }
        if section == .library {
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    func openSettings(category: SettingsCategory) {
        selectedSettingsCategory = category
        selectSection(.settings)
    }

    func selectLibraryScope() {
        selectedSection = .library
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
    }

    func selectCollection(_ relativePath: String) {
        selectedSection = .library
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = relativePath
        selectedTagName = nil
    }

    func selectTag(_ name: String) {
        selectedSection = .library
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedTagName = name
        selectedCollectionPath = nil
    }

    func clearLibraryFilters() {
        selectedCollectionPath = nil
        selectedTagName = nil
        selectedLibraryProjectID = nil
        librarySearchText = ""
    }

    func focusSearchForCurrentSection() {
        if selectedSection == .pdfReader {
            pdfReaderSearchFocusRequest += 1
            return
        }

        selectedSection = .library
        librarySearchFocusRequest += 1
    }

    func requestPDFReaderFindNext() {
        pdfReaderFindNextRequest += 1
    }

    func requestPDFReaderFindPrevious() {
        pdfReaderFindPreviousRequest += 1
    }

    func focusInspector() {
        inspectorFocusRequest += 1
    }

    func toggleCollectionCollapse(_ relativePath: String) {
        if collapsedCollectionPaths.contains(relativePath) {
            collapsedCollectionPaths.remove(relativePath)
        } else {
            collapsedCollectionPaths.insert(relativePath)
        }
    }

    func restoreLastWorkspaceIfNeeded() async {
        guard currentWorkspace == nil else {
            return
        }

        guard let restoredWorkspace = await workspaceService.restoreLastWorkspace() else {
            return
        }

        do {
            currentWorkspace = restoredWorkspace
            try await loadWorkspaceData(in: restoredWorkspace, selectingPaper: nil, selectingMarkdown: nil)
        } catch {
            currentWorkspace = nil
            present(error)
        }
    }

    func createWorkspace() {
        createWorkspace(template: WorkspaceTemplateRegistry.literatureReview)
    }

    func createWorkspace(template: WorkspaceTemplate) {
        guard let destinationURL = Self.selectCreateWorkspaceURL() else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.createWorkspace(at: destinationURL, template: template)
        }
    }

    func workspaceTemplatePreviewSummary(for template: WorkspaceTemplate) -> String {
        WorkspaceTemplateRepository().preview(for: template).joined(separator: ", ")
    }

    func openWorkspace() {
        guard let destinationURL = Self.selectOpenWorkspaceURL() else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.openWorkspace(at: destinationURL)
        }
    }

    func selectResearchProject(_ projectID: ResearchProject.ID, section: WorkspaceSection = .projects) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        currentProjectID = projectID
        resetAgentDraftIfConversationChanged(to: projectID)
        isViewingGlobalTodos = false
        if section == .library {
            selectedSection = .library
            selectedLibraryProjectID = projectID
            selectedCollectionPath = nil
            selectedTagName = nil
            updateWorkspacePreferences { preferences in
                preferences.recentSection = section.rawValue
            }
        } else {
            selectSection(section)
        }

        persistLastOpenedProject(projectID)
        refreshAgentContext()

        if section == .wiki, let currentWorkspace {
            Task {
                do {
                    try await loadMarkdownDocuments(in: currentWorkspace, selecting: nil)
                } catch {
                    present(error)
                }
            }
        }
    }

    func focusResearchProject(_ projectID: ResearchProject.ID) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        currentProjectID = projectID
        resetAgentDraftIfConversationChanged(to: projectID)
        persistLastOpenedProject(projectID)
        refreshAgentContext()
    }

    func selectGlobalTodos() {
        selectedSection = .tasks
        isViewingGlobalTodos = true
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
        updateWorkspacePreferences { preferences in
            preferences.recentSection = WorkspaceSection.tasks.rawValue
        }
    }

    private func persistLastOpenedProject(_ projectID: ResearchProject.ID) {
        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                var registry = try await projectRegistryRepository.load(in: currentResearchRoot)
                registry.lastOpenedProjectID = projectID
                try await projectRegistryRepository.save(registry, in: currentResearchRoot)
            } catch {
                present(error)
            }
        }
    }

    func beginCreatingResearchProject() {
        researchProjectEditorDraft = ResearchProjectEditorDraft()
        isShowingResearchProjectEditor = true
    }

    func beginEditingResearchProject(_ projectID: ResearchProject.ID) {
        guard let project = researchProjects.first(where: { $0.id == projectID }) else {
            present(ProjectRegistryError.projectNotFound(projectID))
            return
        }

        researchProjectEditorDraft = ResearchProjectEditorDraft(project: project)
        isShowingResearchProjectEditor = true
    }

    func toggleResearchProjectCollapse(_ projectID: ResearchProject.ID) {
        guard let index = researchProjects.firstIndex(where: { $0.id == projectID }) else {
            return
        }

        let isCollapsed = !researchProjects[index].isCollapsed
        researchProjects[index].isCollapsed = isCollapsed

        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                let registry = try await projectRegistryRepository.setProjectCollapsed(projectID, isCollapsed: isCollapsed, in: currentResearchRoot)
                researchProjects = registry.projects
            } catch {
                present(error)
            }
        }
    }

    func saveResearchProjectDraft() {
        guard let currentResearchRoot else {
            return
        }

        let draft = researchProjectEditorDraft
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            present(ProjectRegistryError.projectNameRequired)
            return
        }

        isSavingResearchProject = true
        Task {
            defer {
                isSavingResearchProject = false
            }

            do {
                if let projectID = draft.id {
                    guard var project = researchProjects.first(where: { $0.id == projectID }) else {
                        throw ProjectRegistryError.projectNotFound(projectID)
                    }

                    project.name = name
                    project.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    project.colorHex = draft.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#4F7CAC" : draft.colorHex
                    project.iconName = draft.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : draft.iconName
                    let registry = try await projectRegistryRepository.updateProject(project, in: currentResearchRoot)
                    researchProjects = registry.projects
                } else {
                    let project = try await projectRegistryRepository.createProject(
                        named: name,
                        description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: draft.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#4F7CAC" : draft.colorHex,
                        iconName: draft.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : draft.iconName,
                        in: currentResearchRoot
                    )
                    let registry = try await projectRegistryRepository.load(in: currentResearchRoot)
                    researchProjects = registry.projects
                    currentProjectID = project.id
                    selectedSection = .projects
                }

                isShowingResearchProjectEditor = false
            } catch {
                present(error)
            }
        }
    }

    func revealCurrentWorkspaceInFinder() {
        guard let currentWorkspace else {
            return
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentWorkspace.rootURL.path)
    }

    func revealSelectedPaperInFinder() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        revealPaperInFinder(selectedPaperDraft, in: currentWorkspace)
    }

    func revealPaperInFinder(_ paper: Paper) {
        guard let currentWorkspace else {
            return
        }

        revealPaperInFinder(paper, in: currentWorkspace)
    }

    private func revealPaperInFinder(_ paper: Paper, in workspace: ResearchWorkspace) {
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paperDirectoryURL.path)
    }

    func clearRecentWorkspaceBookmark() {
        Task {
            await workspaceService.clearRecentWorkspaceBookmark()
            workspaceSettingsStatusMessage = "Recent workspace bookmark cleared. The current workspace stays open for this session."
        }
    }

    func renameCurrentWorkspace(to newName: String) {
        guard let workspaceToRename = currentWorkspace else {
            return
        }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != workspaceToRename.displayName else {
            return
        }

        let sourceURL = workspaceToRename.rootURL.standardizedFileURL
        let targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(trimmedName, isDirectory: true)
        guard sourceURL != targetURL else {
            return
        }

        isWorking = true
        Task {
            defer {
                isWorking = false
            }

            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.moveItem(at: sourceURL, to: targetURL)
                let workspace = try await workspaceService.openWorkspace(at: targetURL)
                currentWorkspace = workspace
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                workspaceSettingsStatusMessage = "Workspace renamed to \(trimmedName)."
            } catch {
                present(error)
            }
        }
    }

    func updateDefaultCollectionPath(_ value: String) {
        updateWorkspacePreferences { preferences in
            preferences.defaultCollectionPath = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    func updateAddTodosToAppleReminders(_ isEnabled: Bool) {
        addTodosToAppleReminders = isEnabled
        updateWorkspacePreferences { preferences in
            preferences.syncTodosToAppleReminders = isEnabled
        }
    }

    func updateLibraryVisibleColumns(storageValue: String) {
        updateWorkspacePreferences { preferences in
            preferences.updateLibraryVisibleColumns(from: storageValue)
        }
    }

    func updateLibrarySort(field: LibrarySortField, isAscending: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.librarySortState = LibrarySortState(field: field, isAscending: isAscending)
        }
    }

    func clearLibrarySort() {
        updateWorkspacePreferences { preferences in
            preferences.librarySortState = LibrarySortState()
        }
    }

    func resetLibraryVisibleColumns() {
        updateWorkspacePreferences { preferences in
            preferences.libraryVisibleColumns = WorkspacePreferences.defaultLibraryVisibleColumns
        }
    }

    func showAgentKnowledgeLibrary() {
        isShowingAgentKnowledgeLibrary = true
    }

    func agentKnowledgePaperHasPDF(_ paper: Paper) -> Bool {
        guard let currentWorkspace, let pdfURL = paper.pdfURL(in: currentWorkspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    func agentKnowledgePaperHasMarkdown(_ paper: Paper) -> Bool {
        guard let currentWorkspace else {
            return false
        }

        return paperHasExtractedMarkdown(paper, in: currentWorkspace)
    }

    private func paperPDFExists(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        guard let pdfURL = paper.pdfURL(in: workspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    private func paperHasExtractedMarkdown(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        guard FileManager.default.fileExists(atPath: markdownURL.path),
              let contents = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            return false
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.contains("status: not_extracted")
            && !trimmed.localizedCaseInsensitiveContains("PDF text has not been extracted yet")
    }

    private func paperMarkdownConversionMetadata(_ paper: Paper, in workspace: ResearchWorkspace) -> PaperMarkdownConversionMetadata? {
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        guard let contents = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            return nil
        }

        let frontmatter = FrontmatterParser().parse(contents).frontmatter
        return PaperMarkdownConversionMetadata(
            extractionEngine: frontmatter["extraction_engine"]?.stringValue,
            fallbackReason: frontmatter["fallback_reason"]?.stringValue
        )
    }

    private func paperMarkdownConversionState(for result: PaperMarkdownConversionResult) -> PaperMarkdownConversionState {
        guard result.didWriteMarkdown else {
            return .failed
        }

        if result.extractionEngine == "pdfkit_fallback" {
            return .fallback
        }
        return .succeeded
    }

    func setAgentKnowledgePaper(_ paperID: Paper.ID, isSelected: Bool) {
        let availablePaperIDs = Set(papers.map(\.id))
        guard availablePaperIDs.contains(paperID) else {
            return
        }

        if isSelected {
            selectedAgentKnowledgePaperIDs.insert(paperID)
        } else {
            selectedAgentKnowledgePaperIDs.remove(paperID)
        }

        persistAgentKnowledgeSelectionAsCustom()
        refreshAgentContext()
    }

    func selectAllAgentKnowledgePapers() {
        selectedAgentKnowledgePaperIDs = Set(papers.map(\.id))
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = nil
        }
        refreshAgentContext()
    }

    func clearAgentKnowledgePapers() {
        selectedAgentKnowledgePaperIDs = []
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = []
        }
        refreshAgentContext()
    }

    private func persistAgentKnowledgeSelectionAsCustom() {
        let selectedIDs = selectedAgentKnowledgePaperIDs.sorted()
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = selectedIDs
        }
    }

    func reloadLibrary() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func refreshLegacyPaperMigrationPlan() {
        guard let currentWorkspace else {
            return
        }

        isLoadingLegacyPaperMigrationPlan = true
        Task {
            defer {
                isLoadingLegacyPaperMigrationPlan = false
            }

            do {
                try await loadLegacyPaperMigrationPlan(in: currentWorkspace)
                if legacyPaperMigrationPlan.hasLegacyPapers {
                    workspaceSettingsStatusMessage = "Legacy scan found \(legacyPaperMigrationPlan.legacyPaperCount) raw/papers items."
                } else {
                    workspaceSettingsStatusMessage = "No legacy raw/papers items found."
                }
            } catch {
                present(error)
            }
        }
    }

    func copyReadyLegacyPapers() {
        guard let currentWorkspace, legacyPaperMigrationPlan.readyCount > 0 else {
            return
        }

        isRunningLegacyPaperMigration = true
        Task {
            defer {
                isRunningLegacyPaperMigration = false
            }

            do {
                let report = try await legacyPaperMigrationService.copyReadyItems(in: currentWorkspace)
                legacyPaperMigrationReport = report
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                workspaceSettingsStatusMessage = "Copied \(report.copiedCount) legacy papers. Skipped \(report.skippedCount), failed \(report.failedCount). Report: \(report.reportRelativePath ?? "not written")."
            } catch {
                present(error)
            }
        }
    }

    func reloadWiki() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownID)
            } catch {
                present(error)
            }
        }
    }

    func importPDF() {
        guard let currentWorkspace, let pdfURL = Self.selectPDFURL() else {
            return
        }

        importPDF(from: pdfURL, into: currentWorkspace)
    }

    func prepareIdentifierImport(initialInput: String? = nil) {
        identifierImportInput = initialInput ?? ""
        identifierImportCollectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        identifierImportTagsText = ""
        identifierImportPreview = nil
        identifierImportStatusMessage = nil
    }

    func beginIdentifierImport(with initialInput: String? = nil) {
        prepareIdentifierImport(initialInput: initialInput)
        isShowingIdentifierImport = true
    }

    func resetIdentifierImportForm() {
        prepareIdentifierImport()
    }

    func previewIdentifierImport() {
        guard let input = identifierImportInputs.first else {
            identifierImportPreview = nil
            return
        }

        identifierImportStatusMessage = nil

        isResolvingIdentifierImport = true

        Task {
            defer {
                isResolvingIdentifierImport = false
            }

            do {
                identifierImportPreview = try await remoteImportService.preview(for: input)
            } catch {
                present(error)
            }
        }
    }

    func performIdentifierImport(onSuccess: (() -> Void)? = nil) {
        guard let currentWorkspace else {
            return
        }

        let importInputs = identifierImportInputs
        guard !importInputs.isEmpty else {
            return
        }

        identifierImportStatusMessage = nil

        isPerformingIdentifierImport = true

        Task {
            defer {
                isPerformingIdentifierImport = false
            }

            do {
                let importCollectionPath = identifierImportCollectionPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Uncategorized"
                let importTags = commaSeparatedValues(from: identifierImportTagsText)
                var existingPapers = papers
                var importedPaperID: Paper.ID?
                var importedPapers: [Paper] = []
                var failedInputs: [(String, Error)] = []

                for input in importInputs {
                    do {
                        var importedPaper = try await remoteImportService.importItem(
                            from: input,
                            draftPreview: importInputs.count == 1 ? identifierImportPreview : nil,
                            into: currentWorkspace,
                            existingPapers: existingPapers,
                            collectionPath: importCollectionPath,
                            tags: importTags
                        )
                        if let selectedLibraryProjectID,
                           !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
                            importedPaper.projectIDs.append(selectedLibraryProjectID)
                            importedPaper = try await paperRepository.save(importedPaper, in: currentWorkspace)
                        }
                        existingPapers.append(importedPaper)
                        importedPaperID = importedPaper.id
                        importedPapers.append(importedPaper)
                    } catch {
                        failedInputs.append((input, error))
                    }
                }

                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: importedPaperID ?? selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                if !importedPapers.isEmpty {
                    startMarkdownConversion(for: importedPapers, in: currentWorkspace, statusSurface: .workspace)
                }

                let importedCount = importInputs.count - failedInputs.count
                if failedInputs.isEmpty {
                    identifierImportStatusMessage = importedCount > 1 ? "Imported \(importedCount) papers." : "Imported 1 paper."
                    isShowingIdentifierImport = false
                    identifierImportPreview = nil
                    identifierImportInput = ""
                    identifierImportTagsText = ""
                    onSuccess?()
                } else {
                    identifierImportInput = failedInputs.map { $0.0 }.joined(separator: "\n")
                    identifierImportPreview = nil
                    let failedSummary = failedInputs
                        .prefix(3)
                        .map { failedInput in "\(failedInput.0): \(failedInput.1.localizedDescription)" }
                        .joined(separator: " | ")
                    identifierImportStatusMessage = "Imported \(importedCount) of \(importInputs.count). Failed: \(failedSummary)"
                }
            } catch {
                present(error)
            }
        }
    }

    func openSelectedPaperReader() {
        guard canEnterSelectedPaperReader else {
            return
        }

        selectedSection = .pdfReader
    }

    func handlePDFDrop(providers: [NSItemProvider]) -> Bool {
        guard let currentWorkspace else {
            return false
        }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : UTType.fileURL.identifier
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { fileURL, isInPlace, _ in
            guard let fileURL else {
                return
            }

            let importURL: URL
            let shouldRemoveTemporaryFile: Bool
            if isInPlace {
                importURL = fileURL
                shouldRemoveTemporaryFile = false
            } else {
                let pathExtension = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(pathExtension)
                do {
                    if FileManager.default.fileExists(atPath: temporaryURL.path) {
                        try FileManager.default.removeItem(at: temporaryURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: temporaryURL)
                } catch {
                    return
                }
                importURL = temporaryURL
                shouldRemoveTemporaryFile = true
            }

            Task { @MainActor in
                defer {
                    if shouldRemoveTemporaryFile {
                        try? FileManager.default.removeItem(at: importURL)
                    }
                }
                self.importPDF(from: importURL, into: currentWorkspace)
            }
        }

        return true
    }

    func selectPaper(id: Paper.ID?) {
        selectedLibraryPaperIDs = id.map { [$0] } ?? []
        applySelectedPaper(id: id)
    }

    func updateLibrarySelection(_ selection: Set<Paper.ID>) {
        selectedLibraryPaperIDs = selection
        if selection.count == 1 {
            applySelectedPaper(id: selection.first)
        } else {
            selectedPaperID = nil
            selectedPaperDraft = nil
            selectedPaperAnnotationsDraft = ""
        }
    }

    func clearLibrarySelection() {
        updateLibrarySelection([])
    }

    func previewLibrarySelection() {
        guard let paper = previewPaperForLibrarySelection() else {
            libraryBatchStatusMessage = "No selected paper has a PDF to preview."
            return
        }

        openPaperPDF(paper)
    }

    func previewPaper(_ paper: Paper) {
        guard canOpenPDF(for: paper) else {
            libraryBatchStatusMessage = "No PDF is available for \(paper.displayTitle)."
            return
        }

        openPaperPDF(paper)
    }

    private func applySelectedPaper(id: Paper.ID?) {
        selectedPaperID = id
        selectedPaperDraft = papers.first(where: { $0.id == id })
        guard let currentWorkspace else {
            selectedPaperAnnotationsDraft = ""
            return
        }

        Task {
            do {
                try await loadSelectedPaperAnnotations(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updateSelectedPaper(_ mutate: (inout Paper) -> Void) {
        guard var draft = selectedPaperDraft else {
            return
        }

        mutate(&draft)
        selectedPaperDraft = draft
    }

    func discardSelectedPaperChanges() {
        selectPaper(id: selectedPaperID)
    }

    func canOpenPDF(for paper: Paper) -> Bool {
        guard let currentWorkspace, let pdfURL = paper.pdfURL(in: currentWorkspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    func openPaperReader(_ paper: Paper) {
        selectPaper(id: paper.id)
        guard canOpenPDF(for: paper) else {
            return
        }

        selectedSection = .pdfReader
    }

    func openEvidenceSource(_ jump: AgentEvidenceSourceJump) {
        if let page = jump.pdfPage,
           let sourceID = jump.sourceID,
           let paper = papers.first(where: { $0.id == sourceID || $0.paperDirectoryRelativePath.contains(sourceID) }) {
            selectedLibraryPaperIDs = [paper.id]
            selectedPaperID = paper.id
            var draft = paper
            draft.lastReadPage = page
            selectedPaperDraft = draft
            selectedSection = .pdfReader
            agentStatusMessage = "Opened PDF Reader at page \(page) for \(jump.lineTargetDescription)."
            return
        }

        guard let url = jump.sourceURL else {
            agentErrorMessage = jump.warning ?? "Evidence source is unavailable."
            return
        }

        if NSWorkspace.shared.open(url) {
            agentStatusMessage = "Opened source target: \(jump.lineTargetDescription)."
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            agentStatusMessage = "Could not open the line target directly; revealed source file for \(jump.lineTargetDescription)."
        }
    }

    func saveSelectedPaperChanges() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isSavingSelectedPaper = true
        Task {
            defer {
                isSavingSelectedPaper = false
            }

            do {
                let savedPaper = try await paperRepository.save(selectedPaperDraft, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: savedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func openSelectedPaperPDF() {
        guard let selectedPaperDraft else {
            return
        }

        openPaperPDF(selectedPaperDraft)
    }

    func openPaperPDF(_ paper: Paper) {
        guard let currentWorkspace, let pdfURL = paper.pdfURL(in: currentWorkspace) else {
            return
        }

        Task {
            do {
                try await pdfOpeningService.openPDF(at: pdfURL, page: nil)
            } catch {
                present(error)
            }
        }
    }

    private func previewPaperForLibrarySelection() -> Paper? {
        if let selectedPaperDraft, canOpenPDF(for: selectedPaperDraft) {
            return selectedPaperDraft
        }

        return selectedLibraryPapers.first { canOpenPDF(for: $0) }
    }

    func requestDeleteSelectedPaper() {
        guard let selectedPaperDraft else {
            return
        }

        requestDeletePaper(selectedPaperDraft)
    }

    func requestDeletePaper(_ paper: Paper) {
        paperPendingDeletion = paper
        isShowingPaperDeleteConfirmation = true
    }

    func exportBibTeX(for paper: Paper) {
        let bibtex = BibTeXFormatter.bibTeX(for: paper)
        bibTeXExportText = bibtex
        bibTeXExportFileName = "\(paper.citekey).bib"

        copyBibTeX(for: paper)
        isShowingBibTeXExport = true
    }

    func copyBibTeX(for paper: Paper) {
        let bibtex = BibTeXFormatter.bibTeX(for: paper)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
    }

    func copyCitation(for paper: Paper) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.citationText(for: paper), forType: .string)
    }

    func exportSelectedPaperBibTeX() {
        if selectedLibraryPapers.count > 1 {
            exportBibTeXForLibrarySelection()
            return
        }

        guard let selectedPaperDraft else {
            return
        }

        exportBibTeX(for: selectedPaperDraft)
    }

    func copySelectedPaperBibTeX() {
        if selectedLibraryPapers.count > 1 {
            copyBibTeXForLibrarySelection()
            return
        }

        guard let selectedPaperDraft else {
            return
        }

        copyBibTeX(for: selectedPaperDraft)
    }

    func copySelectedPaperCitation() {
        let papersToCopy = selectedLibraryPapers.count > 1 ? selectedLibraryPapers : selectedPaperDraft.map { [$0] } ?? []
        guard !papersToCopy.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(papersToCopy.map(Self.citationText(for:)).joined(separator: "\n"), forType: .string)
    }

    func copyBibTeXForLibrarySelection() {
        let papersToCopy = selectedLibraryPapers
        guard !papersToCopy.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.joinedBibTeX(for: papersToCopy), forType: .string)
    }

    func exportBibTeXForLibrarySelection() {
        let papersToExport = selectedLibraryPapers
        guard !papersToExport.isEmpty else {
            return
        }

        bibTeXExportText = Self.joinedBibTeX(for: papersToExport)
        bibTeXExportFileName = papersToExport.count == 1 ? "\(papersToExport[0].citekey).bib" : "selected-\(papersToExport.count)-references.bib"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibTeXExportText, forType: .string)
        isShowingBibTeXExport = true
    }

    func dismissBibTeXExport() {
        isShowingBibTeXExport = false
    }

    func setStatusForLibrarySelection(_ status: ReadingStatus) {
        runLibrarySelectionBatchEdit(summary: "Set status to \(status.label)") { ids, workspace in
            try await self.libraryBulkEditService.setStatus(status, for: ids, in: workspace)
        }
    }

    func setPriorityForLibrarySelection(_ priority: Priority) {
        runLibrarySelectionBatchEdit(summary: "Set priority to \(priority.label)") { ids, workspace in
            try await self.libraryBulkEditService.setPriority(priority, for: ids, in: workspace)
        }
    }

    func setRatingForLibrarySelection(_ rating: Int?) {
        let summary = rating.map { "Set rating to \($0)" } ?? "Clear rating"
        runLibrarySelectionBatchEdit(summary: summary) { ids, workspace in
            try await self.libraryBulkEditService.setRating(rating, for: ids, in: workspace)
        }
    }

    func moveLibrarySelection(to collectionPath: String) {
        runLibrarySelectionBatchEdit(summary: "Move to \(collectionPath)") { ids, workspace in
            try await self.libraryBulkEditService.moveToCollection(collectionPath, for: ids, in: workspace)
        }
    }

    func addTagsToLibrarySelection(_ tagsText: String? = nil) {
        let tags = commaSeparatedValues(from: tagsText ?? libraryBatchTagText)
        guard !tags.isEmpty else {
            libraryBatchStatusMessage = "Enter at least one tag to add."
            return
        }

        runLibrarySelectionBatchEdit(summary: "Add tags \(tags.joined(separator: ", "))") { ids, workspace in
            try await self.libraryBulkEditService.addTags(tags, for: ids, in: workspace)
        }
    }

    func removeTagsFromLibrarySelection(_ tagsText: String? = nil) {
        let tags = commaSeparatedValues(from: tagsText ?? libraryBatchTagText)
        guard !tags.isEmpty else {
            libraryBatchStatusMessage = "Enter at least one tag to remove."
            return
        }

        runLibrarySelectionBatchEdit(summary: "Remove tags \(tags.joined(separator: ", "))") { ids, workspace in
            try await self.libraryBulkEditService.removeTags(tags, for: ids, in: workspace)
        }
    }

    private func runLibrarySelectionBatchEdit(
        summary: String,
        operation: @escaping @Sendable (Set<Paper.ID>, ResearchWorkspace) async throws -> [Paper]
    ) {
        guard let currentWorkspace else {
            return
        }

        let selectedIDs = selectedLibraryPaperIDs
        guard !selectedIDs.isEmpty else {
            libraryBatchStatusMessage = "Select papers before running a batch action."
            return
        }

        libraryBatchStatusMessage = "\(summary) for \(selectedIDs.count) selected papers..."
        Task {
            do {
                let updatedPapers = try await operation(selectedIDs, currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedLibraryPaperIDs = selectedIDs.intersection(Set(papers.map(\.id)))
                if selectedLibraryPaperIDs.count == 1 {
                    applySelectedPaper(id: selectedLibraryPaperIDs.first)
                } else {
                    selectedPaperID = nil
                    selectedPaperDraft = nil
                    selectedPaperAnnotationsDraft = ""
                }
                libraryBatchStatusMessage = "\(summary) completed for \(updatedPapers.count) papers."
            } catch {
                present(error)
            }
        }
    }

    func saveExportedBibTeXToFile() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = bibTeXExportFileName
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText]

        guard savePanel.runModal() == .OK,
              let destinationURL = savePanel.url else {
            return
        }

        do {
            try bibTeXExportText.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            present(error)
        }
    }

    func cancelPaperDeletion() {
        isShowingPaperDeleteConfirmation = false
        paperPendingDeletion = nil
    }

    func confirmDeletePendingPaper() {
        guard let currentWorkspace, let paper = paperPendingDeletion else {
            cancelPaperDeletion()
            return
        }

        isShowingPaperDeleteConfirmation = false
        paperPendingDeletion = nil
        selectedPaperID = nil
        selectedLibraryPaperIDs = []
        selectedPaperDraft = nil

        Task {
            do {
                try await paperRepository.delete(paper, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: nil,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedPaperReadingState(lastPage: Int) {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        Task {
            do {
                let savedPaper = try await pdfReadingStateService.save(
                    lastPage: lastPage,
                    for: selectedPaperDraft,
                    in: currentWorkspace
                )
                papers = papers.map { $0.id == savedPaper.id ? savedPaper : $0 }
                self.selectedPaperDraft = savedPaper
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedPaperAnnotations() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isSavingSelectedPaperAnnotations = true
        let contents = selectedPaperAnnotationsDraft
        Task {
            defer {
                isSavingSelectedPaperAnnotations = false
            }

            do {
                try await paperAnnotationsRepository.saveAnnotations(contents, for: selectedPaperDraft, in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func saveLLMSettings() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await llmConfigurationStore.save(llmConfiguration, in: currentWorkspace)
                try await apiKeyStore.save(apiKey: llmAPIKey, for: currentWorkspace.rootURL.path)
                llmConnectionStatusMessage = "LLM settings saved."
            } catch {
                present(error)
            }
        }
    }

    func updateLLMConfiguration(_ mutate: (inout LLMConfiguration) -> Void) {
        mutate(&llmConfiguration)
    }

    func useDeepSeekDefaults(model: String = "deepseek-v4-flash") {
        updateLLMConfiguration { configuration in
            configuration.provider = .openAICompatible
            configuration.baseURLString = "https://api.deepseek.com"
            configuration.model = model
            configuration.temperature = 0.2
            configuration.maxTokens = 1500
        }
    }

    func useDeepSeekModel(_ option: DeepSeekModelOption) {
        useDeepSeekDefaults(model: option.id)
    }

    func testLLMConnection() {
        isTestingLLMConnection = true
        llmConnectionStatusMessage = nil

        Task {
            defer {
                isTestingLLMConnection = false
            }

            do {
                let response = try await openAIProvider.complete(
                    prompt: "Reply with OK.",
                    configuration: llmConfiguration,
                    apiKey: llmAPIKey
                )
                llmConnectionStatusMessage = response.isEmpty ? "Connection test returned an empty response." : "Connection OK"
            } catch {
                present(error)
            }
        }
    }

    func generateSelectedPaperSummary() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isGeneratingSummary = true

        Task {
            defer {
                isGeneratingSummary = false
            }

            do {
                let apiKey = llmAPIKey.isEmpty
                    ? try await apiKeyStore.loadAPIKey(for: currentWorkspace.rootURL.path) ?? ""
                    : llmAPIKey

                let summary = try await paperSummaryService.summarize(
                    selectedPaperDraft,
                    in: currentWorkspace,
                    configuration: llmConfiguration,
                    apiKey: apiKey
                )
                summaryPreviewText = summary
                isShowingSummaryPreview = true
            } catch {
                present(error)
            }
        }
    }

    func refreshAgentContext() {
        guard let currentWorkspace else {
            return
        }

        isRefreshingAgentContext = true
        Task {
            defer {
                isRefreshingAgentContext = false
            }
            await refreshAgentState(in: currentWorkspace)
        }
    }

    func setAgentToolApproval(callID: String, isApproved: Bool) {
        if isApproved {
            agentToolApprovals.insert(callID)
            agentToolDenials.remove(callID)
        } else {
            agentToolApprovals.remove(callID)
        }
    }

    func setAgentToolDenied(callID: String, isDenied: Bool) {
        if isDenied {
            agentToolDenials.insert(callID)
            agentToolApprovals.remove(callID)
            agentToolSessionApprovalDrafts.remove(callID)
        } else {
            agentToolDenials.remove(callID)
        }
    }

    func setAgentSessionApprovalDraft(callID: String, isEnabled: Bool) {
        if isEnabled {
            agentToolSessionApprovalDrafts.insert(callID)
            agentToolDenials.remove(callID)
        } else {
            agentToolSessionApprovalDrafts.remove(callID)
        }
    }

    func agentCorrectionFeedback(callID: String) -> String {
        agentToolCorrectionFeedback[callID] ?? ""
    }

    func updateAgentCorrectionFeedback(callID: String, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            agentToolCorrectionFeedback[callID] = nil
        } else {
            agentToolCorrectionFeedback[callID] = text
        }
    }

    func setAgentHook(_ hookID: String, isEnabled: Bool) {
        if isEnabled {
            agentDisabledHookIDs.remove(hookID)
        } else {
            agentDisabledHookIDs.insert(hookID)
        }
        rebuildAgentHookActivitySummary()
    }

    func setAgentTool(_ toolName: String, isEnabled: Bool) {
        guard agentToolDefinitions.contains(where: { $0.name == toolName }) else {
            return
        }

        if isEnabled {
            agentDisabledToolNames.remove(toolName)
        } else {
            agentDisabledToolNames.insert(toolName)
        }
        persistAgentToolStateForCurrentScope()
    }

    func updateMinerUCommand(_ command: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUCommand = trimmed.isEmpty ? "mineru" : trimmed
        }
    }

    func updateAppLanguagePreference(_ preference: AppLanguagePreference) {
        Task { @MainActor [weak self] in
            self?.updateWorkspacePreferences { preferences in
                preferences.appLanguage = preference
            }
        }
    }

    func updateAgentChatFontSize(_ fontSize: Double) {
        updateWorkspacePreferences { preferences in
            preferences.agentChatFontSize = fontSize
        }
    }

    func updateAgentRuntimeSelection(_ selection: AgentRuntimeSelection) {
        updateWorkspacePreferences { preferences in
            preferences.agentRuntimeSelection = selection
            if selection == .langGraphSidecar || selection == .autoFallback {
                preferences.isSidecarDisabledForWorkspace = false
            }
        }
        agentStatusMessage = "AI Lab runtime set to \(selection.label)."
    }

    func restartAgentSidecar() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        Task {
            agentSidecarHealth = await sidecarCoordinator.restart(for: currentResearchRoot)
            agentStatusMessage = agentSidecarHealth.status == "ready"
                ? "Sidecar restarted and health is ready."
                : "Sidecar restart failed or is unavailable."
        }
    }

    func openAgentRunDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let runID = agentCurrentRun?.id
        let relativePath = [AgentRunDirectoryStore.runsRelativePath, runID].compactMap { $0 }.joined(separator: "/")
        NSWorkspace.shared.activateFileViewerSelecting([currentResearchRoot.directoryURL(for: relativePath)])
    }

    func exportAgentDebugBundle() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        guard let run = agentCurrentRun else {
            agentErrorMessage = "No completed or active run is selected for debug export."
            return
        }
        Task {
            do {
                let store = AgentRunDirectoryStore()
                _ = try await store.saveReplay(runID: run.id, in: currentResearchRoot)
                let preview = try await store.debugBundlePreview(runID: run.id, in: currentResearchRoot)
                let confirmed = await MainActor.run { self.confirmAgentDebugBundleExport(preview) }
                guard confirmed else {
                    agentStatusMessage = "Debug bundle export cancelled."
                    return
                }
                let bundleURL = try await store.saveDebugBundle(runID: run.id, in: currentResearchRoot)
                NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                agentStatusMessage = "Debug bundle exported: \(bundleURL.lastPathComponent). Manifest excludes API keys, private paths, .env files, and Keychain data."
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    private func confirmAgentDebugBundleExport(_ preview: AgentDebugBundlePreview) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Export Debug Bundle"
        alert.informativeText = [
            "Run ID: \(preview.runID)",
            "Included files:\n\(preview.includedFiles.isEmpty ? "- none" : preview.includedFiles.map { "- \($0)" }.joined(separator: "\n"))",
            "Excluded patterns:\n\(preview.excludedPatterns.map { "- \($0)" }.joined(separator: "\n"))",
            preview.privacyNotice
        ].joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func disableSidecarForWorkspace() {
        updateWorkspacePreferences { preferences in
            preferences.isSidecarDisabledForWorkspace = true
            preferences.agentRuntimeSelection = .swiftLoop
        }
        agentStatusMessage = "LangGraph sidecar disabled for this workspace."
    }

    func updateMinerUAPIBaseURL(_ baseURLString: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUAPIBaseURLString = trimmed.isEmpty ? "https://mineru.net" : trimmed
        }
    }

    func updateMinerUAPILanguage(_ language: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUAPILanguage = trimmed.isEmpty ? "en" : trimmed
        }
    }

    func setMinerUOverwriteExistingMarkdown(_ shouldOverwrite: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.minerUOverwriteExistingMarkdown = shouldOverwrite
        }
    }

    func saveMinerUMarkdownConversionSettings() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await apiKeyStore.save(apiKey: minerUAPIToken, for: minerUAPITokenAccount(for: currentWorkspace))
                workspaceSettingsStatusMessage = localized("MinerU API 设置已保存。", "MinerU API settings saved.")
            } catch {
                present(error)
            }
        }
    }

    func agentToolDefinition(for call: AgentToolCall) -> AgentToolDefinition? {
        agentToolDefinitions.first { $0.name == call.toolName }
    }

    func isAgentThreadPinned(_ threadID: AgentThread.ID) -> Bool {
        pinnedAgentThreadIDs.contains(threadID)
    }

    func toggleAgentThreadPin(_ thread: AgentThread) {
        if pinnedAgentThreadIDs.contains(thread.id) {
            pinnedAgentThreadIDs.remove(thread.id)
            agentStatusMessage = "已取消置顶 \(thread.title)。"
        } else {
            pinnedAgentThreadIDs.insert(thread.id)
            agentStatusMessage = "已置顶 \(thread.title)。"
        }
        persistPinnedAgentThreadsForCurrentProject()
    }

    func confirmArchiveAgentThread(_ thread: AgentThread) {
        agentThreadPendingArchive = thread
        isShowingAgentThreadArchiveConfirmation = true
    }

    func archiveConfirmedAgentThread() {
        guard let thread = agentThreadPendingArchive else {
            isShowingAgentThreadArchiveConfirmation = false
            return
        }

        pinnedAgentThreadIDs.remove(thread.id)
        persistPinnedAgentThreadsForCurrentProject()
        agentThreadPendingArchive = nil
        isShowingAgentThreadArchiveConfirmation = false
        archiveAgentThread(thread)
    }

    func cancelAgentGeneration() {
        guard isPlanningAgentRun else {
            return
        }

        agentPlanningTask?.cancel()
        agentPlanningTask = nil
        isPlanningAgentRun = false
        agentPendingUserPrompt = nil
        agentStatusMessage = "已停止 AI 输出。"
        agentErrorMessage = nil
    }

    func convertSelectedAgentKnowledgePapersToMarkdown() {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        requestMarkdownConversion(for: selectedAgentKnowledgePapers, in: currentWorkspace, statusSurface: .agent)
    }

    func convertPaperToMarkdown(_ paper: Paper) {
        guard let currentWorkspace else {
            workspaceSettingsStatusMessage = localized("请先打开工作区。", "Open a workspace first.")
            return
        }

        requestMarkdownConversion(for: [paper], in: currentWorkspace, statusSurface: .workspace)
    }

    func convertLibrarySelectionToMarkdown() {
        guard let currentWorkspace else {
            workspaceSettingsStatusMessage = localized("请先打开工作区。", "Open a workspace first.")
            return
        }

        requestMarkdownConversion(for: selectedLibraryPapers, in: currentWorkspace, statusSurface: .workspace)
    }

    func confirmMarkdownOverwriteConversion() {
        guard let request = pendingMarkdownConversionRequest else {
            isShowingMarkdownOverwriteConfirmation = false
            return
        }

        pendingMarkdownConversionRequest = nil
        isShowingMarkdownOverwriteConfirmation = false
        startMarkdownConversion(
            for: request.papers,
            in: request.workspace,
            statusSurface: request.statusSurface,
            forceOverwriteExistingMarkdown: true
        )
    }

    func cancelMarkdownOverwriteConversion() {
        pendingMarkdownConversionRequest = nil
        isShowingMarkdownOverwriteConfirmation = false
    }

    func paperMarkdownConversionState(for paper: Paper) -> PaperMarkdownConversionState {
        guard let currentWorkspace else {
            return .notConverted
        }
        if let state = paperMarkdownConversionStates[paper.id] {
            return state
        }
        guard paperPDFExists(paper, in: currentWorkspace) else {
            return .noPDF
        }
        guard paperHasExtractedMarkdown(paper, in: currentWorkspace) else {
            return .notConverted
        }

        let metadata = paperMarkdownConversionMetadata(paper, in: currentWorkspace)
        if metadata?.extractionEngine == "pdfkit_fallback" {
            return .fallback
        }
        return .succeeded
    }

    func paperMarkdownConversionMessage(for paper: Paper) -> String? {
        if let message = paperMarkdownConversionMessages[paper.id] {
            return message
        }
        guard let currentWorkspace,
              let fallbackReason = paperMarkdownConversionMetadata(paper, in: currentWorkspace)?.fallbackReason,
              !fallbackReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return fallbackReason
    }

    private func requestMarkdownConversion(
        for requestedPapers: [Paper],
        in workspace: ResearchWorkspace,
        statusSurface: MarkdownConversionStatusSurface
    ) {
        let uniquePapers = uniquePapersByID(requestedPapers)
        let existingMarkdownPapers = uniquePapers.filter { paperHasExtractedMarkdown($0, in: workspace) }
        guard existingMarkdownPapers.isEmpty else {
            pendingMarkdownConversionRequest = PendingMarkdownConversionRequest(
                papers: uniquePapers,
                workspace: workspace,
                statusSurface: statusSurface,
                existingMarkdownCount: existingMarkdownPapers.count
            )
            isShowingMarkdownOverwriteConfirmation = true
            return
        }

        startMarkdownConversion(for: uniquePapers, in: workspace, statusSurface: statusSurface)
    }

    private func markdownConversionSummaryMessage(
        convertedCount: Int,
        fallbackCount: Int,
        failedCount: Int,
        skippedNoPDFCount: Int,
        skippedExistingMarkdownCount: Int
    ) -> String {
        var chineseParts = ["已转换 \(convertedCount) 篇论文"]
        var englishParts = ["Converted \(convertedCount) paper(s)"]
        if fallbackCount > 0 {
            chineseParts.append("\(fallbackCount) 篇使用 PDFKit fallback")
            englishParts.append("\(fallbackCount) used PDFKit fallback")
        }
        if failedCount > 0 {
            chineseParts.append("\(failedCount) 篇失败")
            englishParts.append("\(failedCount) failed")
        }
        if skippedNoPDFCount > 0 {
            chineseParts.append("\(skippedNoPDFCount) 篇无 PDF 已跳过")
            englishParts.append("\(skippedNoPDFCount) skipped without PDF")
        }
        if skippedExistingMarkdownCount > 0 {
            chineseParts.append("\(skippedExistingMarkdownCount) 篇已有 Markdown 已跳过")
            englishParts.append("\(skippedExistingMarkdownCount) skipped with existing Markdown")
        }
        return localized(chineseParts.joined(separator: "；") + "。", englishParts.joined(separator: "; ") + ".")
    }

    private func startMarkdownConversion(
        for requestedPapers: [Paper],
        in workspace: ResearchWorkspace,
        statusSurface: MarkdownConversionStatusSurface,
        forceOverwriteExistingMarkdown: Bool? = nil
    ) {
        let uniquePapers = uniquePapersByID(requestedPapers)
        let convertiblePapers = uniquePapers.filter { paperPDFExists($0, in: workspace) }
        let skippedNoPDFPapers = uniquePapers.filter { !paperPDFExists($0, in: workspace) }
        for paper in skippedNoPDFPapers {
            paperMarkdownConversionStates[paper.id] = .noPDF
            paperMarkdownConversionMessages[paper.id] = localized("这篇论文没有可转换的 PDF。", "This paper does not have a convertible PDF.")
        }

        guard !convertiblePapers.isEmpty else {
            let message = localized("请选择至少一篇带 PDF 的论文。", "Select at least one paper with a PDF.")
            switch statusSurface {
            case .agent:
                agentErrorMessage = message
            case .workspace:
                workspaceSettingsStatusMessage = message
            }
            return
        }

        for paper in convertiblePapers {
            paperMarkdownConversionStates[paper.id] = .converting
            paperMarkdownConversionMessages[paper.id] = nil
        }

        if statusSurface == .agent {
            isConvertingAgentKnowledgeMarkdown = true
            agentErrorMessage = nil
            agentStatusMessage = nil
        } else {
            workspaceSettingsStatusMessage = localized(
                "正在转换 \(convertiblePapers.count) 篇论文为 Markdown...",
                "Converting \(convertiblePapers.count) paper(s) to Markdown..."
            )
        }

        let preferences = workspacePreferences
        let apiToken = minerUAPIToken
        Task {
            defer {
                if statusSurface == .agent {
                    isConvertingAgentKnowledgeMarkdown = false
                }
            }

            do {
                let service = PaperMarkdownConversionService()
                let results = try await service.convert(
                    convertiblePapers,
                    in: workspace,
                    configuration: PaperMarkdownConversionConfiguration(
                        minerUAPIToken: apiToken,
                        minerUAPIBaseURLString: preferences.minerUAPIBaseURLString,
                        minerUAPILanguage: preferences.minerUAPILanguage,
                        minerUCommand: preferences.minerUCommand,
                        overwriteExistingMarkdown: forceOverwriteExistingMarkdown ?? preferences.minerUOverwriteExistingMarkdown
                    )
                )
                let convertedCount = results.filter { $0.didWriteMarkdown && $0.extractionEngine == "mineru_api" }.count
                let fallbackCount = results.filter { $0.didWriteMarkdown && $0.extractionEngine == "pdfkit_fallback" }.count
                let skippedExistingMarkdownCount = results.filter { $0.errorMessage == "paper.md already exists; overwrite is disabled." }.count
                let failedCount = results.filter { result in
                    !result.didWriteMarkdown
                        && result.errorMessage != nil
                        && result.errorMessage != "paper.md already exists; overwrite is disabled."
                }.count
                for result in results {
                    paperMarkdownConversionStates[result.paperID] = paperMarkdownConversionState(for: result)
                    paperMarkdownConversionMessages[result.paperID] = result.fallbackReason ?? result.errorMessage
                }

                let message = markdownConversionSummaryMessage(
                    convertedCount: convertedCount,
                    fallbackCount: fallbackCount,
                    failedCount: failedCount,
                    skippedNoPDFCount: skippedNoPDFPapers.count,
                    skippedExistingMarkdownCount: skippedExistingMarkdownCount
                )
                switch statusSurface {
                case .agent:
                    agentStatusMessage = message
                case .workspace:
                    workspaceSettingsStatusMessage = message
                }
                await refreshAgentState(in: workspace)
                try await loadMarkdownDocuments(in: workspace, selecting: selectedMarkdownID)
            } catch {
                for paper in convertiblePapers {
                    paperMarkdownConversionStates[paper.id] = .failed
                    paperMarkdownConversionMessages[paper.id] = error.localizedDescription
                }
                switch statusSurface {
                case .agent:
                    agentErrorMessage = error.localizedDescription
                case .workspace:
                    workspaceSettingsStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func uniquePapersByID(_ papers: [Paper]) -> [Paper] {
        var seen: Set<Paper.ID> = []
        var result: [Paper] = []
        for paper in papers where !seen.contains(paper.id) {
            seen.insert(paper.id)
            result.append(paper)
        }
        return result
    }

    private func resetAgentPermissionDockState() {
        agentToolApprovals = []
        agentToolDenials = []
        agentToolSessionApprovalDrafts = []
        agentToolCorrectionFeedback = [:]
    }

    func startNewAgentConversation() {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        let now = Date()
        let thread = AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: agentConversationProjectID,
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            title: "New Chat",
            createdAt: now,
            updatedAt: now
        )
        pendingAgentThread = thread
        pendingAgentThreadsByProject[agentProjectDraftKey(agentConversationProjectID)] = thread
        activeAgentThreadID = thread.id
        agentGoal = ""
        agentCurrentRun = nil
        agentStreamingResponseText = nil
        agentStreamingRawResponseText = ""
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        agentStatusMessage = "已开始新的 \(agentConversationTitle) 对话。"
        agentErrorMessage = nil
    }

    func discardPendingAgentThread() {
        guard let pendingAgentThread else {
            return
        }

        let projectID = pendingAgentThread.projectID
        pendingAgentThreadsByProject[agentProjectDraftKey(projectID)] = nil
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: pendingAgentThread.id)] = nil
        self.pendingAgentThread = nil
        activeAgentThreadID = preferredAgentThreadID(projectID: projectID)
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: activeAgentThreadID)] ?? ""
        agentCurrentRun = nil
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        agentStatusMessage = "Discarded the empty draft chat."
        agentErrorMessage = nil

        if let currentWorkspace {
            let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
            Task {
                try? await agentService.removeDraft(projectID: projectID, threadID: pendingAgentThread.id, in: root)
            }
        }
    }

    func selectAgentThread(_ thread: AgentThread) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        activeAgentThreadID = thread.id
        pendingAgentThread = nil
        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        agentCurrentRun = thread.runIDs.reversed().compactMap { runsByID[$0] }.first
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: thread.projectID, threadID: thread.id)] ?? ""
        restorePersistedAgentDraft(projectID: thread.projectID, threadID: thread.id)
        agentStreamingResponseText = nil
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        let workspaceSuffix = thread.workspaceName.map { "（\($0)）" } ?? ""
        agentStatusMessage = "已打开 \(thread.title)\(workspaceSuffix)。"
        agentErrorMessage = nil
    }

    func openAgentRun(_ run: AgentRun) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        if let projectID = run.currentProjectID {
            focusResearchProject(projectID)
        }
        activeAgentThreadID = allAgentThreads.first { $0.runIDs.contains(run.id) }?.id
        pendingAgentThread = nil
        agentCurrentRun = run
        agentGoal = run.goal
        agentStreamingResponseText = nil
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        agentStatusMessage = "Opened a previous \(agentConversationTitle) run."
        agentErrorMessage = nil
        refreshAgentContext()
    }

    func beginRenameAgentThread(_ thread: AgentThread) {
        agentThreadPendingRename = thread
        agentThreadRenameDraft = thread.title
        isShowingAgentThreadRename = true
    }

    func renamePendingAgentThreadFromDraft() {
        guard let agentThreadPendingRename, let currentWorkspace else {
            isShowingAgentThreadRename = false
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        var thread = agentThreadPendingRename
        thread.rename(to: agentThreadRenameDraft, updatedAt: Date())
        isShowingAgentThreadRename = false
        self.agentThreadPendingRename = nil

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                agentStatusMessage = "Renamed thread to \(thread.title)."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func archiveAgentThread(_ thread: AgentThread) {
        guard let currentWorkspace else {
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        var archivedThread = thread
        archivedThread.archive(at: Date())

        Task {
            do {
                try await agentService.upsertThread(archivedThread, in: root)
                if activeAgentThreadID == thread.id {
                    activeAgentThreadID = nil
                    pendingAgentThread = nil
                    agentCurrentRun = nil
                    agentGoal = ""
                }
                agentStatusMessage = "Archived \(thread.title)."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func createAgentThread(from run: AgentRun) {
        guard let currentWorkspace else {
            return
        }
        guard run.currentProjectID == agentConversationProjectID else {
            agentErrorMessage = "Only runs from the current project conversation can be organized into a thread."
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        let now = Date()
        let thread = AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: run.currentProjectID,
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            title: Self.agentThreadTitle(for: run),
            runIDs: [run.id],
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                activeAgentThreadID = thread.id
                pendingAgentThread = nil
                agentCurrentRun = run
                agentGoal = agentGoalDrafts[agentDraftKey(projectID: thread.projectID, threadID: thread.id)] ?? ""
                agentStatusMessage = "Created \(thread.title) from history."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func addAgentRunToCurrentThread(_ run: AgentRun) {
        guard let currentWorkspace, var thread = activeAgentThread else {
            agentErrorMessage = "Open a thread before adding a history run."
            return
        }
        guard thread.workspaceID == nil || thread.belongsToWorkspace(id: currentAgentWorkspaceID) else {
            agentErrorMessage = "This thread belongs to another workspace. Start a new chat in the current workspace before adding runs."
            return
        }
        guard run.currentProjectID == agentConversationProjectID, thread.projectID == run.currentProjectID else {
            agentErrorMessage = "Only runs from the current project conversation can be added to this thread."
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        thread.appendRunID(run.id, updatedAt: Date())

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                agentStatusMessage = "Added history run to \(thread.title)."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func duplicateAgentRunPromptToNewChat(_ run: AgentRun) {
        startNewAgentConversation()
        agentGoal = run.goal
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentStatusMessage = "Copied the previous prompt into a new chat."
    }

    func duplicateAgentThreadPromptToNewChat(_ thread: AgentThread) {
        guard let runID = thread.runIDs.last,
              let run = agentRunHistory.first(where: { $0.id == runID }) else {
            agentErrorMessage = "No prompt found for this chat yet."
            return
        }

        duplicateAgentRunPromptToNewChat(run)
    }

    private func resetAgentDraftIfConversationChanged(to projectID: ResearchProject.ID?) {
        guard agentCurrentRun?.currentProjectID != projectID else {
            return
        }

        if let pendingThread = pendingAgentThreadsByProject[agentProjectDraftKey(projectID)] {
            pendingAgentThread = pendingThread
            activeAgentThreadID = pendingThread.id
        } else {
            pendingAgentThread = nil
            activeAgentThreadID = preferredAgentThreadID(projectID: projectID)
        }
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: activeAgentThreadID)] ?? ""
        restorePersistedAgentDraft(projectID: projectID, threadID: activeAgentThreadID)
        agentCurrentRun = nil
        agentStreamingResponseText = nil
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restorePinnedAgentThreadsForCurrentProject()
        restoreAgentToolStateForCurrentScope()
        agentStatusMessage = nil
        agentErrorMessage = nil
    }

    func generateAgentPlan() {
        if isPlanningAgentRun {
            cancelAgentGeneration()
            return
        }

        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        let trimmedGoal = agentGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            agentErrorMessage = AgentPanelValidationError.emptyGoal.localizedDescription
            return
        }

        let conversationHistory = agentConversationMessagesForPrompt()
        let allowedToolNames = effectiveAgentAllowedToolNames
        let interactionMode = agentInteractionMode
        let executionOptions = AgentExecutionOptions(
            mode: .planOnly,
            loopPolicy: interactionMode == .conversation ? .readOnlyAutoApproveWritesRequireApproval : .manualApprovalOnly,
            runtimeSelection: workspacePreferences.agentRuntimeSelection,
            isSidecarDisabledForWorkspace: workspacePreferences.isSidecarDisabledForWorkspace,
            disabledHookIDs: agentDisabledHookIDs,
            plannerInstructions: interactionMode.plannerInstructions,
            allowedToolNames: allowedToolNames,
            allowsPlainTextResponse: interactionMode.allowsPlainTextResponse
        )
        let responseDeltaHandler = interactionMode == .conversation ? makeAgentStreamingDeltaHandler() : nil

        isPlanningAgentRun = true
        agentPendingUserPrompt = trimmedGoal
        agentStreamingResponseText = nil
        agentStreamingRawResponseText = ""
        agentGoal = ""
        persistAgentDraftForCurrentConversation()
        agentErrorMessage = nil
        agentStatusMessage = nil

        agentPlanningTask?.cancel()
        agentPlanningTask = Task {
            defer {
                isPlanningAgentRun = false
                agentPendingUserPrompt = nil
                agentPlanningTask = nil
            }

            do {
                try Task.checkCancellation()
                let apiKey = try await resolvedLLMAPIKey(for: currentWorkspace)
                guard !apiKey.isEmpty else {
                    throw AgentPanelValidationError.missingAPIKey
                }
                try Task.checkCancellation()

                let run = try await agentService.run(
                    goal: trimmedGoal,
                    in: currentWorkspace,
                    root: currentResearchRoot,
                    projects: researchProjects,
                    currentProjectID: agentConversationProjectID,
                    selectedPaperID: selectedPaperID,
                    includedPaperIDs: agentKnowledgePaperIDsForContext,
                    conversationHistory: conversationHistory,
                    configuration: llmConfiguration,
                    apiKey: apiKey,
                    options: executionOptions,
                    responseDeltaHandler: responseDeltaHandler
                )
                try Task.checkCancellation()
                agentCurrentRun = run
                agentStreamingResponseText = nil
                try await attachRunToActiveThread(run, in: currentWorkspace)
                resetAgentPermissionDockState()
                let isWaitingForApproval = interactionMode == .conversation && run.completedAt == nil && !run.plan.toolCalls.isEmpty
                agentStatusMessage = isWaitingForApproval
                    ? "等待批准工具调用。输入草稿已保留。"
                    : (interactionMode == .conversation
                        ? "已根据所选 AI 知识库生成回复。"
                        : "计划已生成。运行前请审查允许写入工作区的工具。")
                await refreshAgentState(in: currentWorkspace)
            } catch is CancellationError {
                agentStatusMessage = "已停止 AI 输出。"
                agentErrorMessage = nil
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func executeApprovedAgentTools() {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard let currentRun = agentCurrentRun else {
            agentErrorMessage = AgentPanelValidationError.missingPlan.localizedDescription
            return
        }
        guard agentInteractionMode.allowsApprovedToolExecution else {
            agentErrorMessage = "Conversation mode cannot execute tools. Switch to Plan or Assistant mode."
            return
        }

        let goal = agentGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? currentRun.goal : agentGoal
        isExecutingAgentTools = true
        agentErrorMessage = nil
        agentStatusMessage = nil

        Task {
            defer {
                isExecutingAgentTools = false
            }

            do {
                if agentInteractionMode == .conversation {
                    let dockItems = agentPermissionDockItems(for: currentRun)
                    let approvedCall = currentRun.plan.toolCalls.first { agentToolApprovals.contains($0.id) }
                    let deniedCall = currentRun.plan.toolCalls.first { agentToolDenials.contains($0.id) }
                    guard let selectedCall = approvedCall ?? deniedCall else {
                        agentErrorMessage = "请先允许或拒绝待审批工具。"
                        return
                    }
                    let selectedItem = dockItems.first { $0.id == selectedCall.id }
                    let action: AgentHumanDecisionAction
                    if approvedCall != nil {
                        action = .allowOnce
                    } else if selectedItem?.risk == .writesWorkspace || selectedItem?.risk == .externalSideEffect {
                        action = .denyAndStop
                    } else {
                        action = .denyAndContinue
                    }
                    let resumedRun = try await agentService.resumePendingToolCall(
                        runID: currentRun.id,
                        action: action,
                        feedback: agentToolCorrectionFeedback[selectedCall.id],
                        in: currentWorkspace,
                        root: currentResearchRoot,
                        currentProjectID: agentConversationProjectID,
                        selectedPaperID: selectedPaperID,
                        includedPaperIDs: agentKnowledgePaperIDsForContext,
                        allowedToolNames: effectiveAgentAllowedToolNames,
                        disabledHookIDs: agentDisabledHookIDs,
                        configuration: llmConfiguration,
                        apiKey: try await resolvedLLMAPIKey(for: currentWorkspace),
                        responseDeltaHandler: makeAgentStreamingDeltaHandler()
                    )
                    agentCurrentRun = resumedRun
                    try await attachRunToActiveThread(resumedRun, in: currentWorkspace)
                    resetAgentPermissionDockState()
                    agentStatusMessage = resumedRun.completedAt == nil ? "等待下一步工具审批。" : "已从审批点继续生成回复。"
                    try await loadWorkspaceData(
                        in: currentWorkspace,
                        selectingPaper: selectedPaperID,
                        selectingMarkdown: selectedMarkdownID
                    )
                    return
                }

                let executedRun = try await agentService.executeApprovedPlan(
                    goal: goal,
                    plan: currentRun.plan,
                    in: currentWorkspace,
                    root: currentResearchRoot,
                    currentProjectID: agentConversationProjectID,
                    selectedPaperID: selectedPaperID,
                    includedPaperIDs: agentKnowledgePaperIDsForContext,
                    allowedToolNames: effectiveAgentAllowedToolNames,
                    approvedToolCallIDs: agentToolApprovals,
                    deniedToolCallIDs: agentToolDenials,
                    correctionFeedbackByCallID: agentToolCorrectionFeedback,
                    disabledHookIDs: agentDisabledHookIDs
                )
                agentCurrentRun = executedRun
                try await attachRunToActiveThread(executedRun, in: currentWorkspace)
                agentStatusMessage = "Approved tools finished. Workspace data has been refreshed."
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func applySummaryPreview(mode: LLMWritebackMode) {
        guard let currentWorkspace, let selectedPaperDraft, let summaryPreviewText else {
            return
        }

        Task {
            do {
                let targetURL = wikiPageURL(for: selectedPaperDraft, in: currentWorkspace)
                let writebackResult = try await llmWritebackService.write(
                    summaryPreviewText,
                    to: targetURL,
                    mode: mode,
                    paper: selectedPaperDraft,
                    in: currentWorkspace
                )

                if writebackResult.didModifyWiki {
                    var updatedPaper = selectedPaperDraft
                    updatedPaper.status = .summarized
                    _ = try await paperRepository.save(updatedPaper, in: currentWorkspace)
                }

                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperDraft.id,
                    selectingMarkdown: currentWorkspace.relativePath(to: writebackResult.writtenURL)
                )
                self.summaryPreviewText = nil
                isShowingSummaryPreview = false
            } catch {
                present(error)
            }
        }
    }

    func updateSummaryPreviewText(_ newValue: String) {
        summaryPreviewText = newValue
    }

    func createCollection(relativePath: String) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let collection = try await collectionRepository.createCollection(at: relativePath, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectCollection(collection.relativePath)
            } catch {
                present(error)
            }
        }
    }

    func createSubfolder(in parentPath: String?) {
        let trimmedParentPath = parentPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let basePath = [trimmedParentPath, "New Folder"].compactMap { $0 }.joined(separator: "/")
        let existingPaths = Set(collections.map(\.relativePath))
        var candidate = basePath
        var suffix = 2
        while existingPaths.contains(candidate) {
            candidate = [trimmedParentPath, "New Folder \(suffix)"].compactMap { $0 }.joined(separator: "/")
            suffix += 1
        }
        createCollection(relativePath: candidate)
    }

    func renameSelectedCollection(to newName: String) {
        guard let currentWorkspace, let selectedCollectionPath else {
            return
        }

        Task {
            do {
                let collection = try await collectionRepository.renameCollection(
                    at: selectedCollectionPath,
                    to: newName,
                    in: currentWorkspace
                )
                let movedPapers = try await paperRepository.loadPapers(in: currentWorkspace)
                    .filter { paper in
                        paper.collectionPath == collection.relativePath
                            || paper.collectionPath?.hasPrefix(collection.relativePath + "/") == true
                    }
                for paper in movedPapers {
                    _ = try await paperRepository.save(paper, in: currentWorkspace)
                }
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectCollection(collection.relativePath)
            } catch {
                present(error)
            }
        }
    }

    func deleteSelectedCollection() {
        guard let currentWorkspace, let selectedCollectionPath else {
            return
        }

        Task {
            do {
                try await collectionRepository.deleteCollection(at: selectedCollectionPath, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                clearLibraryFilters()
            } catch {
                present(error)
            }
        }
    }

    func moveSelectedPaper(to collectionPath: String) {
        guard let selectedPaperDraft else {
            return
        }

        movePaper(selectedPaperDraft, to: collectionPath)
    }

    func movePaper(_ paper: Paper, to collectionPath: String) {
        guard let currentWorkspace else {
            return
        }

        let normalizedPath = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if (paper.collectionPath ?? "") == normalizedPath {
            return
        }

        Task {
            do {
                let movedPaper = try await movePaperToCollectionService.move(
                    paper,
                    to: collectionPath,
                    in: currentWorkspace
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: movedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func togglePaperProject(_ paper: Paper, projectID: ResearchProject.ID) {
        setPaperProjectMembership(paper, projectID: projectID, isMember: projectPaperLink(for: paper, projectID: projectID) == nil)
    }

    func togglePaperCoreProject(_ paper: Paper, projectID: ResearchProject.ID) {
        let isCore = projectPaperLink(for: paper, projectID: projectID)?.isCore == true
        setPaperProjectCore(paper, projectID: projectID, isCore: !isCore)
    }

    func setPaperProjectMembership(_ paper: Paper, projectID: ResearchProject.ID, isMember: Bool) {
        guard let currentWorkspace else {
            return
        }

        let existingLink = projectPaperLink(for: paper, projectID: projectID)

        Task {
            do {
                if isMember {
                    let link = existingLink ?? ProjectPaperLink(projectID: projectID, paperID: paper.id)
                    _ = try await projectPaperLinkRepository.upsert(link, in: currentWorkspace)
                } else {
                    _ = try await projectPaperLinkRepository.remove(projectID: projectID, paperID: paper.id, in: currentWorkspace)
                }
                try await syncPaperProjectMetadataMirror(forPaperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func setPaperProjectCore(_ paper: Paper, projectID: ResearchProject.ID, isCore: Bool) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await projectPaperLinkRepository.setCore(isCore, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await syncPaperProjectMetadataMirror(forPaperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func setPaperProjectPinned(_ paper: Paper, projectID: ResearchProject.ID, isPinned: Bool) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await projectPaperLinkRepository.setPinned(isPinned, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func updatePaperProjectUseFor(_ paper: Paper, projectID: ResearchProject.ID, text: String) {
        guard let currentWorkspace else {
            return
        }

        let useFor = commaSeparatedValues(from: text)
        Task {
            do {
                _ = try await projectPaperLinkRepository.updateUseFor(useFor, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func updatePaperProjectFolderPath(_ paper: Paper, projectID: ResearchProject.ID, folderPath: String) {
        guard let currentWorkspace else {
            return
        }

        let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        Task {
            do {
                _ = try await projectPaperLinkRepository.updateFolderPath(trimmedFolderPath, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    private func syncPaperProjectMetadataMirror(forPaperID paperID: Paper.ID, in workspace: ResearchWorkspace) async throws {
        let links = try await projectPaperLinkRepository.links(forPaperID: paperID, in: workspace)
        guard var paper = selectedPaperDraft?.id == paperID ? selectedPaperDraft : papers.first(where: { $0.id == paperID }) else {
            return
        }

        paper.projectIDs = uniqueOrdered(links.map(\.projectID))
        paper.coreProjectIDs = uniqueOrdered(links.filter(\.isCore).map(\.projectID))
        _ = try await paperRepository.saveMetadataMirror(paper, in: workspace)
    }

    private func savePaperClassification(_ paper: Paper, in workspace: ResearchWorkspace) {
        Task {
            do {
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: savedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func saveTagDefinition(name: String, colorHex: String, textColorHex: String?) {
        guard let currentWorkspace else {
            return
        }

        let definition = TagDefinition(
            name: name,
            colorHex: colorHex,
            textColorHex: textColorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        Task {
            do {
                try await tagRepository.upsert(definition, in: currentWorkspace)
                try await loadTags(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTagDefinition(named name: String) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await tagRepository.deleteTag(named: name, in: currentWorkspace)
                try await loadTags(in: currentWorkspace)
                if selectedTagName == name {
                    selectedTagName = nil
                }
            } catch {
                present(error)
            }
        }
    }

    func selectDashboardDate(_ date: Date) {
        selectedDashboardDate = Calendar.current.startOfDay(for: date)
        if systemCalendarAccessState.canReadSchedule {
            refreshSystemSchedule(around: selectedDashboardDate)
        }
    }

    func requestSystemCalendarAccess() {
        isLoadingSystemSchedule = true

        Task {
            defer {
                isLoadingSystemSchedule = false
            }

            do {
                systemCalendarAccessState = try await systemCalendarService.requestAccess()
                if systemCalendarAccessState.canReadSchedule {
                    try await loadSystemSchedule(around: selectedDashboardDate)
                }
            } catch {
                systemCalendarAccessState = systemCalendarService.accessState
                present(error)
            }
        }
    }

    func refreshSystemSchedule(around referenceDate: Date? = nil) {
        systemCalendarAccessState = systemCalendarService.accessState
        guard systemCalendarAccessState.canReadSchedule else {
            return
        }

        isLoadingSystemSchedule = true

        Task {
            defer {
                isLoadingSystemSchedule = false
            }

            do {
                try await loadSystemSchedule(around: referenceDate ?? selectedDashboardDate)
            } catch {
                present(error)
            }
        }
    }

    func addTodo(
        title: String,
        dueDate: Date?,
        priority: Priority = .medium,
        notes: String? = nil,
        projectIDs: [ResearchProject.ID]? = nil
    ) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let now = Date()
        var todo = TodoItem(
            id: "todo-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            status: .open,
            dueDate: dueDate.map { Calendar.current.startOfDay(for: $0) },
            priority: priority,
            projectIDs: projectIDs ?? currentProjectID.map { [$0] } ?? [],
            tags: selectedTagName.map { [$0] } ?? [],
            relatedPaperIDs: selectedPaperDraft.map { [$0.id] } ?? [],
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                try await todoRepository.upsert(todo, in: currentWorkspace)
                if addTodosToAppleReminders {
                    todo = try await createAppleReminderIfNeeded(for: todo, in: currentWorkspace)
                }
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updateTodo(
        _ todo: TodoItem,
        title: String,
        status: TodoStatus,
        dueDate: Date?,
        priority: Priority,
        notes: String?,
        projectIDs: [ResearchProject.ID]? = nil
    ) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        var updatedTodo = todo
        updatedTodo.title = trimmedTitle
        updatedTodo.status = status
        updatedTodo.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        updatedTodo.priority = priority
        updatedTodo.projectIDs = projectIDs ?? updatedTodo.projectIDs
        updatedTodo.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedTodo.completedAt = status == .done ? (todo.completedAt ?? Date()) : nil
        updatedTodo.updatedAt = Date()

        Task {
            do {
                try await todoRepository.upsert(updatedTodo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func toggleTodo(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        var updatedTodo = todo
        updatedTodo.status = todo.status == .done ? .open : .done
        updatedTodo.completedAt = updatedTodo.status == .done ? Date() : nil
        updatedTodo.updatedAt = Date()

        Task {
            do {
                try await todoRepository.upsert(updatedTodo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func publishTodoToAppleReminders(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await createAppleReminderIfNeeded(for: todo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTodo(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await todoRepository.delete(todoID: todo.id, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func openOrGenerateSelectedPaperWikiPage() {
        if selectedPaperHasWikiPage {
            openSelectedPaperWikiPage()
        } else {
            generateSelectedPaperWikiPage()
        }
    }

    func selectMarkdownDocument(id: String?) {
        guard id != selectedMarkdownID else {
            return
        }

        if selectedMarkdownHasUnsavedChanges {
            pendingMarkdownSelectionID = id
            isShowingUnsavedMarkdownConfirmation = true
            return
        }

        applyMarkdownSelection(id)
    }

    func confirmDiscardUnsavedMarkdownSelection() {
        let nextSelectionID = pendingMarkdownSelectionID
        pendingMarkdownSelectionID = nil
        isShowingUnsavedMarkdownConfirmation = false
        applyMarkdownSelection(nextSelectionID)
    }

    func cancelDiscardUnsavedMarkdownSelection() {
        pendingMarkdownSelectionID = nil
        isShowingUnsavedMarkdownConfirmation = false
    }

    private func applyMarkdownSelection(_ id: String?) {
        selectedMarkdownID = id
        selectedMarkdownDraft = markdownDocuments.first(where: { $0.id == id })
    }

    func openMarkdownDocument(relativePath: String) {
        selectedSection = .wiki

        if markdownDocuments.contains(where: { $0.relativePath == relativePath }) {
            selectMarkdownDocument(id: relativePath)
            return
        }

        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: relativePath)
            } catch {
                present(error)
            }
        }
    }

    func openPaperMarkdown(_ paper: Paper) {
        openMarkdownDocument(relativePath: paper.paperDirectoryRelativePath + "/paper.md")
    }

    func openCurrentProjectOverviewPage() {
        guard let project = currentResearchProject else {
            selectedSection = .wiki
            return
        }

        openMarkdownDocument(relativePath: project.relativePath + "/wiki/projects/project_overview.md")
    }

    func updateSelectedMarkdownContents(_ newValue: String) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        draft.rawContents = expandedMarkdownContentsIfNeeded(newValue)
        selectedMarkdownDraft = draft
    }

    func insertMarkdownSnippet(_ snippet: MarkdownSnippet) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        let snippetBody = preparedSnippetBody(snippet.body)
        let currentContents = draft.rawContents.trimmingCharacters(in: .newlines)
        draft.rawContents = currentContents.isEmpty
            ? snippetBody
            : currentContents + "\n\n" + snippetBody
        selectedMarkdownDraft = draft
    }

    func openMarkdownSnippetsFile() {
        guard let currentWorkspace else {
            return
        }

        NSWorkspace.shared.open(currentWorkspace.markdownSnippetsURL)
    }

    func openWikiFolder() {
        guard let currentWorkspace else {
            return
        }

        if let project = currentResearchProject {
            NSWorkspace.shared.open(currentWorkspace.directoryURL(for: project.relativePath + "/wiki"))
        } else {
            NSWorkspace.shared.open(currentWorkspace.directoryURL(for: "wiki"))
        }
    }

    func saveSelectedMarkdownChanges() {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        isSavingSelectedMarkdown = true
        Task {
            defer {
                isSavingSelectedMarkdown = false
            }

            do {
                _ = try await markdownRepository.saveContents(
                    selectedMarkdownDraft.rawContents,
                    relativePath: selectedMarkdownDraft.relativePath,
                    in: currentWorkspace
                )
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownDraft.relativePath)
            } catch {
                present(error)
            }
        }
    }

    private func runWorkspaceTask(
        compatibilityHint: ResearchRootCompatibility? = nil,
        operation: @escaping @Sendable () async throws -> ResearchWorkspace
    ) {
        isWorking = true

        Task {
            defer {
                isWorking = false
            }

            do {
                let workspace = try await operation()
                currentWorkspace = workspace
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: nil,
                    selectingMarkdown: nil,
                    rootCompatibility: compatibilityHint
                )
                if selectedSection == nil {
                    selectedSection = .projects
                }
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func importPDF(from pdfURL: URL, into workspace: ResearchWorkspace) {
        isImportingPDF = true
        let existingPapers = papers

        Task {
            defer {
                isImportingPDF = false
            }

            do {
                var importedPaper = try await pdfImportService.importPDF(
                    from: pdfURL,
                    into: workspace,
                    existingPapers: existingPapers,
                    collectionPath: selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
                )
                if let selectedLibraryProjectID,
                   !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
                    importedPaper.projectIDs.append(selectedLibraryProjectID)
                    importedPaper = try await paperRepository.save(importedPaper, in: workspace)
                }
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: importedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                startMarkdownConversion(for: [importedPaper], in: workspace, statusSurface: .workspace)
            } catch {
                present(error)
            }
        }
    }

    private func commaSeparatedValues(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty, !seen.contains(trimmedValue) else {
                continue
            }
            seen.insert(trimmedValue)
            result.append(trimmedValue)
        }
        return result
    }

    private func generateSelectedPaperWikiPage() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isGeneratingWikiPage = true
        Task {
            defer {
                isGeneratingWikiPage = false
            }

            do {
                let result = try await wikiPageGenerator.generatePaperWikiPage(
                    for: selectedPaperDraft,
                    in: currentWorkspace
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: result.paper.id,
                    selectingMarkdown: currentWorkspace.relativePath(to: result.fileURL)
                )
                selectedSection = .wiki
            } catch {
                present(error)
            }
        }
    }

    private func openSelectedPaperWikiPage() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        openMarkdownDocument(relativePath: currentWorkspace.relativePath(to: wikiPageURL(for: selectedPaperDraft, in: currentWorkspace)))
    }

    private func loadWorkspaceData(
        in workspace: ResearchWorkspace,
        selectingPaper paperID: Paper.ID?,
        selectingMarkdown markdownID: String?,
        rootCompatibility: ResearchRootCompatibility? = nil
    ) async throws {
        try await loadResearchRoot(in: workspace, compatibility: rootCompatibility)
        try await loadWorkspacePreferences(in: workspace)
        try await loadLibrary(in: workspace, selecting: paperID)
        try await loadLegacyPaperMigrationPlan(in: workspace)
        try await loadCollections(in: workspace)
        try await loadTags(in: workspace)
        try await loadTodos(in: workspace)
        try await loadCalendarEvents(in: workspace)
        systemCalendarAccessState = systemCalendarService.accessState
        if systemCalendarAccessState.canReadSchedule {
            try await loadSystemSchedule(around: selectedDashboardDate)
        }
        try await loadLLMSettings(in: workspace)
        try await loadMarkdownSnippets(in: workspace)
        try await loadMarkdownDocuments(in: workspace, selecting: markdownID)
        await refreshAgentState(in: workspace)
    }

    private func loadResearchRoot(in workspace: ResearchWorkspace, compatibility: ResearchRootCompatibility?) async throws {
        let root = ResearchRoot(rootURL: workspace.rootURL)
        currentResearchRoot = root

        let registry = try await projectRegistryRepository.load(in: root)
        researchProjects = registry.projects
        currentProjectID = registry.lastOpenedProjectID ?? registry.projects.first?.id

        if compatibility == .legacyWorkspace || registry.projects.contains(where: { $0.defaultTags.contains("legacy-workspace") }) {
            rootCompatibilityMessage = "Opened an existing single-workspace library as a research root. Sci-Station created a default project shell without moving your files."
        } else {
            rootCompatibilityMessage = nil
        }
    }

    private func loadLibrary(in workspace: ResearchWorkspace, selecting paperID: Paper.ID?) async throws {
        projectPaperLinks = try await projectPaperLinkRepository.load(in: workspace)
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        papers = loadedPapers

        let nextSelectionID = paperID ?? selectedPaperID ?? loadedPapers.first?.id
        let nextSelectedPaper = loadedPapers.first(where: { $0.id == nextSelectionID })
        selectedPaperID = nextSelectedPaper?.id
        selectedLibraryPaperIDs = nextSelectedPaper.map { [$0.id] } ?? []
        selectedPaperDraft = nextSelectedPaper
        reconcileAgentKnowledgeSelectionWithLoadedPapers()
        try await loadSelectedPaperAnnotations(in: workspace)
    }

    private func loadLegacyPaperMigrationPlan(in workspace: ResearchWorkspace) async throws {
        legacyPaperMigrationPlan = try await legacyPaperMigrationService.makePlan(in: workspace)
    }

    private func loadWorkspacePreferences(in workspace: ResearchWorkspace) async throws {
        workspacePreferences = try await workspacePreferencesRepository.load(in: workspace)
        addTodosToAppleReminders = workspacePreferences.syncTodosToAppleReminders
        restorePinnedAgentThreadsForCurrentProject()
        restoreAgentToolStateForCurrentScope()
    }

    private func reconcileAgentKnowledgeSelectionWithLoadedPapers() {
        let availablePaperIDs = Set(papers.map(\.id))
        if let storedPaperIDs = workspacePreferences.agentKnowledgePaperIDs {
            selectedAgentKnowledgePaperIDs = Set(storedPaperIDs).intersection(availablePaperIDs)
        } else {
            selectedAgentKnowledgePaperIDs = availablePaperIDs
        }
    }

    private func loadSelectedPaperAnnotations(in workspace: ResearchWorkspace) async throws {
        guard let selectedPaperDraft else {
            selectedPaperAnnotationsDraft = ""
            return
        }

        selectedPaperAnnotationsDraft = try await paperAnnotationsRepository.loadAnnotations(for: selectedPaperDraft, in: workspace)
    }

    private func loadCollections(in workspace: ResearchWorkspace) async throws {
        collections = try await collectionRepository.loadCollections(in: workspace)

        if let selectedCollectionPath,
           !collections.contains(where: { $0.relativePath == selectedCollectionPath }) {
            self.selectedCollectionPath = nil
        }
    }

    private func loadTags(in workspace: ResearchWorkspace) async throws {
        tagDefinitions = try await tagRepository.loadDefinitions(in: workspace)

        if let selectedTagName,
           !availableTagDefinitions.contains(where: { $0.name == selectedTagName }) {
            self.selectedTagName = nil
        }
    }

    private func loadTodos(in workspace: ResearchWorkspace) async throws {
        todos = try await todoRepository.loadTodos(in: workspace)
    }

    private func loadCalendarEvents(in workspace: ResearchWorkspace) async throws {
        calendarEvents = try await calendarRepository.loadEvents(in: workspace)
    }

    private func loadSystemSchedule(around referenceDate: Date) async throws {
        let range = systemScheduleRange(around: referenceDate)
        systemScheduleItems = try await systemCalendarService.loadItems(from: range.start, to: range.end)
        if let currentWorkspace {
            try await syncMappedTodos(with: systemScheduleItems, in: currentWorkspace)
        }
    }

    private func createAppleReminderIfNeeded(for todo: TodoItem, in workspace: ResearchWorkspace) async throws -> TodoItem {
        if !systemCalendarService.canCreateReminders {
            systemCalendarAccessState = try await systemCalendarService.requestAccess()
        }

        guard systemCalendarService.canCreateReminders else {
            throw SystemCalendarServiceError.accessDenied
        }

        if todo.externalSource == "apple_reminders", todo.externalIdentifier != nil {
            return todo
        }

        var mappedTodo = todo
        if let reminder = try await systemCalendarService.createReminder(
            title: todo.title,
            dueDate: todo.dueDate,
            notes: todo.notes
        ) {
            mappedTodo.externalSource = "apple_reminders"
            mappedTodo.externalIdentifier = reminder.id
            mappedTodo.externalUpdatedAt = Date()
            mappedTodo.updatedAt = Date()
            try await todoRepository.upsert(mappedTodo, in: workspace)
            systemScheduleItems.append(reminder)
            systemScheduleItems.sort { $0.displayDate < $1.displayDate }
        }

        systemCalendarAccessState = systemCalendarService.accessState
        return mappedTodo
    }

    private func syncMappedTodos(with items: [SystemScheduleItem], in workspace: ResearchWorkspace) async throws {
        var didUpdateTodos = false
        let calendar = Calendar.current

        for todo in todos where todo.externalSource == "apple_reminders" {
            guard let externalIdentifier = todo.externalIdentifier,
                  let item = items.first(where: { $0.id == externalIdentifier || "reminder-\(externalIdentifier)" == $0.id }) else {
                continue
            }

            var syncedTodo = todo
            syncedTodo.title = item.title
            syncedTodo.dueDate = calendar.startOfDay(for: item.displayDate)
            syncedTodo.notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? syncedTodo.notes
            syncedTodo.status = item.isCompleted ? .done : syncedTodo.status
            syncedTodo.completedAt = item.isCompleted ? (syncedTodo.completedAt ?? Date()) : syncedTodo.completedAt
            syncedTodo.externalUpdatedAt = Date()
            syncedTodo.updatedAt = Date()

            if syncedTodo != todo {
                try await todoRepository.upsert(syncedTodo, in: workspace)
                didUpdateTodos = true
            }
        }

        if didUpdateTodos {
            try await loadTodos(in: workspace)
        }
    }

    private func updateWorkspacePreferences(_ mutate: (inout WorkspacePreferences) -> Void) {
        var preferences = workspacePreferences
        mutate(&preferences)
        workspacePreferences = preferences
        persistWorkspacePreferences(preferences)
    }

    private func persistWorkspacePreferences(_ preferences: WorkspacePreferences) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await workspacePreferencesRepository.save(preferences, in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    private func systemScheduleRange(around referenceDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            let start = calendar.date(byAdding: .day, value: -45, to: referenceDate) ?? referenceDate
            let end = calendar.date(byAdding: .day, value: 45, to: referenceDate) ?? referenceDate
            return (start, end)
        }

        let start = calendar.date(byAdding: .day, value: -7, to: monthInterval.start) ?? monthInterval.start
        let end = calendar.date(byAdding: .day, value: 7, to: monthInterval.end) ?? monthInterval.end
        return (start, end)
    }

    private func loadLLMSettings(in workspace: ResearchWorkspace) async throws {
        llmConfiguration = try await llmConfigurationStore.load(in: workspace)
        llmAPIKey = try await apiKeyStore.loadAPIKey(for: workspace.rootURL.path) ?? ""
        minerUAPIToken = try await apiKeyStore.loadAPIKey(for: minerUAPITokenAccount(for: workspace)) ?? ""
    }

    private func resolvedLLMAPIKey(for workspace: ResearchWorkspace) async throws -> String {
        if !llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return llmAPIKey
        }

        return try await apiKeyStore.loadAPIKey(for: workspace.rootURL.path) ?? ""
    }

    private func minerUAPITokenAccount(for workspace: ResearchWorkspace) -> String {
        "\(workspace.rootURL.path)#mineru-api"
    }

    private func refreshAgentState(in workspace: ResearchWorkspace) async {
        do {
            let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
            agentWorkspaceSnapshot = try await agentService.snapshot(
                in: workspace,
                root: root,
                projects: researchProjects,
                currentProjectID: agentConversationProjectID,
                selectedPaperID: selectedPaperID,
                includedPaperIDs: agentKnowledgePaperIDsForContext
            )
            agentToolDefinitions = await agentService.toolDefinitions()
            agentRunHistory = try await agentService.recentRuns(in: root, limit: 200)
            allAgentThreads = try await agentService.allThreads(in: root)
            applyAgentThreadFilterForCurrentScope()
            restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
            restorePinnedAgentThreadsForCurrentProject()
            restoreAgentToolStateForCurrentScope()
            agentSessionEvents = try await agentService.sessionEvents(in: root, limit: 300)
            let runtimeLoader = AgentRuntimeConfigurationLoader()
            agentPresetDetails = try runtimeLoader.loadProductPreset(in: root)
            agentProductMCPServerStatuses = agentPresetDetails?.mcpServers ?? []
            agentLocalMCPServerStatuses = try runtimeLoader.loadLocalMCPServerStatuses(in: root)
            rebuildAgentHookActivitySummary()
            agentSidecarHealth = workspacePreferences.isSidecarDisabledForWorkspace
                ? SidecarHealth(status: "disabled", fallbackReason: "Sidecar disabled for this workspace.")
                : await sidecarCoordinator.refreshHealth()
        } catch {
            agentErrorMessage = error.localizedDescription
        }
    }

    private var agentRuntimeHookDefinitions: [AgentHookDefinition] {
        var hooks = agentPresetDetails?.hooks ?? []
        for defaultHook in AgentSafetyPreset.defaultHooks() where !hooks.contains(where: { $0.id == defaultHook.id }) {
            hooks.append(defaultHook)
        }
        return hooks.isEmpty ? AgentSafetyPreset.defaultHooks() : hooks
    }

    private func rebuildAgentHookActivitySummary() {
        let sessionIDs = agentRelevantSessionIDs
        let visibleEvents = agentSessionEvents.filter { event in
            sessionIDs.isEmpty || sessionIDs.contains(event.sessionID)
        }
        agentHookActivitySummary = AgentHookActivitySummary(
            hooks: agentRuntimeHookDefinitions,
            events: visibleEvents,
            disabledHookIDs: agentDisabledHookIDs
        )
    }

    private func attachRunToActiveThread(_ run: AgentRun, in workspace: ResearchWorkspace) async throws {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        let now = Date()
        let workspaceID = currentAgentWorkspaceID
        let workspaceName = currentAgentWorkspaceName
        let reusableThread = activeAgentThread.flatMap { thread -> AgentThread? in
            guard thread.workspaceID == nil || thread.belongsToWorkspace(id: workspaceID) else {
                return nil
            }
            return thread
        }
        var thread = reusableThread ?? AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: run.currentProjectID,
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            title: Self.agentThreadTitle(for: run),
            createdAt: now,
            updatedAt: now
        )
        thread.assignWorkspace(id: workspaceID, name: workspaceName)

        if thread.title == "New Chat" || thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            thread.title = Self.agentThreadTitle(for: run)
        }
        thread.appendRunID(run.id, updatedAt: now)

        try await agentService.upsertThread(thread, in: root)
        pendingAgentThreadsByProject[agentProjectDraftKey(run.currentProjectID)] = nil
        pendingAgentThread = nil
        activeAgentThreadID = thread.id
        allAgentThreads = try await agentService.allThreads(in: root)
        applyAgentThreadFilterForCurrentScope()
        persistAgentDraftForCurrentConversation()
    }

    private var currentAgentWorkspaceID: String? {
        guard let currentWorkspace else {
            return nil
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        return AgentThreadRepository.workspaceID(for: root)
    }

    private var currentAgentWorkspaceName: String? {
        currentResearchRoot?.displayName ?? currentWorkspace?.displayName
    }

    private func applyAgentThreadFilterForCurrentScope() {
        let workspaceID = currentAgentWorkspaceID
        agentThreads = allAgentThreads
            .filter { !$0.isArchived }
            .filter { thread in
                !isAgentThreadWorkspaceFilterEnabled || thread.belongsToWorkspace(id: workspaceID)
            }
            .sorted { first, second in
                if first.updatedAt == second.updatedAt {
                    return first.id < second.id
                }
                return first.updatedAt > second.updatedAt
            }

        if let pendingAgentThread,
           isAgentThreadWorkspaceFilterEnabled,
           !pendingAgentThread.belongsToWorkspace(id: workspaceID) {
            self.pendingAgentThread = nil
        }

        if let activeAgentThreadID,
           !agentThreads.contains(where: { $0.id == activeAgentThreadID }),
           pendingAgentThread?.id != activeAgentThreadID {
            self.activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
        } else if activeAgentThreadID == nil {
            activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
        }
    }

    private func preferredAgentThreadID(projectID: ResearchProject.ID?) -> AgentThread.ID? {
        let workspaceID = currentAgentWorkspaceID
        return agentThreads.first { $0.belongsToWorkspace(id: workspaceID) && $0.projectID == projectID }?.id
            ?? agentThreads.first { $0.belongsToWorkspace(id: workspaceID) }?.id
            ?? agentThreads.first { $0.projectID == projectID }?.id
            ?? agentThreads.first?.id
    }

    private func saveAgentDraftForCurrentConversation() {
        agentGoalDrafts[agentDraftKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)] = agentGoal
    }

    private func appendAgentStreamingResponseDelta(_ delta: String) {
        guard !delta.isEmpty else {
            return
        }
        agentStreamingRawResponseText += delta
        let visibleText = AgentVisibleResponseExtractor.visibleText(from: agentStreamingRawResponseText)
        agentStreamingResponseText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : visibleText
    }

    private func makeAgentStreamingDeltaHandler() -> (@Sendable (String) async -> Void) {
        { [weak self] delta in
            await self?.appendAgentStreamingResponseDelta(delta)
        }
    }

    private func persistAgentToolStateForCurrentScope() {
        let scopeKey = agentToolPreferenceScopeKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        let disabledToolNames = agentDisabledToolNames.sorted()
        updateWorkspacePreferences { preferences in
            if disabledToolNames.isEmpty {
                preferences.agentDisabledToolNamesByScope[scopeKey] = nil
            } else {
                preferences.agentDisabledToolNamesByScope[scopeKey] = disabledToolNames
            }
        }
    }

    private func restoreAgentToolStateForCurrentScope() {
        let scopeKey = agentToolPreferenceScopeKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        agentDisabledToolNames = Set(workspacePreferences.agentDisabledToolNamesByScope[scopeKey] ?? [])
    }

    private func persistPinnedAgentThreadsForCurrentProject() {
        let projectKey = agentProjectPreferenceKey(agentConversationProjectID)
        let pinnedIDs = pinnedAgentThreadIDs.sorted()
        updateWorkspacePreferences { preferences in
            if pinnedIDs.isEmpty {
                preferences.pinnedAgentThreadIDsByProject[projectKey] = nil
            } else {
                preferences.pinnedAgentThreadIDsByProject[projectKey] = pinnedIDs
            }
        }
    }

    private func restorePinnedAgentThreadsForCurrentProject() {
        let projectKey = agentProjectPreferenceKey(agentConversationProjectID)
        pinnedAgentThreadIDs = Set(workspacePreferences.pinnedAgentThreadIDsByProject[projectKey] ?? [])
    }

    private func agentToolPreferenceScopeKey(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) -> String {
        "project:\(agentProjectPreferenceKey(projectID))|thread:\(threadID ?? "__project__")"
    }

    private func agentProjectPreferenceKey(_ projectID: ResearchProject.ID?) -> String {
        projectID ?? "__global__"
    }

    private func agentDraftKey(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) -> String {
        AgentPromptDraft.key(projectID: projectID, threadID: threadID)
    }

    private func persistAgentDraftForCurrentConversation() {
        persistAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID, text: agentGoal)
    }

    private func persistAgentDraft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?, text: String) {
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: threadID)] = text
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            try? await agentService.saveDraft(text, projectID: projectID, threadID: threadID, in: root)
        }
    }

    private func scheduleAgentDraftPersistence() {
        let projectID = agentConversationProjectID
        let threadID = activeAgentThreadID
        let text = agentGoal

        agentDraftSaveTask?.cancel()
        agentDraftSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.persistAgentDraft(projectID: projectID, threadID: threadID, text: text)
            }
        }
    }

    private func restorePersistedAgentDraft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) {
        let key = agentDraftKey(projectID: projectID, threadID: threadID)
        if let draft = agentGoalDrafts[key] {
            agentGoal = draft
            return
        }
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                guard let draft = try await agentService.draft(projectID: projectID, threadID: threadID, in: root) else {
                    return
                }
                guard agentConversationProjectID == projectID, activeAgentThreadID == threadID else {
                    return
                }
                agentGoalDrafts[key] = draft
                agentGoal = draft
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    private func agentConversationMessagesForPrompt(limit: Int = 6) -> [LLMChatMessage] {
        agentConversationRuns
            .suffix(limit)
            .flatMap { run -> [LLMChatMessage] in
                let assistantText = [
                    run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ]
                .compactMap { $0 }
                .first ?? "Plan generated."

                return [
                    LLMChatMessage(role: .user, content: run.goal),
                    LLMChatMessage(role: .assistant, content: assistantText)
                ]
            }
    }

    private func agentProjectDraftKey(_ projectID: ResearchProject.ID?) -> String {
        projectID ?? "global"
    }

    private nonisolated static func agentThreadTitle(for run: AgentRun) -> String {
        let planTitle = run.plan.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let planTitle, !planTitle.isEmpty {
            return planTitle
        }

        let trimmedGoal = run.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedGoal.count > 48 else {
            return trimmedGoal.isEmpty ? "New Chat" : trimmedGoal
        }

        return String(trimmedGoal.prefix(45)) + "..."
    }

    private func loadMarkdownSnippets(in workspace: ResearchWorkspace) async throws {
        markdownSnippets = try await markdownSnippetRepository.load(in: workspace)
            .sorted { lhs, rhs in
                lhs.trigger.localizedStandardCompare(rhs.trigger) == .orderedAscending
            }
    }

    private func expandedMarkdownContentsIfNeeded(_ contents: String) -> String {
        for snippet in markdownSnippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            guard contents.hasSuffix(snippet.trigger) else {
                continue
            }

            let prefix = contents.dropLast(snippet.trigger.count)
            return String(prefix) + preparedSnippetBody(snippet.body)
        }

        return contents
    }

    private func preparedSnippetBody(_ body: String) -> String {
        body.replacingOccurrences(of: "${cursor}", with: "")
    }

    private func loadMarkdownDocuments(in workspace: ResearchWorkspace, selecting markdownID: String?) async throws {
        let loadedDocuments = try await markdownRepository.loadDocuments(in: workspace, project: currentResearchProject)
        markdownDocuments = loadedDocuments
        backlinkIndex = BacklinkIndex(documents: loadedDocuments)

        let nextSelectionID = markdownID ?? selectedMarkdownID ?? loadedDocuments.first?.id
        selectedMarkdownID = nextSelectionID
        selectedMarkdownDraft = loadedDocuments.first(where: { $0.id == nextSelectionID })
    }

    func paperHasWikiPage(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        FileManager.default.fileExists(atPath: wikiPageURL(for: paper, in: workspace).path)
    }

    func paperWikiStatusText(for paper: Paper, in workspace: ResearchWorkspace) -> String {
        paperHasWikiPage(paper, in: workspace) ? "Ready" : "Missing"
    }

    private func wikiPageURL(for paper: Paper, in workspace: ResearchWorkspace) -> URL {
        if let summaryURL = paper.summaryURL(in: workspace) {
            return summaryURL
        }

        return workspace.fileURL(for: "wiki/papers/\(paper.citekey).md")
    }

    private nonisolated static func joinedBibTeX(for papers: [Paper]) -> String {
        papers
            .map(BibTeXFormatter.bibTeX(for:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n") + "\n"
    }

    private nonisolated static func citationText(for paper: Paper) -> String {
        let authors = paper.authorsDisplay
        let year = paper.year.map { "(\($0))" } ?? "(n.d.)"
        let venue = (paper.publicationTitle ?? paper.venue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = venue.map { " \($0)." } ?? ""
        return "\(authors) \(year). \(paper.displayTitle).\(suffix)"
    }

    private static func selectCreateWorkspaceURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Research Workspace"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ResearchWorkspace"
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private static func selectOpenWorkspaceURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Research Workspace"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private static func selectPDFURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import PDF"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    private static func defaultPanelDirectoryURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}