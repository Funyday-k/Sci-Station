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

extension String {
    var stableHashForDebug: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

enum AgentPanelValidationError: LocalizedError {
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

enum MarkdownConversionStatusSurface {
    case agent
    case workspace
}

enum GraphExternalPaperImportError: LocalizedError {
    case missingWorkspace

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Open a workspace before adding graph papers to the library."
        }
    }
}

enum RecommendationReadingTodoError: LocalizedError {
    case missingWorkspace
    case missingImportIdentifier

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "请先打开工作区，再加入推荐论文。"
        case .missingImportIdentifier:
            return "无法加入推荐论文：缺少 arXiv、PDF 或来源链接。"
        }
    }
}

struct PendingMarkdownConversionRequest {
    var papers: [Paper]
    var workspace: ResearchWorkspace
    var statusSurface: MarkdownConversionStatusSurface
    var existingMarkdownCount: Int
}

struct PaperMarkdownConversionMetadata {
    var extractionEngine: String?
    var fallbackReason: String?
}

struct AgentMarkdownWritebackDraft {
    var targetPath: String
    var draftPath: String
    var contents: String
}

struct AgentRetrievalSelectedSourceFileStatus {
    var relativePath: String
    var exists: Bool
    var isDirectory: Bool
    var byteCount: Int
    var lineCount: Int?

    var isReadableMarkdown: Bool {
        exists && !isDirectory && byteCount > 0 && lineCount != nil
    }

    var diagnosticText: String {
        [
            "selected_source_exists=\(exists)",
            "selected_source_is_directory=\(isDirectory)",
            "selected_source_bytes=\(byteCount)",
            lineCount.map { "selected_source_lines=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
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

enum RecommendationAIEvaluationError: LocalizedError {
    case missingAPIKey
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "LLM API key is missing."
        case .timedOut(let seconds):
            return "AI request timed out after \(Int(seconds)) seconds."
        }
    }
}

struct RecommendationAISearchStrategy: Hashable, Sendable {
    var query: String
    var categories: [String]
    var source: String
}

func recommendationWithTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 1) * 1_000_000_000))
            throw RecommendationAIEvaluationError.timedOut(seconds)
        }
        guard let value = try await group.next() else {
            throw RecommendationAIEvaluationError.timedOut(seconds)
        }
        group.cancelAll()
        return value
    }
}

struct AppShellRenderState {
    var currentWorkspace: ResearchWorkspace?
    var selectedSection: WorkspaceSection?
    var selectedProjectSpaceTabID: String
    var selectedPaperTitle: String?
    var selectedPaperAuthors: String?
    var isWorking: Bool
    var shellWindowWidth: Double
    var route: WorkspaceRoute
    var context: WorkspaceContextSnapshot
    var toolbarModel: ToolbarModel
    var responsiveModel: ResponsiveShellModel
    var effectiveRightRailMode: RightRailMode
}

@MainActor
final class AppViewModel: ObservableObject {
    static let arxivRecommendationTag = "arXiv 推荐"

    let workspaceStore = WorkspaceStore()
    let libraryStore = LibraryStore()
    let knowledgeStore = KnowledgeStore()
    let recommendationStore = RecommendationStore()
    let agentStore = AgentStore()
    let navigationStore = NavigationStore()
    let graphStore = GraphStore()

