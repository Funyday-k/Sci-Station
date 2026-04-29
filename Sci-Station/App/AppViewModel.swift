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
    @Published private(set) var legacyPaperMigrationPlan = LegacyPaperMigrationPlan.empty
    @Published private(set) var isLoadingLegacyPaperMigrationPlan = false
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
    @Published private(set) var selectedPaperID: Paper.ID?
    @Published private(set) var selectedPaperDraft: Paper?
    @Published var selectedPaperAnnotationsDraft = ""
    @Published private(set) var isSavingSelectedPaperAnnotations = false
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
    @Published private(set) var isTestingLLMConnection = false
    @Published private(set) var llmConnectionStatusMessage: String?
    @Published private(set) var isGeneratingSummary = false
    @Published private(set) var summaryPreviewText: String?
    @Published var isShowingSummaryPreview = false
    @Published private(set) var isGeneratingWikiPage = false
    @Published private(set) var markdownDocuments: [MarkdownDocument] = []
    @Published private(set) var selectedMarkdownID: String?
    @Published private(set) var selectedMarkdownDraft: MarkdownDocument?
    @Published private(set) var markdownSnippets: [MarkdownSnippet] = MarkdownSnippetRepository.defaultSnippets
    @Published private(set) var isSavingSelectedMarkdown = false

    private let workspaceService: WorkspaceService
    private let projectRegistryRepository: ProjectRegistryRepository
    private let paperRepository: PaperRepository
    private let legacyPaperMigrationService: LegacyPaperMigrationService
    private let collectionRepository: CollectionRepository
    private let movePaperToCollectionService: MovePaperToCollectionService
    private let tagRepository: TagRepository
    private let todoRepository: TodoRepository
    private let calendarRepository: CalendarRepository
    private let workspacePreferencesRepository: WorkspacePreferencesRepository
    private let paperAnnotationsRepository: PaperAnnotationsRepository
    private let systemCalendarService: SystemCalendarService
    private let pdfReadingStateService: PDFReadingStateService
    private let remoteImportService: RemoteImportService
    private let llmConfigurationStore: LLMConfigurationStore
    private let apiKeyStore: KeychainAPIKeyStore
    private let openAIProvider: OpenAICompatibleProvider
    private let paperSummaryService: PaperSummaryService
    private let llmWritebackService: LLMWritebackService
    private let pdfImportService: PDFImportService
    private let markdownRepository: MarkdownRepository
    private let markdownSnippetRepository: MarkdownSnippetRepository
    private let wikiPageGenerator: WikiPageGenerator
    private let pdfOpeningService: any PDFOpeningService
    private let librarySearchService: LibrarySearchService
    private let batchImportInputParser = BatchImportInputParser()
    private var backlinkIndex = BacklinkIndex(documents: [])

    var identifierImportInputs: [String] {
        batchImportInputParser.parse(identifierImportInput)
    }

    init(
        workspaceService: WorkspaceService? = nil,
        projectRegistryRepository: ProjectRegistryRepository? = nil,
        paperRepository: PaperRepository? = nil,
        legacyPaperMigrationService: LegacyPaperMigrationService? = nil,
        collectionRepository: CollectionRepository? = nil,
        tagRepository: TagRepository? = nil,
        todoRepository: TodoRepository? = nil,
        calendarRepository: CalendarRepository? = nil,
        workspacePreferencesRepository: WorkspacePreferencesRepository? = nil,
        paperAnnotationsRepository: PaperAnnotationsRepository? = nil,
        systemCalendarService: SystemCalendarService? = nil,
        pdfReadingStateService: PDFReadingStateService? = nil,
        remoteImportService: RemoteImportService? = nil,
        llmConfigurationStore: LLMConfigurationStore? = nil,
        apiKeyStore: KeychainAPIKeyStore? = nil,
        openAIProvider: OpenAICompatibleProvider? = nil,
        paperSummaryService: PaperSummaryService? = nil,
        llmWritebackService: LLMWritebackService? = nil,
        markdownRepository: MarkdownRepository? = nil,
        markdownSnippetRepository: MarkdownSnippetRepository? = nil,
        pdfOpeningService: (any PDFOpeningService)? = nil
    ) {
        let resolvedWorkspaceService = workspaceService ?? WorkspaceService()
        let resolvedProjectRegistryRepository = projectRegistryRepository ?? ProjectRegistryRepository()
        let resolvedPaperRepository = paperRepository ?? PaperRepository()
        let resolvedLegacyPaperMigrationService = legacyPaperMigrationService ?? LegacyPaperMigrationService()
        let resolvedCollectionRepository = collectionRepository ?? CollectionRepository()
        let resolvedTagRepository = tagRepository ?? TagRepository()
        let resolvedTodoRepository = todoRepository ?? TodoRepository()
        let resolvedCalendarRepository = calendarRepository ?? CalendarRepository()
        let resolvedWorkspacePreferencesRepository = workspacePreferencesRepository ?? WorkspacePreferencesRepository()
        let resolvedPaperAnnotationsRepository = paperAnnotationsRepository ?? PaperAnnotationsRepository()
        let resolvedSystemCalendarService = systemCalendarService ?? SystemCalendarService()
        let resolvedPDFReadingStateService = pdfReadingStateService ?? PDFReadingStateService(paperRepository: resolvedPaperRepository)
        let resolvedRemoteImportService = remoteImportService ?? RemoteImportService(
            pdfImportService: PDFImportService(repository: resolvedPaperRepository),
            linkOnlyImportService: LinkOnlyImportService(repository: resolvedPaperRepository)
        )
        let resolvedLLMConfigurationStore = llmConfigurationStore ?? LLMConfigurationStore()
        let resolvedAPIKeyStore = apiKeyStore ?? KeychainAPIKeyStore()
        let resolvedOpenAIProvider = openAIProvider ?? OpenAICompatibleProvider()
        let resolvedPaperSummaryService = paperSummaryService ?? PaperSummaryService(provider: resolvedOpenAIProvider)
        let resolvedLLMWritebackService = llmWritebackService ?? LLMWritebackService()
        let resolvedMarkdownRepository = markdownRepository ?? MarkdownRepository()
        let resolvedMarkdownSnippetRepository = markdownSnippetRepository ?? MarkdownSnippetRepository()

        self.workspaceService = resolvedWorkspaceService
        self.projectRegistryRepository = resolvedProjectRegistryRepository
        self.paperRepository = resolvedPaperRepository
        self.legacyPaperMigrationService = resolvedLegacyPaperMigrationService
        self.collectionRepository = resolvedCollectionRepository
        self.movePaperToCollectionService = MovePaperToCollectionService(paperRepository: resolvedPaperRepository)
        self.tagRepository = resolvedTagRepository
        self.todoRepository = resolvedTodoRepository
        self.calendarRepository = resolvedCalendarRepository
        self.workspacePreferencesRepository = resolvedWorkspacePreferencesRepository
        self.paperAnnotationsRepository = resolvedPaperAnnotationsRepository
        self.systemCalendarService = resolvedSystemCalendarService
        self.systemCalendarAccessState = resolvedSystemCalendarService.accessState
        self.pdfReadingStateService = resolvedPDFReadingStateService
        self.remoteImportService = resolvedRemoteImportService
        self.llmConfigurationStore = resolvedLLMConfigurationStore
        self.apiKeyStore = resolvedAPIKeyStore
        self.openAIProvider = resolvedOpenAIProvider
        self.paperSummaryService = resolvedPaperSummaryService
        self.llmWritebackService = resolvedLLMWritebackService
        self.pdfImportService = PDFImportService(repository: resolvedPaperRepository)
        self.markdownRepository = resolvedMarkdownRepository
        self.markdownSnippetRepository = resolvedMarkdownSnippetRepository
        self.wikiPageGenerator = WikiPageGenerator(paperRepository: resolvedPaperRepository)
        self.pdfOpeningService = pdfOpeningService ?? SystemPDFOpeningService()
        self.librarySearchService = LibrarySearchService()
    }

    var filteredPapers: [Paper] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return papers.filter { paper in
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
    }

    var libraryVisibleColumnStorage: String {
        workspacePreferences.libraryVisibleColumnsStorageValue
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
        guard let destinationURL = Self.selectCreateWorkspaceURL() else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.createWorkspace(at: destinationURL)
        }
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
        currentProjectID = projectID
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
        currentProjectID = projectID
        persistLastOpenedProject(projectID)
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

    func resetLibraryVisibleColumns() {
        updateWorkspacePreferences { preferences in
            preferences.libraryVisibleColumns = WorkspacePreferences.defaultLibraryVisibleColumns
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
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let droppedFileURL = Self.fileURL(from: item) else {
                return
            }

            Task { @MainActor in
                self.importPDF(from: droppedFileURL, into: currentWorkspace)
            }
        }

        return true
    }

    func selectPaper(id: Paper.ID?) {
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

    func exportSelectedPaperBibTeX() {
        guard let selectedPaperDraft else {
            return
        }

        exportBibTeX(for: selectedPaperDraft)
    }

    func dismissBibTeXExport() {
        isShowingBibTeXExport = false
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
        guard let currentWorkspace else {
            return
        }

        var updatedPaper = paper
        if updatedPaper.projectIDs.contains(projectID) {
            updatedPaper.projectIDs.removeAll { $0 == projectID }
            updatedPaper.coreProjectIDs.removeAll { $0 == projectID }
        } else {
            updatedPaper.projectIDs.append(projectID)
        }

        savePaperClassification(updatedPaper, in: currentWorkspace)
    }

    func togglePaperCoreProject(_ paper: Paper, projectID: ResearchProject.ID) {
        guard let currentWorkspace, paper.projectIDs.contains(projectID) else {
            return
        }

        var updatedPaper = paper
        if updatedPaper.coreProjectIDs.contains(projectID) {
            updatedPaper.coreProjectIDs.removeAll { $0 == projectID }
        } else {
            updatedPaper.coreProjectIDs.append(projectID)
        }

        savePaperClassification(updatedPaper, in: currentWorkspace)
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
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        papers = loadedPapers

        let nextSelectionID = paperID ?? selectedPaperID ?? loadedPapers.first?.id
        selectedPaperID = nextSelectionID
        selectedPaperDraft = loadedPapers.first(where: { $0.id == nextSelectionID })
        try await loadSelectedPaperAnnotations(in: workspace)
    }

    private func loadLegacyPaperMigrationPlan(in workspace: ResearchWorkspace) async throws {
        legacyPaperMigrationPlan = try await legacyPaperMigrationService.makePlan(in: workspace)
    }

    private func loadWorkspacePreferences(in workspace: ResearchWorkspace) async throws {
        workspacePreferences = try await workspacePreferencesRepository.load(in: workspace)
        addTodosToAppleReminders = workspacePreferences.syncTodosToAppleReminders
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

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}