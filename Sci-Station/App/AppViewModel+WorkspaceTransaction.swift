import Foundation

@MainActor
struct AppWorkspaceSessionSnapshot {
    let domainStores: AppDomainStoresSnapshot
    let workspaceModuleConfiguration: WorkspaceModuleConfiguration
    let workspaceModuleWarnings: [WorkspaceModuleWarning]
    let workspaceModuleDirectoryStatuses: [WorkspaceModuleDirectoryStatus]
    let workspaceModuleOverrides: [String: WorkspaceModuleOverride]
    let rootCompatibilityMessage: String?
    let legacyPaperMigrationPlan: LegacyPaperMigrationPlan
    let todoTagDefinitions: [TagDefinition]
    let todos: [TodoItem]
    let calendarEvents: [CalendarEvent]
    let systemScheduleItems: [SystemScheduleItem]
    let systemCalendarAccessState: SystemCalendarAccessState
    let selectedDashboardDate: Date
    let addTodosToAppleReminders: Bool
    let workspacePreferences: WorkspacePreferences
    let selectedPaperID: Paper.ID?
    let selectedPaperDraft: Paper?
    let selectedPaperAnnotationsDraft: String
    let selectedCollectionPath: String?
    let selectedTagName: String?
    let selectedLibraryProjectID: ResearchProject.ID?
    let llmConfiguration: LLMConfiguration
    let hasLLMAPIKey: Bool
    let hasMinerUAPIToken: Bool
    let hasLoadedSensitiveAIKeys: Bool
    let agentWorkspaceSnapshot: AgentWorkspaceSnapshot?
    let agentDisabledToolNames: Set<String>
    let agentSessionEvents: [AgentSessionEvent]
    let allAgentThreads: [AgentThread]
    let agentNextRunContextScope: AgentContextScope
    let agentNextRunProjectID: ResearchProject.ID?
    let isAgentThreadWorkspaceFilterEnabled: Bool
    let activeAgentThreadID: AgentThread.ID?
    let pendingAgentThread: AgentThread?
    let pinnedAgentThreadIDs: Set<AgentThread.ID>
    let agentPresetDetails: AgentPresetSummary?
    let agentProductMCPServerStatuses: [AgentMCPServerStatus]
    let agentWorkspaceProfile: AgentWorkspaceProfile
    let agentWorkspaceProfileSummary: AgentWorkspaceProfileSummary?
    let agentWorkspaceProfileMCPServerStatuses: [AgentMCPServerStatus]
    let agentPromptResolutionSummaries: [String]
    let agentLocalMCPServerStatuses: [AgentMCPServerStatus]
    let agentMCPRuntimeStatuses: [AgentMCPRuntimeStatus]
    let agentHookActivitySummary: AgentHookActivitySummary
    let agentSidecarHealth: SidecarHealth
    let agentRetrievalIndexStatus: AgentEmbeddingIndexStatusSnapshot
    let agentDisabledHookIDs: Set<String>
    let selectedAgentKnowledgePaperIDs: Set<Paper.ID>
    let markdownSnippets: [MarkdownSnippet]
    let backlinkIndex: BacklinkIndex
    let graph: GraphStore.Snapshot
}

@MainActor
extension AppViewModel {
    func captureWorkspaceSessionSnapshot() -> AppWorkspaceSessionSnapshot {
        AppWorkspaceSessionSnapshot(
            domainStores: AppDomainStoresSnapshot(
                workspaceStore: workspaceStore,
                libraryStore: libraryStore,
                knowledgeStore: knowledgeStore,
                recommendationStore: recommendationStore,
                agentStore: agentStore,
                navigationStore: navigationStore
            ),
            workspaceModuleConfiguration: workspaceModuleConfiguration,
            workspaceModuleWarnings: workspaceModuleWarnings,
            workspaceModuleDirectoryStatuses: workspaceModuleDirectoryStatuses,
            workspaceModuleOverrides: workspaceModuleOverrides,
            rootCompatibilityMessage: rootCompatibilityMessage,
            legacyPaperMigrationPlan: legacyPaperMigrationPlan,
            todoTagDefinitions: todoTagDefinitions,
            todos: todos,
            calendarEvents: calendarEvents,
            systemScheduleItems: systemScheduleItems,
            systemCalendarAccessState: systemCalendarAccessState,
            selectedDashboardDate: selectedDashboardDate,
            addTodosToAppleReminders: addTodosToAppleReminders,
            workspacePreferences: workspacePreferences,
            selectedPaperID: selectedPaperID,
            selectedPaperDraft: selectedPaperDraft,
            selectedPaperAnnotationsDraft: selectedPaperAnnotationsDraft,
            selectedCollectionPath: selectedCollectionPath,
            selectedTagName: selectedTagName,
            selectedLibraryProjectID: selectedLibraryProjectID,
            llmConfiguration: llmConfiguration,
            hasLLMAPIKey: hasLLMAPIKey,
            hasMinerUAPIToken: hasMinerUAPIToken,
            hasLoadedSensitiveAIKeys: hasLoadedSensitiveAIKeys,
            agentWorkspaceSnapshot: agentWorkspaceSnapshot,
            agentDisabledToolNames: agentDisabledToolNames,
            agentSessionEvents: agentSessionEvents,
            allAgentThreads: allAgentThreads,
            agentNextRunContextScope: agentNextRunContextScope,
            agentNextRunProjectID: agentNextRunProjectID,
            isAgentThreadWorkspaceFilterEnabled: isAgentThreadWorkspaceFilterEnabled,
            activeAgentThreadID: activeAgentThreadID,
            pendingAgentThread: pendingAgentThread,
            pinnedAgentThreadIDs: pinnedAgentThreadIDs,
            agentPresetDetails: agentPresetDetails,
            agentProductMCPServerStatuses: agentProductMCPServerStatuses,
            agentWorkspaceProfile: agentWorkspaceProfile,
            agentWorkspaceProfileSummary: agentWorkspaceProfileSummary,
            agentWorkspaceProfileMCPServerStatuses: agentWorkspaceProfileMCPServerStatuses,
            agentPromptResolutionSummaries: agentPromptResolutionSummaries,
            agentLocalMCPServerStatuses: agentLocalMCPServerStatuses,
            agentMCPRuntimeStatuses: agentMCPRuntimeStatuses,
            agentHookActivitySummary: agentHookActivitySummary,
            agentSidecarHealth: agentSidecarHealth,
            agentRetrievalIndexStatus: agentRetrievalIndexStatus,
            agentDisabledHookIDs: agentDisabledHookIDs,
            selectedAgentKnowledgePaperIDs: selectedAgentKnowledgePaperIDs,
            markdownSnippets: markdownSnippets,
            backlinkIndex: backlinkIndex,
            graph: graphStore.snapshot()
        )
    }