    var currentWorkspace: ResearchWorkspace? {
        get { workspaceStore.workspace }
        set { workspaceStore.setWorkspace(newValue) }
    }
    var currentResearchRoot: ResearchRoot? {
        get { workspaceStore.root }
        set { workspaceStore.setRoot(newValue) }
    }
    @Published var workspaceModuleConfiguration = WorkspaceModuleRegistry.defaultConfiguration() {
        didSet {
            markHomeAggregationChanged()
        }
    }
    @Published var workspaceModuleWarnings: [WorkspaceModuleWarning] = []
    @Published var workspaceModuleDirectoryStatuses: [WorkspaceModuleDirectoryStatus] = []
    @Published var workspaceModuleOverrides: [String: WorkspaceModuleOverride] = [:]
    var researchProjects: [ResearchProject] {
        get { workspaceStore.projects }
        set {
            workspaceStore.setProjects(newValue)
            markWorkspaceDashboardChanged()
        }
    }
    var currentProjectID: ResearchProject.ID? {
        get { workspaceStore.currentProjectID }
        set {
            workspaceStore.setCurrentProjectID(newValue)
            markHomeAggregationChanged()
        }
    }
    var selectedProjectSpaceProjectID: ResearchProject.ID? {
        get { navigationStore.selectedProjectID }
        set { navigationStore.selectedProjectID = newValue }
    }
    var selectedProjectSpaceTabID: String {
        get { navigationStore.selectedProjectTabID }
        set { navigationStore.selectedProjectTabID = newValue }
    }
    var isViewingGlobalTodos: Bool {
        get { navigationStore.isViewingGlobalTodos }
        set { navigationStore.isViewingGlobalTodos = newValue }
    }
    @Published var rootCompatibilityMessage: String?
    @Published var shellStatusMessage: String?
    @Published var isShowingResearchProjectEditor = false
    @Published var researchProjectEditorDraft = ResearchProjectEditorDraft()
    @Published var isSavingResearchProject = false
    @Published var isShowingProjectDeleteConfirmation = false
    @Published var projectPendingDeletion: ResearchProject?
    @Published var projectPendingLifecycleAction: ProjectLifecycleAction = .archive
    @Published var isShowingArchivedProjects = false
    var selectedSection: WorkspaceSection? {
        get { navigationStore.selectedSection }
        set { navigationStore.selectedSection = newValue }
    }
    @Published var isShowingError = false
    @Published var errorMessage: String?
    @Published var isWorking = false
    var papers: [Paper] {
        get { libraryStore.papers }
        set {
            libraryStore.setPapers(newValue)
            markWorkspaceDashboardChanged()
        }
    }
    var projectPaperLinks: [ProjectPaperLink] {
        get { libraryStore.projectLinks }
        set { libraryStore.setProjectLinks(newValue) }
    }
    @Published var legacyPaperMigrationPlan = LegacyPaperMigrationPlan.empty
    @Published var legacyPaperMigrationReport: LegacyPaperMigrationReport?
    @Published var isLoadingLegacyPaperMigrationPlan = false
    @Published var isRunningLegacyPaperMigration = false
    var collections: [PaperCollection] {
        get { libraryStore.collections }
        set { libraryStore.setCollections(newValue) }
    }
    var tagDefinitions: [TagDefinition] {
        get { libraryStore.tags }
        set { libraryStore.setTags(newValue) }
    }
    @Published var todoTagDefinitions: [TagDefinition] = []
    @Published var todos: [TodoItem] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var systemScheduleItems: [SystemScheduleItem] = []
    @Published var systemCalendarAccessState: SystemCalendarAccessState = .notDetermined
    @Published var isLoadingSystemSchedule = false
    @Published var addTodosToAppleReminders = true
    @Published var workspacePreferences = WorkspacePreferences()
    @Published var workspaceSettingsStatusMessage: String?
    var isShellNarrowWidth: Bool {
        get { navigationStore.isShellNarrowWidth }
        set { navigationStore.updateWindow(width: shellWindowWidth, isNarrow: newValue) }
    }
    var shellWindowWidth: Double {
        get { navigationStore.shellWindowWidth }
        set { navigationStore.updateWindow(width: newValue, isNarrow: isShellNarrowWidth) }
    }
    @Published var isEditingHomeLayout = false
    @Published var isShowingHomeWidgetGallery = false
    /// Home / Project Dashboard reload signals live on a focused store so their
    /// frequent bumps no longer fire the app-wide `objectWillChange`. The Home
    /// and Dashboard views observe `homeDashboardStore` directly. See
    /// `HomeDashboardStore` (Performance Phase 3, step 1).
    let homeDashboardStore = HomeDashboardStore()
    var homeAggregationRevision: Int { homeDashboardStore.homeAggregationRevision }
    var projectDashboardRevision: Int { homeDashboardStore.projectDashboardRevision }
    @Published var isShowingWorkspaceCreationWizard = false
    @Published var workspaceCreationDraft = WorkspaceCreationDraft()
    @Published var isShowingAIManagementPanel = false
    var selectedSettingsCategory: SettingsCategory {
        get { navigationStore.selectedSettingsCategory }
        set { navigationStore.selectedSettingsCategory = newValue }
    }
    @Published var selectedPaperID: Paper.ID?
    var selectedLibraryPaperIDs: Set<Paper.ID> {
        get { libraryStore.selectedPaperIDs }
        set { libraryStore.setSelectedPaperIDs(newValue) }
    }
    @Published var selectedPaperDraft: Paper?
    @Published var selectedPaperAnnotationsDraft = ""
    @Published var isSavingSelectedPaperAnnotations = false
    @Published var selectedPDFAnnotations: [PDFAnnotationRecord] = []
    @Published var selectedPDFSelectionPreview: String?
    @Published var selectedPDFSelectionPageIndex: Int?
    @Published var libraryBatchTagText = ""
    @Published var libraryBatchStatusMessage: String?
    @Published var isShowingPaperDeleteConfirmation = false
    @Published var paperPendingDeletion: Paper?
    @Published var isShowingBibTeXExport = false
    @Published var bibTeXExportText = ""
    @Published var bibTeXExportFileName = "reference.bib"
    @Published var selectedCollectionPath: String?
    @Published var selectedTagName: String?
    @Published var selectedLibraryProjectID: ResearchProject.ID?
    @Published var collapsedCollectionPaths: Set<String> = []
    @Published var selectedDashboardDate = Calendar.current.startOfDay(for: Date())
    @Published var librarySearchText = ""
    @Published var librarySearchFocusRequest = 0
    @Published var pdfReaderSearchFocusRequest = 0
    @Published var pdfReaderFindNextRequest = 0
    @Published var pdfReaderFindPreviousRequest = 0
    @Published var pdfReaderGoToPageRequest = 0
    @Published var pdfReaderRequestedPageIndex: Int?
    @Published var inspectorFocusRequest = 0
    @Published var isImportingPDF = false
    @Published var isShowingIdentifierImport = false
    @Published var identifierImportInput = ""
    @Published var identifierImportCollectionPath = "Uncategorized"
    @Published var identifierImportTagsText = ""
    @Published var identifierImportPreview: PaperMetadataDraft?
    @Published var identifierImportStatusMessage: String?
    @Published var isResolvingIdentifierImport = false
    @Published var isPerformingIdentifierImport = false
    @Published var isSavingSelectedPaper = false
    @Published var llmConfiguration = LLMConfiguration()
    @Published var hasLLMAPIKey = false
    @Published var hasMinerUAPIToken = false
    @Published var hasLoadedSensitiveAIKeys = false
    @Published var isTestingLLMConnection = false
    @Published var llmConnectionStatusMessage: String?
    @Published var isGeneratingSummary = false
    @Published var summaryPreviewText: String?
    @Published var isShowingSummaryPreview = false
    @Published var agentGoal = "" {
        didSet {
            saveAgentDraftForCurrentConversation()
            scheduleAgentDraftPersistence()
        }
    }
    @Published var agentWorkspaceSnapshot: AgentWorkspaceSnapshot?
    var agentToolDefinitions: [AgentToolDefinition] {
        get { agentStore.toolDefinitions }
        set { agentStore.setToolDefinitions(newValue) }
    }
    @Published var agentDisabledToolNames: Set<String> = []
    var agentCurrentRun: AgentRun? {
        get { agentStore.currentRun }
        set {
            agentStore.setCurrentRun(newValue)
            markWorkspaceDashboardChanged()
        }
    }
    @Published var agentToolApprovals: Set<String> = []
    @Published var agentToolDenials: Set<String> = []
    @Published var agentToolSessionApprovalDrafts: Set<String> = []
    @Published var agentToolCorrectionFeedback: [String: String] = [:]
    var agentRunHistory: [AgentRun] {
        get { agentStore.runHistory }
        set {
            agentStore.setRunHistory(newValue)
            markWorkspaceDashboardChanged()
        }
    }
    @Published var agentSessionEvents: [AgentSessionEvent] = []
    @Published var agentTimelineVisibleLimit = 160
    var agentThreads: [AgentThread] {
        get { agentStore.threads }
        set { agentStore.setThreads(newValue) }
    }
    @Published var allAgentThreads: [AgentThread] = []
    @Published var agentNextRunContextScope: AgentContextScope = .project
    @Published var agentNextRunProjectID: ResearchProject.ID?
    @Published var isAgentThreadWorkspaceFilterEnabled = false {
        didSet { applyAgentThreadFilterForCurrentScope() }
    }
    @Published var activeAgentThreadID: AgentThread.ID?
    @Published var pendingAgentThread: AgentThread?
    @Published var pinnedAgentThreadIDs: Set<AgentThread.ID> = []
    @Published var agentPresetDetails: AgentPresetSummary?
    @Published var agentProductMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published var agentWorkspaceProfile = AgentWorkspaceProfile()
    @Published var agentWorkspaceProfileSummary: AgentWorkspaceProfileSummary?
    @Published var agentWorkspaceProfileMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published var agentPromptResolutionSummaries: [String] = []
    @Published var agentLocalMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published var agentMCPRuntimeStatuses: [AgentMCPRuntimeStatus] = []
    @Published var agentHookActivitySummary = AgentHookActivitySummary()
    @Published var agentSidecarHealth = SidecarHealth(status: "unavailable")
    @Published var agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot.disabled() {
        didSet {
            markHomeAggregationChanged()
        }
    }
    @Published var paperMarkdownQualityReport: PaperMarkdownQualityReport?
    @Published var isCheckingPaperMarkdownQuality = false
    @Published var agentDisabledHookIDs: Set<String> = []
    @Published var isShowingAgentThreadRename = false
    @Published var isShowingAgentThreadArchiveConfirmation = false
    @Published var agentThreadRenameDraft = ""
    @Published var agentThreadPendingArchive: AgentThread?
    var agentStatusMessage: String? {
        get { agentStore.statusMessage }
        set { agentStore.setStatusMessage(newValue) }
    }
    var agentErrorMessage: String? {
        get { agentStore.errorMessage }
        set { agentStore.setErrorMessage(newValue) }
    }
    @Published var selectedAgentKnowledgePaperIDs: Set<Paper.ID> = []
    @Published var isShowingAgentKnowledgeLibrary = false
    @Published var agentInteractionMode: AgentInteractionMode = .conversation
    @Published var agentPendingUserPrompt: String?
    /// High-frequency streaming text lives on a focused store so per-tick
    /// updates no longer fire the app-wide `objectWillChange`. AI Lab views
    /// observe `agentStreamStore` directly. See `AgentStreamStore`.
    let agentStreamStore = AgentStreamStore()
    var agentStreamingResponseText: String? { agentStreamStore.streamingResponseText }
    @Published var isRefreshingAgentContext = false
    @Published var isPlanningAgentRun = false
    @Published var isExecutingAgentTools = false
    @Published var isConvertingAgentKnowledgeMarkdown = false
    @Published var paperMarkdownConversionStates: [Paper.ID: PaperMarkdownConversionState] = [:]
    @Published var paperMarkdownConversionMessages: [Paper.ID: String] = [:]
    @Published var isShowingMarkdownOverwriteConfirmation = false
    @Published var isGeneratingWikiPage = false
    var markdownDocuments: [MarkdownDocument] {
        get { knowledgeStore.documents }
        set {
            knowledgeStore.setDocuments(newValue)
            markWorkspaceDashboardChanged()
        }
    }
    var selectedMarkdownID: String? {
        get { knowledgeStore.selectedDocumentID }
        set { knowledgeStore.setSelection(id: newValue, draft: selectedMarkdownDraft) }
    }
    var selectedMarkdownDraft: MarkdownDocument? {
        get { knowledgeStore.selectedDraft }
        set { knowledgeStore.setSelection(id: selectedMarkdownID, draft: newValue) }
    }
    @Published var isShowingUnsavedMarkdownConfirmation = false
    @Published var markdownSnippets: [MarkdownSnippet] = MarkdownSnippetRepository.defaultSnippets
    @Published var isSavingSelectedMarkdown = false
    var selectedMarkdownSaveState: MarkdownSaveState {
        get { knowledgeStore.saveState }
        set { knowledgeStore.setSaveState(newValue, errorMessage: selectedMarkdownSaveErrorMessage) }
    }
    var selectedMarkdownSaveErrorMessage: String? {
        get { knowledgeStore.saveErrorMessage }
        set { knowledgeStore.setSaveState(selectedMarkdownSaveState, errorMessage: newValue) }
    }

