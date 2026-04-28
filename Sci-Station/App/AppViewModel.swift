import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var currentWorkspace: ResearchWorkspace?
    @Published var selectedSection: WorkspaceSection? = .library
    @Published var isShowingError = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var papers: [Paper] = []
    @Published private(set) var collections: [PaperCollection] = []
    @Published private(set) var tagDefinitions: [TagDefinition] = []
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var calendarEvents: [CalendarEvent] = []
    @Published private(set) var systemScheduleItems: [SystemScheduleItem] = []
    @Published private(set) var systemCalendarAccessState: SystemCalendarAccessState = .notDetermined
    @Published private(set) var isLoadingSystemSchedule = false
    @Published var addTodosToAppleReminders = false
    @Published private(set) var selectedPaperID: Paper.ID?
    @Published private(set) var selectedPaperDraft: Paper?
    @Published var isShowingPaperDeleteConfirmation = false
    @Published private(set) var paperPendingDeletion: Paper?
    @Published var isShowingBibTeXExport = false
    @Published private(set) var bibTeXExportText = ""
    @Published private(set) var bibTeXExportFileName = "reference.bib"
    @Published private(set) var selectedCollectionPath: String?
    @Published private(set) var selectedTagName: String?
    @Published var selectedDashboardDate = Calendar.current.startOfDay(for: Date())
    @Published var librarySearchText = ""
    @Published private(set) var isImportingPDF = false
    @Published var isShowingIdentifierImport = false
    @Published var identifierImportInput = ""
    @Published var identifierImportCollectionPath = "Uncategorized"
    @Published var identifierImportTagsText = ""
    @Published private(set) var identifierImportPreview: PaperMetadataDraft?
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
    @Published private(set) var isSavingSelectedMarkdown = false

    private let workspaceService: WorkspaceService
    private let paperRepository: PaperRepository
    private let collectionRepository: CollectionRepository
    private let movePaperToCollectionService: MovePaperToCollectionService
    private let tagRepository: TagRepository
    private let todoRepository: TodoRepository
    private let calendarRepository: CalendarRepository
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
    private let wikiPageGenerator: WikiPageGenerator
    private let pdfOpeningService: any PDFOpeningService
    private var backlinkIndex = BacklinkIndex(documents: [])

    init(
        workspaceService: WorkspaceService? = nil,
        paperRepository: PaperRepository? = nil,
        collectionRepository: CollectionRepository? = nil,
        tagRepository: TagRepository? = nil,
        todoRepository: TodoRepository? = nil,
        calendarRepository: CalendarRepository? = nil,
        systemCalendarService: SystemCalendarService? = nil,
        pdfReadingStateService: PDFReadingStateService? = nil,
        remoteImportService: RemoteImportService? = nil,
        llmConfigurationStore: LLMConfigurationStore? = nil,
        apiKeyStore: KeychainAPIKeyStore? = nil,
        openAIProvider: OpenAICompatibleProvider? = nil,
        paperSummaryService: PaperSummaryService? = nil,
        llmWritebackService: LLMWritebackService? = nil,
        markdownRepository: MarkdownRepository? = nil,
        pdfOpeningService: (any PDFOpeningService)? = nil
    ) {
        let resolvedWorkspaceService = workspaceService ?? WorkspaceService()
        let resolvedPaperRepository = paperRepository ?? PaperRepository()
        let resolvedCollectionRepository = collectionRepository ?? CollectionRepository()
        let resolvedTagRepository = tagRepository ?? TagRepository()
        let resolvedTodoRepository = todoRepository ?? TodoRepository()
        let resolvedCalendarRepository = calendarRepository ?? CalendarRepository()
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

        self.workspaceService = resolvedWorkspaceService
        self.paperRepository = resolvedPaperRepository
        self.collectionRepository = resolvedCollectionRepository
        self.movePaperToCollectionService = MovePaperToCollectionService(paperRepository: resolvedPaperRepository)
        self.tagRepository = resolvedTagRepository
        self.todoRepository = resolvedTodoRepository
        self.calendarRepository = resolvedCalendarRepository
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
        self.wikiPageGenerator = WikiPageGenerator(paperRepository: resolvedPaperRepository)
        self.pdfOpeningService = pdfOpeningService ?? SystemPDFOpeningService()
    }

    var filteredPapers: [Paper] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return papers.filter { paper in
            let matchesCollection = selectedCollectionPath.map { selectedPath in
                guard let collectionPath = paper.collectionPath else {
                    return false
                }

                return collectionPath == selectedPath || collectionPath.hasPrefix(selectedPath + "/")
            } ?? true
            let matchesTag = selectedTagName.map { paper.tags.contains($0) } ?? true
            let matchesQuery = query.isEmpty
                || paper.title.lowercased().contains(query)
                || paper.citekey.lowercased().contains(query)
                || paper.authors.joined(separator: " ").lowercased().contains(query)
                || paper.tags.joined(separator: " ").lowercased().contains(query)

            return matchesCollection && matchesTag && matchesQuery
        }
    }

    var availableTagDefinitions: [TagDefinition] {
        let existingNames = Set(tagDefinitions.map(\.name))
        let inferredDefinitions = Set(papers.flatMap(\.tags))
            .subtracting(existingNames)
            .sorted()
            .map { TagDefinition(name: $0, colorHex: "#E5E7EB", textColorHex: "#374151") }

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

    var recentlyReadPapers: [Paper] {
        Array(
            papers
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
    }

    var libraryScopeSummary: String {
        if let selectedCollectionPath {
            return "Collection: \(selectedCollectionPath)"
        }

        if let selectedTagName {
            return "Tag: \(selectedTagName)"
        }

        return "All Papers"
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

    func selectSection(_ section: WorkspaceSection) {
        selectedSection = section
        if section == .library {
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    func selectLibraryScope() {
        selectedSection = .library
        selectedCollectionPath = nil
        selectedTagName = nil
    }

    func selectCollection(_ relativePath: String) {
        selectedSection = .library
        selectedCollectionPath = relativePath
        selectedTagName = nil
    }

    func selectTag(_ name: String) {
        selectedSection = .library
        selectedTagName = name
        selectedCollectionPath = nil
    }

    func clearLibraryFilters() {
        selectedCollectionPath = nil
        selectedTagName = nil
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

        runWorkspaceTask {
            try await self.workspaceService.createWorkspace(at: destinationURL)
        }
    }

    func openWorkspace() {
        guard let destinationURL = Self.selectOpenWorkspaceURL() else {
            return
        }

        runWorkspaceTask {
            try await self.workspaceService.openWorkspace(at: destinationURL)
        }
    }

    func revealCurrentWorkspaceInFinder() {
        guard let currentWorkspace else {
            return
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentWorkspace.rootURL.path)
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
        identifierImportCollectionPath = selectedCollectionPath ?? "Uncategorized"
        identifierImportTagsText = ""
        identifierImportPreview = nil
    }

    func beginIdentifierImport(with initialInput: String? = nil) {
        prepareIdentifierImport(initialInput: initialInput)
        isShowingIdentifierImport = true
    }

    func resetIdentifierImportForm() {
        prepareIdentifierImport()
    }

    func previewIdentifierImport() {
        let trimmedInput = identifierImportInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            identifierImportPreview = nil
            return
        }

        isResolvingIdentifierImport = true

        Task {
            defer {
                isResolvingIdentifierImport = false
            }

            do {
                identifierImportPreview = try await remoteImportService.preview(for: trimmedInput)
            } catch {
                present(error)
            }
        }
    }

    func performIdentifierImport(onSuccess: (() -> Void)? = nil) {
        guard let currentWorkspace else {
            return
        }

        let trimmedInput = identifierImportInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return
        }

        isPerformingIdentifierImport = true

        Task {
            defer {
                isPerformingIdentifierImport = false
            }

            do {
                let importedPaper = try await remoteImportService.importItem(
                    from: trimmedInput,
                    draftPreview: identifierImportPreview,
                    into: currentWorkspace,
                    existingPapers: papers,
                    collectionPath: identifierImportCollectionPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Uncategorized",
                    tags: commaSeparatedValues(from: identifierImportTagsText)
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: importedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                isShowingIdentifierImport = false
                identifierImportPreview = nil
                identifierImportInput = ""
                identifierImportTagsText = ""
                onSuccess?()
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

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        isShowingBibTeXExport = true
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
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        Task {
            do {
                let movedPaper = try await movePaperToCollectionService.move(
                    selectedPaperDraft,
                    to: collectionPath,
                    in: currentWorkspace
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: movedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
                selectCollection(collectionPath)
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

    func addTodo(title: String, dueDate: Date?, priority: Priority = .medium, notes: String? = nil) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let now = Date()
        let todo = TodoItem(
            id: "todo-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            status: .open,
            dueDate: dueDate.map { Calendar.current.startOfDay(for: $0) },
            priority: priority,
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
                    try await createAppleReminderIfNeeded(for: todo)
                }
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updateTodo(_ todo: TodoItem, title: String, status: TodoStatus, dueDate: Date?, priority: Priority, notes: String?) {
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
        updatedTodo.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

        draft.rawContents = newValue
        selectedMarkdownDraft = draft
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
                try await loadWorkspaceData(in: workspace, selectingPaper: nil, selectingMarkdown: nil)
                if selectedSection == nil {
                    selectedSection = .library
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
                let importedPaper = try await pdfImportService.importPDF(
                    from: pdfURL,
                    into: workspace,
                    existingPapers: existingPapers,
                    collectionPath: selectedCollectionPath ?? "Uncategorized"
                )
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
        selectingMarkdown markdownID: String?
    ) async throws {
        try await loadLibrary(in: workspace, selecting: paperID)
        try await loadCollections(in: workspace)
        try await loadTags(in: workspace)
        try await loadTodos(in: workspace)
        try await loadCalendarEvents(in: workspace)
        systemCalendarAccessState = systemCalendarService.accessState
        if systemCalendarAccessState.canReadSchedule {
            try await loadSystemSchedule(around: selectedDashboardDate)
        }
        try await loadLLMSettings(in: workspace)
        try await loadMarkdownDocuments(in: workspace, selecting: markdownID)
    }

    private func loadLibrary(in workspace: ResearchWorkspace, selecting paperID: Paper.ID?) async throws {
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        papers = loadedPapers

        let nextSelectionID = paperID ?? selectedPaperID ?? loadedPapers.first?.id
        selectedPaperID = nextSelectionID
        selectedPaperDraft = loadedPapers.first(where: { $0.id == nextSelectionID })
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
    }

    private func createAppleReminderIfNeeded(for todo: TodoItem) async throws {
        if !systemCalendarService.canCreateReminders {
            systemCalendarAccessState = try await systemCalendarService.requestAccess()
        }

        guard systemCalendarService.canCreateReminders else {
            throw SystemCalendarServiceError.accessDenied
        }

        if let reminder = try await systemCalendarService.createReminder(
            title: todo.title,
            dueDate: todo.dueDate,
            notes: todo.notes
        ) {
            systemScheduleItems.append(reminder)
            systemScheduleItems.sort { $0.displayDate < $1.displayDate }
        }

        systemCalendarAccessState = systemCalendarService.accessState
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

    private func loadMarkdownDocuments(in workspace: ResearchWorkspace, selecting markdownID: String?) async throws {
        let loadedDocuments = try await markdownRepository.loadDocuments(in: workspace)
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
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

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
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

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
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
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