    func restoreWorkspaceSessionSnapshot(
        _ snapshot: AppWorkspaceSessionSnapshot,
        restoreGraph: Bool = true,
        closeReplacedGraph: Bool = true
    ) async {
        let abandonedGraphRepository = restoreGraph && closeReplacedGraph ? graphStore.repository : nil

        snapshot.domainStores.restore(
            workspaceStore: workspaceStore,
            libraryStore: libraryStore,
            knowledgeStore: knowledgeStore,
            recommendationStore: recommendationStore,
            agentStore: agentStore,
            navigationStore: navigationStore
        )
        workspaceModuleConfiguration = snapshot.workspaceModuleConfiguration
        workspaceModuleWarnings = snapshot.workspaceModuleWarnings
        workspaceModuleDirectoryStatuses = snapshot.workspaceModuleDirectoryStatuses
        workspaceModuleOverrides = snapshot.workspaceModuleOverrides
        rootCompatibilityMessage = snapshot.rootCompatibilityMessage
        legacyPaperMigrationPlan = snapshot.legacyPaperMigrationPlan
        todoTagDefinitions = snapshot.todoTagDefinitions
        todos = snapshot.todos
        calendarEvents = snapshot.calendarEvents
        systemScheduleItems = snapshot.systemScheduleItems
        systemCalendarAccessState = snapshot.systemCalendarAccessState
        selectedDashboardDate = snapshot.selectedDashboardDate
        addTodosToAppleReminders = snapshot.addTodosToAppleReminders
        workspacePreferences = snapshot.workspacePreferences
        selectedPaperID = snapshot.selectedPaperID
        selectedPaperDraft = snapshot.selectedPaperDraft
        selectedPaperAnnotationsDraft = snapshot.selectedPaperAnnotationsDraft
        selectedCollectionPath = snapshot.selectedCollectionPath
        selectedTagName = snapshot.selectedTagName
        selectedLibraryProjectID = snapshot.selectedLibraryProjectID
        llmConfiguration = snapshot.llmConfiguration
        hasLLMAPIKey = snapshot.hasLLMAPIKey
        hasMinerUAPIToken = snapshot.hasMinerUAPIToken
        hasLoadedSensitiveAIKeys = snapshot.hasLoadedSensitiveAIKeys
        agentWorkspaceSnapshot = snapshot.agentWorkspaceSnapshot
        agentDisabledToolNames = snapshot.agentDisabledToolNames
        agentSessionEvents = snapshot.agentSessionEvents
        allAgentThreads = snapshot.allAgentThreads
        agentNextRunContextScope = snapshot.agentNextRunContextScope
        agentNextRunProjectID = snapshot.agentNextRunProjectID
        isAgentThreadWorkspaceFilterEnabled = snapshot.isAgentThreadWorkspaceFilterEnabled
        activeAgentThreadID = snapshot.activeAgentThreadID
        pendingAgentThread = snapshot.pendingAgentThread
        pinnedAgentThreadIDs = snapshot.pinnedAgentThreadIDs
        agentPresetDetails = snapshot.agentPresetDetails
        agentProductMCPServerStatuses = snapshot.agentProductMCPServerStatuses
        agentWorkspaceProfile = snapshot.agentWorkspaceProfile
        agentWorkspaceProfileSummary = snapshot.agentWorkspaceProfileSummary
        agentWorkspaceProfileMCPServerStatuses = snapshot.agentWorkspaceProfileMCPServerStatuses
        agentPromptResolutionSummaries = snapshot.agentPromptResolutionSummaries
        agentLocalMCPServerStatuses = snapshot.agentLocalMCPServerStatuses
        agentMCPRuntimeStatuses = snapshot.agentMCPRuntimeStatuses
        agentHookActivitySummary = snapshot.agentHookActivitySummary
        agentSidecarHealth = snapshot.agentSidecarHealth
        agentRetrievalIndexStatus = snapshot.agentRetrievalIndexStatus
        agentDisabledHookIDs = snapshot.agentDisabledHookIDs
        selectedAgentKnowledgePaperIDs = snapshot.selectedAgentKnowledgePaperIDs
        markdownSnippets = snapshot.markdownSnippets
        backlinkIndex = snapshot.backlinkIndex
        if restoreGraph {
            graphStore.restore(snapshot.graph)
        }

        if let abandonedGraphRepository,
           snapshot.graph.repository.map({ abandonedGraphRepository !== $0 }) ?? true {
            await abandonedGraphRepository.close()
        }
    }