    let workspaceService: WorkspaceService
    let projectRegistryRepository: ProjectRegistryRepository
    let paperRepository: PaperRepository
    let projectPaperLinkRepository: ProjectPaperLinkRepository
    let legacyPaperMigrationService: LegacyPaperMigrationService
    let collectionRepository: CollectionRepository
    let movePaperToCollectionService: MovePaperToCollectionService
    let tagRepository: TagRepository
    let todoTagRepository = TodoTagRepository()
    let todoRepository: TodoRepository
    let calendarRepository: CalendarRepository
    let workspacePreferencesRepository: WorkspacePreferencesRepository
    let workspaceModuleConfigurationStore: WorkspaceModuleConfigurationStore
    let workspaceModuleOverrideRepository: WorkspaceModuleOverrideRepository
    let agentWorkspaceProfileRepository: AgentWorkspaceProfileRepository
    let agentPromptLibraryResolver = AgentPromptLibraryResolver()
    let agentSkillLoader = AgentSkillLoader()
    let paperAnnotationsRepository: PaperAnnotationsRepository
    let pdfAnnotationStore: PDFAnnotationStore
    let libraryBulkEditService: LibraryBulkEditService
    let systemCalendarService: SystemCalendarService
    let pdfReadingStateService: PDFReadingStateService
    let remoteImportService: RemoteImportService
    let pdfDownloadService: DownloadService
    let arxivRecommendationClient = ArxivRecommendationClient()
    let recommendationPipeline = RecommendationPipeline()
    let llmConfigurationStore: LLMConfigurationStore
    let apiKeyStore: KeychainAPIKeyStore
    let credentialBroker: CredentialBroker
    let openAIProvider: OpenAICompatibleProvider
    let paperSummaryService: PaperSummaryService
    let llmWritebackService: LLMWritebackService
    let agentService: SciStationAgentService
    let agentSessionEventLogger = AgentSessionEventLogger()
    let appDebugEventLogger = AppDebugEventLogger()
    let sidecarCoordinator: SidecarRuntimeCoordinator
    let agentEmbeddingIndexController: AgentEmbeddingIndexController
    let paperMarkdownQualityInspector = PaperMarkdownQualityInspector()
    let pdfImportService: PDFImportService
    let markdownRepository: MarkdownRepository
    let markdownSnippetRepository: MarkdownSnippetRepository
    let wikiPageGenerator: WikiPageGenerator
    var pendingMarkdownConversionRequest: PendingMarkdownConversionRequest?
    let pdfOpeningService: any PDFOpeningService
    let librarySearchService: LibrarySearchService
    let batchImportInputParser = BatchImportInputParser()
    var backlinkIndex = BacklinkIndex(documents: [])
    var pendingMarkdownSelectionID: String?
    var agentGoalDrafts: [String: String] = [:]
    var pendingAgentThreadsByProject: [String: AgentThread] = [:]
    var agentThreadPendingRename: AgentThread?
    var agentDraftSaveTask: Task<Void, Never>?
    let workspaceSessionCoordinator = WorkspaceSessionCoordinator()
    var agentPlanningTask: Task<Void, Never>?
    var agentContextRefreshTask: Task<Void, Never>?
    var agentLiveRunID: String?
    var agentLiveEventRefreshTask: Task<Void, Never>?
    var agentRetrySourceRunID: String?
    var agentStreamingRenderTask: Task<Void, Never>?
    var agentStreamingRenderGeneration = 0
    var agentStreamingResponseCommitScheduled = false
    var agentStreamingPendingResponseText: String?
    var agentStreamingRawResponseText = ""
    var workspaceModuleConfigurationWatchTask: Task<Void, Never>?
    var shellStatusDismissTask: Task<Void, Never>?
    var paperReaderReturnRoute: WorkspaceRoute?
    var shellStoreObservations: Set<AnyCancellable> = []

