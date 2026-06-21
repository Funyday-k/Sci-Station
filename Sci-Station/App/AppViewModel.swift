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

private extension String {
    var stableHashForDebug: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
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

private enum GraphExternalPaperImportError: LocalizedError {
    case missingWorkspace

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Open a workspace before adding graph papers to the library."
        }
    }
}

private enum RecommendationReadingTodoError: LocalizedError {
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

private struct AgentMarkdownWritebackDraft {
    var targetPath: String
    var draftPath: String
    var contents: String
}

private struct AgentRetrievalSelectedSourceFileStatus {
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

private enum RecommendationAIEvaluationError: LocalizedError {
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

private struct RecommendationAISearchStrategy: Hashable, Sendable {
    var query: String
    var categories: [String]
    var source: String
}

private func recommendationWithTimeout<T: Sendable>(
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
    private static let arxivRecommendationTag = "arXiv 推荐"

    @Published private(set) var currentWorkspace: ResearchWorkspace?
    @Published private(set) var currentResearchRoot: ResearchRoot?
    @Published private(set) var workspaceModuleConfiguration = WorkspaceModuleRegistry.defaultConfiguration() {
        didSet {
            markHomeAggregationChanged()
        }
    }
    @Published private(set) var workspaceModuleWarnings: [WorkspaceModuleWarning] = []
    @Published private(set) var workspaceModuleDirectoryStatuses: [WorkspaceModuleDirectoryStatus] = []
    @Published private(set) var workspaceModuleOverrides: [String: WorkspaceModuleOverride] = [:]
    @Published private(set) var researchProjects: [ResearchProject] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var currentProjectID: ResearchProject.ID? {
        didSet {
            markHomeAggregationChanged()
        }
    }
    @Published private(set) var selectedProjectSpaceProjectID: ResearchProject.ID?
    @Published private(set) var selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
    @Published private(set) var isViewingGlobalTodos = false
    @Published private(set) var rootCompatibilityMessage: String?
    @Published private(set) var shellStatusMessage: String?
    @Published var isShowingResearchProjectEditor = false
    @Published var researchProjectEditorDraft = ResearchProjectEditorDraft()
    @Published private(set) var isSavingResearchProject = false
    @Published var isShowingProjectDeleteConfirmation = false
    @Published private(set) var projectPendingDeletion: ResearchProject?
    @Published private(set) var projectPendingLifecycleAction: ProjectLifecycleAction = .archive
    @Published var isShowingArchivedProjects = false
    @Published var selectedSection: WorkspaceSection? = .projects
    @Published var isShowingError = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var papers: [Paper] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var projectPaperLinks: [ProjectPaperLink] = []
    @Published private(set) var legacyPaperMigrationPlan = LegacyPaperMigrationPlan.empty
    @Published private(set) var legacyPaperMigrationReport: LegacyPaperMigrationReport?
    @Published private(set) var isLoadingLegacyPaperMigrationPlan = false
    @Published private(set) var isRunningLegacyPaperMigration = false
    @Published private(set) var collections: [PaperCollection] = []
    @Published private(set) var tagDefinitions: [TagDefinition] = []
    @Published private(set) var todoTagDefinitions: [TagDefinition] = []
    @Published private(set) var todos: [TodoItem] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var calendarEvents: [CalendarEvent] = []
    @Published private(set) var systemScheduleItems: [SystemScheduleItem] = []
    @Published private(set) var systemCalendarAccessState: SystemCalendarAccessState = .notDetermined
    @Published private(set) var isLoadingSystemSchedule = false
    @Published var addTodosToAppleReminders = true
    @Published private(set) var workspacePreferences = WorkspacePreferences()
    @Published private(set) var workspaceSettingsStatusMessage: String?
    @Published private(set) var isShellNarrowWidth = false
    @Published private(set) var shellWindowWidth: Double = 1440
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
    @Published private(set) var workspaceCreationDraft = WorkspaceCreationDraft()
    @Published var selectedSettingsCategory: SettingsCategory = .workspace
    @Published private(set) var selectedPaperID: Paper.ID?
    @Published private(set) var selectedLibraryPaperIDs: Set<Paper.ID> = []
    @Published private(set) var selectedPaperDraft: Paper?
    @Published var selectedPaperAnnotationsDraft = ""
    @Published private(set) var isSavingSelectedPaperAnnotations = false
    @Published private(set) var selectedPDFAnnotations: [PDFAnnotationRecord] = []
    @Published private(set) var selectedPDFSelectionPreview: String?
    @Published private(set) var selectedPDFSelectionPageIndex: Int?
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
    @Published private(set) var pdfReaderGoToPageRequest = 0
    @Published private(set) var pdfReaderRequestedPageIndex: Int?
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
    @Published private(set) var agentCurrentRun: AgentRun? {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var agentToolApprovals: Set<String> = []
    @Published private(set) var agentToolDenials: Set<String> = []
    @Published private(set) var agentToolSessionApprovalDrafts: Set<String> = []
    @Published private(set) var agentToolCorrectionFeedback: [String: String] = [:]
    @Published private(set) var agentRunHistory: [AgentRun] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var agentSessionEvents: [AgentSessionEvent] = []
    @Published private(set) var agentTimelineVisibleLimit = 160
    @Published private(set) var agentThreads: [AgentThread] = []
    @Published private(set) var allAgentThreads: [AgentThread] = []
    @Published private(set) var agentNextRunContextScope: AgentContextScope = .project
    @Published private(set) var agentNextRunProjectID: ResearchProject.ID?
    @Published var isAgentThreadWorkspaceFilterEnabled = false {
        didSet { applyAgentThreadFilterForCurrentScope() }
    }
    @Published private(set) var activeAgentThreadID: AgentThread.ID?
    @Published private(set) var pendingAgentThread: AgentThread?
    @Published private(set) var pinnedAgentThreadIDs: Set<AgentThread.ID> = []
    @Published private(set) var agentPresetDetails: AgentPresetSummary?
    @Published private(set) var agentProductMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published private(set) var agentWorkspaceProfileSummary: AgentWorkspaceProfileSummary?
    @Published private(set) var agentWorkspaceProfileMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published private(set) var agentLocalMCPServerStatuses: [AgentMCPServerStatus] = []
    @Published private(set) var agentHookActivitySummary = AgentHookActivitySummary()
    @Published private(set) var agentSidecarHealth = SidecarHealth(status: "unavailable")
    @Published private(set) var agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot.disabled() {
        didSet {
            markHomeAggregationChanged()
        }
    }
    @Published private(set) var paperMarkdownQualityReport: PaperMarkdownQualityReport?
    @Published private(set) var isCheckingPaperMarkdownQuality = false
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
    /// High-frequency streaming text lives on a focused store so per-tick
    /// updates no longer fire the app-wide `objectWillChange`. AI Lab views
    /// observe `agentStreamStore` directly. See `AgentStreamStore`.
    let agentStreamStore = AgentStreamStore()
    var agentStreamingResponseText: String? { agentStreamStore.streamingResponseText }
    @Published private(set) var isRefreshingAgentContext = false
    @Published private(set) var isPlanningAgentRun = false
    @Published private(set) var isExecutingAgentTools = false
    @Published private(set) var isConvertingAgentKnowledgeMarkdown = false
    @Published private(set) var paperMarkdownConversionStates: [Paper.ID: PaperMarkdownConversionState] = [:]
    @Published private(set) var paperMarkdownConversionMessages: [Paper.ID: String] = [:]
    @Published var isShowingMarkdownOverwriteConfirmation = false
    @Published private(set) var isGeneratingWikiPage = false
    @Published private(set) var markdownDocuments: [MarkdownDocument] = [] {
        didSet {
            markWorkspaceDashboardChanged()
        }
    }
    @Published private(set) var selectedMarkdownID: String?
    @Published private(set) var selectedMarkdownDraft: MarkdownDocument?
    @Published var isShowingUnsavedMarkdownConfirmation = false
    @Published private(set) var markdownSnippets: [MarkdownSnippet] = MarkdownSnippetRepository.defaultSnippets
    @Published private(set) var isSavingSelectedMarkdown = false
    @Published private(set) var selectedMarkdownSaveState = MarkdownSaveState.clean
    @Published private(set) var selectedMarkdownSaveErrorMessage: String?

    private let workspaceService: WorkspaceService
    private let projectRegistryRepository: ProjectRegistryRepository
    private let paperRepository: PaperRepository
    private let projectPaperLinkRepository: ProjectPaperLinkRepository
    private let legacyPaperMigrationService: LegacyPaperMigrationService
    private let collectionRepository: CollectionRepository
    private let movePaperToCollectionService: MovePaperToCollectionService
    private let tagRepository: TagRepository
    private let todoTagRepository = TodoTagRepository()
    private let todoRepository: TodoRepository
    private let calendarRepository: CalendarRepository
    private let workspacePreferencesRepository: WorkspacePreferencesRepository
    private let workspaceModuleConfigurationStore: WorkspaceModuleConfigurationStore
    private let workspaceModuleOverrideRepository: WorkspaceModuleOverrideRepository
    private let paperAnnotationsRepository: PaperAnnotationsRepository
    private let pdfAnnotationStore: PDFAnnotationStore
    private let libraryBulkEditService: LibraryBulkEditService
    private let systemCalendarService: SystemCalendarService
    private let pdfReadingStateService: PDFReadingStateService
    private let remoteImportService: RemoteImportService
    private let pdfDownloadService: DownloadService
    private let arxivRecommendationClient = ArxivRecommendationClient()
    private let recommendationPipeline = RecommendationPipeline()
    private let llmConfigurationStore: LLMConfigurationStore
    private let apiKeyStore: KeychainAPIKeyStore
    private let openAIProvider: OpenAICompatibleProvider
    private let paperSummaryService: PaperSummaryService
    private let llmWritebackService: LLMWritebackService
    private let agentService: SciStationAgentService
    private let agentSessionEventLogger = AgentSessionEventLogger()
    private let appDebugEventLogger = AppDebugEventLogger()
    private let sidecarCoordinator: SidecarRuntimeCoordinator
    private let agentEmbeddingIndexController: AgentEmbeddingIndexController
    private let paperMarkdownQualityInspector = PaperMarkdownQualityInspector()
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
    private var agentContextRefreshTask: Task<Void, Never>?
    private var agentLiveRunID: String?
    private var agentLiveEventRefreshTask: Task<Void, Never>?
    private var agentRetrySourceRunID: String?
    private var agentStreamingRenderTask: Task<Void, Never>?
    private var agentStreamingRenderGeneration = 0
    private var agentStreamingResponseCommitScheduled = false
    private var agentStreamingPendingResponseText: String?
    private var agentStreamingRawResponseText = ""
    private var workspaceModuleConfigurationWatchTask: Task<Void, Never>?
    private var shellStatusDismissTask: Task<Void, Never>?
    private var paperReaderReturnRoute: WorkspaceRoute?

    private let recommendationFeedbackStore = RecommendationFeedbackStore()
    @Published private(set) var recommendationRunResult: RecommendationRunResult?
    @Published private(set) var recommendationHistory: [RecommendationRunResult] = []
    @Published private(set) var recommendationFeedbackByScoreID: [String: RecommendationFeedbackType] = [:]
    @Published private(set) var recommendationCandidateCount: Int = 0
    @Published private(set) var isRefreshingRecommendations: Bool = false
    @Published private(set) var isEvaluatingRecommendationsWithAI: Bool = false
    @Published private(set) var recommendationErrorMessage: String?
    @Published private(set) var recommendationAIEvaluationStatusMessage: String?
    @Published private(set) var recommendationLibraryImportScoreIDs: Set<String> = []
    @Published private(set) var recommendationReadingTodoImportScoreIDs: Set<String> = []
#if DEBUG
    private var uiTestBridgeServer: UITestBridgeServer?
    /// When the UI test bridge is active, all `recordAppDebugEvent` calls are
    /// forced regardless of the per-workspace ``agentDebugLoggingEnabled``
    /// preference. Scenarios depend on domain events (e.g. ``wiki.file.rename``)
    /// landing in ``.sci-station/debug/app_events.jsonl`` even on a fresh
    /// workspace where the user has not opted into verbose logging.
    private var uiTestBridgeForceDebugLogging: Bool = false
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
        topSidebarItems.map { workspaceSection(for: $0.top) }
    }

    var topSidebarItems: [TopSidebarItem] {
        TopSidebarBuilder.items(pinnedOrder: workspacePreferences.pinnedTopLevelOrder)
    }

    var currentWorkspaceRoute: WorkspaceRoute {
        switch selectedSection {
        case .some(.dashboard):
            return .home
        case .some(.projects):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID, projectTabID: selectedProjectSpaceProjectID == nil ? nil : selectedProjectSpaceTabID)
        case .some(.library):
            return WorkspaceRoute(top: .library, secondarySelection: selectedLibraryProjectID ?? selectedCollectionPath ?? selectedTagName)
        case .some(.calendar), .some(.tasks):
            return WorkspaceRoute(top: .calendar, secondarySelection: isViewingGlobalTodos ? "global_todos" : nil)
        case .some(.llmLab):
            return WorkspaceRoute(top: .aiLab, projectID: agentConversationProjectID)
        case .some(.settings):
            return WorkspaceRoute(top: .settings)
        case .some(.pdfReader):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID ?? currentProjectID, projectTabID: "pdf-reader")
        case .some(.wiki):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID ?? currentProjectID, projectTabID: "wiki")
        case .some(.materials):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID ?? currentProjectID, projectTabID: "materials")
        case .some(.graph):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID ?? currentProjectID, projectTabID: "graph")
        case .some(.inbox), .some(.papers), .some(.concepts), .some(.methods), .some(.gaps):
            return WorkspaceRoute(top: .projects, projectID: selectedProjectSpaceProjectID ?? currentProjectID, projectTabID: projectSpaceTabID(for: selectedSection ?? .projects))
        case .none:
            return .home
        }
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

    private func workspaceContextSnapshot(for route: WorkspaceRoute) -> WorkspaceContextSnapshot {
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

    private func responsiveShellModel(route: WorkspaceRoute, context: WorkspaceContextSnapshot) -> ResponsiveShellModel {
        ResponsiveShellPolicy.resolve(
            width: shellWindowWidth,
            route: route,
            context: context,
            preferredRightRailMode: workspacePreferences.rightRailMode
        )
    }

    private func markHomeAggregationChanged() {
        homeDashboardStore.markHomeAggregationChanged()
    }

    private func markWorkspaceDashboardChanged() {
        homeDashboardStore.markProjectDashboardChanged()
    }

    var effectiveRightRailMode: RightRailMode {
        guard currentWorkspace != nil else {
            return .hidden
        }
        return effectiveRightRailMode(responsiveModel: responsiveShellModel, selectedSection: selectedSection)
    }

    private func effectiveRightRailMode(responsiveModel: ResponsiveShellModel, selectedSection: WorkspaceSection?) -> RightRailMode {
        guard currentWorkspace != nil else {
            return .hidden
        }
        let mode = responsiveModel.effectiveRightRailMode
        return mode == .inspector && !rightRailHasContent(for: selectedSection) ? .hidden : mode
    }

    var rightRailHasContent: Bool {
        rightRailHasContent(for: selectedSection)
    }

    private func rightRailHasContent(for selectedSection: WorkspaceSection?) -> Bool {
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
        guard let kind = kind?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return workspaceContributionCatalog(for: currentProjectID).artifactKindDescriptor(for: kind)
    }

    private func orderedWorkspaceSections(_ sections: [WorkspaceSection], using configuration: WorkspaceModuleConfiguration) -> [WorkspaceSection] {
        orderedSections(sections, using: configuration) { section in
            guard let routeID = section.moduleRouteID else { return nil }
            return configuration.modules.first { module in
                module.routes.contains { $0.id == routeID }
            }?.id
        }
    }

    private func orderedProjectSections(_ sections: [WorkspaceSection], using configuration: WorkspaceModuleConfiguration) -> [WorkspaceSection] {
        orderedSections(sections, using: configuration) { section in
            guard let tabID = section.moduleProjectTabID else { return nil }
            return configuration.modules.first { module in
                module.projectTabs.contains { $0.id == tabID }
            }?.id
        }
    }

    private func orderedSections(
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
        workspaceModuleConfigurationStore: WorkspaceModuleConfigurationStore? = nil,
        workspaceModuleOverrideRepository: WorkspaceModuleOverrideRepository? = nil,
        paperAnnotationsRepository: PaperAnnotationsRepository? = nil,
        pdfAnnotationStore: PDFAnnotationStore? = nil,
        libraryBulkEditService: LibraryBulkEditService? = nil,
        systemCalendarService: SystemCalendarService? = nil,
        pdfReadingStateService: PDFReadingStateService? = nil,
        remoteImportService: RemoteImportService? = nil,
        pdfDownloadService: DownloadService? = nil,
        llmConfigurationStore: LLMConfigurationStore? = nil,
        apiKeyStore: KeychainAPIKeyStore? = nil,
        openAIProvider: OpenAICompatibleProvider? = nil,
        paperSummaryService: PaperSummaryService? = nil,
        llmWritebackService: LLMWritebackService? = nil,
        agentService: SciStationAgentService? = nil,
        sidecarCoordinator: SidecarRuntimeCoordinator? = nil,
        agentEmbeddingIndexController: AgentEmbeddingIndexController? = nil,
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
        let resolvedWorkspaceModuleConfigurationStore = workspaceModuleConfigurationStore ?? WorkspaceModuleConfigurationStore()
        let resolvedWorkspaceModuleOverrideRepository = workspaceModuleOverrideRepository ?? WorkspaceModuleOverrideRepository()
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
#if DEBUG
        installUITestBridgeIfRequested()
#endif
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
        TodoQueries.dueOn(todos, date: selectedDashboardDate)
    }

    var currentProjectTodos: [TodoItem] {
        guard let currentProjectID else {
            return todos
        }

        return todos(for: currentProjectID)
    }

    var currentProjectOpenTodos: [TodoItem] {
        currentProjectTodos.filter(TodoQueries.isOpen)
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
            return agentOrphanRuns
        }

        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        return thread.runIDs.compactMap { runsByID[$0] }
    }

    var agentTimelineItems: [AgentSessionTimelineItem] {
        AgentSessionTimelineItem.items(
            from: agentSessionEvents,
            runs: agentConversationRuns + [agentCurrentRun].compactMap { $0 },
            sessionIDs: agentRelevantSessionIDs,
            limit: agentTimelineVisibleLimit
        )
    }

    var agentTimelineEvents: [AgentTimelineEvent] {
        AgentTimelineEvent.events(from: agentTimelineItems)
    }

    var canLoadEarlierAgentTimelineEvents: Bool {
        agentTimelineAllItems.count > agentTimelineItems.count
    }

    private var agentTimelineAllItems: [AgentSessionTimelineItem] {
        let sessionIDs = agentRelevantSessionIDs
        guard !sessionIDs.isEmpty else {
            return []
        }
        return AgentSessionTimelineItem.items(
            from: agentSessionEvents,
            runs: agentConversationRuns + [agentCurrentRun].compactMap { $0 },
            sessionIDs: sessionIDs,
            limit: nil
        )
    }

    func loadEarlierAgentTimelineEvents() {
        let previousLimit = agentTimelineVisibleLimit
        let totalCount = agentTimelineAllItems.count
        guard totalCount > previousLimit else {
            return
        }
        agentTimelineVisibleLimit = min(totalCount, previousLimit + 160)
        recordAppDebugEvent("ai.timeline.project", payload: .object([
            "event_count": .number(String(totalCount)),
            "hidden_count": .number(String(max(0, totalCount - agentTimelineVisibleLimit))),
            "visible_limit": .number(String(agentTimelineVisibleLimit))
        ]))
    }

    private var agentRelevantSessionIDs: Set<String> {
        var ids = Set(agentConversationRuns.map(\.id))
        if let currentRunID = agentCurrentRun?.id {
            ids.insert(currentRunID)
        }
        if let agentLiveRunID {
            ids.insert(agentLiveRunID)
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
        agentThreadContextTitle
    }

    var agentThreadContextTitle: String {
        if let thread = pendingAgentThread ?? activeAgentThread {
            return agentContextTitle(scope: thread.contextScope ?? AgentContextScope.inferred(projectID: thread.projectID), projectID: thread.projectID)
        }

        return agentNextRunContextTitle
    }

    var agentNextRunContextTitle: String {
        agentContextTitle(scope: agentNextRunContextScope, projectID: agentConversationProjectID)
    }

    var agentContextSelectionToken: String {
        agentConversationProjectID ?? "__workspace__"
    }

    var agentConversationProjectID: ResearchProject.ID? {
        if agentNextRunContextScope == .workspace {
            return nil
        }
        return agentNextRunProjectID
            ?? pendingAgentThread?.projectID
            ?? activeAgentThread?.projectID
            ?? currentProjectID
    }

    func setAgentVisibleMode(_ mode: AgentVisibleMode) {
        let previousMode = agentVisibleMode
        guard previousMode != mode else {
            return
        }

        agentInteractionMode = mode.defaultInteractionMode
        recordAppDebugEvent("ai.mode.change", payload: .object([
            "from": .string(previousMode.rawValue),
            "to": .string(mode.rawValue),
            "thread_id_present": .bool(activeAgentThreadID != nil)
        ]))
    }

    func setAgentContextSelectionToken(_ token: String) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        recordAppDebugEvent("agent.context_changed", payload: .object([
            "token": .string(token),
            "previous_project_id": .string(agentConversationProjectID ?? "")
        ]))
        if token == "__workspace__" {
            agentNextRunContextScope = .workspace
            agentNextRunProjectID = nil
        } else {
            agentNextRunContextScope = .project
            agentNextRunProjectID = token
        }

        if activeAgentThread == nil, pendingAgentThread == nil {
            activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
            agentGoal = agentGoalDrafts[agentDraftKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)] ?? ""
            restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        }

        restoreAgentToolStateForCurrentScope()
        refreshAgentContext()
    }

    private func agentContextTitle(scope: AgentContextScope, projectID: ResearchProject.ID?) -> String {
        switch scope {
        case .workspace:
            return "全工作区"
        case .project:
            return projectID.map(projectName(for:)) ?? "全工作区"
        }
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
        TodoQueries.forProject(todos, projectID: projectID)
    }

    func openTodos(for projectID: ResearchProject.ID) -> [TodoItem] {
        todos(for: projectID).filter(TodoQueries.isOpen)
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
        appLanguage == .english
    }

    var appLanguage: AppLanguage {
        AppLanguage(preference: workspacePreferences.appLanguage)
    }

    func t(_ key: L10nKey) -> String {
        L10n.text(key, language: appLanguage)
    }

    func tf(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: L10n.text(key, language: appLanguage), locale: Locale(identifier: appLanguage.rawValue), arguments: arguments)
    }

    /// Migration helper for UI strings that have not moved to L10nKey yet.
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
        return "allow / ask / deny rules active; \(writingTools) tools require approval; \(waitingCount) waiting; \(agentToolApprovals.count) allow once; \(agentToolDenials.count) denied; read-only tools auto-run"
    }

    var agentHookSummary: String {
        let enabledNames = agentHookActivitySummary.enabledEventNames.map(\.rawValue)
        let resultsCount = agentHookActivitySummary.results.count
        return "\(enabledNames.joined(separator: ", ").nilIfEmpty ?? "No hooks enabled"); \(resultsCount) results in current timeline"
    }

    var agentMCPStatusSummary: String {
        let productCount = agentProductMCPServerStatuses.count
        let profileCount = agentWorkspaceProfileMCPServerStatuses.count
        let localCount = agentLocalMCPServerStatuses.count
        return ".sci-ai/sci-station: \(productCount) templates; profile: \(profileCount) managed; .sci-ai/workspace.local: \(localCount) local configs; local gateway tools/list+tools/call; side-effect tools require permissions"
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

    var agentDebugLoggingSummary: String {
        workspacePreferences.agentDebugLoggingEnabled
            ? "enabled; .sci-station/debug/app_events.jsonl"
            : "disabled"
    }

    var agentRetrievalIndexSummary: String {
        "\(agentRetrievalStatusLabel); chunks=\(agentRetrievalIndexStatus.chunkCount); stale=\(agentRetrievalIndexStatus.staleCount)"
    }

    var agentRetrievalStoreSummary: String {
        [
            agentRetrievalIndexStatus.store,
            agentRetrievalIndexStatus.fallbackReason.map { "fallback: \($0)" },
            agentRetrievalIndexStatus.errorMessage.map { "error: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    var agentRetrievalModelSummary: String {
        "\(agentRetrievalIndexStatus.provider) / \(agentRetrievalIndexStatus.modelID) / dim \(agentRetrievalIndexStatus.dimension)"
    }

    var agentRetrievalDiagnosticSummary: String {
        var sections = [agentRetrievalIndexStatus.diagnosticText]
        sections.append("runtime_selection=\(agentRuntimeSelectionSummary)")
        sections.append("runtime_effective=\(agentRuntimeEffectiveSummary)")
        sections.append("sidecar_health=\(agentSidecarHealthSummary)")
        sections.append("sidecar_fallback=\(agentRuntimeFallbackSummary)")
        sections.append("selected_source=\(selectedAgentRetrievalSourcePath() ?? "none")")
        if let selectedSourceStatus = selectedAgentRetrievalSourceFileStatus() {
            sections.append(selectedSourceStatus.diagnosticText)
        }
        sections.append("last_provider_failure=\(agentLastProviderFailureSummary)")
        if let agentRetrievalZeroChunkHint {
            sections.append("hint=\(agentRetrievalZeroChunkHint)")
        }
        if let paperMarkdownQualityReport {
            sections.append([
                "paper_md_status=\(paperMarkdownQualityReport.status.rawValue)",
                "paper_md_path=\(paperMarkdownQualityReport.markdownRelativePath)",
                "paper_md_engine=\(paperMarkdownQualityReport.extractionEngine ?? "unknown")",
                "paper_md_abstract=\(paperMarkdownQualityReport.hasAbstractHeading)",
                "paper_md_figures=\(paperMarkdownQualityReport.figureAssetCount)",
                "paper_md_display_math=\(paperMarkdownQualityReport.hasDisplayMath)",
                "paper_md_issues=\(paperMarkdownQualityReport.issues.map(\.code.rawValue).joined(separator: ","))"
            ].joined(separator: "\n"))
        }
        return sections.joined(separator: "\n")
    }

    var redactedAgentRetrievalDiagnosticSummary: String {
        AgentDiagnosticRedactor.redacted(agentRetrievalDiagnosticSummary)
    }

    var agentRetrievalSourceHealthSummary: String {
        let source = selectedAgentRetrievalSourcePath() ?? localized("未选择 source", "No source selected")
        let paperHealth = paperMarkdownQualityReport.map { report in
            report.summary(usesEnglishInterface: usesEnglishInterface)
        } ?? localized("paper.md 尚未检查", "paper.md not checked")
        return "\(source); \(agentRetrievalIndexSummary); \(paperHealth)"
    }

    var agentRetrievalSourceHealthIssueLines: [String] {
        var lines: [String] = []
        if let agentRetrievalZeroChunkHint {
            lines.append(agentRetrievalZeroChunkHint)
        }
        lines.append(contentsOf: paperMarkdownQualityIssueLines.prefix(3))
        return lines
    }

    var agentLastProviderFailureSummary: String {
        let latestFailedRun = ([agentCurrentRun].compactMap { $0 } + agentRunHistory)
            .filter { $0.failureCategory == .providerError || $0.lifecycleState == .failed }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .first
        guard let latestFailedRun else {
            return "none"
        }
        return [
            latestFailedRun.failureCategory?.rawValue ?? latestFailedRun.lifecycleState.rawValue,
            latestFailedRun.plan.risk?.nilIfBlank ?? latestFailedRun.plan.summary.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: ": ")
    }

    var agentRetrievalStatusLabel: String {
        switch agentRetrievalIndexStatus.status.uiStatus {
        case .ready:
            return localized("Ready / 已就绪", "Ready")
        case .fallback:
            return localized("Fallback deterministic retrieval / 确定性检索 fallback", "Fallback deterministic retrieval")
        case .error:
            if agentRetrievalIndexStatus.errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
                return localized("Error not indexable / 不可索引", "Error not indexable")
            }
            return localized("Error / 错误", "Error")
        case .disabled:
            return localized("Disabled FTS-only / 已禁用，仅 FTS", "Disabled FTS-only")
        case .indexing:
            return localized("Indexing / 正在索引", "Indexing")
        case .stale, .migrationRequired:
            return localized("Stale / 需要重建", "Stale")
        }
    }

    var agentRetrievalZeroChunkHint: String? {
        guard agentRetrievalIndexStatus.status.uiStatus != .indexing,
              agentRetrievalIndexStatus.chunkCount == 0 else {
            return nil
        }
        if agentRetrievalIndexStatus.status.uiStatus == .disabled {
            return localized("检索索引已禁用；当前只使用 FTS 文本检索。", "Retrieval indexing is disabled; workflows are using FTS-only text retrieval.")
        }
        if agentRetrievalIndexStatus.errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
            return localized("chunks=0：选中的 source 不可索引。请确认路径是 paper.md、annotations.md、wiki 或 materials，legacy raw/papers 可直接重建或先迁移。", "chunks=0: the selected source is not indexable. Confirm the path is paper.md, annotations.md, wiki, or materials; legacy raw/papers can be rebuilt directly or migrated first.")
        }
        if let selectedSourceStatus = selectedAgentRetrievalSourceFileStatus() {
            if !selectedSourceStatus.exists {
                return localized("chunks=0：选中的 source 文件不存在，请重新选择论文或重新生成 paper.md。", "chunks=0: the selected source file does not exist; select the paper again or regenerate paper.md.")
            }
            if selectedSourceStatus.isDirectory {
                return localized("chunks=0：选中的 source 是文件夹，不是可索引的 Markdown 文件。", "chunks=0: the selected source is a folder, not an indexable Markdown file.")
            }
            if selectedSourceStatus.byteCount == 0 {
                return localized("chunks=0：选中的 paper.md 存在但为空，请重新转换或修复内容后再 Rebuild Source。", "chunks=0: the selected paper.md exists but is empty; reconvert or fix it before running Rebuild Source.")
            }
            if let lineCount = selectedSourceStatus.lineCount {
                return localized("chunks=0：选中的 paper.md 已存在且非空（\(selectedSourceStatus.byteCount) bytes，\(lineCount) lines），请点击 Rebuild Source 生成本地 fallback chunks。", "chunks=0: the selected paper.md exists and is non-empty (\(selectedSourceStatus.byteCount) bytes, \(lineCount) lines); run Rebuild Source to generate local fallback chunks.")
            }
        }
        return localized("chunks=0：请确认 paper.md 存在且非空，然后运行 Rebuild Source；若是 PDFKit fallback，请用 Check paper.md 查看可读性限制。", "chunks=0: confirm paper.md exists and is not empty, then run Rebuild Source; if it is a PDFKit fallback, use Check paper.md to review readability limits.")
    }

    var paperMarkdownQualitySummary: String {
        guard let paperMarkdownQualityReport else {
            return localized("尚未检查", "Not checked")
        }
        return paperMarkdownQualityReport.summary(usesEnglishInterface: usesEnglishInterface)
    }

    var paperMarkdownQualityIssueLines: [String] {
        paperMarkdownQualityReport?.issueLines(usesEnglishInterface: usesEnglishInterface) ?? []
    }

    private var agentSidecarHealthIsAvailable: Bool {
        agentSidecarHealth.status == "ready"
    }

    var agentMCPServerStatuses: [AgentMCPServerStatus] {
        agentProductMCPServerStatuses + agentWorkspaceProfileMCPServerStatuses + agentLocalMCPServerStatuses
    }

    func agentPermissionDockItems(for run: AgentRun) -> [AgentPermissionDockItem] {
        var filteredRun = run
        if let allowedToolNames = run.enabledToolNames.map({ Set($0) }) ?? effectiveAgentAllowedToolNames {
            filteredRun.plan.toolCalls = filteredRun.plan.toolCalls.filter { allowedToolNames.contains($0.toolName) }
        }

        var items = AgentPermissionDockItem.items(
            for: filteredRun,
            toolDefinitions: agentToolDefinitions,
            state: AgentPermissionDockState(
                approvedCallIDs: agentToolApprovals,
                deniedCallIDs: agentToolDenials,
                sessionScopedApprovalDraftCallIDs: agentToolSessionApprovalDrafts,
                correctionFeedbackByCallID: agentToolCorrectionFeedback
            )
        )
        for index in items.indices {
            items[index].moduleScopeDescription = WorkspaceModuleRegistry.moduleScopeDescription(
                for: items[index].targetPaths,
                in: effectiveModuleConfiguration(for: run.projectID ?? run.currentProjectID ?? agentConversationProjectID)
            )
        }
        return items.filter { item in
            switch item.approvalState {
            case .waitingForApproval, .allowedOnce, .denied, .deniedByPolicy, .sessionApprovalDraft:
                return item.sideEffectsRequirePermission || item.decision.action != .allow
            case .autoAllowed, .completed, .failed:
                return false
            }
        }
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

    var selectedMarkdownSaveStateLabel: String {
        switch selectedMarkdownSaveState {
        case .clean:
            return "Saved"
        case .dirty:
            return "Unsaved"
        case .saving:
            return "Saving"
        case .failed:
            return "Error"
        }
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
        if section.inProjectSpaceOnly, let projectID = currentProjectID {
            selectResearchProject(projectID, section: section)
            return
        }

        let targetSection = isWorkspaceSectionAvailable(section) ? section : fallbackWorkspaceSection()
        selectedSection = targetSection
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        persistWorkspaceRoute(WorkspaceRoute(top: topRoute(for: targetSection)))
        if targetSection == .library {
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    func selectTopLevelRoute(_ top: WorkspaceRoute.Top) {
        selectSection(workspaceSection(for: top))
    }

    func openSettings(category: SettingsCategory) {
        selectedSettingsCategory = category
        selectSection(.settings)
    }

    func selectLibraryScope() {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library))
    }

    func selectCollection(_ relativePath: String) {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = relativePath
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library, secondarySelection: relativePath))
    }

    func selectTag(_ name: String) {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedTagName = name
        selectedCollectionPath = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library, secondarySelection: name))
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

        guard isWorkspaceSectionAvailable(.library) else {
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

    func requestPDFReaderGoToPage(_ pageIndex: Int) {
        pdfReaderRequestedPageIndex = max(0, pageIndex)
        pdfReaderGoToPageRequest += 1
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
        beginWorkspaceCreation(template: WorkspaceTemplateRegistry.literatureReview)
    }

    /// One-click sample workspace for first-run onboarding: pick an empty folder,
    /// then create a workspace pre-seeded with example research content.
    func createSampleWorkspace() {
        guard let destinationURL = Self.selectCreateWorkspaceURL(suggestedName: "Sci-Station Sample") else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.createSampleWorkspace(at: destinationURL)
        }
    }

    func createWorkspace(template: WorkspaceTemplate) {
        beginWorkspaceCreation(template: template)
    }

    func beginWorkspaceCreation(template: WorkspaceTemplate = WorkspaceTemplateRegistry.literatureReview) {
        workspaceCreationDraft = WorkspaceCreationWizard.draft(selecting: template)
        isShowingWorkspaceCreationWizard = true
    }

    func updateWorkspaceCreationName(_ name: String) {
        workspaceCreationDraft.workspaceName = name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let targetURL = workspaceCreationDraft.targetURL else {
            return
        }

        workspaceCreationDraft.targetURL = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(trimmedName, isDirectory: true)
    }

    func updateWorkspaceCreationTemplate(_ templateID: String) {
        let option = WorkspaceCreationWizard.templateOption(id: templateID)
        guard option.isSelectable, let template = option.template else {
            return
        }
        workspaceCreationDraft.templateID = template.id
        workspaceCreationDraft.enabledModuleIDs = Set(template.enabledModuleIDs)
    }

    func setWorkspaceCreationPrivacyAcknowledged(_ value: Bool) {
        workspaceCreationDraft.privacyAcknowledged = value
    }

    func chooseWorkspaceCreationDestination() {
        guard let destinationURL = Self.selectCreateWorkspaceURL(suggestedName: workspaceCreationDraft.workspaceName) else {
            return
        }

        workspaceCreationDraft.targetURL = destinationURL
        workspaceCreationDraft.workspaceName = destinationURL.lastPathComponent
    }

    func completeWorkspaceCreation() {
        let validation = workspaceCreationTargetValidation
        guard validation.canCreate, let destinationURL = workspaceCreationDraft.targetURL else {
            present(WorkspaceError.incompatibleCreationTarget(validation.message))
            return
        }

        guard workspaceCreationDraft.privacyAcknowledged else {
            present(WorkspaceError.incompatibleCreationTarget("Confirm the privacy and AI setup boundary before creating the workspace."))
            return
        }

        let template = WorkspaceCreationWizard.template(for: workspaceCreationDraft)
        let compatibility = validation.compatibility ?? ResearchRoot.compatibility(at: destinationURL)
        isShowingWorkspaceCreationWizard = false
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
        let targetSection = isWorkspaceProjectTabAvailable(section, projectID: projectID) ? section : fallbackProjectSection(for: projectID)
        let targetTabID = projectSpaceTabID(for: targetSection)
        currentProjectID = projectID
        selectedProjectSpaceProjectID = projectID
        selectedProjectSpaceTabID = targetTabID
        selectedSection = .projects
        resetAgentDraftIfConversationChanged(to: projectID)
        isViewingGlobalTodos = false
        if targetTabID == "papers" {
            selectedLibraryProjectID = projectID
            selectedCollectionPath = nil
            selectedTagName = nil
        }

        persistLastOpenedProject(projectID)
        persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: projectID, projectTabID: targetTabID))
        refreshAgentContext()

        if targetTabID == "wiki", let currentWorkspace {
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
        guard isWorkspaceSectionAvailable(.tasks) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .tasks
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = true
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .calendar, secondarySelection: "global_todos"))
    }

    func selectProjectSpaceTab(_ tabID: String) {
        guard let projectID = selectedProjectSpaceProjectID ?? currentProjectID else {
            selectTopLevelRoute(.projects)
            return
        }

        let requestedTabID = ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(tabID) ? ProjectSpaceTabsBuilder.mergedReadingTabID : tabID
        let availableTabs = projectSpaceTabs(for: projectID)
        let resolvedTabID: String
        if availableTabs.contains(where: { $0.id == requestedTabID }) {
            resolvedTabID = requestedTabID
        } else {
            resolvedTabID = ProjectSpaceTabsBuilder.overviewTabID
            recordShellDebugEvent("project_space.builder_warn", payload: .object([
                "project_id": .string(projectID),
                "hidden_tabs": jsonStringArray([requestedTabID]),
                "reason": .string("module_disabled")
            ]))
        }

        if selectedSection == .projects,
           selectedProjectSpaceProjectID == projectID,
           selectedProjectSpaceTabID == resolvedTabID {
            return
        }

        let previousFocusedProjectID = currentProjectID
        let previousTabID = selectedProjectSpaceTabID
        currentProjectID = projectID
        selectedProjectSpaceProjectID = projectID
        selectedProjectSpaceTabID = resolvedTabID
        selectedSection = .projects
        isViewingGlobalTodos = false

        if resolvedTabID == "papers" {
            selectedLibraryProjectID = projectID
            selectedCollectionPath = nil
            selectedTagName = nil
        }

        if previousFocusedProjectID != projectID {
            persistLastOpenedProject(projectID)
        }
        persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: projectID, projectTabID: resolvedTabID))
        recordShellDebugEvent("project_space.tab_change", payload: .object([
            "project_id": .string(projectID),
            "from_tab": .string(previousTabID),
            "to_tab": .string(resolvedTabID),
            "available_tabs": jsonStringArray(availableTabs.map(\.id))
        ]))

        if resolvedTabID == "wiki", let currentWorkspace {
            Task {
                do {
                    try await loadMarkdownDocuments(in: currentWorkspace, selecting: nil)
                } catch {
                    present(error)
                }
            }
        }
        if previousFocusedProjectID != projectID || resolvedTabID == "ai-drafts" {
            refreshAgentContext()
        }
    }

    func moveTopSidebarItem(_ itemID: String, before targetID: String) {
        guard itemID != targetID, itemID != WorkspaceRoute.Top.settings.rawValue else {
            return
        }
        let movableIDs = TopSidebarBuilder.items(pinnedOrder: workspacePreferences.pinnedTopLevelOrder)
            .filter { !$0.isPinFixed }
            .map(\.id)
        guard movableIDs.contains(itemID) else {
            return
        }

        var nextOrder = movableIDs.filter { $0 != itemID }
        let insertionIndex = nextOrder.firstIndex(of: targetID) ?? nextOrder.count
        nextOrder.insert(itemID, at: insertionIndex)
        updateWorkspacePreferences { preferences in
            preferences.pinnedTopLevelOrder = nextOrder + [WorkspaceRoute.Top.settings.rawValue]
        }
        recordSidebarRender()
    }

    func moveProjectSpaceTab(_ tabID: String, before targetID: String) {
        guard tabID != targetID, let projectID = selectedProjectSpaceProjectID else {
            return
        }
        let tabs = projectSpaceTabs(for: projectID)
        guard tabs.contains(where: { $0.id == tabID && !$0.isPinFixed }) else {
            return
        }
        let movableIDs = tabs.filter { !$0.isPinFixed }.map(\.id)
        var nextOrder = movableIDs.filter { $0 != tabID }
        let insertionIndex = nextOrder.firstIndex(of: targetID) ?? nextOrder.count
        nextOrder.insert(tabID, at: insertionIndex)
        updateWorkspacePreferences { preferences in
            preferences.projectSpacePinnedOrder = nextOrder
        }
    }

    /// Called on route / tab changes. The right rail mode itself is now a
    /// sticky user preference (set via the toolbar Inspector / AI buttons)
    /// and is no longer auto-flipped here. The only remaining job is to keep
    /// the global AI panel's context summary in sync when the rail is in AI
    /// mode — previously the route-driven flip handled that as a side effect.
    func applyRightRailRouteSuggestion() {
        if workspacePreferences.rightRailMode == .ai {
            recordGlobalAIContextUpdate(reason: "route_change")
        }
    }

    func setRightRailMode(_ mode: RightRailMode, source: String = "manual") {
        let previousMode = workspacePreferences.rightRailMode
        updateWorkspacePreferences { preferences in
            preferences.rightRailMode = mode
            preferences.isGlobalAIPanelOpen = mode == .ai
        }
        recordShellDebugEvent("shell.right_rail.change", payload: .object([
            "from": .string(previousMode.rawValue),
            "to": .string(mode.rawValue),
            "source": .string(source),
            "top": .string(currentWorkspaceRoute.top.rawValue),
            "project_id_present": .bool(currentWorkspaceContextSnapshot.projectID != nil),
            "tab_id": .string(currentWorkspaceContextSnapshot.projectTabID ?? "")
        ]))
    }

    func openGlobalAIPanel(source: String = "toolbar") {
        setRightRailMode(.ai, source: source)
        recordShellDebugEvent("shell.ai_panel.open", payload: currentWorkspaceContextDebugPayload(reason: source))
        recordGlobalAIContextUpdate(reason: source)
    }

    func showContextInspector(source: String = "toolbar") {
        setRightRailMode(.inspector, source: source)
    }

    func hideRightRail(source: String = "manual") {
        setRightRailMode(.hidden, source: source)
    }

    /// Toggle a specific right-rail mode. If the rail is already showing the
    /// requested mode, the rail collapses; otherwise it switches to that mode.
    /// This is what the toolbar Inspector / AI buttons drive so that a single
    /// click in either direction reaches the user's intent without having to
    /// hunt for a close button inside the rail itself.
    func toggleRightRailMode(_ mode: RightRailMode, source: String = "toolbar") {
        guard mode != .hidden else {
            hideRightRail(source: source)
            return
        }
        if effectiveRightRailMode == mode {
            hideRightRail(source: "\(source)_toggle_off")
        } else {
            setRightRailMode(mode, source: source)
        }
    }

    func recordGlobalAIContextUpdate(reason: String = "context_update") {
        guard workspacePreferences.rightRailMode == .ai else {
            return
        }
        recordShellDebugEvent("shell.ai_panel.context_update", payload: currentWorkspaceContextDebugPayload(reason: reason))
    }

    func recordToolbarPolicyChange(_ model: ToolbarModel) {
        let actionCount = model.globalActions.count + model.pageActions.count + model.overflowActions.count
        recordShellDebugEvent("toolbar.policy.resolve", payload: .object([
            "top": .string(currentWorkspaceRoute.top.rawValue),
            "tab_id": .string(currentWorkspaceContextSnapshot.projectTabID ?? ""),
            "action_count": .number(String(actionCount)),
            "hidden_action_count": .number("0"),
            "global_actions": jsonStringArray(model.globalActions.map { $0.id.rawValue }),
            "page_actions": jsonStringArray(model.pageActions.map { $0.id.rawValue }),
            "overflow_actions": jsonStringArray(model.overflowActions.map { $0.id.rawValue })
        ]))
    }

    func refreshCurrentWorkspaceView() {
        switch selectedSection {
        case .wiki:
            reloadWiki()
        case .llmLab:
            refreshAgentContext()
        case .calendar, .tasks:
            refreshSystemSchedule(around: selectedDashboardDate)
        case .library:
            reloadLibrary()
        default:
            guard let currentWorkspace else {
                return
            }
            Task {
                do {
                    try await loadWorkspaceData(in: currentWorkspace, selectingPaper: selectedPaperID, selectingMarkdown: selectedMarkdownID)
                } catch {
                    present(error)
                }
            }
        }
    }

    // MARK: - Graph UI

    private var _graphRepository: GraphRepository?

    private func initializeGraphRepository(in workspace: ResearchWorkspace) async {
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let repo = GraphRepository(debug: appDebugEventLogger)
        do {
            try await repo.open(in: root)
            _graphRepository = repo
            // Run the indexer to populate/update the graph.
            let indexer = GraphIndexer(
                repository: repo,
                paperRepository: PaperRepository(),
                projectRegistryRepository: projectRegistryRepository,
                markdownRepository: MarkdownRepository(),
                todoRepository: TodoRepository(),
                debug: appDebugEventLogger
            )
            try await indexer.run(in: workspace, root: root, force: false)
        } catch {
            // Graph initialization failure is non-fatal; the tab will show
            // an empty state.
            _graphRepository = nil
        }
    }

    func graphReadModel() async -> GraphReadModel? {
        guard let repo = _graphRepository else { return nil }
        return GraphReadModel(repository: repo)
    }

    func showGraphActionPlaceholder(reason: String) {
        recordShellDebugEvent("graph.ui.action", payload: .object([
            "action": .string("pending_implementation"),
            "reason": .string(reason)
        ]))
    }

    func handleGraphNodeAction(_ action: NodeAction) {
        switch action {
        case .openPaper(let paperID):
            selectPaper(id: paperID)
        case .openWikiPage(let path):
            openMarkdownDocument(relativePath: path)
        case .addToProject, .markAsCore, .createTodo:
            // Graph write actions are not enabled in this build. Log the
            // intent so the UI can stay responsive without mutating data.
            recordShellDebugEvent("graph.ui.action", payload: .object([
                "action": .string("write_action_pending"),
                "node_action": .string(String(describing: action))
            ]))
        case .generateReadingOrder(let centerPaperID):
            startGraphInsightAgentRun(
                actionName: "generate_reading_order",
                preferredToolName: GraphAgentTools.generateReadingPath,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.generateReadingPath) for center_paper_id \(centerPaperID), then explain the recommended reading order with graph evidence."
            )
        case .explainConnection(let fromID, let toID):
            startGraphInsightAgentRun(
                actionName: "explain_connection",
                preferredToolName: GraphAgentTools.findBridgePapers,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.findBridgePapers) with from_paper_id \(fromID) and to_paper_id \(toID), then explain the connection with graph evidence."
            )
        case .findBridgePapers(let fromID, let toID):
            startGraphInsightAgentRun(
                actionName: "find_bridge_papers",
                preferredToolName: GraphAgentTools.findBridgePapers,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.findBridgePapers) with from_paper_id \(fromID) and to_paper_id \(toID), then summarize the bridge papers and evidence."
            )
        }
    }

    private func startGraphInsightAgentRun(actionName: String, preferredToolName: String, prompt: String) {
        guard currentWorkspace != nil else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard enabledAgentWorkflowIDs.contains("graph_insight") else {
            agentErrorMessage = "Citation Graph module is required for graph insights."
            recordAppDebugEvent(AppDebugEventName.agentToolGraphBlockedByModule.rawValue, payload: .object([
                "action": .string(actionName),
                "workflow": .string("graph_insight")
            ]))
            return
        }

        let projectID = currentProjectID
        setAgentVisibleMode(.agent)
        if let projectID {
            setAgentContextSelectionToken(projectID)
        } else {
            setAgentContextSelectionToken("__workspace__")
        }
        selectSection(.llmLab)
        startNewAgentConversation()
        agentGoal = prompt
        recordAppDebugEvent(AppDebugEventName.agentIntentGraphRouted.rawValue, payload: .object([
            "action": .string(actionName),
            "tool": .string(preferredToolName),
            "workflow": .string("graph_insight"),
            "project_id": .string(projectID ?? "")
        ]))
        generateAgentPlan()
    }

    func importGraphExternalPaper(from identifier: String) async throws -> Paper {
        guard let currentWorkspace else {
            throw GraphExternalPaperImportError.missingWorkspace
        }

        if let existing = existingPaper(matchingGraphImportIdentifier: identifier) {
            selectPaper(id: existing.id)
            return existing
        }

        let collectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        var importedPaper = try await remoteImportService.importItem(
            from: identifier,
            draftPreview: nil,
            into: currentWorkspace,
            existingPapers: papers,
            collectionPath: collectionPath,
            tags: []
        )

        if let selectedLibraryProjectID,
           !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
            importedPaper.projectIDs.append(selectedLibraryProjectID)
            importedPaper = try await paperRepository.save(importedPaper, in: currentWorkspace)
        }

        try await loadWorkspaceData(
            in: currentWorkspace,
            selectingPaper: importedPaper.id,
            selectingMarkdown: selectedMarkdownID
        )
        startMarkdownConversion(for: [importedPaper], in: currentWorkspace, statusSurface: .workspace)
        return importedPaper
    }

    private func existingPaper(matchingGraphImportIdentifier identifier: String) -> Paper? {
        let parsed = IdentifierParser().parse(identifier)
        switch parsed.kind {
        case .inspire:
            let inspireID = parsed.normalizedValue
            return papers.first { paper in
                PaperIdentityGenerator.normalizedInspire(paper.inspireID) == inspireID || paper.resolvedGraphNodeID == "inspire:\(inspireID)"
            }
        case .doi:
            guard let doi = PaperIdentityGenerator.normalizedDOI(parsed.normalizedValue) else { return nil }
            return papers.first { PaperIdentityGenerator.normalizedDOI($0.doi) == doi }
        case .arxiv:
            guard let arxiv = PaperIdentityGenerator.normalizedArxiv(parsed.normalizedValue) else { return nil }
            return papers.first { PaperIdentityGenerator.normalizedArxiv($0.arxiv) == arxiv || $0.resolvedGraphNodeID == "arxiv:\(arxiv)" }
        case .pdfURL, .url, .unknown:
            return nil
        }
    }

    func updateShellWindowWidth(_ width: CGFloat) {
        let nextWidth = Double(width)
        let previousModel = responsiveShellModel
        let nextModel = ResponsiveShellPolicy.resolve(
            width: nextWidth,
            route: currentWorkspaceRoute,
            context: currentWorkspaceContextSnapshot,
            preferredRightRailMode: workspacePreferences.rightRailMode
        )
        let nextIsNarrow = nextModel.bucket == .compact || nextModel.bucket == .narrow
        guard shellWindowWidth != nextWidth || isShellNarrowWidth != nextIsNarrow else {
            return
        }
        shellWindowWidth = nextWidth
        isShellNarrowWidth = nextIsNarrow
        recordShellDebugEvent("shell.responsive_policy.apply", payload: .object([
            "from_bucket": .string(previousModel.bucket.rawValue),
            "to_bucket": .string(nextModel.bucket.rawValue),
            "width": .number(String(nextWidth)),
            "home_widget_columns": .number(String(nextModel.homeWidgetColumns)),
            "toolbar_overflow": .bool(nextModel.shouldMoveToolbarPageActionsToOverflow),
            "from": .string(workspacePreferences.rightRailMode.rawValue),
            "to": .string(nextModel.effectiveRightRailMode.rawValue),
            "source": .string("window_width"),
            "is_narrow": .bool(nextIsNarrow)
        ]))
    }

    func enterHomeLayoutEdit() {
        isEditingHomeLayout = true
        recordHomeDebugEvent("home.widget.layout_enter_edit")
    }

    func exitHomeLayoutEdit() {
        isEditingHomeLayout = false
        isShowingHomeWidgetGallery = false
        recordHomeDebugEvent("home.widget.layout_exit_edit")
    }

    func showHomeWidgetGallery(_ isShowing: Bool) {
        isShowingHomeWidgetGallery = isShowing
        recordHomeDebugEvent("home.widget.gallery", payload: .object([
            "is_showing": .bool(isShowing)
        ]))
    }

    func moveHomeWidget(_ widgetID: String, offset: Int, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                widgetID,
                offset: offset,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(widgetID),
            "offset": .number(String(offset)),
            "columns": .number(String(columns))
        ]))
    }

    func moveHomeWidget(_ sourceWidgetID: String, before targetWidgetID: String, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                sourceWidgetID,
                before: targetWidgetID,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(sourceWidgetID),
            "before": .string(targetWidgetID),
            "columns": .number(String(columns))
        ]))
    }

    /// Drop-target move: place source widget at the slot currently held by
    /// target. Used by the dashboard drag handler so forward and backward
    /// drags both end up swapping into the target's tile.
    func moveHomeWidget(_ sourceWidgetID: String, onto targetWidgetID: String, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                sourceWidgetID,
                onto: targetWidgetID,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(sourceWidgetID),
            "onto": .string(targetWidgetID),
            "columns": .number(String(columns))
        ]))
    }

    func resizeHomeWidget(_ widgetID: String, to size: HomeWidgetSize, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.resizeWidget(
                widgetID,
                to: size,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.resize", payload: .object([
            "widget_id": .string(widgetID),
            "size": .string(size.rawValue),
            "columns": .number(String(columns))
        ]))
    }

    func toggleHomeWidget(_ widgetID: String, isEnabled: Bool, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.setWidget(
                widgetID,
                isEnabled: isEnabled,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.toggle", payload: .object([
            "widget_id": .string(widgetID),
            "is_enabled": .bool(isEnabled),
            "columns": .number(String(columns))
        ]))
    }

    func resetHomeWidgetLayout(columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.reset(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: columns)
        }
        recordHomeDebugEvent("home.widget.reset_default", payload: .object([
            "columns": .number(String(columns))
        ]))
    }

    func toggleProjectTreeExpansion() {
        updateWorkspacePreferences { preferences in
            preferences.isProjectTreeExpanded.toggle()
        }
        recordShellDebugEvent("sidebar.project_tree.toggle", payload: .object([
            "is_expanded": .bool(workspacePreferences.isProjectTreeExpanded)
        ]))
    }

    func isResearchProjectPinned(_ projectID: ResearchProject.ID) -> Bool {
        workspacePreferences.pinnedProjectIDs.contains(projectID)
    }

    func toggleResearchProjectPin(_ project: ResearchProject) {
        updateWorkspacePreferences { preferences in
            if preferences.pinnedProjectIDs.contains(project.id) {
                preferences.pinnedProjectIDs.removeAll { $0 == project.id }
            } else {
                preferences.pinnedProjectIDs.append(project.id)
            }
        }
        recordShellDebugEvent("sidebar.project_tree.toggle", payload: .object([
            "project_id": .string(project.id),
            "pin_state": .bool(isResearchProjectPinned(project.id))
        ]))
    }

    func confirmArchiveResearchProject(_ project: ResearchProject) {
        projectPendingDeletion = project
        projectPendingLifecycleAction = .archive
        isShowingProjectDeleteConfirmation = true
        recordShellDebugEvent("project.archive.requested", payload: .object([
            "project_id_hash": .string(project.id.stableHashForDebug),
            "relative_path_present": .bool(!project.relativePath.isEmpty)
        ]))
    }

    func confirmTrashResearchProject(_ project: ResearchProject) {
        projectPendingDeletion = project
        projectPendingLifecycleAction = .deleteToTrash
        isShowingProjectDeleteConfirmation = true
        recordShellDebugEvent("project.delete.requested", payload: .object([
            "project_id_hash": .string(project.id.stableHashForDebug),
            "mode": .string(ProjectLifecycleAction.deleteToTrash.rawValue)
        ]))
    }

    func confirmDeleteResearchProject(_ project: ResearchProject) {
        confirmArchiveResearchProject(project)
    }

    func cancelDeleteResearchProject() {
        projectPendingDeletion = nil
        projectPendingLifecycleAction = .archive
        isShowingProjectDeleteConfirmation = false
    }

    func confirmDeletePendingResearchProject() {
        guard let project = projectPendingDeletion, let currentResearchRoot else {
            cancelDeleteResearchProject()
            return
        }

        projectPendingDeletion = nil
        isShowingProjectDeleteConfirmation = false
        let action = projectPendingLifecycleAction
        projectPendingLifecycleAction = .archive

        Task {
            do {
                let result: ProjectLifecycleResult
                switch action {
                case .archive:
                    result = try await projectRegistryRepository.archiveProject(project.id, in: currentResearchRoot)
                case .deleteToTrash:
                    result = try await projectRegistryRepository.deleteProjectToTrash(project.id, in: currentResearchRoot)
                }

                researchProjects = result.registry.projects
                updateWorkspacePreferences { preferences in
                    preferences.pinnedProjectIDs.removeAll { $0 == project.id }
                }

                if selectedProjectSpaceProjectID == project.id || currentProjectID == project.id {
                    selectedProjectSpaceProjectID = nil
                    currentProjectID = activeResearchProjects.first?.id
                    selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
                    selectedSection = .projects
                    selectedLibraryProjectID = nil
                    persistWorkspaceRoute(WorkspaceRoute(top: .projects))
                }

                switch action {
                case .archive:
                    showShellStatus(tf(.projectArchiveStatusFormat, project.name))
                    recordShellDebugEvent("project.archive.confirmed", payload: .object([
                        "project_id_hash": .string(project.id.stableHashForDebug)
                    ]))
                case .deleteToTrash:
                    showShellStatus(tf(.projectTrashStatusFormat, project.name))
                    recordShellDebugEvent("project.delete.confirmed", payload: .object([
                        "project_id_hash": .string(project.id.stableHashForDebug),
                        "mode": .string(ProjectLifecycleAction.deleteToTrash.rawValue)
                    ]))
                }
            } catch {
                present(error)
            }
        }
    }

    func restoreResearchProject(_ project: ResearchProject) {
        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                let result = try await projectRegistryRepository.restoreProject(project.id, in: currentResearchRoot)
                researchProjects = result.registry.projects
                showShellStatus(tf(.projectRestoreStatusFormat, result.project.name))
                recordShellDebugEvent("project.restore.confirmed", payload: .object([
                    "project_id_hash": .string(project.id.stableHashForDebug)
                ]))
            } catch {
                present(error)
            }
        }
    }

    func recordSidebarRender() {
        let items = topSidebarItems
        recordShellDebugEvent("sidebar.render", payload: .object([
            "top_items": jsonStringArray(items.map(\.id)),
            "pinned_order": jsonStringArray(workspacePreferences.pinnedTopLevelOrder)
        ]))
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
                    selectedProjectSpaceProjectID = project.id
                    selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
                    selectedSection = .projects
                    persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: project.id, projectTabID: ProjectSpaceTabsBuilder.overviewTabID))
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
                    workspaceSettingsStatusMessage = localized(
                        "Legacy 扫描发现 \(legacyPaperMigrationPlan.legacyPaperCount) 个 raw/papers 项。",
                        "Legacy scan found \(legacyPaperMigrationPlan.legacyPaperCount) raw/papers items."
                    )
                } else {
                    workspaceSettingsStatusMessage = localized(
                        "未发现 legacy raw/papers 项。",
                        "No legacy raw/papers items found."
                    )
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
                workspaceSettingsStatusMessage = localized(
                    "已复制 \(report.copiedCount) 篇 legacy 论文；跳过 \(report.skippedCount)，失败 \(report.failedCount)。报告：\(report.reportRelativePath ?? "未写入")。",
                    "Copied \(report.copiedCount) legacy papers. Skipped \(report.skippedCount), failed \(report.failedCount). Report: \(report.reportRelativePath ?? "not written")."
                )
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

    func importPDFFromGlobalMenu() {
        guard currentWorkspace != nil else {
            return
        }
        ensurePaperImportContextForGlobalMenu()
        importPDF()
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

    func beginIdentifierImportFromGlobalMenu() {
        guard currentWorkspace != nil else {
            return
        }
        ensurePaperImportContextForGlobalMenu()
        beginIdentifierImport()
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
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
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
            paperMarkdownQualityReport = nil
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
        paperMarkdownQualityReport = nil
        selectedPDFAnnotations = []
        selectedPDFSelectionPreview = nil
        selectedPDFSelectionPageIndex = nil
        guard let currentWorkspace else {
            selectedPaperAnnotationsDraft = ""
            return
        }

        Task {
            do {
                try await loadSelectedPaperAnnotations(in: currentWorkspace)
                try await loadSelectedPDFAnnotations(in: currentWorkspace)
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
        guard let currentWorkspace else { return false }
        return localPDFURL(for: paper, in: currentWorkspace) != nil || remotePDFURL(for: paper) != nil
    }

    func openPaperReader(_ paper: Paper) {
        let returnRoute = currentWorkspaceRoute
        selectPaper(id: paper.id)
        guard let currentWorkspace else { return }

        if localPDFURL(for: paper, in: currentWorkspace) != nil {
            activatePaperReader(returnRoute: returnRoute)
            return
        }

        guard remotePDFURL(for: paper) != nil else {
            libraryBatchStatusMessage = localized("没有可打开的 PDF。", "No PDF is available to open.")
            return
        }

        Task {
            do {
                showShellStatus(localized("正在下载 PDF…", "Downloading PDF…"))
                let updatedPaper = try await ensureLocalPDFAvailable(for: paper, in: currentWorkspace)
                selectPaper(id: updatedPaper.id)
                activatePaperReader(returnRoute: returnRoute)
                showShellStatus(localized("PDF 已下载并打开。", "PDF downloaded and opened."))
            } catch {
                libraryBatchStatusMessage = localized("无法打开 PDF：\(error.localizedDescription)", "Could not open PDF: \(error.localizedDescription)")
                present(error)
            }
        }
    }

    private func activatePaperReader(returnRoute: WorkspaceRoute) {
        paperReaderReturnRoute = returnRoute
        selectedSection = .pdfReader
        showContextInspector(source: "paper_reader_open")
        persistWorkspaceRoute(currentWorkspaceRoute)
    }

    private func localPDFURL(for paper: Paper, in workspace: ResearchWorkspace) -> URL? {
        guard let pdfURL = paper.pdfURL(in: workspace), FileManager.default.fileExists(atPath: pdfURL.path) else {
            return nil
        }
        return pdfURL
    }

    private func remotePDFURL(for paper: Paper) -> URL? {
        guard let value = paper.pdfURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private func ensureLocalPDFAvailable(for paper: Paper, in workspace: ResearchWorkspace) async throws -> Paper {
        if localPDFURL(for: paper, in: workspace) != nil {
            return paper
        }
        guard let remoteURL = remotePDFURL(for: paper) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let downloadedURL = try await pdfDownloadService.downloadPDF(from: remoteURL)
        var updatedPaper = papers.first(where: { $0.id == paper.id }) ?? paper
        let directoryURL = workspace.directoryURL(for: updatedPaper.paperDirectoryRelativePath)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let targetURL = directoryURL.appendingPathComponent("paper.pdf", isDirectory: false)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: targetURL)
        updatedPaper.pdfRelativePath = "paper.pdf"
        updatedPaper.updatedAt = Date()
        let savedPaper = try await paperRepository.save(updatedPaper, in: workspace)
        try await loadWorkspaceData(in: workspace, selectingPaper: savedPaper.id, selectingMarkdown: selectedMarkdownID)
        return savedPaper
    }

    func returnFromPaperReader() {
        if let returnRoute = paperReaderReturnRoute {
            paperReaderReturnRoute = nil
            applyWorkspaceRoute(returnRoute)
            return
        }

        if let projectID = selectedProjectSpaceProjectID ?? currentProjectID,
           activeResearchProjects.contains(where: { $0.id == projectID }) {
            selectResearchProject(projectID, section: .library)
            return
        }

        selectSection(.library)
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
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let pdfURL: URL
                if let localURL = localPDFURL(for: paper, in: currentWorkspace) {
                    pdfURL = localURL
                } else {
                    let updatedPaper = try await ensureLocalPDFAvailable(for: paper, in: currentWorkspace)
                    guard let localURL = localPDFURL(for: updatedPaper, in: currentWorkspace) else {
                        return
                    }
                    pdfURL = localURL
                }
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
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedPaperReadingState(lastPage: Int, scaleFactor: Double?) {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        Task {
            do {
                let savedPaper = try await pdfReadingStateService.save(
                    lastPage: lastPage,
                    scaleFactor: scaleFactor,
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

    func reloadSelectedPDFAnnotations() {
        guard let currentWorkspace else {
            selectedPDFAnnotations = []
            return
        }

        Task {
            do {
                try await loadSelectedPDFAnnotations(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updatePDFSelection(preview: String?, pageIndex: Int?) {
        selectedPDFSelectionPreview = preview.map { limitedText($0, maxCharacters: 800) }
        selectedPDFSelectionPageIndex = pageIndex
    }

    func createPDFAnnotation(_ annotation: PDFAnnotationRecord) {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        var annotation = annotation
        if annotation.selectionFingerprint?.isEmpty != false {
            annotation.selectionFingerprint = annotation.duplicateFingerprint
        }

        if annotation.kind != .note,
           selectedPDFAnnotations.contains(where: { existing in
               existing.kind == annotation.kind && existing.duplicateFingerprint == annotation.duplicateFingerprint
           }) {
            recordAppDebugEvent("pdf.annotation.duplicate_skipped", payload: pdfAnnotationDebugPayload(annotation))
            return
        }

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.create", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func updatePDFAnnotationNote(id: PDFAnnotationRecord.ID, noteText: String) {
        guard let currentWorkspace, let selectedPaperDraft,
              let index = selectedPDFAnnotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        var annotation = selectedPDFAnnotations[index]
        annotation.noteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText
        annotation.updatedAt = Date()
        selectedPDFAnnotations[index] = annotation

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.update", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func deletePDFAnnotation(id: PDFAnnotationRecord.ID) {
        guard let currentWorkspace, let selectedPaperDraft,
              let annotation = selectedPDFAnnotations.first(where: { $0.id == id }) else {
            return
        }

        selectedPDFAnnotations.removeAll { $0.id == id }
        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.deleteAnnotation(id: id, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.delete", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func movePDFAnnotationNote(id: PDFAnnotationRecord.ID, pageIndex: Int, x: Double, y: Double) {
        guard let currentWorkspace, let selectedPaperDraft,
              let index = selectedPDFAnnotations.firstIndex(where: { $0.id == id && $0.kind == .note }) else {
            return
        }

        var annotation = selectedPDFAnnotations[index]
        annotation.pageIndex = pageIndex
        annotation.bounds = [PDFAnnotationBounds(
            pageIndex: pageIndex,
            x: x,
            y: y,
            width: 24,
            height: 24
        )]
        annotation.updatedAt = Date()
        selectedPDFAnnotations[index] = annotation

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.update", payload: pdfAnnotationDebugPayload(annotation))
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
            configuration.maxTokens = 384_000
        }
    }

    func useDeepSeekModel(_ option: DeepSeekModelOption) {
        useDeepSeekDefaults(model: option.id)
    }

    func testLLMConnection() {
        guard let currentWorkspace else {
            llmConnectionStatusMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        isTestingLLMConnection = true
        llmConnectionStatusMessage = nil

        Task {
            defer {
                isTestingLLMConnection = false
            }

            do {
                let apiKey = try await resolvedLLMAPIKey(for: currentWorkspace)
                guard !apiKey.isEmpty else {
                    throw AgentPanelValidationError.missingAPIKey
                }
                let response = try await openAIProvider.complete(
                    prompt: "Reply with OK.",
                    configuration: llmConfiguration,
                    apiKey: apiKey
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
                let summary = try await paperSummaryService.summarize(
                    selectedPaperDraft,
                    in: currentWorkspace,
                    configuration: llmConfiguration,
                    apiKey: try await resolvedLLMAPIKey(for: currentWorkspace)
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
        agentContextRefreshTask?.cancel()
        agentContextRefreshTask = Task {
            defer {
                isRefreshingAgentContext = false
            }
            guard !Task.isCancelled else {
                return
            }
            await refreshAgentState(in: currentWorkspace)
        }
    }

    func setAgentToolApproval(callID: String, isApproved: Bool) {
        if isApproved {
            agentToolApprovals.insert(callID)
            agentToolDenials.remove(callID)
            recordAppDebugEvent("ai.permission.inline_decision", payload: .object([
                "tool_call_id": .string(callID),
                "decision": .string("allow"),
                "risk": .string(agentPermissionRiskDescription(callID: callID))
            ]))
        } else {
            agentToolApprovals.remove(callID)
        }
    }

    func setAgentToolDenied(callID: String, isDenied: Bool) {
        if isDenied {
            agentToolDenials.insert(callID)
            agentToolApprovals.remove(callID)
            agentToolSessionApprovalDrafts.remove(callID)
            recordAppDebugEvent("ai.permission.inline_decision", payload: .object([
                "tool_call_id": .string(callID),
                "decision": .string("deny"),
                "risk": .string(agentPermissionRiskDescription(callID: callID))
            ]))
        } else {
            agentToolDenials.remove(callID)
        }
    }

    func requestAgentToolRewrite(callID: String) {
        let feedback = localized(
            "请根据当前对话重写这个草稿，保留来源依据，并先解释目标路径与主要改动。",
            "Please rewrite this draft from the current conversation, preserve source evidence, and explain the target path and main changes first."
        )
        agentToolCorrectionFeedback[callID] = feedback
        agentToolDenials.insert(callID)
        agentToolApprovals.remove(callID)
        agentToolSessionApprovalDrafts.remove(callID)
        agentStatusMessage = localized("已标记为需要 AI 重写。", "Marked for AI rewrite.")
        recordAppDebugEvent("ai.draft_review.rewrite_requested", payload: .object([
            "tool_call_id": .string(callID),
            "reason_present": .bool(true)
        ]))
    }

    private func agentPermissionRiskDescription(callID: String) -> String {
        guard let currentRun = agentCurrentRun,
              let item = agentPermissionDockItems(for: currentRun).first(where: { $0.id == callID }) else {
            return "unknown"
        }
        return item.risk.rawValue
    }

    func setAgentSessionApprovalDraft(callID: String, isEnabled: Bool) {
        if isEnabled {
            agentToolSessionApprovalDrafts.insert(callID)
            agentToolDenials.remove(callID)
        } else {
            agentToolSessionApprovalDrafts.remove(callID)
        }
    }

    func saveAgentToolCallDraft(callID: String) {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard let currentRun = agentCurrentRun,
              let call = currentRun.plan.toolCalls.first(where: { $0.id == callID }),
              let draft = markdownWritebackDraft(for: call, in: currentRun, workspace: currentWorkspace) else {
            agentErrorMessage = localized("没有可保存的 Markdown 草稿。", "No Markdown draft is available to save.")
            return
        }

        Task {
            do {
                let document = try await markdownRepository.saveContents(
                    draft.contents,
                    relativePath: draft.draftPath,
                    in: currentWorkspace
                )
                agentToolSessionApprovalDrafts.insert(callID)
                agentToolDenials.remove(callID)
                agentToolApprovals.remove(callID)
                let message = localized(
                    "已保存草稿：\(document.relativePath)。原目标 \(draft.targetPath) 尚未写入。",
                    "Saved draft: \(document.relativePath). Original target \(draft.targetPath) was not written."
                )
                agentStatusMessage = message
                let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
                let event = AgentSessionEvent(
                    sessionID: currentRun.id,
                    kind: .permissionResolved,
                    summary: message,
                    payloadJSON: JSONValue.object([
                        "action": .string("save_draft_only"),
                        "draft_path": .string(document.relativePath),
                        "target_path": .string(draft.targetPath),
                        "tool_call_id": .string(callID),
                        "tool_name": .string(call.toolName)
                    ]).canonicalJSON
                )
                try await agentSessionEventLogger.append(event, in: root)
                agentSessionEvents.append(event)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: document.relativePath
                )
            } catch {
                agentErrorMessage = error.localizedDescription
            }
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

    func setAllAgentTools(isEnabled: Bool) {
        agentDisabledToolNames = isEnabled ? [] : Set(agentToolDefinitions.map(\.name))
        persistAgentToolStateForCurrentScope()
    }

    func updateMinerUCommand(_ command: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUCommand = trimmed.isEmpty ? "mineru" : trimmed
        }
    }

    func updateAppLanguagePreference(_ preference: AppLanguagePreference) {
        let previousPreference = workspacePreferences.appLanguage
        Task { @MainActor [weak self] in
            self?.updateWorkspacePreferences { preferences in
                preferences.appLanguage = preference
            }
            self?.recordAppDebugEvent("l10n.language.change", payload: .object([
                "from": .string(previousPreference.rawValue),
                "to": .string(preference.rawValue)
            ]))
        }
    }

    var liquidGlassTintColor: Color {
        Self.color(for: workspacePreferences.liquidGlassTint)
    }

    func liquidGlassTintLabel(for preference: LiquidGlassTintPreference) -> String {
        switch preference {
        case .system:
            return localized("系统强调色", "System Accent")
        case .blue:
            return localized("雾蓝", "Mist Blue")
        case .mint:
            return localized("薄荷", "Mint")
        case .lavender:
            return localized("淡紫", "Lavender")
        case .rose:
            return localized("浅玫瑰", "Soft Rose")
        case .amber:
            return localized("浅琥珀", "Soft Amber")
        case .graphite:
            return localized("石墨", "Graphite")
        }
    }

    func updateLiquidGlassTintPreference(_ preference: LiquidGlassTintPreference) {
        updateWorkspacePreferences { preferences in
            preferences.liquidGlassTint = preference
        }
        recordAppDebugEvent("appearance.liquid_glass_tint.change", payload: .object([
            "tint": .string(preference.rawValue)
        ]))
    }

    static func color(for preference: LiquidGlassTintPreference) -> Color {
        switch preference {
        case .system:
            return .accentColor
        case .blue:
            return Color(red: 0.36, green: 0.55, blue: 0.82)
        case .mint:
            return Color(red: 0.34, green: 0.66, blue: 0.57)
        case .lavender:
            return Color(red: 0.58, green: 0.50, blue: 0.78)
        case .rose:
            return Color(red: 0.78, green: 0.45, blue: 0.55)
        case .amber:
            return Color(red: 0.78, green: 0.58, blue: 0.28)
        case .graphite:
            return Color(red: 0.48, green: 0.51, blue: 0.55)
        }
    }

    func updateAgentChatFontSize(_ fontSize: Double) {
        updateWorkspacePreferences { preferences in
            preferences.agentChatFontSize = fontSize
        }
    }

    func updateAgentLoopBudget(_ mutate: (inout AgentLoopOptions) -> Void) {
        updateWorkspacePreferences { preferences in
            mutate(&preferences.agentLoopBudget)
        }
    }

    func resetAgentLoopBudget() {
        updateWorkspacePreferences { preferences in
            preferences.agentLoopBudget = WorkspacePreferences.defaultAgentLoopBudget
        }
        agentStatusMessage = "AI Lab tool budget reset to defaults."
    }

    func updateAgentRuntimeSelection(_ selection: AgentRuntimeSelection) {
        updateWorkspacePreferences { preferences in
            preferences.agentRuntimeSelection = selection
            if selection == .langGraphSidecar || selection == .autoFallback {
                preferences.isSidecarDisabledForWorkspace = false
            }
        }
        recordAppDebugEvent("agent.runtime_selection_changed", payload: .object([
            "selection": .string(selection.rawValue)
        ]))
        agentStatusMessage = "AI Lab runtime set to \(selection.label)."
    }

    func setAgentDebugLoggingEnabled(_ isEnabled: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.agentDebugLoggingEnabled = isEnabled
        }
        recordAppDebugEvent(AppDebugEventName.debugModeChanged.rawValue, payload: .object([
            "enabled": .bool(isEnabled)
        ]), force: true)
        agentStatusMessage = isEnabled
            ? "Debug mode enabled. App input, output, and AI Lab operations will be logged locally."
            : "Debug mode disabled. Existing local debug logs were kept."
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

    func openAgentDebugLogDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let directory = currentResearchRoot.directoryURL(for: ".sci-station/debug")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recordAppDebugEvent(AppDebugEventName.debugLogOpened.rawValue)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
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

    /// User-facing scrubbed diagnostics export. Collects app/OS/config context
    /// plus recent debug events, runs everything through the path-aware redactor
    /// (home dir, absolute paths, API keys, tokens), and writes a plain-text file
    /// the tester can attach to a beta bug report.
    func exportDiagnosticsReport() {
        Task {
            let report = await buildDiagnosticsReport()
            await MainActor.run {
                let panel = NSSavePanel()
                panel.title = self.localized("导出诊断包", "Export Diagnostics")
                panel.prompt = self.localized("导出", "Export")
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "sci-station-diagnostics.txt"
                panel.allowedContentTypes = [.plainText]
                guard panel.runModal() == .OK, let destinationURL = panel.url else {
                    self.shellStatusMessage = self.localized("诊断导出已取消。", "Diagnostics export cancelled.")
                    return
                }
                do {
                    try Data(report.utf8).write(to: destinationURL, options: .atomic)
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    self.shellStatusMessage = self.localized(
                        "已导出脱敏诊断包（不含绝对路径与密钥）。",
                        "Exported scrubbed diagnostics (no absolute paths or secrets)."
                    )
                } catch {
                    self.present(error)
                }
            }
        }
    }

    private func buildDiagnosticsReport() async -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let prefs = workspacePreferences

        var lines: [String] = []
        lines.append("Sci-Station Diagnostics")
        lines.append("generated_at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("app_version: \(version) (\(build))")
        lines.append("os: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("language: \(prefs.appLanguage.rawValue)")
        lines.append("agent_runtime: \(prefs.agentRuntimeSelection.rawValue)")
        lines.append("agent_debug_logging: \(prefs.agentDebugLoggingEnabled)")
        lines.append("workspace_open: \(currentWorkspace != nil)")
        lines.append("modules: \(workspaceModuleStatusSummary)")
        lines.append("")
        lines.append("== Recent debug events (scrubbed) ==")
        if let root = currentResearchRoot {
            let logger = AppDebugEventLogger()
            if let events = try? await logger.events(in: root, limit: 100) {
                let encoder = AgentRunDirectoryStore.encoder()
                for event in events {
                    if let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
                        lines.append(line)
                    }
                }
            } else {
                lines.append("(no debug events available)")
            }
        } else {
            lines.append("(no workspace open)")
        }

        let raw = lines.joined(separator: "\n") + "\n"
        // Defense in depth: scrub the entire report even though events are
        // already redacted at write time.
        return AgentRunDirectoryStore.redactPathLikeTextPublic(raw)
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

    func refreshAgentRetrievalIndexStatus() {
        guard let currentResearchRoot else {
            agentRetrievalIndexStatus = .disabled()
            return
        }
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.status(in: currentResearchRoot)
        }
    }

    func rebuildAgentRetrievalCurrentProject() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot(status: .indexing, store: agentRetrievalIndexStatus.store)
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.rebuildCurrentProject(in: currentResearchRoot, projectID: currentProjectID)
            agentStatusMessage = "Retrieval index rebuild finished: \(agentRetrievalIndexSummary)."
        }
    }

    func rebuildAgentRetrievalSelectedSource() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        guard let relativePath = selectedAgentRetrievalSourcePath() else {
            agentErrorMessage = "No selected paper or wiki source is available for retrieval rebuild."
            return
        }
        agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot(status: .indexing, store: agentRetrievalIndexStatus.store)
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.rebuildSelectedSource(relativePath, in: currentResearchRoot)
            let suffix = agentRetrievalIndexStatus.zeroChunkGuidance.map { " \($0)" } ?? ""
            agentStatusMessage = "Retrieval source rebuild finished for \(relativePath): \(agentRetrievalIndexSummary).\(suffix)"
        }
    }

    func checkSelectedPaperMarkdownQuality() {
        guard let currentWorkspace else {
            agentErrorMessage = localized("没有打开的工作区。", "No workspace is open.")
            return
        }
        guard let paper = selectedPaperDraft else {
            agentErrorMessage = localized("请先选择一篇论文，再检查 paper.md。", "Select a paper before checking paper.md.")
            return
        }

        isCheckingPaperMarkdownQuality = true
        Task {
            defer {
                isCheckingPaperMarkdownQuality = false
            }
            let report = paperMarkdownQualityInspector.inspect(paper, in: currentWorkspace)
            paperMarkdownQualityReport = report
            agentStatusMessage = localized(
                "paper.md 检查完成：\(report.summary(usesEnglishInterface: false))",
                "paper.md check finished: \(report.summary(usesEnglishInterface: true))"
            )
        }
    }

    func openAgentRetrievalIndexDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let url = currentResearchRoot.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyAgentRetrievalDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(redactedAgentRetrievalDiagnosticSummary, forType: .string)
        agentStatusMessage = "Redacted retrieval diagnostic copied."
    }

    func openSelectedPaperMarkdown() {
        guard let selectedPaperDraft else {
            agentErrorMessage = localized("请先选择一篇论文。", "Select a paper first.")
            return
        }
        openPaperMarkdown(selectedPaperDraft)
    }

    func openLegacyPaperMigrationReport() {
        guard let currentWorkspace,
              let relativePath = legacyPaperMigrationReport?.reportRelativePath?.nilIfBlank else {
            agentErrorMessage = localized("当前没有可打开的迁移报告。", "No migration report is available to open.")
            return
        }
        NSWorkspace.shared.open(currentWorkspace.fileURL(for: relativePath))
    }

    private func selectedAgentRetrievalSourcePath() -> String? {
        if let selectedPaperDraft {
            return paperMarkdownPath(for: selectedPaperDraft)
        }
        if let selectedMarkdownDraft {
            return selectedMarkdownDraft.relativePath
        }
        return nil
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

        let prompt = agentPendingUserPrompt
        let partialResponse = agentStreamingResponseText
        let runContextProjectID = agentConversationProjectID
        let runtimeSelector = workspacePreferences.agentRuntimeSelection.rawValue
        let enabledToolNamesSnapshot = effectiveAgentAllowedToolNames?.sorted() ?? agentEnabledToolNames.sorted()
        let retryOfRunID = agentRetrySourceRunID
        agentPlanningTask?.cancel()
        agentPlanningTask = nil
        agentRetrySourceRunID = nil
        isPlanningAgentRun = false
        agentPendingUserPrompt = nil
        publishAgentStreamingResponseNow()
        agentStatusMessage = "已停止 AI 输出。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.stop_requested", payload: .object([
            "prompt": .string(prompt ?? ""),
            "partial_assistant_response": .string(partialResponse ?? ""),
            "retry_of_run_id": .string(retryOfRunID ?? "")
        ]))

        if let prompt, let currentWorkspace {
            Task {
                await recordAgentCancelledRun(
                    prompt: prompt,
                    message: "用户已停止本次 AI 输出。",
                    partialAssistantResponse: partialResponse,
                    in: currentWorkspace,
                    currentProjectID: runContextProjectID,
                    runtimeSelector: runtimeSelector,
                    enabledToolNames: enabledToolNamesSnapshot,
                    retryOfRunID: retryOfRunID
                )
            }
        }
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

    private func recordAgentInlineFailure(
        prompt: String,
        message: String,
        partialAssistantResponse: String?,
        in workspace: ResearchWorkspace,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String],
        failureCategory: AgentRunFailureCategory = .unknown,
        retryOfRunID: String? = nil
    ) async {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        do {
            let failedRun = try await agentService.recordFailedRun(
                goal: prompt,
                message: message,
                partialAssistantResponse: partialAssistantResponse,
                in: root,
                currentProjectID: currentProjectID,
                runtimeSelector: runtimeSelector,
                enabledToolNames: enabledToolNames,
                failureCategory: failureCategory,
                retryOfRunID: retryOfRunID
            )
            agentCurrentRun = failedRun
            try await attachRunToActiveThread(failedRun, in: workspace)
            resetAgentPermissionDockState()
            await refreshAgentState(in: workspace)
        } catch {
            agentErrorMessage = "\(message) 保存错误状态失败：\(error.localizedDescription)"
        }
    }

    private func recordAgentCancelledRun(
        prompt: String,
        message: String,
        partialAssistantResponse: String?,
        in workspace: ResearchWorkspace,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String],
        retryOfRunID: String? = nil
    ) async {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        do {
            let cancelledRun = try await agentService.recordCancelledRun(
                goal: prompt,
                message: message,
                partialAssistantResponse: partialAssistantResponse,
                in: root,
                currentProjectID: currentProjectID,
                runtimeSelector: runtimeSelector,
                enabledToolNames: enabledToolNames,
                retryOfRunID: retryOfRunID
            )
            agentCurrentRun = cancelledRun
            try await attachRunToActiveThread(cancelledRun, in: workspace)
            resetAgentPermissionDockState()
            await refreshAgentState(in: workspace)
        } catch {
            agentErrorMessage = "\(message) 保存停止状态失败：\(error.localizedDescription)"
        }
    }

    func startNewAgentConversation() {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        let now = Date()
        let contextProjectID = agentConversationProjectID
        let thread = AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: contextProjectID,
            contextScope: agentNextRunContextScope,
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            runtimeSelector: workspacePreferences.agentRuntimeSelection.rawValue,
            createdFromRoute: "ai_lab",
            title: "New Chat",
            createdAt: now,
            updatedAt: now
        )
        pendingAgentThread = thread
        pendingAgentThreadsByProject[agentProjectDraftKey(contextProjectID)] = thread
        activeAgentThreadID = thread.id
        agentGoal = ""
        agentCurrentRun = nil
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        agentStatusMessage = "已开始新的 \(agentNextRunContextTitle) 对话。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.thread_started", payload: .object([
            "thread_id": .string(thread.id),
            "project_id": .string(contextProjectID ?? ""),
            "scope": .string(agentNextRunContextScope.rawValue)
        ]), threadID: thread.id)
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
        recordAppDebugEvent("agent.thread_draft_discarded", payload: .object([
            "thread_id": .string(pendingAgentThread.id),
            "project_id": .string(projectID ?? "")
        ]), threadID: pendingAgentThread.id)

        if let currentWorkspace {
            let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
            Task {
                try? await agentService.removeDraft(projectID: projectID, threadID: pendingAgentThread.id, in: root)
            }
        }
    }

    func selectAgentThread(_ thread: AgentThread) {
        guard !thread.isArchived else {
            agentStatusMessage = "该对话已归档，不能作为当前对话打开。"
            activeAgentThreadID = preferredAgentThreadID(projectID: thread.projectID)
            pendingAgentThread = nil
            recordAppDebugEvent("agent.archived_thread_selection_blocked", payload: .object([
                "thread_id": .string(thread.id),
                "title": .string(thread.title)
            ]), threadID: thread.id)
            return
        }
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        activeAgentThreadID = thread.id
        pendingAgentThread = nil
        agentNextRunContextScope = thread.contextScope ?? AgentContextScope.inferred(projectID: thread.projectID)
        agentNextRunProjectID = thread.projectID
        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        agentCurrentRun = thread.runIDs.reversed().compactMap { runsByID[$0] }.first
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: thread.projectID, threadID: thread.id)] ?? ""
        restorePersistedAgentDraft(projectID: thread.projectID, threadID: thread.id)
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        let workspaceSuffix = thread.workspaceName.map { "（\($0)）" } ?? ""
        agentStatusMessage = "已打开 \(thread.title)\(workspaceSuffix)。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.thread_selected", payload: .object([
            "thread_id": .string(thread.id),
            "title": .string(thread.title),
            "project_id": .string(thread.projectID ?? ""),
            "run_ids": jsonStringArray(thread.runIDs)
        ]), threadID: thread.id)
    }

    func openAgentRun(_ run: AgentRun) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentNextRunContextScope = run.contextScope ?? AgentContextScope.inferred(projectID: run.projectID ?? run.currentProjectID)
        agentNextRunProjectID = run.projectID ?? run.currentProjectID
        activeAgentThreadID = allAgentThreads.first { !$0.isArchived && $0.runIDs.contains(run.id) }?.id
        pendingAgentThread = nil
        agentCurrentRun = run
        agentGoal = run.goal
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        agentStatusMessage = "Opened a previous \(agentConversationTitle) run."
        agentErrorMessage = nil
        recordAppDebugEvent("agent.run_opened", payload: .object([
            "run_id": .string(run.id),
            "goal": .string(run.goal),
            "bound_thread_id": .string(activeAgentThreadID ?? "")
        ]), runID: run.id)
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
                recordAppDebugEvent("agent.thread_archived", payload: .object([
                    "thread_id": .string(thread.id),
                    "title": .string(thread.title),
                    "run_ids": jsonStringArray(thread.runIDs)
                ]), threadID: thread.id)
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
            contextScope: run.contextScope ?? AgentContextScope.inferred(projectID: run.currentProjectID),
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            runtimeSelector: run.runtimeSelector,
            createdFromRoute: run.createdFromRoute ?? "ai_lab",
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

    func retryAgentRun(_ run: AgentRun) {
        guard run.isRetryable else {
            agentErrorMessage = "这个 run 当前不是可重试状态。"
            return
        }
        guard !isPlanningAgentRun else {
            agentErrorMessage = "当前 AI 正在运行，请先停止或等待完成。"
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentNextRunContextScope = run.contextScope ?? AgentContextScope.inferred(projectID: run.projectID ?? run.currentProjectID)
        agentNextRunProjectID = run.projectID ?? run.currentProjectID
        if let thread = allAgentThreads.first(where: { $0.runIDs.contains(run.id) && !$0.isArchived }) {
            activeAgentThreadID = thread.id
            pendingAgentThread = nil
        }
        agentGoal = run.goal
        agentRetrySourceRunID = run.id
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        agentStatusMessage = "正在重试上一条失败请求。"
        agentErrorMessage = nil
        generateAgentPlan()
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
        guard activeAgentThread == nil, pendingAgentThread == nil else {
            return
        }
        guard agentCurrentRun?.currentProjectID != projectID else {
            return
        }

        agentNextRunContextScope = projectID == nil ? .workspace : .project
        agentNextRunProjectID = projectID
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
        resetAgentStreamingPreview()
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

        if let warning = agentToolAvailabilityWarning {
            agentErrorMessage = warning
            recordAppDebugEvent("ai.toolset.unavailable", payload: .object([
                "visible_mode": .string(agentVisibleMode.rawValue),
                "enabled_tool_count": .number(String(agentEnabledToolNames.count)),
                "available_tool_count": .number(String(agentToolDefinitions.count))
            ]))
            return
        }

        let conversationHistory = agentConversationMessagesForPrompt(latestGoal: trimmedGoal)
        let allowedToolNames = effectiveAgentAllowedToolNames
        let interactionMode = agentInteractionMode
        let usesToolLoopRuntime = interactionMode.usesToolLoopRuntime
        let runContextProjectID = agentConversationProjectID
        let runtimeSelection = workspacePreferences.agentRuntimeSelection
        let enabledToolNamesSnapshot = allowedToolNames?.sorted() ?? agentEnabledToolNames.sorted()
        let retryOfRunID = agentRetrySourceRunID
        agentRetrySourceRunID = nil
        let executionOptions = AgentExecutionOptions(
            mode: .planOnly,
            loopPolicy: usesToolLoopRuntime ? .readOnlyAutoApproveWritesRequireApproval : .manualApprovalOnly,
            runtimeSelection: runtimeSelection,
            isSidecarDisabledForWorkspace: workspacePreferences.isSidecarDisabledForWorkspace,
            disabledHookIDs: agentDisabledHookIDs,
            plannerInstructions: interactionMode.plannerInstructions,
            allowedToolNames: allowedToolNames,
            enabledWorkflowIDs: enabledAgentWorkflowIDs,
            allowsPlainTextResponse: interactionMode.allowsPlainTextResponse,
            loopOptions: workspacePreferences.agentLoopBudget,
            retryOfRunID: retryOfRunID
        )
        let responseDeltaHandler = usesToolLoopRuntime ? makeAgentStreamingDeltaHandler() : nil

        isPlanningAgentRun = true
        agentPendingUserPrompt = trimmedGoal
        recordAppDebugEvent("agent.prompt_submitted", payload: .object([
            "prompt": .string(trimmedGoal),
            "interaction_mode": .string(interactionMode.rawValue),
            "runtime_selection": .string(runtimeSelection.rawValue),
            "project_id": .string(runContextProjectID ?? ""),
            "selected_paper_id": .string(selectedPaperID ?? ""),
            "allowed_tool_names": jsonStringArray(allowedToolNames?.sorted() ?? []),
            "enabled_tool_names": jsonStringArray(enabledToolNamesSnapshot),
            "conversation_history_messages": .number(String(conversationHistory.count)),
            "conversation_history_characters": .number(String(conversationHistory.reduce(0) { $0 + $1.content.count }))
        ]))
        resetAgentStreamingPreview()
        startAgentLiveEventRefresh(in: currentWorkspace)
        agentGoal = ""
        persistAgentDraftForCurrentConversation()
        agentErrorMessage = nil
        agentStatusMessage = nil

        agentPlanningTask?.cancel()
        agentPlanningTask = Task {
            defer {
                stopAgentLiveEventRefresh(clearRunID: true)
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
                    currentProjectID: runContextProjectID,
                    selectedPaperID: selectedPaperID,
                    includedPaperIDs: agentKnowledgePaperIDsForContext,
                    conversationHistory: conversationHistory,
                    configuration: llmConfiguration,
                    apiKey: apiKey,
                    options: executionOptions,
                    responseDeltaHandler: responseDeltaHandler,
                    sessionEventHandler: makeAgentSessionEventHandler()
                )
                try Task.checkCancellation()
                agentCurrentRun = run
                resetAgentStreamingPreview()
                try await attachRunToActiveThread(run, in: currentWorkspace)
                resetAgentPermissionDockState()
                let isWaitingForApproval = usesToolLoopRuntime && run.lifecycleState == .waitingForApproval
                agentStatusMessage = isWaitingForApproval
                    ? "等待批准工具调用。输入草稿已保留。"
                    : (usesToolLoopRuntime
                        ? "已根据所选 AI 知识库生成回复。"
                        : "计划已生成。运行前请审查允许写入工作区的工具。")
                recordAgentRunDebugOutput(run, event: "agent.run_completed")
                await refreshAgentState(in: currentWorkspace)
            } catch is CancellationError {
                agentStatusMessage = "已停止 AI 输出。"
                agentErrorMessage = nil
                recordAppDebugEvent("agent.run_cancelled", payload: .object([
                    "prompt": .string(trimmedGoal),
                    "partial_assistant_response": .string(agentStreamingResponseText ?? "")
                ]))
            } catch {
                let message = error.localizedDescription
                let failureCategory: AgentRunFailureCategory = (error is AgentPlanParserError) ? .malformedResponse : .providerError
                agentErrorMessage = message
                recordAppDebugEvent("agent.run_failed", payload: .object([
                    "prompt": .string(trimmedGoal),
                    "error": .string(message),
                    "partial_assistant_response": .string(agentStreamingResponseText ?? "")
                ]))
                await recordAgentInlineFailure(
                    prompt: trimmedGoal,
                    message: message,
                    partialAssistantResponse: agentStreamingResponseText,
                    in: currentWorkspace,
                    currentProjectID: runContextProjectID,
                    runtimeSelector: runtimeSelection.rawValue,
                    enabledToolNames: enabledToolNamesSnapshot,
                    failureCategory: failureCategory,
                    retryOfRunID: retryOfRunID
                )
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
        let runContextProjectID = currentRun.projectID ?? currentRun.currentProjectID ?? agentConversationProjectID
        isExecutingAgentTools = true
        agentErrorMessage = nil
        agentStatusMessage = nil
        recordAppDebugEvent("agent.tools_execution_started", payload: .object([
            "run_id": .string(currentRun.id),
            "goal": .string(goal),
            "approved_tool_call_ids": jsonStringArray(Array(agentToolApprovals).sorted()),
            "denied_tool_call_ids": jsonStringArray(Array(agentToolDenials).sorted())
        ]), runID: currentRun.id)
        startAgentLiveEventRefresh(in: currentWorkspace, liveRunID: currentRun.id)

        Task {
            defer {
                stopAgentLiveEventRefresh(clearRunID: true)
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
                        currentProjectID: runContextProjectID,
                        selectedPaperID: selectedPaperID,
                        includedPaperIDs: agentKnowledgePaperIDsForContext,
                        allowedToolNames: effectiveAgentAllowedToolNames,
                        disabledHookIDs: agentDisabledHookIDs,
                        loopOptions: workspacePreferences.agentLoopBudget,
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
                    recordAgentRunDebugOutput(resumedRun, event: "agent.tools_resume_completed")
                    return
                }

                let executedRun = try await agentService.executeApprovedPlan(
                    goal: goal,
                    plan: currentRun.plan,
                    in: currentWorkspace,
                    root: currentResearchRoot,
                    currentProjectID: runContextProjectID,
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
                recordAgentRunDebugOutput(executedRun, event: "agent.tools_execution_completed")
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                agentErrorMessage = error.localizedDescription
                recordAppDebugEvent("agent.tools_execution_failed", payload: .object([
                    "run_id": .string(currentRun.id),
                    "error": .string(error.localizedDescription)
                ]), runID: currentRun.id)
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
        startDate: Date? = nil,
        dueDate: Date?,
        kind: TodoKind = .general,
        priority: Priority = .medium,
        notes: String? = nil,
        projectIDs: [ResearchProject.ID]? = nil,
        tags: [String]? = nil,
        relatedPaperIDs: [String]? = nil
    ) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let now = Date()
        let resolvedTags = tags ?? selectedTagName.map { [$0] } ?? []
        let resolvedPaperIDs = relatedPaperIDs ?? selectedPaperDraft.map { [$0.id] } ?? []
        var todo = TodoItem(
            id: "todo-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            kind: kind,
            status: .open,
            startDate: startDate.map { Calendar.current.startOfDay(for: $0) },
            dueDate: dueDate.map { Calendar.current.startOfDay(for: $0) },
            priority: priority,
            projectIDs: projectIDs ?? currentProjectID.map { [$0] } ?? [],
            tags: resolvedTags,
            relatedPaperIDs: resolvedPaperIDs,
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
        kind: TodoKind? = nil,
        status: TodoStatus,
        startDate: Date? = nil,
        dueDate: Date?,
        priority: Priority,
        notes: String?,
        projectIDs: [ResearchProject.ID]? = nil,
        tags: [String]? = nil,
        relatedPaperIDs: [String]? = nil
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
        updatedTodo.kind = kind ?? updatedTodo.kind
        updatedTodo.status = status
        updatedTodo.startDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        updatedTodo.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        updatedTodo.priority = priority
        updatedTodo.projectIDs = projectIDs ?? updatedTodo.projectIDs
        updatedTodo.tags = tags ?? updatedTodo.tags
        updatedTodo.relatedPaperIDs = relatedPaperIDs ?? updatedTodo.relatedPaperIDs
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
        if let nextSelectionID,
           !markdownDocuments.contains(where: { $0.id == nextSelectionID }) {
            selectedMarkdownID = nil
            selectedMarkdownDraft = nil
            updateSelectedMarkdownSaveState(.clean)
            openMarkdownDocument(relativePath: nextSelectionID)
            return
        }
        applyMarkdownSelection(nextSelectionID)
    }

    func cancelDiscardUnsavedMarkdownSelection() {
        pendingMarkdownSelectionID = nil
        isShowingUnsavedMarkdownConfirmation = false
    }

    private func applyMarkdownSelection(_ id: String?) {
        selectedMarkdownID = id
        selectedMarkdownDraft = markdownDocuments.first(where: { $0.id == id })
        updateSelectedMarkdownSaveState(.clean)
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
                let directDocument = try await markdownRepository.loadDocument(relativePath: relativePath, in: currentWorkspace)
                mergeMarkdownDocument(directDocument)
                selectedMarkdownID = directDocument.id
                selectedMarkdownDraft = directDocument
                updateSelectedMarkdownSaveState(.clean)
                recordAppDebugEvent("paper_markdown.open_direct", payload: .object([
                    "relative_path": .string(directDocument.relativePath),
                    "is_paper_markdown": .bool(directDocument.relativePath.hasSuffix("/paper.md"))
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: directDocument.id)
            } catch {
                present(error)
            }
        }
    }

    func openWorkspaceRelativePath(_ relativePath: String) {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              !normalizedPath.contains(".."),
              let currentWorkspace else {
            return
        }

        if normalizedPath.hasSuffix(".md") {
            openMarkdownDocument(relativePath: normalizedPath)
            return
        }

        let fileURL = currentWorkspace.fileURL(for: normalizedPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL.deletingLastPathComponent()])
        }
    }

    func openPaperMarkdown(_ paper: Paper) {
        openMarkdownDocument(relativePath: paperMarkdownPath(for: paper))
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
        updateSelectedMarkdownSaveState(selectedMarkdownHasUnsavedChanges ? .dirty : .clean)
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
        updateSelectedMarkdownSaveState(.dirty)
    }

    func insertMarkdownFormatting(_ action: MarkdownFormattingAction) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        let insertion = action.insertionText
        let currentContents = draft.rawContents.trimmingCharacters(in: .newlines)
        draft.rawContents = currentContents.isEmpty
            ? insertion
            : currentContents + "\n\n" + insertion
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(.dirty)
    }

    func addFrontmatterToSelectedMarkdown() {
        guard var draft = selectedMarkdownDraft else {
            return
        }
        guard !draft.rawContents.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") else {
            return
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : draft.title
        draft.rawContents = """
        ---
        title: "\(title)"
        tags: []
        ---

        \(draft.rawContents)
        """
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(.dirty)
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

    func createMarkdownPage(named name: String) {
        guard let currentWorkspace else {
            return
        }

        let relativePath = wikiManagedRelativePath(from: name, defaultFileName: "untitled.md")
        let title = markdownTitle(from: name)
        let contents = "# \(title)\n"
        Task {
            do {
                let document = try await markdownRepository.createDocument(relativePath: relativePath, contents: contents, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.create", payload: .object(["relative_path": .string(document.relativePath)]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func createMarkdownFolder(named name: String) {
        guard let currentWorkspace else {
            return
        }

        let relativePath = wikiManagedFolderPath(from: name, defaultFolderName: "notes")
        Task {
            do {
                let createdPath = try await markdownRepository.createFolder(relativePath: relativePath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.create", payload: .object([
                    "relative_path": .string(createdPath),
                    "kind": .string("folder")
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownID)
            } catch {
                present(error)
            }
        }
    }

    func renameSelectedMarkdownDocument(to newFileName: String) {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let oldPath = selectedMarkdownDraft.relativePath
        Task {
            do {
                let document = try await markdownRepository.renameDocument(relativePath: oldPath, toFileName: newFileName, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.rename", payload: .object([
                    "from": .string(oldPath),
                    "to": .string(document.relativePath)
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func moveSelectedMarkdownDocument(toFolder folderPath: String) {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let oldPath = selectedMarkdownDraft.relativePath
        let fileName = (oldPath as NSString).lastPathComponent
        let destinationFolder = wikiManagedFolderPath(from: folderPath, defaultFolderName: "notes")
        let destinationPath = (destinationFolder as NSString).appendingPathComponent(fileName)
            .replacingOccurrences(of: "\\", with: "/")
        Task {
            do {
                let document = try await markdownRepository.moveDocument(from: oldPath, to: destinationPath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.rename", payload: .object([
                    "from": .string(oldPath),
                    "to": .string(document.relativePath),
                    "operation": .string("move")
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func archiveSelectedMarkdownDocument() {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let archivedPath = selectedMarkdownDraft.relativePath
        let remainingIDs = markdownDocuments.map(\.id).filter { $0 != selectedMarkdownDraft.id }
        Task {
            do {
                let trashPath = try await markdownRepository.archiveDocument(relativePath: archivedPath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.archive", payload: .object([
                    "relative_path": .string(archivedPath),
                    "trash_path": .string(trashPath)
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: remainingIDs.first)
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedMarkdownChanges() {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        isSavingSelectedMarkdown = true
        updateSelectedMarkdownSaveState(.saving)
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
                updateSelectedMarkdownSaveState(.clean)
            } catch {
                updateSelectedMarkdownSaveState(.failed, errorMessage: error.localizedDescription)
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
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
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
        await initializeGraphRepository(in: workspace)
    }

    private func loadResearchRoot(in workspace: ResearchWorkspace, compatibility: ResearchRootCompatibility?) async throws {
        let root = ResearchRoot(rootURL: workspace.rootURL)
        currentResearchRoot = root

        // In DEBUG, start streaming SwiftUI runtime issues to a
        // workspace-local log so the AI usage-test orchestrator can read
        // them as an independent assertion channel. Idempotent.
        #if DEBUG
        if uiTestBridgeForceDebugLogging {
            _ = SwiftUIRuntimeWarningCapture.shared.install(rootURL: workspace.rootURL)
        } else {
            SwiftUIRuntimeWarningCapture.shared.stop()
        }
        #endif

        let moduleConfiguration = try await workspaceModuleConfigurationStore.load(in: root)
        applyWorkspaceModuleConfiguration(moduleConfiguration, in: root)
        observeWorkspaceModuleConfigurationChanges(in: root)
        normalizeSelectedSectionForModuleAvailability()

        let registry = try await projectRegistryRepository.load(in: root)
        researchProjects = registry.projects
        currentProjectID = registry.lastOpenedProjectID ?? registry.projects.first?.id
        workspaceModuleOverrides = await loadProjectModuleOverrides(for: registry.projects, in: root)
        normalizeSelectedSectionForModuleAvailability()

        if compatibility == .legacyWorkspace || registry.projects.contains(where: { $0.defaultTags.contains("legacy-workspace") }) {
            rootCompatibilityMessage = "Opened an existing single-workspace library as a research root. Sci-Station created a default project shell without moving your files."
        } else {
            rootCompatibilityMessage = nil
        }
        agentRetrievalIndexStatus = await agentEmbeddingIndexController.status(in: root)
    }

    func saveWorkspaceModuleConfiguration(_ configuration: WorkspaceModuleConfiguration) async throws {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        do {
            try await workspaceModuleConfigurationStore.save(configuration, in: root)
            applyWorkspaceModuleConfiguration(configuration, in: root)
        } catch {
            throw ModuleSettingsError.persistFailed(error.localizedDescription)
        }
    }

    func resetWorkspaceModulesToTemplateDefault() async throws {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        let template = (try? WorkspaceTemplateRepository().loadTemplate(in: root)) ?? WorkspaceTemplateRegistry.literatureReview
        let beforeModules = workspaceModuleConfiguration.modules.filter(\.enabled).map(\.id).sorted()
        let configuration = WorkspaceModuleRegistry.configuration(for: template)
        try await saveWorkspaceModuleConfiguration(configuration)
        recordModuleSettingsDebugEvent("module_settings.reset_to_template", payload: .object([
            "template_id": .string(template.id),
            "before_modules": jsonStringArray(beforeModules),
            "after_modules": jsonStringArray(configuration.modules.filter(\.enabled).map(\.id).sorted())
        ]))
    }

    @discardableResult
    func setProjectModuleOverride(projectID: ResearchProject.ID, moduleID: String, enabled: Bool?) async throws -> WorkspaceModuleOverride? {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        let override = try await workspaceModuleOverrideRepository.setOverride(projectID: projectID, moduleID: moduleID, enabled: enabled, in: root)
        if let override {
            workspaceModuleOverrides[projectID] = override
        } else {
            workspaceModuleOverrides.removeValue(forKey: projectID)
        }
        normalizeSelectedSectionForModuleAvailability()
        recordModuleSettingsDebugEvent("module_settings.override_apply", payload: .object([
            "project_id": .string(projectID),
            "id": .string(moduleID),
            "enabled": .bool(enabled ?? (workspaceModuleConfiguration.module(id: moduleID)?.enabled ?? false)),
            "fallback_to_workspace": .bool(enabled == nil),
            "cleared": .bool(enabled == nil)
        ]))
        return override
    }

    func repairWorkspaceModuleDirectory(_ status: WorkspaceModuleDirectoryStatus, approved: Bool) async -> WorkspaceModuleDirectoryRepairOutcome {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            return .failed(path: status.path, reason: "No workspace is open.")
        }

        let repairer = WorkspaceModuleDirectoryRepairer { request in
            AgentPermissionDecision(
                action: approved ? .allow : .deny,
                scope: .once,
                message: approved ? "Approved from Module Settings." : "Denied from Module Settings."
            )
        }
        let outcome = await repairer.repair(status, in: root, activeProjects: activeResearchProjects)
        workspaceModuleDirectoryStatuses = WorkspaceModuleRegistry.directoryStatuses(for: workspaceModuleConfiguration, in: root)
        recordModuleSettingsDebugEvent("module_settings.repair", payload: .object([
            "module_id": .string(status.moduleID),
            "path": .string(status.path),
            "outcome": .string(outcome.debugOutcome),
            "reason": .string(moduleDirectoryRepairReason(outcome))
        ]))
        return outcome
    }

    func recordModuleSettingsDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload, force: true)
    }

    func recordHomeDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload)
    }

    func recordShellDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload)
    }

    private func applyWorkspaceModuleConfiguration(_ configuration: WorkspaceModuleConfiguration, in root: ResearchRoot) {
        let mergedConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: configuration)
        workspaceModuleConfiguration = mergedConfiguration
        workspaceModuleWarnings = WorkspaceModuleRegistry.warnings(for: mergedConfiguration)
        workspaceModuleDirectoryStatuses = WorkspaceModuleRegistry.directoryStatuses(for: mergedConfiguration, in: root)
        normalizeSelectedSectionForModuleAvailability()
    }

    private func observeWorkspaceModuleConfigurationChanges(in root: ResearchRoot) {
        workspaceModuleConfigurationWatchTask?.cancel()
        workspaceModuleConfigurationWatchTask = Task { [weak self] in
            guard let self else { return }
            for await configuration in workspaceModuleConfigurationStore.subscribeChanges(in: root) {
                await MainActor.run {
                    self.applyWorkspaceModuleConfiguration(configuration, in: root)
                }
            }
        }
    }

    private func loadProjectModuleOverrides(for projects: [ResearchProject], in root: ResearchRoot) async -> [String: WorkspaceModuleOverride] {
        var overrides: [String: WorkspaceModuleOverride] = [:]
        for project in projects {
            if let override = try? await workspaceModuleOverrideRepository.loadOverride(projectID: project.id, in: root) {
                overrides[project.id] = override
            }
        }
        return overrides
    }

    private func moduleDirectoryRepairReason(_ outcome: WorkspaceModuleDirectoryRepairOutcome) -> String {
        switch outcome {
        case let .created(paths):
            return paths.joined(separator: ", ")
        case let .skippedWildcard(path):
            return "Skipped wildcard path \(path) because no active project instance was available."
        case let .denied(_, reason), let .failed(_, reason):
            return reason
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
        restoreWorkspaceRouteFromPreferences()
        normalizeSelectedSectionForModuleAvailability()
        restorePinnedAgentThreadsForCurrentProject()
        restoreAgentToolStateForCurrentScope()
    }

    private func fallbackWorkspaceSection() -> WorkspaceSection {
        visibleWorkspaceSidebarSections.first ?? .dashboard
    }

    private func fallbackProjectSection() -> WorkspaceSection {
        fallbackProjectSection(for: currentProjectID)
    }

    private func fallbackProjectSection(for projectID: ResearchProject.ID?) -> WorkspaceSection {
        visibleProjectSidebarSections(for: projectID).first ?? fallbackWorkspaceSection()
    }

    private func normalizeSelectedSectionForModuleAvailability() {
        if let selectedSection, !isWorkspaceSectionAvailable(selectedSection) {
            self.selectedSection = fallbackWorkspaceSection()
        }
        normalizeProjectSpaceSelectionForAvailability()
        if isViewingGlobalTodos && !isWorkspaceSectionAvailable(.tasks) {
            isViewingGlobalTodos = false
        }
        if !isWorkspaceSectionAvailable(.library) {
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    private func normalizeProjectSpaceSelectionForAvailability() {
        guard let projectID = selectedProjectSpaceProjectID else {
            return
        }

        guard activeResearchProjects.contains(where: { $0.id == projectID }) else {
            selectedProjectSpaceProjectID = nil
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
            selectedSection = .projects
            showShellStatus(localized("项目已不存在，已回到项目列表。", "Project no longer exists; returned to the project list."))
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(RoutePersistenceFallbackReason.projectMissing.rawValue)
            ]))
            return
        }

        let availableTabs = projectSpaceTabs(for: projectID)
        if ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(selectedProjectSpaceTabID),
           availableTabs.contains(where: { $0.id == ProjectSpaceTabsBuilder.mergedReadingTabID }) {
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.mergedReadingTabID
            return
        }
        if !availableTabs.contains(where: { $0.id == selectedProjectSpaceTabID }) {
            let hiddenTabID = selectedProjectSpaceTabID
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
            recordShellDebugEvent("project_space.builder_warn", payload: .object([
                "project_id": .string(projectID),
                "hidden_tabs": jsonStringArray([hiddenTabID]),
                "reason": .string("module_disabled")
            ]))
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(RoutePersistenceFallbackReason.moduleDisabled.rawValue)
            ]))
        }
    }

    private func restoreWorkspaceRouteFromPreferences() {
        let candidate = workspacePreferences.lastRoute ?? legacyRouteFromRecentSection()
        let result = RoutePersistence.restoreResult(
            candidate: candidate,
            activeProjectIDs: Set(activeResearchProjects.map(\.id)),
            configuration: effectiveModuleConfiguration(for: candidate.projectID ?? currentProjectID)
        )
        applyRestoredRoute(result.route)
        if let fallbackReason = result.fallbackReason {
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(fallbackReason.rawValue)
            ]))
        }
    }

    private func applyRestoredRoute(_ route: WorkspaceRoute) {
        selectedSection = workspaceSection(for: route.top)
        isViewingGlobalTodos = route.secondarySelection == "global_todos"
        selectedProjectSpaceProjectID = nil

        switch route.top {
        case .home, .settings:
            break
        case .projects:
            if let projectID = route.projectID, activeResearchProjects.contains(where: { $0.id == projectID }) {
                currentProjectID = projectID
                selectedProjectSpaceProjectID = projectID
                let availableTabIDs = Set(projectSpaceTabs(for: projectID).map(\.id))
                let restoredTabID = route.projectTabID ?? ProjectSpaceTabsBuilder.overviewTabID
                let migratedTabID = ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(restoredTabID) ? ProjectSpaceTabsBuilder.mergedReadingTabID : restoredTabID
                selectedProjectSpaceTabID = availableTabIDs.contains(migratedTabID) ? migratedTabID : ProjectSpaceTabsBuilder.overviewTabID
                if selectedProjectSpaceTabID == "papers" {
                    selectedLibraryProjectID = projectID
                    selectedCollectionPath = nil
                    selectedTagName = nil
                }
            }
        case .library:
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        case .calendar:
            break
        case .aiLab:
            break
        }
    }

    private func legacyRouteFromRecentSection() -> WorkspaceRoute {
        guard let rawValue = workspacePreferences.recentSection,
              let section = WorkspaceSection(rawValue: rawValue) else {
            return .home
        }
        if section.inProjectSpaceOnly, let currentProjectID {
            return WorkspaceRoute(top: .projects, projectID: currentProjectID, projectTabID: projectSpaceTabID(for: section))
        }
        return WorkspaceRoute(top: topRoute(for: section))
    }

    private func persistWorkspaceRoute(_ route: WorkspaceRoute) {
        if workspacePreferences.lastRoute == route,
           workspacePreferences.recentSection == recentSectionValue(for: route) {
            return
        }
        updateWorkspacePreferences { preferences in
            preferences.lastRoute = route
            preferences.recentSection = recentSectionValue(for: route)
        }
        recordShellDebugEvent("route.persist", payload: .object([
            "top": .string(route.top.rawValue),
            "project_id_present": .bool(route.projectID != nil),
            "tab_id": .string(route.projectTabID ?? "")
        ]))
    }

    private func recentSectionValue(for route: WorkspaceRoute) -> String {
        switch route.top {
        case .home:
            return WorkspaceSection.dashboard.rawValue
        case .projects:
            return WorkspaceSection.projects.rawValue
        case .library:
            return WorkspaceSection.library.rawValue
        case .calendar:
            return WorkspaceSection.calendar.rawValue
        case .aiLab:
            return WorkspaceSection.llmLab.rawValue
        case .settings:
            return WorkspaceSection.settings.rawValue
        }
    }

    private func topRoute(for section: WorkspaceSection) -> WorkspaceRoute.Top {
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

    private func workspaceSection(for top: WorkspaceRoute.Top) -> WorkspaceSection {
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

    private func projectSpaceTabID(for section: WorkspaceSection) -> String {
        section.moduleProjectTabID ?? ProjectSpaceTabsBuilder.overviewTabID
    }

    private func ensurePaperImportContextForGlobalMenu() {
        guard !ToolbarPolicy.showsPaperImportActions(route: currentWorkspaceRoute, context: currentWorkspaceContextSnapshot) else {
            return
        }
        selectLibraryScope()
        showShellStatus(localized("已切换到 Library，可继续导入论文。", "Switched to Library for paper import."))
    }

    private func currentWorkspaceContextDebugPayload(reason: String) -> JSONValue {
        let snapshot = currentWorkspaceContextSnapshot
        return .object([
            "reason": .string(reason),
            "top": .string(snapshot.topLevelSectionID),
            "project_id_present": .bool(snapshot.projectID != nil),
            "project_tab_id": .string(snapshot.projectTabID ?? ""),
            "selected_paper_id_present": .bool(snapshot.selectedPaperID != nil),
            "selected_paper_title": .string(snapshot.selectedPaperTitle ?? ""),
            "selected_paper_markdown_path": .string(snapshot.selectedPaperMarkdownPath ?? ""),
            "selected_markdown_path": .string(snapshot.selectedMarkdownPath ?? ""),
            "selected_todo_id_present": .bool(snapshot.selectedTodoID != nil),
            "pdf_page_index": .string(snapshot.pdfPageIndex.map(String.init) ?? ""),
            "selected_text_preview_present": .bool(snapshot.selectedTextPreview != nil)
        ])
    }

    private func calendarDayRange(for date: Date) -> DateInterval? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func showShellStatus(_ message: String) {
        shellStatusMessage = message
        shellStatusDismissTask?.cancel()
        shellStatusDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self?.shellStatusMessage == message {
                    self?.shellStatusMessage = nil
                }
            }
        }
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

    private func loadSelectedPDFAnnotations(in workspace: ResearchWorkspace) async throws {
        guard let selectedPaperDraft else {
            selectedPDFAnnotations = []
            return
        }

        selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.loadAnnotations(for: selectedPaperDraft, in: workspace))
    }

    private func deduplicatedPDFAnnotations(_ annotations: [PDFAnnotationRecord]) -> [PDFAnnotationRecord] {
        var seenFingerprints = Set<String>()
        return annotations.filter { annotation in
            guard annotation.kind != .note else {
                return true
            }
            return seenFingerprints.insert(annotation.duplicateFingerprint).inserted
        }
    }

    private func applyWorkspaceRoute(_ route: WorkspaceRoute) {
        applyRestoredRoute(route)
        persistWorkspaceRoute(route)
        applyRightRailRouteSuggestion()
        refreshAgentContext()
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
        todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: workspace)
    }

    /// All task tag definitions, augmented with any inferred tags found on
    /// existing todos that lack an explicit definition (so colors stay stable).
    var availableTodoTagDefinitions: [TagDefinition] {
        let existingNames = Set(todoTagDefinitions.map(\.name))
        let inferred = Set(todos.flatMap(\.tags))
            .subtracting(existingNames)
            .map { Self.inferredTagDefinition(named: $0) }
        return (todoTagDefinitions + inferred)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func todoTagDefinition(named name: String) -> TagDefinition? {
        availableTodoTagDefinitions.first(where: { $0.name == name })
    }

    func upsertTodoTag(_ definition: TagDefinition) {
        guard let currentWorkspace else {
            return
        }
        Task {
            do {
                try await todoTagRepository.upsert(definition, in: currentWorkspace)
                todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTodoTag(named name: String) {
        guard let currentWorkspace else {
            return
        }
        Task {
            do {
                try await todoTagRepository.deleteTag(named: name, in: currentWorkspace)
                todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
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
        guard preferences != workspacePreferences else {
            return
        }
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

    private func recordAppDebugEvent(
        _ event: String,
        payload: JSONValue = .object([:]),
        runID: String? = nil,
        threadID: String? = nil,
        force: Bool = false
    ) {
        let bridgeForced: Bool
        #if DEBUG
        bridgeForced = uiTestBridgeForceDebugLogging
        #else
        bridgeForced = false
        #endif
        guard force || bridgeForced || workspacePreferences.agentDebugLoggingEnabled else {
            return
        }
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        let debugEvent = AppDebugEvent(
            event: event,
            workspaceID: currentAgentWorkspaceID,
            projectID: agentConversationProjectID,
            threadID: threadID ?? activeAgentThreadID,
            runID: runID ?? agentCurrentRun?.id,
            payload: payload
        )

        Task {
            try? await appDebugEventLogger.append(debugEvent, in: root)
        }
    }

    private func recordAgentRunDebugOutput(_ run: AgentRun, event: String) {
        var payload: [String: JSONValue] = [
            "run_id": .string(run.id),
            "goal": .string(run.goal),
            "mode": .string(run.mode.rawValue),
            "summary": .string(run.plan.summary),
            "tool_results": .array(run.toolResults.map { result in
                var fields: [String: JSONValue] = [
                    "call_id": .string(result.callID),
                    "tool_name": .string(result.toolName),
                    "succeeded": .bool(result.succeeded),
                    "requires_confirmation": .bool(result.requiresConfirmation),
                    "message": .string(result.message),
                    "modified_paths": jsonStringArray(result.modifiedPaths)
                ]
                if let errorMessage = result.errorMessage {
                    fields["error_message"] = .string(errorMessage)
                }
                if let payload = result.payload {
                    fields["payload"] = payload
                }
                return .object(fields)
            })
        ]
        if let finalResponseDraft = run.plan.finalResponseDraft {
            payload["final_response"] = .string(finalResponseDraft)
        }
        if let runtimeSelector = run.runtimeSelector {
            payload["runtime_selector"] = .string(runtimeSelector)
        }
        if let enabledToolNames = run.enabledToolNames {
            payload["enabled_tool_names"] = jsonStringArray(enabledToolNames)
        }
        recordAppDebugEvent(event, payload: .object(payload), runID: run.id)
    }

    private func jsonStringArray(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
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
        let persistedAPIKey = try await apiKeyStore.loadAPIKey(for: workspace.rootURL.path)
        return LLMAPIKeyResolver.resolve(inMemory: llmAPIKey, persisted: persistedAPIKey)
    }

    private func minerUAPITokenAccount(for workspace: ResearchWorkspace) -> String {
        "\(workspace.rootURL.path)#mineru-api"
    }

    func loadRecommendationHistory(limit: Int = 20) {
        guard let workspace = currentWorkspace else {
            return
        }

        Task {
            do {
                recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: limit)
            } catch {
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("history_load"),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        }
    }

    func selectRecommendationHistory(_ result: RecommendationRunResult) {
        recommendationRunResult = result
        recommendationCandidateCount = result.candidateCount
        recommendationErrorMessage = nil
        recommendationAIEvaluationStatusMessage = nil
        Task {
            await refreshRecommendationFeedbackState(for: result)
        }
    }

    func refreshArxivRecommendations(project: ResearchProject?, query: String, categories: [String], topK: Int, includeCrossList: Bool = true, aiModel: String = "deepseek-v4-flash", referencePaperIDs: Set<Paper.ID> = []) {
        guard let workspace = currentWorkspace else {
            return
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategories = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let categoriesForRequest = resolvedCategories.isEmpty ? defaultArxivRecommendationCategories(in: workspace) : resolvedCategories
        let requestedTopK = min(max(topK, 1), 100)
        let selectedAIModel = aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "deepseek-v4-flash" : aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let referencePapers = recommendationReferencePapers(ids: referencePaperIDs)
        let referenceIDs = referencePapers.map(\.id)
        let referenceIDSet = Set(referenceIDs)
        let weightedKeywords = WeightedKeyword.parse(trimmedQuery)
        let request = PaperRecommendationRequest(
            arxivCategories: categoriesForRequest,
            includeCrossList: includeCrossList,
            keywords: weightedKeywords,
            seedPaperIDs: referenceIDs,
            projectID: project?.id,
            limit: requestedTopK,
            aiModel: selectedAIModel
        )
        isRefreshingRecommendations = true
        recommendationErrorMessage = nil
        recommendationAIEvaluationStatusMessage = nil

        Task {
            defer {
                isRefreshingRecommendations = false
            }
            do {
                var config = arxivOnlyRecommendationConfig(in: workspace, topK: requestedTopK)
                let search = try await fetchArxivRecommendationCandidates(
                    query: trimmedQuery,
                    categories: categoriesForRequest,
                    topK: requestedTopK,
                    config: config,
                    workspace: workspace,
                    project: project,
                    referencePapers: referencePapers,
                    includeCrossList: request.includeCrossList,
                    aiModel: selectedAIModel
                )
                config.maxDailyCandidates = min(max(config.maxDailyCandidates, requestedTopK * 5), 100)
                let existingHistory = (try? await recommendationPipeline.loadHistory(workspace: workspace, limit: 200)) ?? recommendationHistory
                let feedbackRecords = (try? await recommendationFeedbackStore.load(in: workspace)) ?? []
                let feedbackProfile = RecommendationFeedbackStore.profile(
                    records: feedbackRecords,
                    scores: existingHistory.flatMap(\.scores),
                    projectID: project?.id
                )
                let context = RecommendationContext(
                    projectID: project?.id,
                    corePaperIDs: referenceIDSet,
                    openGapKeywords: recommendationKeywords(query: trimmedQuery, project: project, categories: categoriesForRequest),
                    weightedKeywords: weightedKeywords,
                    interestPapers: referencePapers,
                    seedPapers: referencePapers,
                    projectContextTexts: recommendationProjectContextTexts(project: project),
                    feedbackProfile: feedbackProfile,
                    evaluatedAt: Date()
                )
                let result = try await recommendationPipeline.run(
                    workspace: workspace,
                    papers: [],
                    dailyFeedCandidates: search.candidates,
                    graph: nil,
                    context: context,
                    config: config,
                    trigger: .manual,
                    locale: appLanguage == .english ? .en : .zh,
                    force: true,
                    query: trimmedQuery,
                    categories: categoriesForRequest,
                    referencePaperIDs: referenceIDs,
                    keywords: weightedKeywords,
                    includeCrossList: request.includeCrossList,
                    aiModel: selectedAIModel,
                    sourceDate: search.sourceDate,
                    sourceNote: search.sourceNote
                )
                recommendationCandidateCount = search.candidates.count
                if var result {
                    recommendationRunResult = result
                    await refreshRecommendationFeedbackState(for: result)
                    if result.scores.isEmpty {
                        recommendationAIEvaluationStatusMessage = localized(
                            "本次 AI/arXiv 搜索没有可显示推荐。候选 \(result.candidateCount) 篇，来源：\(search.sourceNote)。",
                            "No displayable recommendations for this AI/arXiv search. \(result.candidateCount) candidates, source: \(search.sourceNote)."
                        )
                        showShellStatus(localized("AI/arXiv 本次没有返回可显示推荐。", "AI/arXiv returned no displayable recommendations."))
                    } else {
                        showShellStatus(localized("已获取 \(result.scores.count) 条 AI 辅助推荐。", "Fetched \(result.scores.count) AI-assisted recommendations."))
                    }
                    recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                    if !result.scores.isEmpty {
                        isEvaluatingRecommendationsWithAI = true
                        do {
                            result.aiEvaluation = try await evaluateRecommendationsWithAI(result, model: selectedAIModel, workspace: workspace)
                            try await recommendationPipeline.persistSnapshot(result, workspace: workspace)
                            recommendationRunResult = result
                            await refreshRecommendationFeedbackState(for: result)
                            recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                            recommendationAIEvaluationStatusMessage = localized("AI 已完成推荐评价。", "AI evaluation completed.")
                        } catch {
                            recommendationAIEvaluationStatusMessage = localized("AI 评价暂不可用：\(error.localizedDescription)", "AI evaluation unavailable: \(error.localizedDescription)")
                        }
                        isEvaluatingRecommendationsWithAI = false
                    }
                } else {
                    showShellStatus(localized("arXiv 推荐没有变化。", "arXiv recommendations are unchanged."))
                }
                recordAppDebugEvent("recommendation.arxiv_refresh", payload: .object([
                    "candidate_count": .number(String(search.candidates.count)),
                    "top_k": .number(String(result?.scores.count ?? 0)),
                    "reference_paper_count": .number(String(referenceIDs.count)),
                    "include_cross_list": .bool(request.includeCrossList),
                    "source_note": .string(search.sourceNote),
                    "scope": .string(project.map { "project:\($0.id)" } ?? "workspace")
                ]))
            } catch {
                isEvaluatingRecommendationsWithAI = false
                recommendationErrorMessage = error.localizedDescription
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("arxiv_refresh"),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToLibrary(_ score: RecommendationScore, scope: RecommendationTarget) {
        guard let workspace = currentWorkspace else {
            recommendationErrorMessage = RecommendationReadingTodoError.missingWorkspace.localizedDescription
            return
        }
        guard !recommendationLibraryImportScoreIDs.contains(score.id) else {
            return
        }
        recommendationLibraryImportScoreIDs.insert(score.id)

        Task {
            defer { recommendationLibraryImportScoreIDs.remove(score.id) }
            do {
                let paper = try await importRecommendationCandidateToLibrary(score.candidate, scope: scope, in: workspace)
                try await loadWorkspaceData(in: workspace, selectingPaper: paper.id, selectingMarkdown: selectedMarkdownID)
                recordRecommendationFeedback(.save, for: score, scope: scope)
                showShellStatus(localized("已加入论文库，并自动添加 arXiv 推荐标签。", "Added to Library with the arXiv recommendation tag."))
            } catch {
                recommendationErrorMessage = localized("无法加入论文库：\(error.localizedDescription)", "Could not add to Library: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.push.error", payload: .object([
                    "phase": .string("library_import"),
                    "score_id": .string(score.id),
                    "scope": .string(scope.identifier),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToReadingTodo(_ score: RecommendationScore, scope: RecommendationTarget) {
        guard let workspace = currentWorkspace else {
            recommendationErrorMessage = RecommendationReadingTodoError.missingWorkspace.localizedDescription
            return
        }
        guard !recommendationReadingTodoImportScoreIDs.contains(score.id) else {
            return
        }
        recommendationReadingTodoImportScoreIDs.insert(score.id)

        Task {
            defer { recommendationReadingTodoImportScoreIDs.remove(score.id) }
            do {
                let paper = try await importRecommendationCandidateToLibrary(score.candidate, scope: scope, in: workspace)
                try await upsertReadingTodo(for: paper, score: score, scope: scope, in: workspace)
                try await loadWorkspaceData(in: workspace, selectingPaper: paper.id, selectingMarkdown: selectedMarkdownID)
                recordRecommendationFeedback(.save, for: score, scope: scope)
                showShellStatus(localized("已创建阅读 Todo，可在任务页继续安排阅读。", "Created a reading todo; continue from Tasks."))
            } catch {
                recommendationErrorMessage = localized("无法创建阅读 Todo：\(error.localizedDescription)", "Could not create reading todo: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.push.error", payload: .object([
                    "phase": .string("reading_todo_import"),
                    "score_id": .string(score.id),
                    "scope": .string(scope.identifier),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToReadingList(_ score: RecommendationScore, scope: RecommendationTarget) {
        addRecommendationToReadingTodo(score, scope: scope)
    }

    func recommendationFeedbackType(for score: RecommendationScore) -> RecommendationFeedbackType? {
        recommendationFeedbackByScoreID[score.id]
    }

    func isAddingRecommendationToLibrary(_ score: RecommendationScore) -> Bool {
        recommendationLibraryImportScoreIDs.contains(score.id)
    }

    func isAddingRecommendationToReadingTodo(_ score: RecommendationScore) -> Bool {
        recommendationReadingTodoImportScoreIDs.contains(score.id)
    }

    func recordRecommendationFeedback(_ type: RecommendationFeedbackType, for score: RecommendationScore, scope: RecommendationTarget? = nil) {
        guard let workspace = currentWorkspace else {
            return
        }
        let runID = recommendationRunResult?.id ?? score.id
        let projectID = scope?.projectIDForRecommendationFeedback ?? recommendationRunResult?.contextProjectID ?? currentProjectID
        Task {
            do {
                try await recommendationFeedbackStore.record(
                    candidate: score.candidate,
                    type: type,
                    projectID: projectID,
                    recommendationRunID: runID,
                    in: workspace
                )
                recommendationFeedbackByScoreID[score.id] = type
                recordAppDebugEvent("recommendation.feedback", payload: .object([
                    "score_id": .string(score.id),
                    "feedback_type": .string(type.rawValue),
                    "run_id": .string(runID),
                    "project_id_present": .bool(projectID != nil)
                ]))
            } catch {
                recommendationErrorMessage = localized("保存推荐反馈失败：\(error.localizedDescription)", "Failed to save recommendation feedback: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("feedback_save"),
                    "score_id": .string(score.id),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        }
    }

    func openRecommendationReadingTodo() {
        selectProjectSpaceTab("tasks")
    }

    func archiveRecommendationHistory(_ result: RecommendationRunResult) {
        guard let workspace = currentWorkspace else {
            return
        }
        Task {
            do {
                try await recommendationPipeline.archiveSnapshot(id: result.id, workspace: workspace)
                recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                if recommendationRunResult?.id == result.id {
                    recommendationRunResult = recommendationHistory.first
                }
                showShellStatus(localized("历史推荐已归档。", "Recommendation history archived."))
                recordAppDebugEvent("recommendation.archive", payload: .object([
                    "snapshot_id": .string(result.id)
                ]))
            } catch {
                recommendationErrorMessage = localized("归档历史推荐失败：\(error.localizedDescription)", "Failed to archive recommendation history: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("archive"),
                    "snapshot_id": .string(result.id),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func isRecommendationInReadingList(_ score: RecommendationScore, scope: RecommendationTarget) -> Bool {
        let keys = recommendationCandidateKeys(score.candidate)
        return todos.contains { todo in
            guard todo.kind == .reading, todoMatchesScope(todo, scope: scope) else {
                return false
            }
            let paperKeys = todo.relatedPaperIDs.flatMap { paperID -> [String] in
                [paperID, "paper:\(paperID)"]
            }
            let externalKeys = [todo.externalIdentifier, Optional(todo.id)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return !keys.isDisjoint(with: Set(paperKeys.map { $0.lowercased() } + externalKeys))
        }
    }

    func isRecommendationInLibrary(_ score: RecommendationScore) -> Bool {
        existingPaper(matchingRecommendationCandidate: score.candidate) != nil
    }

    private func importRecommendationCandidateToLibrary(_ candidate: RecommendationCandidate, scope: RecommendationTarget, in workspace: ResearchWorkspace) async throws -> Paper {
        if var existing = existingPaper(matchingRecommendationCandidate: candidate) {
            existing = applyRecommendationLibraryMetadata(to: existing, candidate: candidate, scope: scope)
            return try await paperRepository.save(existing, in: workspace)
        }

        guard let importIdentifier = recommendationImportIdentifier(for: candidate) else {
            throw RecommendationReadingTodoError.missingImportIdentifier
        }

        let collectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        var importedPaper = try await remoteImportService.importItem(
            from: importIdentifier,
            draftPreview: recommendationMetadataDraft(for: candidate),
            into: workspace,
            existingPapers: papers,
            collectionPath: collectionPath,
            tags: [Self.arxivRecommendationTag]
        )
        importedPaper = applyRecommendationLibraryMetadata(to: importedPaper, candidate: candidate, scope: scope)
        return try await paperRepository.save(importedPaper, in: workspace)
    }

    private func applyRecommendationLibraryMetadata(to paper: Paper, candidate: RecommendationCandidate, scope: RecommendationTarget) -> Paper {
        var updatedPaper = paper
        updatedPaper.tags = uniqueOrdered(updatedPaper.tags + [Self.arxivRecommendationTag])
        if let projectID = scope.projectID, !updatedPaper.projectIDs.contains(projectID) {
            updatedPaper.projectIDs.append(projectID)
        }
        if updatedPaper.abstract == nil {
            updatedPaper.abstract = candidate.abstractText
        }
        if updatedPaper.pdfURL == nil {
            updatedPaper.pdfURL = candidate.pdfURL
        }
        if updatedPaper.url == nil {
            updatedPaper.url = candidate.sourceURL
        }
        if updatedPaper.categories.isEmpty {
            updatedPaper.categories = candidate.categories
        }
        return updatedPaper
    }

    private func recommendationMetadataDraft(for candidate: RecommendationCandidate) -> PaperMetadataDraft? {
        let arxivID = PaperIdentityGenerator.normalizedArxiv(candidate.externalKey) ?? PaperIdentityGenerator.normalizedArxiv(candidate.canonicalID)
        let sourceURL = candidate.sourceURL ?? arxivID.map { "https://arxiv.org/abs/\($0)" }
        let pdfURL = candidate.pdfURL ?? arxivID.map { "https://arxiv.org/pdf/\($0).pdf" }
        return PaperMetadataDraft(
            title: candidate.displayTitle,
            authors: candidate.authors,
            year: candidate.publishedYear,
            venue: candidate.sourceName ?? "arXiv",
            doi: nil,
            arxiv: arxivID,
            inspireID: nil,
            url: sourceURL,
            pdfURL: pdfURL,
            abstract: candidate.abstractText,
            categories: candidate.categories,
            sourceProvider: "recommendation-arxiv"
        )
    }

    private func recommendationImportIdentifier(for candidate: RecommendationCandidate) -> String? {
        [candidate.externalKey, candidate.sourceURL, candidate.pdfURL, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first
    }

    private func existingPaper(matchingRecommendationCandidate candidate: RecommendationCandidate) -> Paper? {
        if let paperID = candidate.paperID, let paper = papers.first(where: { $0.id == paperID }) {
            return paper
        }
        let arxivID = PaperIdentityGenerator.normalizedArxiv(candidate.externalKey) ?? PaperIdentityGenerator.normalizedArxiv(candidate.canonicalID)
        if let arxivID, let paper = papers.first(where: { PaperIdentityGenerator.normalizedArxiv($0.arxiv) == arxivID || $0.resolvedGraphNodeID == "arxiv:\(arxivID)" }) {
            return paper
        }
        return nil
    }

    private func upsertReadingTodo(for paper: Paper, score: RecommendationScore, scope: RecommendationTarget, in workspace: ResearchWorkspace) async throws {
        let now = Date()
        let projectIDs = scope.projectID.map { [$0] } ?? []
        let loadedTodos = try await todoRepository.loadTodos(in: workspace)
        var todo = loadedTodos.first { existing in
            existing.id == readingTodoID(for: paper.id, scope: scope)
                || (existing.kind == .reading && existing.relatedPaperIDs.contains(paper.id) && todoMatchesScope(existing, scope: scope))
        } ?? TodoItem(
            id: readingTodoID(for: paper.id, scope: scope),
            title: localized("阅读：\(paper.displayTitle)", "Read: \(paper.displayTitle)"),
            kind: .reading,
            status: .open,
            dueDate: nil,
            priority: .medium,
            projectIDs: projectIDs,
            tags: [Self.arxivRecommendationTag],
            relatedPaperIDs: [paper.id],
            notes: score.reason,
            externalSource: "sci_station_recommendation",
            externalIdentifier: score.candidate.externalKey ?? score.candidate.canonicalID,
            createdAt: now,
            updatedAt: now
        )

        todo.kind = .reading
        todo.projectIDs = uniqueOrdered(todo.projectIDs + projectIDs)
        todo.tags = uniqueOrdered(todo.tags + [Self.arxivRecommendationTag])
        todo.relatedPaperIDs = uniqueOrdered(todo.relatedPaperIDs + [paper.id])
        todo.notes = todo.notes ?? score.reason
        todo.externalSource = todo.externalSource ?? "sci_station_recommendation"
        todo.externalIdentifier = todo.externalIdentifier ?? score.candidate.externalKey ?? score.candidate.canonicalID
        todo.updatedAt = now
        try await todoRepository.upsert(todo, in: workspace)
    }

    private func readingTodoID(for paperID: Paper.ID, scope: RecommendationTarget) -> String {
        "todo-reading-\(sanitizedTodoIDComponent(scope.identifier))-\(sanitizedTodoIDComponent(paperID))"
    }

    private func sanitizedTodoIDComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { $0.append($1) }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func todoMatchesScope(_ todo: TodoItem, scope: RecommendationTarget) -> Bool {
        switch scope {
        case .workspace:
            return todo.projectIDs.isEmpty
        case .project(let projectID):
            return todo.projectIDs.contains(projectID)
        }
    }

    private func arxivOnlyRecommendationConfig(in workspace: ResearchWorkspace, topK: Int) -> RecommendationConfig {
        var config = (try? RecommendationConfigStore().load(in: workspace)) ?? RecommendationConfig()
        config.topK = min(max(topK, 1), 100)
        config.externalNetworkEnabled = true
        config.weights = RecommendationWeights(
            citedByCore: 0,
            libraryInterestSimilarity: 0.10,
            keywordRelevance: 0.20,
            seedSimilarity: 0.25,
            projectContextSimilarity: 0.15,
            recency: 0.15,
            novelty: 0.10,
            quality: 0.05,
            aiScore: 0.10,
            feedback: 0.05,
            openGapCoverage: 0.10,
            authorOverlapWithCore: 0.10,
            duplicatePenalty: 0.90
        )
        return config
    }

    private func fetchArxivRecommendationCandidates(
        query: String,
        categories: [String],
        topK: Int,
        config: RecommendationConfig,
        workspace: ResearchWorkspace,
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        aiModel: String
    ) async throws -> (candidates: [RecommendationCandidate], sourceDate: Date, sourceNote: String) {
        let maxResults = min(max(config.maxDailyCandidates, topK * 5), 100)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var strategies: [RecommendationAISearchStrategy] = []
        var statusNotes: [String] = []
        let apiKey: String
        do {
            apiKey = try await resolvedLLMAPIKey(for: workspace)
        } catch {
            apiKey = ""
            statusNotes.append(localized("AI API Key 暂不可用：\(error.localizedDescription)", "AI API key unavailable: \(error.localizedDescription)"))
            recordAppDebugEvent("recommendation.ai_search.error", payload: .object([
                "phase": .string("api_key"),
                "reason": .string(error.localizedDescription)
            ]))
        }
        if !apiKey.isEmpty {
            recommendationAIEvaluationStatusMessage = localized(
                "正在把项目、关键词和 \(referencePapers.count) 篇参考论文提交给 AI 生成 arXiv 搜索策略…",
                "Submitting the project, keywords, and \(referencePapers.count) reference papers to AI for arXiv search planning…"
            )
            do {
                let aiStrategies = try await recommendationAISearchStrategies(
                    query: trimmedQuery,
                    categories: categories,
                    project: project,
                    referencePapers: referencePapers,
                    includeCrossList: includeCrossList,
                    topK: topK,
                    model: aiModel,
                    apiKey: apiKey
                )
                strategies.append(contentsOf: aiStrategies)
                if !aiStrategies.isEmpty {
                    statusNotes.append(localized("AI 已生成 \(aiStrategies.count) 个搜索策略", "AI generated \(aiStrategies.count) search strategies"))
                }
            } catch {
                statusNotes.append(localized("AI 搜索策略不可用：\(error.localizedDescription)", "AI search planning unavailable: \(error.localizedDescription)"))
                recordAppDebugEvent("recommendation.ai_search.error", payload: .object([
                    "phase": .string("strategy"),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        } else {
            statusNotes.append(localized("未配置 AI API Key，已回退到直接 arXiv 搜索", "No AI API key configured; falling back to direct arXiv search"))
        }

        if !trimmedQuery.isEmpty {
            strategies.append(RecommendationAISearchStrategy(query: trimmedQuery, categories: categories, source: "manual"))
        }
        strategies.append(RecommendationAISearchStrategy(query: "", categories: categories, source: "category"))

        var candidatesByKey: [String: RecommendationCandidate] = [:]
        var usedStrategies: [RecommendationAISearchStrategy] = []
        for strategy in uniqueRecommendationSearchStrategies(strategies) {
            let request = ArxivRecommendationRequest(
                query: strategy.query,
                categories: strategy.categories.isEmpty ? categories : strategy.categories,
                maxResults: maxResults
            )
            let candidates: [RecommendationCandidate]
            do {
                let client = arxivRecommendationClient
                candidates = try await recommendationWithTimeout(seconds: 20) {
                    try await client.fetch(request)
                }
            } catch {
                statusNotes.append(localized("一个 arXiv 搜索已跳过：\(error.localizedDescription)", "Skipped one arXiv search: \(error.localizedDescription)"))
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("arxiv_fetch"),
                    "reason": .string(error.localizedDescription)
                ]))
                continue
            }
            if !candidates.isEmpty {
                usedStrategies.append(strategy)
            }
            for candidate in candidates {
                let key = candidate.externalKey ?? candidate.paperID ?? candidate.canonicalID
                if candidatesByKey[key] == nil {
                    candidatesByKey[key] = candidate
                }
            }
            if candidatesByKey.count >= maxResults {
                break
            }
        }

        let candidates = RecommendationPipeline.filterCategoryBoundary(
            Array(candidatesByKey.values),
            selectedCategories: categories,
            includeCrossList: includeCrossList
        )
            .sorted { lhs, rhs in
                if lhs.publishedAt == rhs.publishedAt {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }
                return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
            .prefix(maxResults)
            .map { $0 }
        let strategySummary = usedStrategies
            .prefix(3)
            .map { strategy in
                strategy.query.isEmpty ? strategy.categories.prefix(4).joined(separator: " · ") : strategy.query
            }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        if candidates.isEmpty {
            return (
                [],
                Date(),
                (statusNotes + [localized("arXiv 没有返回候选论文。请减少关键词或更换领域。", "arXiv returned no candidate papers. Try fewer keywords or different fields.")]).joined(separator: "；")
            )
        }
        return (
            candidates,
            Date(),
            (statusNotes + [localized("arXiv 返回 \(candidates.count) 篇候选", "arXiv returned \(candidates.count) candidates"), strategySummary]).filter { !$0.isEmpty }.joined(separator: "；")
        )
    }

    private func recommendationAISearchStrategies(
        query: String,
        categories: [String],
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        topK: Int,
        model: String,
        apiKey: String
    ) async throws -> [RecommendationAISearchStrategy] {
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedAPIKey.isEmpty else {
            throw RecommendationAIEvaluationError.missingAPIKey
        }
        var configuration = llmConfiguration
        configuration.model = model
        configuration.temperature = 0.15
        configuration.maxTokens = 1600
        let requestConfiguration = configuration
        let prompt = recommendationAISearchPrompt(
            query: query,
            categories: categories,
            project: project,
            referencePapers: referencePapers,
            includeCrossList: includeCrossList,
            topK: topK
        )
        let provider = openAIProvider
        let response = try await recommendationWithTimeout(seconds: 20) {
            try await provider.complete(
                prompt: prompt,
                configuration: requestConfiguration,
                apiKey: resolvedAPIKey
            )
        }
        return parseRecommendationAISearchStrategies(response, fallbackCategories: categories)
    }

    private func recommendationAISearchPrompt(
        query: String,
        categories: [String],
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        topK: Int
    ) -> String {
        let projectText = project.map { project in
            """
            Name: \(project.name)
            Description: \(project.description)
            """
        } ?? "No active project."
        let references = referencePapers.prefix(8).map { paper in
            """
            ID: \(paper.id)
            Title: \(paper.displayTitle)
            Authors: \(paper.authors.prefix(8).joined(separator: ", "))
            Year: \(paper.year.map(String.init) ?? "")
            Categories: \(paper.categories.joined(separator: ", "))
            Abstract: \(limitedRecommendationText(paper.abstract, maxCharacters: 900))
            """
        }
        .joined(separator: "\n\n")
        let referenceText = references.isEmpty ? "No reference papers selected." : references
        return """
        You are an AI literature search planner for arXiv. The app will execute your searches against the arXiv API and then recommend papers to the user.

        Return strict JSON only:
        {"searches":[{"query":"2 to 6 English keywords, no boolean operators","categories":["arXiv category ids"],"reason":"short reason"}]}

        Requirements:
        - Generate 3 to 5 complementary arXiv searches for finding recommendation candidates.
        - Use the selected reference papers as the main relevance signal.
        - Keep queries broad enough to return papers. Do not use full titles as queries.
        - Treat the selected arXiv categories as a hard boundary. Only return categories from the selected list.
        - include_cross_list is \(includeCrossList ? "true" : "false"): if false, candidates must have one selected category as their primary arXiv category.
        - The user asked for \(topK) recommendations.

        User query:
        \(query.isEmpty ? "(empty)" : query)

        Selected arXiv categories:
        \(categories.joined(separator: ", "))

        Project:
        \(projectText)

        Reference papers submitted by the user:
        \(referenceText)
        """
    }

    private func parseRecommendationAISearchStrategies(_ response: String, fallbackCategories: [String]) -> [RecommendationAISearchStrategy] {
        let jsonText = recommendationEvaluationJSONText(from: response.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let rawSearches = object["searches"] as? [[String: Any]]
            ?? object["queries"] as? [[String: Any]]
            ?? []
        return rawSearches.compactMap { item in
            let query = ((item["query"] as? String) ?? (item["keywords"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCategories = recommendationStringList(from: item["categories"])
                .prefix(6)
                .map { $0 }
            let allowed = Set(fallbackCategories.map { $0.lowercased() })
            let categories = rawCategories.filter { allowed.contains($0.lowercased()) }
            let resolvedCategories = categories.isEmpty ? fallbackCategories : categories
            guard !query.isEmpty || !resolvedCategories.isEmpty else {
                return nil
            }
            return RecommendationAISearchStrategy(
                query: String(query.prefix(120)),
                categories: resolvedCategories,
                source: "ai"
            )
        }
        .prefix(5)
        .map { $0 }
    }

    private func uniqueRecommendationSearchStrategies(_ strategies: [RecommendationAISearchStrategy]) -> [RecommendationAISearchStrategy] {
        var seen: Set<String> = []
        var unique: [RecommendationAISearchStrategy] = []
        for strategy in strategies {
            let query = strategy.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let categories = strategy.categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !query.isEmpty || !categories.isEmpty else {
                continue
            }
            let key = ([query.lowercased()] + categories.map { $0.lowercased() }.sorted()).joined(separator: "|")
            if seen.insert(key).inserted {
                unique.append(RecommendationAISearchStrategy(query: query, categories: categories, source: strategy.source))
            }
        }
        return unique
    }

    private func recommendationStringList(from value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let string = value as? String {
            return string
                .components(separatedBy: CharacterSet(charactersIn: ",;|"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private func limitedRecommendationText(_ value: String?, maxCharacters: Int) -> String {
        guard let value else {
            return ""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxCharacters {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters))
    }

    private func startOfUTCRecommendationDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    private func utcRecommendationDay(offset: Int, from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date.addingTimeInterval(Double(offset) * 86_400)
    }

    private func defaultArxivRecommendationCategories(in workspace: ResearchWorkspace) -> [String] {
        let config = (try? RecommendationConfigStore().load(in: workspace)) ?? RecommendationConfig()
        let arxivCategories = config.dailySources.first { $0.kind == .arxiv }?.categories ?? []
        return arxivCategories.isEmpty ? ["cs.AI", "cs.CL", "cs.CV", "cs.LG"] : arxivCategories
    }

    private func recommendationKeywords(query: String, project: ResearchProject?, categories: [String]) -> [String] {
        let text = query.isEmpty ? (project?.name ?? "") : query
        let tokens = RecommendationTextSimilarity.tokens(text)
        return (tokens + categories.map { $0.lowercased() }).filter { !$0.isEmpty }
    }

    private func recommendationProjectContextTexts(project: ResearchProject?) -> [String] {
        var texts: [String] = []
        if let project {
            texts.append([project.name, project.description, project.defaultTags.joined(separator: " ")].joined(separator: " "))
            texts.append(contentsOf: papers(for: project.id).prefix(20).map(RecommendationScorer.paperText(_:)))
        } else {
            texts.append(contentsOf: papers.prefix(20).map(RecommendationScorer.paperText(_:)))
        }
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func refreshRecommendationFeedbackState(for result: RecommendationRunResult) async {
        guard let workspace = currentWorkspace else {
            recommendationFeedbackByScoreID = [:]
            return
        }
        do {
            let records = try await recommendationFeedbackStore.load(in: workspace)
            recommendationFeedbackByScoreID = recommendationFeedbackState(records: records, result: result)
        } catch {
            recommendationFeedbackByScoreID = [:]
            recordAppDebugEvent("recommendation.error", payload: .object([
                "phase": .string("feedback_load"),
                "run_id": .string(result.id),
                "reason": .string(error.localizedDescription)
            ]))
        }
    }

    private func recommendationFeedbackState(records: [RecommendationFeedbackRecord], result: RecommendationRunResult) -> [String: RecommendationFeedbackType] {
        var state: [String: RecommendationFeedbackType] = [:]
        let sortedRecords = records.sorted { $0.createdAt < $1.createdAt }
        for score in result.scores {
            let keys = RecommendationFeedbackStore.candidateKeys(score.candidate)
            if let record = sortedRecords.last(where: { keys.contains($0.paperKey) && ($0.projectID == nil || $0.projectID == result.contextProjectID) }) {
                state[score.id] = record.feedbackType
            }
        }
        return state
    }

    private func recommendationReferencePapers(ids: Set<Paper.ID>) -> [Paper] {
        papers.filter { ids.contains($0.id) }
    }

    private func recommendationCandidateKeys(_ candidate: RecommendationCandidate) -> Set<String> {
        Set([candidate.paperID, candidate.externalKey, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { key in [key, "external:\(key)", "paper:\(key)"] })
    }

    private func evaluateRecommendationsWithAI(_ result: RecommendationRunResult, model: String, workspace: ResearchWorkspace) async throws -> RecommendationAIEvaluation {
        let apiKey = try await resolvedLLMAPIKey(for: workspace)
        guard !apiKey.isEmpty else {
            throw RecommendationAIEvaluationError.missingAPIKey
        }
        var configuration = llmConfiguration
        configuration.model = model
        configuration.temperature = 0.2
        configuration.maxTokens = 3200
        let requestConfiguration = configuration
        let prompt = recommendationAIEvaluationPrompt(for: result)
        let provider = openAIProvider
        let response = try await recommendationWithTimeout(seconds: 45) {
            try await provider.complete(
                prompt: prompt,
                configuration: requestConfiguration,
                apiKey: apiKey
            )
        }
        return parseRecommendationAIEvaluationResponse(response, model: model, result: result)
    }

    private func recommendationAIEvaluationPrompt(for result: RecommendationRunResult) -> String {
        let language = appLanguage == .english ? "English" : "Chinese"
        let referencePapers = result.referencePaperIDs.compactMap { referenceID in
            self.papers.first(where: { $0.id == referenceID })
        }
        let references = referencePapers.prefix(8).map { paper in
            """
            ID: \(paper.id)
            Title: \(paper.displayTitle)
            Authors: \(paper.authors.prefix(8).joined(separator: ", "))
            Year: \(paper.year.map(String.init) ?? "")
            Categories: \(paper.categories.joined(separator: ", "))
            Abstract: \(limitedRecommendationText(paper.abstract, maxCharacters: 900))
            """
        }
        .joined(separator: "\n\n")
        let candidatePapers = result.scores.map { score in
            """
            ID: \(score.id)
            External key: \(score.candidate.externalKey ?? "")
            Canonical key: \(score.candidate.canonicalID)
            Title: \(score.candidate.displayTitle)
            Abstract: \(score.candidate.abstractText ?? "")
            """
        }
        .joined(separator: "\n\n")
        return """
        You are evaluating individual paper recommendations for a research workflow. Use the user query, selected reference papers, and each candidate paper title and abstract.
        Do not write an overall evaluation. Return strict JSON only with this shape:
        {"reviews":[{"id":"copy the exact candidate ID","relevance":0.0,"novelty":0.0,"method_soundness":0.0,"usefulness":0.0,"risk":0.0,"summary":"one sentence in \(language)","recommendation_comment":"one decision-oriented comment in \(language)","suitable_for":["short use case"],"possible_weaknesses":["short weakness"]}]}

        Requirements:
        - Return one review for each candidate paper.
        - The id field must exactly copy the candidate ID line, not the arXiv URL and not a rewritten title.
        - Keep every text field concise.

        User query:
        \(result.query.isEmpty ? "(empty)" : result.query)

        Categories:
        \(result.categories.joined(separator: ", "))

        Reference papers submitted by the user:
        \(references.isEmpty ? "No reference papers selected." : references)

        Candidate papers:
        \(candidatePapers)
        """
    }

    private func parseRecommendationAIEvaluationResponse(_ response: String, model: String, result: RecommendationRunResult) -> RecommendationAIEvaluation {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = recommendationEvaluationJSONText(from: trimmed)
        let idAliasMap = recommendationScoreIDAliasMap(result)
        var overall = ""
        var commentsByID: [String: String] = [:]
        var reviewsByID: [String: RecommendationAIReview] = [:]
        if let data = jsonText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            overall = (object["overall"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
            if let comments = object["comments"] as? [[String: Any]] {
                for comment in comments {
                    guard let rawID = (comment["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let text = (comment["comment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let id = idAliasMap[recommendationNormalizedAIIdentifier(rawID)],
                          !text.isEmpty else {
                        continue
                    }
                    commentsByID[id] = text
                }
            }
            if let reviews = object["reviews"] as? [[String: Any]] {
                for review in reviews {
                    guard let rawID = (review["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let id = idAliasMap[recommendationNormalizedAIIdentifier(rawID)] else {
                        continue
                    }
                    let parsed = RecommendationAIReview(
                        relevance: recommendationDouble(from: review["relevance"]),
                        novelty: recommendationDouble(from: review["novelty"]),
                        methodSoundness: recommendationDouble(from: review["method_soundness"] ?? review["methodSoundness"]),
                        usefulness: recommendationDouble(from: review["usefulness"]),
                        risk: recommendationDouble(from: review["risk"]),
                        summary: ((review["summary"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        recommendationComment: ((review["recommendation_comment"] as? String) ?? (review["comment"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        suitableFor: recommendationStringList(from: review["suitable_for"]),
                        possibleWeaknesses: recommendationStringList(from: review["possible_weaknesses"])
                    )
                    reviewsByID[id] = parsed
                    if commentsByID[id] == nil {
                        commentsByID[id] = parsed.recommendationComment.nilIfEmpty ?? parsed.summary
                    }
                }
            }
        } else {
            overall = trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? "" : trimmed
        }
        return RecommendationAIEvaluation(model: model, overall: overall, commentsByScoreID: commentsByID, reviewsByScoreID: reviewsByID, generatedAt: Date())
    }

    private func recommendationScoreIDAliasMap(_ result: RecommendationRunResult) -> [String: String] {
        var aliases: [String: String] = [:]
        for score in result.scores {
            let rawKeys = [
                score.id,
                score.candidate.canonicalID,
                score.candidate.externalKey,
                score.candidate.paperID,
                score.candidate.sourceURL
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            for key in rawKeys {
                let normalized = recommendationNormalizedAIIdentifier(key)
                aliases[normalized] = score.id
                if normalized.hasPrefix("external:") {
                    aliases[String(normalized.dropFirst("external:".count))] = score.id
                }
                if normalized.hasPrefix("paper:") {
                    aliases[String(normalized.dropFirst("paper:".count))] = score.id
                }
                if normalized.hasPrefix("arxiv:") {
                    aliases["external:\(normalized)"] = score.id
                    aliases[String(normalized.dropFirst("arxiv:".count))] = score.id
                }
            }
        }
        return aliases
    }

    private func recommendationNormalizedAIIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return ""
        }
        if let url = URL(string: trimmed),
           let last = url.pathComponents.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty {
            if url.host?.contains("arxiv.org") == true {
                return "arxiv:\(last.replacingOccurrences(of: ".pdf", with: ""))"
            }
            return last
        }
        return trimmed
    }

    private func recommendationDouble(from value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return double
        }
        return 0
    }

    private func recommendationEvaluationJSONText(from response: String) -> String {
        if let open = response.firstIndex(of: "{"),
           let close = response.lastIndex(of: "}"),
           open <= close {
            return String(response[open...close])
        }
        return response
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
            agentRunHistory = try await agentService.recentRuns(in: root, limit: 1000)
            allAgentThreads = try await agentService.allThreads(in: root)
            applyAgentThreadFilterForCurrentScope()
            restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
            restorePinnedAgentThreadsForCurrentProject()
            restoreAgentToolStateForCurrentScope()
            agentSessionEvents = try await agentService.sessionEvents(in: root, limit: nil)
            let runtimeLoader = AgentRuntimeConfigurationLoader()
            agentPresetDetails = try runtimeLoader.loadProductPreset(in: root)
            agentProductMCPServerStatuses = agentPresetDetails?.mcpServers ?? []
            agentWorkspaceProfileSummary = try await runtimeLoader.loadWorkspaceProfile(in: root)
            agentWorkspaceProfileMCPServerStatuses = agentWorkspaceProfileSummary?.mcpServers ?? []
            agentLocalMCPServerStatuses = try runtimeLoader.loadLocalMCPServerStatuses(in: root)
            rebuildAgentHookActivitySummary()
            agentSidecarHealth = workspacePreferences.isSidecarDisabledForWorkspace
                ? SidecarHealth(status: "disabled", fallbackReason: "Sidecar disabled for this workspace.")
                : await sidecarCoordinator.refreshHealth()
        } catch {
            agentErrorMessage = error.localizedDescription
        }
    }

    private func startAgentLiveEventRefresh(in workspace: ResearchWorkspace, liveRunID: String? = nil) {
        agentLiveEventRefreshTask?.cancel()
        agentLiveRunID = liveRunID
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        let baselineEventIDs = Set(agentSessionEvents.map(\.id))
        agentLiveEventRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                do {
                    let events = try await self.agentService.sessionEvents(in: root, limit: nil)
                    await MainActor.run {
                        self.mergeAgentLiveSessionEvents(events, baselineEventIDs: baselineEventIDs)
                    }
                } catch {
                    // Best-effort UI refresh; the final run refresh remains authoritative.
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func stopAgentLiveEventRefresh(clearRunID: Bool) {
        agentLiveEventRefreshTask?.cancel()
        agentLiveEventRefreshTask = nil
        if clearRunID {
            agentLiveRunID = nil
        }
    }

    private func makeAgentSessionEventHandler() -> (@Sendable (AgentSessionEvent) async -> Void) {
        { [weak self] event in
            guard let self else {
                return
            }
            await MainActor.run {
                self.appendAgentLiveSessionEvent(event)
            }
        }
    }

    private func appendAgentLiveSessionEvent(_ event: AgentSessionEvent) {
        mergeAgentLiveSessionEvents([event], baselineEventIDs: [])
        agentLiveRunID = event.sessionID
    }

    private func mergeAgentLiveSessionEvents(_ events: [AgentSessionEvent], baselineEventIDs: Set<String>) {
        guard !events.isEmpty else {
            return
        }
        var eventsByID: [String: AgentSessionEvent] = [:]
        for event in agentSessionEvents {
            eventsByID[event.id] = event
        }
        for event in events {
            eventsByID[event.id] = event
        }
        let sortedEvents = eventsByID.values.sorted(by: agentSessionEventSort)

        if agentLiveRunID == nil,
           let liveEvent = events.sorted(by: { $0.createdAt < $1.createdAt }).first(where: { event in
               !baselineEventIDs.contains(event.id) && event.kind != .hookResult
           }) {
            agentLiveRunID = liveEvent.sessionID
        }
        guard sortedEvents != agentSessionEvents else {
            return
        }
        agentSessionEvents = sortedEvents
        rebuildAgentHookActivitySummary()
    }

    private nonisolated func agentSessionEventSort(_ first: AgentSessionEvent, _ second: AgentSessionEvent) -> Bool {
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        if first.sessionID != second.sessionID {
            return first.sessionID.localizedStandardCompare(second.sessionID) == .orderedAscending
        }
        let firstPriority = agentSessionEventSortPriority(first.kind)
        let secondPriority = agentSessionEventSortPriority(second.kind)
        if firstPriority != secondPriority {
            return firstPriority < secondPriority
        }
        return first.id.localizedStandardCompare(second.id) == .orderedAscending
    }

    private nonisolated func agentSessionEventSortPriority(_ kind: AgentSessionEventKind) -> Int {
        switch kind {
        case .userMessage:
            return 0
        case .reasoningSummary:
            return 10
        case .assistantMessage:
            return 20
        case .toolCallStarted:
            return 30
        case .toolCallCompleted, .toolCallFailed:
            return 40
        case .artifactDraft, .permissionRequested:
            return 50
        case .permissionResolved:
            return 60
        case .runCancelled:
            return 70
        case .hookResult, .compactionSummary:
            return 90
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
            contextScope: run.contextScope ?? AgentContextScope.inferred(projectID: run.currentProjectID),
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            runtimeSelector: run.runtimeSelector,
            createdFromRoute: run.createdFromRoute ?? "ai_lab",
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

    private var agentDraftProjectIDForCurrentConversation: ResearchProject.ID? {
        pendingAgentThread?.projectID ?? activeAgentThread?.projectID ?? agentConversationProjectID
    }

    private func saveAgentDraftForCurrentConversation() {
        agentGoalDrafts[agentDraftKey(projectID: agentDraftProjectIDForCurrentConversation, threadID: activeAgentThreadID)] = agentGoal
    }

    private func appendAgentStreamingResponseDelta(_ delta: String) {
        guard !delta.isEmpty else {
            return
        }
        agentStreamingRawResponseText += delta
        scheduleAgentStreamingResponseRender()
    }

    private func resetAgentStreamingPreview() {
        agentStreamingRenderGeneration += 1
        agentStreamingRenderTask?.cancel()
        agentStreamingRenderTask = nil
        agentStreamingRawResponseText = ""
        enqueueAgentStreamingResponseText(nil)
    }

    private func scheduleAgentStreamingResponseRender() {
        guard agentStreamingRenderTask == nil else {
            return
        }

        let generation = agentStreamingRenderGeneration
        agentStreamingRenderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.agentStreamingRenderGeneration == generation else {
                        return
                    }
                    self.agentStreamingRenderTask = nil
                    self.publishAgentStreamingResponseNow(invalidatingPendingRender: false)
                }
            }
        }
    }

    private func publishAgentStreamingResponseNow(invalidatingPendingRender: Bool = true) {
        if invalidatingPendingRender {
            agentStreamingRenderGeneration += 1
        }
        agentStreamingRenderTask?.cancel()
        agentStreamingRenderTask = nil
        let visibleText = AgentVisibleResponseExtractor.visibleText(from: agentStreamingRawResponseText)
        enqueueAgentStreamingResponseText(visibleText)
    }

    private func enqueueAgentStreamingResponseText(_ text: String?) {
        let normalizedText = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        agentStreamingPendingResponseText = normalizedText

        guard !agentStreamingResponseCommitScheduled else {
            return
        }

        agentStreamingResponseCommitScheduled = true
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.agentStreamingResponseCommitScheduled = false
                let nextText = self.agentStreamingPendingResponseText
                self.agentStreamingPendingResponseText = nil
                guard self.agentStreamingResponseText != nextText else {
                    return
                }
                self.agentStreamStore.streamingResponseText = nextText
            }
        }
    }

    private func markdownWritebackDraft(
        for call: AgentToolCall,
        in run: AgentRun,
        workspace: ResearchWorkspace
    ) -> AgentMarkdownWritebackDraft? {
        guard call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" else {
            return nil
        }

        let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? run.plan.title ?? "Markdown draft"
        let body = stringArgument("body", in: call.argumentsJSON)?.nilIfEmpty
            ?? run.plan.finalResponseDraft?.nilIfEmpty
            ?? run.plan.summary
        let targetPath = stringArgument("relative_path", in: call.argumentsJSON)?.nilIfEmpty
            ?? "wiki/plans/\(slug(from: title)).md"
        let normalizedTargetPath = targetPath.replacingOccurrences(of: "\\", with: "/")
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let bodyContents = body.hasPrefix("# ") ? body : "# \(title)\n\n\(body)"
        let contents = """
        ---
        title: "\(escapedYAMLScalar(title))"
        draft_for: "\(escapedYAMLScalar(normalizedTargetPath))"
        source_run_id: "\(run.id)"
        source_tool_call_id: "\(call.id)"
        source_tool_name: "\(call.toolName)"
        created_at: "\(createdAt)"
        status: draft_only
        ---

        > Draft-only save from AI Lab. The original target `\(normalizedTargetPath)` has not been written.

        \(bodyContents.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        return AgentMarkdownWritebackDraft(
            targetPath: normalizedTargetPath,
            draftPath: uniqueDraftPath(for: normalizedTargetPath, title: title, workspace: workspace),
            contents: contents + "\n"
        )
    }

    private func uniqueDraftPath(for targetPath: String, title: String, workspace: ResearchWorkspace) -> String {
        let targetBase = targetPath.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: ".md", with: "")
            .nilIfEmpty
        let base = slug(from: targetBase ?? title)
        let candidate = "wiki/drafts/\(base).draft.md"
        guard FileManager.default.fileExists(atPath: workspace.fileURL(for: candidate).path) else {
            return candidate
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return "wiki/drafts/\(base)-\(timestamp).draft.md"
    }

    private func escapedYAMLScalar(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func stringArgument(_ key: String, in rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }

    private func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowercased = title.lowercased()
        var output = ""
        var previousWasDash = false
        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        let slug = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "markdown-draft" : slug
    }

    private func limitedText(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(maxCharacters)) + "..."
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
        let visibleThreadIDs = Set(agentThreads.map(\.id))
        pinnedAgentThreadIDs = Set(workspacePreferences.pinnedAgentThreadIDsByProject[projectKey] ?? [])
            .intersection(visibleThreadIDs)
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
        persistAgentDraft(projectID: agentDraftProjectIDForCurrentConversation, threadID: activeAgentThreadID, text: agentGoal)
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
        let projectID = agentDraftProjectIDForCurrentConversation
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
        if let threadID,
           allAgentThreads.contains(where: { $0.id == threadID && $0.isArchived }) {
            return
        }
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

    private func agentConversationMessagesForPrompt(latestGoal: String? = nil, limit: Int = 6) -> [LLMChatMessage] {
        var messages = agentConversationRuns
            .suffix(limit)
            .flatMap { run -> [LLMChatMessage] in
                if shouldSkipRunInAgentConversationHistory(run) {
                    return []
                }
                let assistantText = [
                    run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ]
                .compactMap { $0 }
                .first ?? "Plan generated."

                return [
                    LLMChatMessage(role: .user, content: run.goal),
                    LLMChatMessage(role: .assistant, content: limitedText(assistantText, maxCharacters: 2_000))
                ]
            }
        if let latestGoal,
           isContinuationPrompt(latestGoal),
           let evidenceSummary = agentContinuationEvidenceSummary() {
            messages.append(LLMChatMessage(role: .user, content: evidenceSummary))
        }
        return messages
    }

    private func shouldSkipRunInAgentConversationHistory(_ run: AgentRun) -> Bool {
        if run.failureCategory == .cancelledByUser {
            return true
        }
        let text = [
            run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let failurePrefixes = [
            "模型没有返回最终回复",
            "The model did not return a final response",
            "Sidecar run completed without a visible response"
        ]
        return failurePrefixes.contains { text.hasPrefix($0) }
    }

    private func isContinuationPrompt(_ goal: String) -> Bool {
        let normalized = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        let compact = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return [
            "继续",
            "接着",
            "继续说",
            "继续写",
            "go on",
            "continue",
            "keep going"
        ].contains { compact == $0 || compact.hasPrefix($0 + " ") }
    }

    private func agentContinuationEvidenceSummary() -> String? {
        guard let run = agentConversationRuns.reversed().first(where: { !$0.toolResults.isEmpty }) else {
            return nil
        }
        let resultLines = run.toolResults.suffix(8).enumerated().map { index, result in
            continuationEvidenceLine(index: index + 1, result: result)
        }
        .joined(separator: "\n")
        guard !resultLines.isEmpty else {
            return nil
        }
        return """
        Continuation context from the previous Sci-Station run.
        The latest user prompt is a continuation request. Reuse this compact evidence summary before deciding to re-read full papers; only call read_paper again if the user asks for new sections or this summary is insufficient.

        previous_run_goal:
        \(run.goal)

        previous_tool_evidence:
        \(resultLines)
        """
    }

    private func continuationEvidenceLine(index: Int, result: AgentToolResult) -> String {
        let payload = result.payload?.objectValue
        let paperID = payload?["paper_id"]?.stringValue
            ?? payload?["paper"]?.objectValue?["id"]?.stringValue
        let source = payload?["source"]?.stringValue
            ?? payload?["paper"]?.objectValue?["raw_markdown_path"]?.stringValue
        let heading = payload?["heading"]?.stringValue
        let targetPath = payload?["target_path"]?.stringValue
        let summary = [
            paperID.map { "paper_id=\($0)" },
            source.map { "source=\($0)" },
            heading.map { "heading=\($0)" },
            targetPath.map { "target=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        return "- #\(index) \(result.toolName) \(result.succeeded ? "succeeded" : "failed")\(summary.isEmpty ? "" : " (\(summary))"): \(limitedText(result.message, maxCharacters: 500))"
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
        var loadedDocuments = try await markdownRepository.loadDocuments(in: workspace, project: currentResearchProject)
        if let markdownID,
           !loadedDocuments.contains(where: { $0.id == markdownID }),
           let externalDocument = try? await markdownRepository.loadDocument(relativePath: markdownID, in: workspace) {
            loadedDocuments.append(externalDocument)
        }
        markdownDocuments = loadedDocuments
        backlinkIndex = BacklinkIndex(documents: loadedDocuments)

        let nextSelectionID = markdownID ?? selectedMarkdownID ?? loadedDocuments.first?.id
        selectedMarkdownID = nextSelectionID
        selectedMarkdownDraft = loadedDocuments.first(where: { $0.id == nextSelectionID })
        updateSelectedMarkdownSaveState(.clean)
    }

    private func mergeMarkdownDocument(_ document: MarkdownDocument) {
        if let index = markdownDocuments.firstIndex(where: { $0.id == document.id }) {
            markdownDocuments[index] = document
        } else {
            markdownDocuments.append(document)
        }
        backlinkIndex = BacklinkIndex(documents: markdownDocuments)
    }

    private func updateSelectedMarkdownSaveState(_ state: MarkdownSaveState, errorMessage: String? = nil) {
        guard selectedMarkdownSaveState != state || selectedMarkdownSaveErrorMessage != errorMessage else {
            return
        }

        selectedMarkdownSaveState = state
        selectedMarkdownSaveErrorMessage = errorMessage
        recordAppDebugEvent("markdown.editor.save_state", payload: .object([
            "state": .string(state.rawValue),
            "relative_path": .string(selectedMarkdownDraft?.relativePath ?? ""),
            "error_present": .bool(errorMessage != nil)
        ]))
    }

    private func paperMarkdownPath(for paper: Paper) -> String {
        paper.paperDirectoryRelativePath + "/paper.md"
    }

    private func currentWikiRootRelativePath() -> String {
        if let project = currentResearchProject {
            return project.relativePath + "/wiki"
        }
        return "wiki"
    }

    private func wikiManagedRelativePath(from input: String, defaultFileName: String) -> String {
        var normalized = input
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty {
            normalized = defaultFileName
        }
        if !normalized.contains("/") && (normalized as NSString).pathExtension.isEmpty {
            normalized = wikiPathSlug(from: normalized) + ".md"
        } else if (normalized as NSString).pathExtension.isEmpty {
            normalized += ".md"
        }
        if normalized.hasPrefix("wiki/") || normalized.hasPrefix("projects/") {
            return normalized
        }
        return currentWikiRootRelativePath() + "/" + normalized
    }

    private func wikiManagedFolderPath(from input: String, defaultFolderName: String) -> String {
        var normalized = input
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty {
            normalized = defaultFolderName
        }
        if !normalized.contains("/") {
            normalized = wikiPathSlug(from: normalized)
        }
        if normalized.hasPrefix("wiki/") || normalized.hasPrefix("projects/") {
            return normalized
        }
        return currentWikiRootRelativePath() + "/" + normalized
    }

    private func markdownTitle(from input: String) -> String {
        let lastComponent = input
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "Untitled"
        let title = (lastComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title.capitalized
    }

    private func wikiPathSlug(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : " "
        })
        let slug = filtered
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" })
            .joined(separator: "-")
        return slug.isEmpty ? "untitled" : slug
    }

    private func pdfAnnotationDebugPayload(_ annotation: PDFAnnotationRecord) -> JSONValue {
        .object([
            "annotation_id": .string(annotation.id),
            "paper_id": .string(annotation.paperID),
            "kind": .string(annotation.kind.rawValue),
            "page_index": .string(String(annotation.pageIndex)),
            "bounds_count": .string(String(annotation.bounds.count)),
            "fingerprint": .string(annotation.duplicateFingerprint),
            "selected_text_preview_present": .bool(!annotation.selectedTextPreview.isEmpty),
            "note_present": .bool(annotation.noteText?.isEmpty == false)
        ])
    }

    private func selectedAgentRetrievalSourceFileStatus() -> AgentRetrievalSelectedSourceFileStatus? {
        guard let currentResearchRoot, let relativePath = selectedAgentRetrievalSourcePath() else {
            return nil
        }
        let fileURL = currentResearchRoot.fileURL(for: relativePath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
        guard exists else {
            return AgentRetrievalSelectedSourceFileStatus(relativePath: relativePath, exists: false, isDirectory: false, byteCount: 0, lineCount: nil)
        }
        let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let lineCount: Int?
        if !isDirectory.boolValue, let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            lineCount = contents.components(separatedBy: .newlines).count
        } else {
            lineCount = nil
        }
        return AgentRetrievalSelectedSourceFileStatus(
            relativePath: relativePath,
            exists: true,
            isDirectory: isDirectory.boolValue,
            byteCount: byteCount,
            lineCount: lineCount
        )
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

    private static func selectCreateWorkspaceURL(suggestedName: String = "ResearchWorkspace") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Research Workspace"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "ResearchWorkspace"
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

#if DEBUG
    private func installUITestBridgeIfRequested() {
        guard let configuration = UITestBridgeConfiguration.fromProcessInfo() else {
            return
        }
        let server = UITestBridgeServer(socketURL: configuration.socketURL) { [weak self] command in
            guard let self else {
                throw UITestBridgeCommandError.unavailable
            }
            return try await self.handleUITestBridgeCommand(command)
        }
        do {
            try server.start()
            uiTestBridgeServer = server
            uiTestBridgeForceDebugLogging = true
            if let currentWorkspace {
                _ = SwiftUIRuntimeWarningCapture.shared.install(rootURL: currentWorkspace.rootURL)
            }
        } catch {
            NSLog("Sci-Station UI test bridge failed to start: %@", String(describing: error))
        }
    }

    private func handleUITestBridgeCommand(_ command: UITestBridgeCommand) async throws -> UITestBridgeCommandResult {
        recordUITestBridgeEvent(.uitestBridgeCommandReceived, command: command.name)
        do {
            let result: UITestBridgeCommandResult
            switch command.name {
            case "ping":
                result = UITestBridgeCommandResult(fields: [
                    "socket_path": .string(uiTestBridgeServer?.socketURL.path ?? ""),
                    "workspace_open": .bool(currentWorkspace != nil),
                    "selected_section": .string(selectedSection?.rawValue ?? "")
                ])
            case "workspace.open":
                let path = try bridgeString(command.args, keys: ["path", "root", "root_path"])
                let workspace = try await openWorkspaceForUITestBridge(rootURL: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
                result = UITestBridgeCommandResult(fields: [
                    "workspace_id": .string(workspace.id.path),
                    "root_path": .string(workspace.rootURL.path)
                ])
            case "route.select":
                let sectionRaw = try bridgeString(command.args, keys: ["section", "route"])
                guard let section = WorkspaceSection(rawValue: sectionRaw) else {
                    throw UITestBridgeCommandError.invalidArgument("section", sectionRaw)
                }
                selectSection(section)
                result = UITestBridgeCommandResult(fields: [
                    "selected_section": .string(selectedSection?.rawValue ?? section.rawValue)
                ])
            case "project.select_first":
                result = try selectFirstProjectForUITestBridge()
            case "project.tab.select":
                result = try selectProjectTabForUITestBridge(args: command.args)
            case "home.layout.enter_edit":
                selectSection(.dashboard)
                enterHomeLayoutEdit()
                result = UITestBridgeCommandResult(fields: [
                    "selected_section": .string(selectedSection?.rawValue ?? ""),
                    "is_editing": .bool(isEditingHomeLayout)
                ])
            case "home.layout.exit_edit":
                exitHomeLayoutEdit()
                result = UITestBridgeCommandResult(fields: [
                    "is_editing": .bool(isEditingHomeLayout)
                ])
            case "library.import.attachFixturePDF":
                result = try await importFixturePDFForUITestBridge(args: command.args)
            case "wiki.page.create":
                result = try await createWikiPageForUITestBridge(args: command.args)
            case "wiki.page.rename_selected":
                result = try await renameSelectedWikiPageForUITestBridge(args: command.args)
            case "agent.prompt.set":
                result = try await setAgentPromptForUITestBridge(args: command.args)
            default:
                throw UITestBridgeCommandError.unknownCommand(command.name)
            }
            recordUITestBridgeEvent(.uitestBridgeCommandCompleted, command: command.name)
            return result
        } catch {
            recordUITestBridgeEvent(.uitestBridgeCommandFailed, command: command.name, error: error.localizedDescription)
            throw error
        }
    }

    private func openWorkspaceForUITestBridge(rootURL: URL) async throws -> ResearchWorkspace {
        isWorking = true
        defer { isWorking = false }
        let compatibility = ResearchRoot.compatibility(at: rootURL)
        let workspace = try await workspaceService.openWorkspace(at: rootURL)
        currentWorkspace = workspace
        try await loadWorkspaceData(
            in: workspace,
            selectingPaper: nil,
            selectingMarkdown: nil,
            rootCompatibility: compatibility
        )
        if selectedSection == nil {
            selectedSection = .projects
        }
        return workspace
    }

    private func selectFirstProjectForUITestBridge() throws -> UITestBridgeCommandResult {
        guard let project = activeResearchProjects.first ?? researchProjects.first else {
            throw UITestBridgeCommandError.missingArgument("project")
        }
        selectResearchProject(project.id, section: .projects)
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(project.id),
            "selected_section": .string(selectedSection?.rawValue ?? ""),
            "project_tab_id": .string(selectedProjectSpaceTabID)
        ])
    }

    private func selectProjectTabForUITestBridge(args: [String: JSONValue]) throws -> UITestBridgeCommandResult {
        if selectedProjectSpaceProjectID == nil {
            _ = try selectFirstProjectForUITestBridge()
        }
        let tabID = try bridgeString(args, keys: ["tab_id", "tab", "id"])
        selectProjectSpaceTab(tabID)
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(selectedProjectSpaceProjectID ?? ""),
            "project_tab_id": .string(selectedProjectSpaceTabID)
        ])
    }

    private func importFixturePDFForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        let sourceURL = try fixturePDFURLForUITestBridge(args: args)
        let collectionPath = bridgeOptionalString(args, keys: ["collection_path", "collection"]) ?? selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        let importedPaper = try await importPDFForUITestBridge(from: sourceURL, collectionPath: collectionPath)
        let fields: [String: JSONValue] = [
            "paper_id": .string(importedPaper.id),
            "title": .string(importedPaper.displayTitle),
            "pdf_path": .string(sourceURL.path)
        ]
        return UITestBridgeCommandResult(fields: fields)
    }

    private func importPDFForUITestBridge(from pdfURL: URL, collectionPath: String) async throws -> Paper {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        isImportingPDF = true
        defer { isImportingPDF = false }
        var importedPaper = try await pdfImportService.importPDF(
            from: pdfURL,
            into: currentWorkspace,
            existingPapers: papers,
            collectionPath: collectionPath
        )
        if let selectedLibraryProjectID,
           !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
            importedPaper.projectIDs.append(selectedLibraryProjectID)
            importedPaper = try await paperRepository.save(importedPaper, in: currentWorkspace)
        }
        try await loadWorkspaceData(
            in: currentWorkspace,
            selectingPaper: importedPaper.id,
            selectingMarkdown: selectedMarkdownID
        )
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library))
        startMarkdownConversion(for: [importedPaper], in: currentWorkspace, statusSurface: .workspace)
        return importedPaper
    }

    private func createWikiPageForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        let name = bridgeOptionalString(args, keys: ["name", "title"]) ?? "UITest Smoke Page"
        let relativePath = bridgeOptionalString(args, keys: ["relative_path", "path"])
            ?? wikiManagedRelativePath(from: name, defaultFileName: "uitest_smoke_page.md")
        let contents = bridgeOptionalString(args, keys: ["contents", "body"])
            ?? "# \(markdownTitle(from: name))\n"
        let document: MarkdownDocument
        do {
            document = try await markdownRepository.createDocument(relativePath: relativePath, contents: contents, in: currentWorkspace)
        } catch MarkdownRepositoryError.destinationAlreadyExists(_) {
            document = try await markdownRepository.loadDocument(relativePath: relativePath, in: currentWorkspace)
        }
        recordAppDebugEvent("wiki.file.create", payload: .object(["relative_path": .string(document.relativePath)]))
        try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
        selectedSection = .wiki
        return UITestBridgeCommandResult(fields: [
            "relative_path": .string(document.relativePath),
            "selected_markdown_id": .string(selectedMarkdownID ?? "")
        ])
    }

    private func renameSelectedWikiPageForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            throw UITestBridgeCommandError.missingArgument("selected markdown")
        }
        let newFileName = try bridgeString(args, keys: ["new_file_name", "file_name", "name"])
        let oldPath = selectedMarkdownDraft.relativePath
        let document = try await markdownRepository.renameDocument(relativePath: oldPath, toFileName: newFileName, in: currentWorkspace)
        recordAppDebugEvent("wiki.file.rename", payload: .object([
            "from": .string(oldPath),
            "to": .string(document.relativePath)
        ]))
        try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
        selectedSection = .wiki
        return UITestBridgeCommandResult(fields: [
            "from": .string(oldPath),
            "to": .string(document.relativePath)
        ])
    }

    private func setAgentPromptForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        let text = try bridgeString(args, keys: ["text", "prompt", "goal"])
        selectSection(.llmLab)
        if bridgeBool(args, key: "new_thread", defaultValue: true) {
            startNewAgentConversation()
        }
        agentGoal = text
        let projectID = agentDraftProjectIDForCurrentConversation
        let threadID = activeAgentThreadID
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        try await agentService.saveDraft(text, projectID: projectID, threadID: threadID, in: root)
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: threadID)] = text
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(projectID ?? ""),
            "thread_id": .string(threadID ?? ""),
            "text_length": .number(String(text.count))
        ])
    }

    private func fixturePDFURLForUITestBridge(args: [String: JSONValue]) throws -> URL {
        if let path = bridgeOptionalString(args, keys: ["fixture_path", "path", "pdf_path"]) {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw UITestBridgeCommandError.invalidArgument("fixture_path", path)
            }
            return url
        }
        let fixtureID = bridgeOptionalString(args, keys: ["fixture_id", "id"]) ?? "fixture"
        let sanitized = fixtureID
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
        let fileName = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-_")).nilIfBlank ?? "fixture"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-uitest-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false).appendingPathExtension("pdf")
        if !FileManager.default.fileExists(atPath: url.path) {
            try minimalFixturePDF(named: fileName).write(to: url, options: .atomic)
        }
        return url
    }

    private func minimalFixturePDF(named title: String) -> Data {
        let escapedTitle = title.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        let text = """
        %PDF-1.1
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
        4 0 obj << /Length 64 >> stream
        BT /F1 12 Tf 72 720 Td (Sci-Station UI test fixture: \(escapedTitle)) Tj ET
        endstream endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """
        return Data(text.utf8)
    }

    private func recordUITestBridgeEvent(_ event: AppDebugEventName, command: String, error: String? = nil) {
        var payload: [String: JSONValue] = ["command": .string(command)]
        if let error {
            payload["error"] = .string(error)
        }
        recordAppDebugEvent(event.rawValue, payload: .object(payload), force: true)
    }

    private func bridgeString(_ args: [String: JSONValue], keys: [String]) throws -> String {
        guard let value = bridgeOptionalString(args, keys: keys) else {
            throw UITestBridgeCommandError.missingArgument(keys.joined(separator: " / "))
        }
        return value
    }

    private func bridgeOptionalString(_ args: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
            if case let .number(value)? = args[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func bridgeStringArray(_ args: [String: JSONValue], key: String) -> [String] {
        guard let values = args[key]?.arrayValue else {
            return []
        }
        return values.compactMap { value in
            value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
    }

    private func bridgeBool(_ args: [String: JSONValue], key: String, defaultValue: Bool) -> Bool {
        switch args[key] {
        case .bool(let value):
            return value
        case .string(let value):
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return defaultValue
        }
    }

    private enum UITestBridgeCommandError: LocalizedError {
        case unavailable
        case missingWorkspace
        case missingArgument(String)
        case invalidArgument(String, String)
        case unknownCommand(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "UI test bridge is unavailable."
            case .missingWorkspace:
                return "Open a workspace before using this UI test bridge command."
            case .missingArgument(let name):
                return "Missing UI test bridge argument: \(name)."
            case .invalidArgument(let name, let value):
                return "Invalid UI test bridge argument \(name): \(value)."
            case .unknownCommand(let command):
                return "Unknown UI test bridge command: \(command)."
            }
        }
    }
#endif

    private static func defaultPanelDirectoryURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