    func makeWorkspaceLoadStagingModel() -> AppViewModel {
        AppViewModel(
            workspaceService: workspaceService,
            projectRegistryRepository: projectRegistryRepository,
            projectPaperLinkRepository: projectPaperLinkRepository,
            paperRepository: paperRepository,
            legacyPaperMigrationService: legacyPaperMigrationService,
            collectionRepository: collectionRepository,
            tagRepository: tagRepository,
            todoRepository: todoRepository,
            calendarRepository: calendarRepository,
            workspacePreferencesRepository: workspacePreferencesRepository,
            workspaceModuleConfigurationStore: workspaceModuleConfigurationStore,
            workspaceModuleOverrideRepository: workspaceModuleOverrideRepository,
            agentWorkspaceProfileRepository: agentWorkspaceProfileRepository,
            paperAnnotationsRepository: paperAnnotationsRepository,
            pdfAnnotationStore: pdfAnnotationStore,
            libraryBulkEditService: libraryBulkEditService,
            systemCalendarService: systemCalendarService,
            pdfReadingStateService: pdfReadingStateService,
            remoteImportService: remoteImportService,
            pdfDownloadService: pdfDownloadService,
            llmConfigurationStore: llmConfigurationStore,
            apiKeyStore: apiKeyStore,
            credentialBroker: credentialBroker,
            openAIProvider: openAIProvider,
            paperSummaryService: paperSummaryService,
            llmWritebackService: llmWritebackService,
            agentService: agentService,
            sidecarCoordinator: sidecarCoordinator,
            agentEmbeddingIndexController: agentEmbeddingIndexController,
            markdownRepository: markdownRepository,
            markdownSnippetRepository: markdownSnippetRepository,
            pdfOpeningService: pdfOpeningService,
            installRuntimeBridges: false
        )
    }

    func stageWorkspaceLoad(
        in workspace: ResearchWorkspace,
        selectingPaper paperID: Paper.ID?,
        selectingMarkdown markdownID: String?,
        rootCompatibility: ResearchRootCompatibility?
    ) async throws -> LoadedWorkspaceState<AppWorkspaceSessionSnapshot> {
        let sourceSnapshot = captureWorkspaceSessionSnapshot()
        let stagingModel = makeWorkspaceLoadStagingModel()
        await stagingModel.restoreWorkspaceSessionSnapshot(sourceSnapshot, restoreGraph: false)
        stagingModel.currentWorkspace = workspace

        do {
            return try await WorkspaceStateLoader.load(workspace: workspace) {
                try await stagingModel.loadWorkspaceDataUncommitted(
                    in: workspace,
                    selectingPaper: paperID,
                    selectingMarkdown: markdownID,
                    rootCompatibility: rootCompatibility
                )
                return stagingModel.captureWorkspaceSessionSnapshot()
            }
        } catch {
            if let stagedGraphRepository = stagingModel.graphStore.repository {
                await stagedGraphRepository.close()
            }
            throw error
        }
    }

    func finalizeCommittedWorkspaceLoad(
        _ workspace: ResearchWorkspace,
        replacing snapshot: AppWorkspaceSessionSnapshot
    ) async {
        currentWorkspace = workspace

#if DEBUG
        if uiTestBridgeForceDebugLogging {
            _ = SwiftUIRuntimeWarningCapture.shared.install(rootURL: workspace.rootURL)
        } else {
            SwiftUIRuntimeWarningCapture.shared.stop()
        }
#endif

        if let root = currentResearchRoot {
            observeWorkspaceModuleConfigurationChanges(in: root)
        }
        restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)

        if systemCalendarAccessState.canReadSchedule {
            do {
                try await syncMappedTodos(with: systemScheduleItems, in: workspace)
            } catch {
                recordAppDebugEvent("workspace.schedule_sync_failed", payload: .object([
                    "message": .string(error.localizedDescription)
                ]))
            }
        }

        if let previousGraphRepository = snapshot.graph.repository,
           graphStore.repository.map({ previousGraphRepository !== $0 }) ?? true {
            await previousGraphRepository.close()
        }
    }
}