    let recommendationFeedbackStore = RecommendationFeedbackStore()
    var recommendationRunResult: RecommendationRunResult? {
        get { recommendationStore.runResult }
        set { recommendationStore.setRunResult(newValue) }
    }
    var recommendationHistory: [RecommendationRunResult] {
        get { recommendationStore.history }
        set { recommendationStore.setHistory(newValue) }
    }
    var recommendationFeedbackByScoreID: [String: RecommendationFeedbackType] {
        get { recommendationStore.feedbackByScoreID }
        set { recommendationStore.setFeedback(newValue) }
    }
    var recommendationCandidateCount: Int {
        get { recommendationStore.candidateCount }
        set { recommendationStore.setCandidateCount(newValue) }
    }
    var isRefreshingRecommendations: Bool {
        get { recommendationStore.isRefreshing }
        set { recommendationStore.setRefreshing(newValue) }
    }
    var isEvaluatingRecommendationsWithAI: Bool {
        get { recommendationStore.isEvaluatingWithAI }
        set { recommendationStore.setEvaluatingWithAI(newValue) }
    }
    var recommendationErrorMessage: String? {
        get { recommendationStore.errorMessage }
        set { recommendationStore.setErrorMessage(newValue) }
    }
    var recommendationAIEvaluationStatusMessage: String? {
        get { recommendationStore.aiEvaluationStatusMessage }
        set { recommendationStore.setAIEvaluationStatusMessage(newValue) }
    }
    @Published var recommendationLibraryImportScoreIDs: Set<String> = []
    @Published var recommendationReadingTodoImportScoreIDs: Set<String> = []
    @Published var isShowingSkillImport = false
    @Published var pendingSkillImportPlan: AgentSkillInstallPlan?
#if DEBUG
    var uiTestBridgeServer: UITestBridgeServer?
    /// When the UI test bridge is active, all `recordAppDebugEvent` calls are
    /// forced regardless of the per-workspace ``agentDebugLoggingEnabled``
    /// preference. Scenarios depend on domain events (e.g. ``wiki.file.rename``)
    /// landing in ``.sci-station/debug/app_events.jsonl`` even on a fresh
    /// workspace where the user has not opted into verbose logging.
    var uiTestBridgeForceDebugLogging: Bool = false
#endif

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
        var names = Set(agentToolDefinitions.map(\.name)).subtracting(agentDisabledToolNames)
        if !enabledAgentWorkflowIDs.contains("graph_insight") {
            names.subtract(GraphAgentTools.allNames)
        }
        return names
    }

    var agentEnabledToolSummary: String {
        let count = agentEnabledToolNames.count
        return "\(count) 工具"
    }

    var agentVisibleMode: AgentVisibleMode {
        agentInteractionMode.visibleMode
    }

    var agentVisibleModeStatusText: String {
        agentVisibleMode.permissionSummary
    }

    var agentToolAvailabilityWarning: String? {
        guard !agentToolDefinitions.isEmpty else {
            return nil
        }
        if agentEnabledToolNames.isEmpty {
            return "当前模式没有可用工具。请在工具菜单启用至少一个工具后再发送。"
        }
        guard agentVisibleMode.hasRequiredTools(
            availableTools: agentToolDefinitions,
            enabledToolNames: agentEnabledToolNames
        ) else {
            switch agentVisibleMode {
            case .plan:
                return "Plan 模式至少需要一个只读工具。请启用读取/搜索工具，或检查当前工具范围。"
            case .agent:
                return "Agent 模式没有可用工具。请启用工具后再运行。"
            }
        }
        return nil
    }

    var agentKnowledgePaperIDsForContext: Set<Paper.ID> {
        selectedAgentKnowledgePaperIDs.intersection(Set(papers.map(\.id)))
    }

    var agentModeStatusText: String {
        agentVisibleModeStatusText
    }

    var workspaceTemplateOptions: [WorkspaceTemplate] {
        WorkspaceTemplateRegistry.builtInTemplates
    }

    var workspaceCreationTemplateOptions: [WorkspaceCreationTemplateOption] {
        WorkspaceCreationWizard.templateOptions
    }

    var workspaceCreationPreview: WorkspaceCreationPreview {
        WorkspaceCreationWizard.preview(for: workspaceCreationDraft)
    }

    var workspaceCreationTargetValidation: WorkspaceCreationTargetValidation {
        WorkspaceCreationWizard.validateTargetURL(workspaceCreationDraft.targetURL)
    }

    var canCompleteWorkspaceCreation: Bool {
        workspaceCreationTargetValidation.canCreate
            && workspaceCreationDraft.privacyAcknowledged
            && WorkspaceCreationWizard.templateOption(id: workspaceCreationDraft.templateID).isSelectable
            && !isWorking
    }

    var visibleWorkspaceSidebarSections: [WorkspaceSection] {
        topSidebarItems.map { WorkspaceNavigationPolicy.section(for: $0.top) }
    }

    var topSidebarItems: [TopSidebarItem] {
        TopSidebarBuilder.items(pinnedOrder: workspacePreferences.pinnedTopLevelOrder)
    }

    var currentWorkspaceRoute: WorkspaceRoute {
        WorkspaceNavigationPolicy.route(
            selectedSection: selectedSection,
            selectedProjectID: selectedProjectSpaceProjectID,
            selectedProjectTabID: selectedProjectSpaceTabID,
            currentProjectID: currentProjectID,
            librarySecondarySelection: selectedLibraryProjectID ?? selectedCollectionPath ?? selectedTagName,
            isViewingGlobalTodos: isViewingGlobalTodos,
            agentProjectID: agentConversationProjectID
        )
    }

    var shellRenderState: AppShellRenderState {
        let route = currentWorkspaceRoute
        let context = workspaceContextSnapshot(for: route)
        let baseToolbarModel = ToolbarPolicy.resolve(route: route, context: context, language: appLanguage)
        let toolbarModel = ResponsiveShellPolicy.toolbarModel(baseToolbarModel, width: shellWindowWidth)
        let responsiveModel = responsiveShellModel(route: route, context: context)
        let effectiveRightRailMode = effectiveRightRailMode(responsiveModel: responsiveModel, selectedSection: selectedSection)
        return AppShellRenderState(
            currentWorkspace: currentWorkspace,
            selectedSection: selectedSection,
            selectedProjectSpaceTabID: selectedProjectSpaceTabID,
            selectedPaperTitle: selectedPaperDraft?.displayTitle,
            selectedPaperAuthors: selectedPaperDraft?.authorsDisplay,
            isWorking: isWorking,
            shellWindowWidth: shellWindowWidth,
            route: route,
            context: context,
            toolbarModel: toolbarModel,
            responsiveModel: responsiveModel,
            effectiveRightRailMode: effectiveRightRailMode
        )
    }

    var currentWorkspaceContextSnapshot: WorkspaceContextSnapshot {
        let route = currentWorkspaceRoute
        return workspaceContextSnapshot(for: route)
    }

    func workspaceContextSnapshot(for route: WorkspaceRoute) -> WorkspaceContextSnapshot {
        let projectID = route.projectID
        let project = projectID.flatMap { id in activeResearchProjects.first { $0.id == id } }
        let selectedDateRange: DateInterval? = route.top == .calendar ? calendarDayRange(for: selectedDashboardDate) : nil
        let selectedPaperMarkdownPath = selectedPaperDraft.map { paperMarkdownPath(for: $0) }

        return WorkspaceContextSnapshot(
            topLevelSectionID: route.top.rawValue,
            projectID: projectID,
            projectTitle: project?.name,
            projectTabID: route.projectTabID,
            selectedPaperID: selectedPaperDraft?.id,
            selectedPaperTitle: selectedPaperDraft?.displayTitle,
            selectedPaperMarkdownPath: selectedPaperMarkdownPath,
            selectedMarkdownPath: selectedMarkdownDraft?.relativePath ?? selectedPaperMarkdownPath,
            selectedTodoID: nil,
            calendarDateRange: selectedDateRange,
            pdfPageIndex: selectedPDFSelectionPageIndex ?? selectedPaperDraft?.lastReadPage,
            selectedTextPreview: selectedPDFSelectionPreview
        )
    }

    var toolbarModel: ToolbarModel {
        let route = currentWorkspaceRoute
        let model = ToolbarPolicy.resolve(route: route, context: workspaceContextSnapshot(for: route), language: appLanguage)
        return ResponsiveShellPolicy.toolbarModel(model, width: shellWindowWidth)
    }

    var responsiveShellModel: ResponsiveShellModel {
        let route = currentWorkspaceRoute
        return responsiveShellModel(route: route, context: workspaceContextSnapshot(for: route))
    }

    func responsiveShellModel(route: WorkspaceRoute, context: WorkspaceContextSnapshot) -> ResponsiveShellModel {
        ResponsiveShellPolicy.resolve(
            width: shellWindowWidth,
            route: route,
            context: context,
            preferredRightRailMode: workspacePreferences.rightRailMode
        )
    }

    func markHomeAggregationChanged() {
        homeDashboardStore.markHomeAggregationChanged()
    }

    func markWorkspaceDashboardChanged() {
        homeDashboardStore.markProjectDashboardChanged()
    }

    var effectiveRightRailMode: RightRailMode {
        guard currentWorkspace != nil else {
            return .hidden
        }
        return effectiveRightRailMode(responsiveModel: responsiveShellModel, selectedSection: selectedSection)
    }

    func effectiveRightRailMode(responsiveModel: ResponsiveShellModel, selectedSection: WorkspaceSection?) -> RightRailMode {
        guard currentWorkspace != nil else {
            return .hidden
        }
        let mode = responsiveModel.effectiveRightRailMode
        return mode == .inspector && !rightRailHasContent(for: selectedSection) ? .hidden : mode
    }

    var rightRailHasContent: Bool {
        rightRailHasContent(for: selectedSection)
    }

    func rightRailHasContent(for selectedSection: WorkspaceSection?) -> Bool {
        switch selectedSection {
        case .some(.library), .some(.wiki), .some(.dashboard), .some(.projects), .some(.calendar), .some(.tasks), .some(.pdfReader):
            return true
        default:
            return false
        }
    }

    var pinnedResearchProjects: [ResearchProject] {
        let activeByID = Dictionary(uniqueKeysWithValues: activeResearchProjects.map { ($0.id, $0) })
        return workspacePreferences.pinnedProjectIDs.compactMap { activeByID[$0] }
    }

    var recentResearchProjects: [ResearchProject] {
        let pinnedIDs = Set(workspacePreferences.pinnedProjectIDs)
        return activeResearchProjects
            .filter { !pinnedIDs.contains($0.id) }
            .sorted { first, second in
                if first.updatedAt == second.updatedAt {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.updatedAt > second.updatedAt
            }
    }

    var archivedResearchProjects: [ResearchProject] {
        researchProjects
            .filter(\.isArchived)
            .sorted { first, second in
                if first.updatedAt == second.updatedAt {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.updatedAt > second.updatedAt
            }
    }

    func sidebarProjects(searchText: String, includeArchived: Bool) -> [ResearchProject] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = includeArchived ? researchProjects : activeResearchProjects
        return candidates.filter { project in
            guard !trimmedSearch.isEmpty else {
                return true
            }
            return project.name.localizedCaseInsensitiveContains(trimmedSearch)
                || project.description.localizedCaseInsensitiveContains(trimmedSearch)
                || project.relativePath.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var visibleProjectSidebarSections: [WorkspaceSection] {
        visibleProjectSidebarSections(for: currentProjectID)
    }

    var selectedProjectSpaceProject: ResearchProject? {
        guard let selectedProjectSpaceProjectID else {
            return nil
        }
        return activeResearchProjects.first { $0.id == selectedProjectSpaceProjectID }
    }

    var selectedProjectSpaceTabs: [ProjectSpaceTab] {
        guard let projectID = selectedProjectSpaceProjectID else {
            return []
        }
        return projectSpaceTabs(for: projectID)
    }

    var enabledAgentWorkflowIDs: Set<String> {
        Set(workspaceContributionCatalog(for: currentProjectID).availableWorkflows())
    }

    var workspaceModuleStatusSummary: String {
        let enabledCount = workspaceModuleConfiguration.modules.filter(\.enabled).count
        let workspaceWorkflowCount = workspaceContributionCatalog(for: nil).availableWorkflows().count
        return "\(enabledCount)/\(workspaceModuleConfiguration.modules.count) modules enabled; \(workspaceWorkflowCount) workflows available"
    }

    func effectiveModuleConfiguration(for projectID: ResearchProject.ID?) -> WorkspaceModuleConfiguration {
        ModuleOverrideMerger.effectiveConfiguration(
            workspace: workspaceModuleConfiguration,
            override: projectID.flatMap { workspaceModuleOverrides[$0] }
        )
    }

    func workspaceContributionCatalog(for projectID: ResearchProject.ID?) -> PluginWorkspaceContributionCatalog {
        PluginWorkspaceContributionCatalog(configuration: effectiveModuleConfiguration(for: projectID))
    }

    func visibleProjectSidebarSections(for projectID: ResearchProject.ID?) -> [WorkspaceSection] {
        let configuration = effectiveModuleConfiguration(for: projectID)
        return orderedProjectSections(WorkspaceSection.legacyProjectSidebarSections, using: configuration)
            .filter { isWorkspaceProjectTabAvailable($0, projectID: projectID) }
    }

    func projectSpaceTabs(for projectID: ResearchProject.ID) -> [ProjectSpaceTab] {
        ProjectSpaceTabsBuilder.tabs(
            for: projectID,
            catalog: workspaceContributionCatalog(for: projectID),
            pinnedOrder: workspacePreferences.projectSpacePinnedOrder
        )
    }

    func isWorkspaceSectionAvailable(_ section: WorkspaceSection) -> Bool {
        if section.isTopLevel {
            return true
        }
        guard let routeID = section.moduleRouteID else {
            return true
        }
        return workspaceContributionCatalog(for: nil).availableRoutes().contains { $0.id == routeID }
    }

    func isWorkspaceProjectTabAvailable(_ section: WorkspaceSection, projectID: ResearchProject.ID? = nil) -> Bool {
        guard let tabID = section.moduleProjectTabID else {
            return true
        }
        return workspaceContributionCatalog(for: projectID ?? currentProjectID).availableProjectTabs().contains { $0.id == tabID }
    }

    func workspaceArtifactKindDescriptor(for kind: String?) -> WorkspaceModuleArtifactKindDescriptor? {
        guard let kind = kind?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty else {
            return nil
        }
        return workspaceContributionCatalog(for: currentProjectID).artifactKindDescriptor(for: kind)
    }

    func orderedWorkspaceSections(_ sections: [WorkspaceSection], using configuration: WorkspaceModuleConfiguration) -> [WorkspaceSection] {
        orderedSections(sections, using: configuration) { section in
            guard let routeID = section.moduleRouteID else { return nil }
            return configuration.modules.first { module in
                module.routes.contains { $0.id == routeID }
            }?.id
        }
    }

    func orderedProjectSections(_ sections: [WorkspaceSection], using configuration: WorkspaceModuleConfiguration) -> [WorkspaceSection] {
        orderedSections(sections, using: configuration) { section in
            guard let tabID = section.moduleProjectTabID else { return nil }
            return configuration.modules.first { module in
                module.projectTabs.contains { $0.id == tabID }
            }?.id
        }
    }

    func orderedSections(
        _ sections: [WorkspaceSection],
        using configuration: WorkspaceModuleConfiguration,
        moduleIDForSection: (WorkspaceSection) -> String?
    ) -> [WorkspaceSection] {
        let pinnedOrder = WorkspaceModuleSettingsMutation.pinnedOrder(in: configuration)
        guard !pinnedOrder.isEmpty else {
            return sections
        }

        return sections.enumerated().sorted { first, second in
            let firstRank = moduleIDForSection(first.element).flatMap { pinnedOrder.firstIndex(of: $0) }
            let secondRank = moduleIDForSection(second.element).flatMap { pinnedOrder.firstIndex(of: $0) }
            switch (firstRank, secondRank) {
            case let (lhs?, rhs?):
                if lhs == rhs { return first.offset < second.offset }
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return first.offset < second.offset
            }
        }.map(\.element)
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

    var effectiveAgentAllowedToolNames: Set<String>? {
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
        workspaceModuleConfigurationStore: WorkspaceModuleConfigurationStore? = nil,
        workspaceModuleOverrideRepository: WorkspaceModuleOverrideRepository? = nil,
        agentWorkspaceProfileRepository: AgentWorkspaceProfileRepository? = nil,
        paperAnnotationsRepository: PaperAnnotationsRepository? = nil,
        pdfAnnotationStore: PDFAnnotationStore? = nil,
        libraryBulkEditService: LibraryBulkEditService? = nil,
        systemCalendarService: SystemCalendarService? = nil,
        pdfReadingStateService: PDFReadingStateService? = nil,
        remoteImportService: RemoteImportService? = nil,
        pdfDownloadService: DownloadService? = nil,
        llmConfigurationStore: LLMConfigurationStore? = nil,
        apiKeyStore: KeychainAPIKeyStore? = nil,
        credentialBroker: CredentialBroker? = nil,
        openAIProvider: OpenAICompatibleProvider? = nil,
        paperSummaryService: PaperSummaryService? = nil,
        llmWritebackService: LLMWritebackService? = nil,
        agentService: SciStationAgentService? = nil,
        sidecarCoordinator: SidecarRuntimeCoordinator? = nil,
        agentEmbeddingIndexController: AgentEmbeddingIndexController? = nil,
        markdownRepository: MarkdownRepository? = nil,
        markdownSnippetRepository: MarkdownSnippetRepository? = nil,
        pdfOpeningService: (any PDFOpeningService)? = nil,
        installRuntimeBridges: Bool = true
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
        let resolvedWorkspaceModuleConfigurationStore = workspaceModuleConfigurationStore ?? WorkspaceModuleConfigurationStore()
        let resolvedWorkspaceModuleOverrideRepository = workspaceModuleOverrideRepository ?? WorkspaceModuleOverrideRepository()
        let resolvedAgentWorkspaceProfileRepository = agentWorkspaceProfileRepository ?? AgentWorkspaceProfileRepository()
        let resolvedPaperAnnotationsRepository = paperAnnotationsRepository ?? PaperAnnotationsRepository()
        let resolvedPDFAnnotationStore = pdfAnnotationStore ?? PDFAnnotationStore()
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
        let resolvedCredentialBroker = credentialBroker ?? CredentialBroker(store: resolvedAPIKeyStore)
        let resolvedOpenAIProvider = openAIProvider ?? OpenAICompatibleProvider()
        let resolvedPaperSummaryService = paperSummaryService ?? PaperSummaryService(provider: resolvedOpenAIProvider)
        let resolvedLLMWritebackService = llmWritebackService ?? LLMWritebackService()
        let resolvedSidecarCoordinator = sidecarCoordinator ?? SidecarRuntimeCoordinator()
        let resolvedAgentEmbeddingIndexController = agentEmbeddingIndexController ?? AgentEmbeddingIndexController()
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
        self.workspaceModuleConfigurationStore = resolvedWorkspaceModuleConfigurationStore
        self.workspaceModuleOverrideRepository = resolvedWorkspaceModuleOverrideRepository
        self.agentWorkspaceProfileRepository = resolvedAgentWorkspaceProfileRepository
        self.paperAnnotationsRepository = resolvedPaperAnnotationsRepository
        self.pdfAnnotationStore = resolvedPDFAnnotationStore
        self.libraryBulkEditService = resolvedLibraryBulkEditService
        self.systemCalendarService = resolvedSystemCalendarService
        self.systemCalendarAccessState = resolvedSystemCalendarService.accessState
        self.pdfReadingStateService = resolvedPDFReadingStateService
        self.remoteImportService = resolvedRemoteImportService
        self.pdfDownloadService = pdfDownloadService ?? DownloadService()
        self.llmConfigurationStore = resolvedLLMConfigurationStore
        self.apiKeyStore = resolvedAPIKeyStore
        self.credentialBroker = resolvedCredentialBroker
        self.openAIProvider = resolvedOpenAIProvider
        self.paperSummaryService = resolvedPaperSummaryService
        self.llmWritebackService = resolvedLLMWritebackService
        self.agentService = resolvedAgentService
        self.sidecarCoordinator = resolvedSidecarCoordinator
        self.agentEmbeddingIndexController = resolvedAgentEmbeddingIndexController
        self.pdfImportService = PDFImportService(repository: resolvedPaperRepository)
        self.markdownRepository = resolvedMarkdownRepository
        self.markdownSnippetRepository = resolvedMarkdownSnippetRepository
        self.wikiPageGenerator = WikiPageGenerator(paperRepository: resolvedPaperRepository)
        self.pdfOpeningService = pdfOpeningService ?? SystemPDFOpeningService()
        self.librarySearchService = LibrarySearchService()
        for publisher in [workspaceStore.objectWillChange, navigationStore.objectWillChange] {
            publisher.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &shellStoreObservations)
        }
#if DEBUG
        if installRuntimeBridges {
            installUITestBridgeIfRequested()
        }
#endif
    }

}
