import Foundation
import SciStationCore

@main
struct SciStationCoreTestRunner {
    static func main() async {
        do {
            try await CoreVerificationSuite().runAll()
            print("All SciStation core checks passed.")
        } catch {
            fputs("SciStation core check failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CoreVerificationSuite {
    func runAll() async throws {
        try await createWorkspaceInitializesExpectedStructure()
        try await createWorkspaceInitializesResearchRootAndDefaultProject()
        try await projectRegistryCreatesUpdatesAndCollapsesProjects()
        try await openWorkspaceBackfillsMissingStructure()
        try await openLegacyWorkspaceCreatesResearchRootRegistry()
        try await restoreLastWorkspaceClearsMissingBookmark()
        try await workspacePreferencesRoundTrip()
        try librarySortStateSortsPapers()
        try await libraryBulkEditServiceUpdatesSelectedPapers()
        try await markdownSnippetRepositoryLoadsWorkspaceSnippets()
        try await workspaceMaterialRepositoryLoadsOnlyUserMaterials()
        try batchImportInputParserSplitsMultipleIdentifiers()
        try await vscodeBridgePreparesPythonRunTask()
        try citekeyGenerationUsesAuthorYearKeyword()
        try metadataCodecRoundTripKeepsEditableFields()
        try await paperRepositorySaveAndLoadRoundTripsPaper()
        try await paperRepositoryKeepsLegacyRawPapersLoadable()
        try await legacyPaperMigrationPlanDetectsRawPaperConflicts()
        try await legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper()
        try await projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata()
        try await projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML()
        try await paperRepositoryKeepsLegacyProjectMetadataWithoutLinks()
        try await paperRepositoryDeletesPaperDirectory()
        try librarySearchMatchesExtendedMetadata()
        try await paperAnnotationsRepositoryRoundTripsAnnotations()
        try await paperRepositoryLoadsNestedCollectionPapers()
        try await tagRepositoryUpsertsAndDeletesDefinitions()
        try await todoRepositoryCreatesCompletesAndDeletesTodos()
        try identifierParserRecognizesSupportedKinds()
        try metadataProviderBuildsStableLookupURLs()
        try arxivEntryParserExtractsMetadataDraft()
        try inspireMetadataMapperExtractsMetadataDraft()
        try llmRequestBuildsExpectedPayload()
        try paperSummaryPromptBuilderIncludesContext()
        try await llmConfigurationStorePersistsWithoutAPIKey()
        try await llmWritebackServiceKeepsDraftsSeparateFromWiki()
        try agentPlanParserExtractsJSONFromMarkdownFence()
        try agentVisibleResponseExtractorHidesJSONEnvelope()
        try await agentPlannerAcceptsPlainTextConversationResponse()
        try await agentToolExecutorRequiresApprovalForTodoWrites()
        try await agentPaperClassificationToolUpdatesMetadata()
        try await agentPaperReadToolsReturnSectionsAndSearchMatches()
        try await agentWorkspaceSnapshotIncludesProjectContext()
        try await agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault()
        try await agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext()
        try agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext()
        try await agentRunLoggerWritesWorkspaceFiles()
        try await agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory()
        try await agentServiceExecutesApprovedPlan()
        try await agentLoopRunnerCallsReadOnlyToolThenContinues()
        try await agentLoopRunnerPausesForWorkspaceWrite()
        try await agentLoopRunnerStopsAtMaxSteps()
        try await agentLoopRunnerInjectsToolResultMessages()
        try await agentLoopRunnerResumesPendingApproval()
        try await agentLoopRunnerDoesNotRepeatApprovedWriteOnResume()
        try await agentLoopRunnerEditArgumentsRevalidatesBeforeExecution()
        try await agentLoopRunnerSafetyDenyIsFatal()
        try await agentLoopRunnerCachesRepeatedReadOnlyToolCall()
        try await agentLoopRunnerStopsAtContextBudget()
        try await externalAgentRuntimeStreamsLegacyLoopEvents()
        try await fakeExternalRuntimeDrivesAITimelineEvents()
        try await langGraphRuntimePerformsInitializeHandshake()
        try await langGraphRuntimeReplaysGoldenFixtureRunSuccess()
        try await langGraphRuntimeReplaysGoldenFixtureApprovalResume()
        try await langGraphRuntimeRejectsInvalidFixtureSchemaVersion()
        try await langGraphRuntimeCanonicalizesSidecarLocalSequence()
        try await langGraphRuntimeFallsBackWhenInitializeTimesOut()
        try await langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes()
        try await sidecarLLMProxyDisablesProviderNativeToolCalling()
        try await authorizedResourceProviderListsAndReadsDocuments()
        try agentEvidenceRefStableIDMarksStale()
        try await runtimeEventEnvelopeSequencesAreStableAndDeduplicated()
        try agentHumanDecisionActionDecodesLegacyAliases()
        try agentToolRiskUnknownValueDecodesAsExternalSideEffect()
        try runtimeEventEnvelopeUsesExternalTaggedUnion()
        try stableToolResultV1MapsToToolCallCompletedEvent()
        try await mcpGatewayListsAndCallsReadOnlySciStationTools()
        try await mcpGatewayRequiresApprovalForWorkspaceWrites()
        try await p32LegacyPendingCheckpointMigratesToRunDirectory()
        try await persistentLedgerPreventsDuplicateApprovedWriteAfterRestart()
        try await approvalRequestPersistsFingerprintForLedgerResume()
        try await toolHostBuildApprovalRequestHasNoSideEffects()
        try await readOnlyToolNotPausedByGenericPreToolUseReminder()
        try await deterministicSafetyPolicyBlocksSecretPromptBeforeLLM()
        try await hookDenyBlocksSensitivePathWrite()
        try await agentSkillLoaderProgressivelyLoadsMatchingSkill()
        try openAIProviderPayloadIncludesToolChoiceAuto()
        try await agentRunLoggerSkipsDamagedHistoryLines()
        try await agentRunLoggerFiltersProjectConversations()
        try await agentThreadRepositoryGlobalStoreFiltersByWorkspaceID()
        try await agentThreadRepositoryMigratesPerWorkspaceLegacy()
        try await agentThreadRepositoryArchivesAndReadsLegacyThreads()
        try await agentPromptDraftRepositoryPersistsDrafts()
        try agentToolDefinitionsExposePlatformMetadata()
        try agentPermissionRulesEvaluateSafetyDecisions()
        try agentHookEngineEvaluatesLifecycleResults()
        try agentPluginSkillAndMCPModelsValidate()
        try sciAITrackedPresetManifestValidates()
        try sciAIConfigurationBoundaryValidates()
        try await agentSessionEventLoggerAppendsAndReplaysEvents()
        try agentSessionTimelineItemsFilterCurrentSessions()
        try agentPermissionDockSummarizesPolicies()
        try agentHookActivitySummaryReflectsTogglesAndResults()
        try agentMCPServerStatusSummaryParsesProductAndLocal()
        try openAIStreamDeltaParserIgnoresBadChunks()
        try llmProviderV2RequestModelsToolDefinitions()
        try await pdfImportCreatesLibraryMarkdownAndFigures()
        try await minerUAPIConversionCopiesImageAssets()
        try await movePaperToCollectionUpdatesMetadataAndPath()
        try await wikiPageGenerationWritesTemplateAndUpdatesMetadata()
        try await wikiPageGenerationRejectsSilentOverwrite()
        try frontmatterParserParsesArraysAndBody()
        try wikiLinkParserExtractsTargets()
        try backlinkIndexFindsIncomingReferences()
        try await markdownRepositoryLoadsAndSavesDocuments()
    }

    private func createWorkspaceInitializesExpectedStructure() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ResearchWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        try expect(workspace.missingRequiredItems().isEmpty, "Workspace should not miss any required paths after creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.sharedResearchURL.path), "shared_research.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.libraryBibURL.path), "refs/library.bib should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.tagsDefinitionURL.path), "refs/tags.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: ".sci-station").path), ".sci-station should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "refs/csl").path), "refs/csl should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "settings").path), "settings should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.workspacePreferencesURL.path), "workspace_preferences.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.markdownSnippetsURL.path), "markdown_snippets.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "tasks").path), "tasks should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "imports").path), "imports should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.dataURL.path), "data should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.figuresURL.path), "figures should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/todos.yaml").path), "tasks/todos.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/calendar.yaml").path), "tasks/calendar.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/import_history.yaml").path), "imports/import_history.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/failed_imports.yaml").path), "imports/failed_imports.yaml should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/project_overview.md").path), "project_overview.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/core_papers.md").path), "core_papers.md should exist after workspace creation.")
        try expect(FileManager.default.fileExists(atPath: workspace.researchFlowDatabaseURL.path), "researchflow.sqlite should exist after workspace creation.")
    }

    private func openWorkspaceBackfillsMissingStructure() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("BackfillWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true),
            withIntermediateDirectories: true
        )

        let workspace = try await workspaceService.openWorkspace(at: workspaceURL)
        try expect(workspace.missingRequiredItems().isEmpty, "Opening an older workspace should backfill missing paths.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: ".sci-station").path), "Opening should create .sci-station when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "refs/csl").path), "Opening should create refs/csl when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.tagsDefinitionURL.path), "Opening should create refs/tags.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.workspacePreferencesURL.path), "Opening should create workspace_preferences.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.markdownSnippetsURL.path), "Opening should create markdown_snippets.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "tasks").path), "Opening should create tasks when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.directoryURL(for: "imports").path), "Opening should create imports when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.dataURL.path), "Opening should create data when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.figuresURL.path), "Opening should create figures when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "tasks/todos.yaml").path), "Opening should create tasks/todos.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "imports/import_history.yaml").path), "Opening should create imports/import_history.yaml when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/project_overview.md").path), "Opening should create project_overview.md when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: "wiki/projects/core_papers.md").path), "Opening should create core_papers.md when missing.")
        try expect(FileManager.default.fileExists(atPath: workspace.researchFlowDatabaseURL.path), "Opening should create researchflow.sqlite when missing.")
    }

    private func createWorkspaceInitializesResearchRootAndDefaultProject() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ResearchRootWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let registry = try await projectRegistryRepository.load(in: root)
        let defaultProject = try require(registry.projects.first, "Research root should create a default project.")

        try expect(root.missingRequiredItems().isEmpty, "Research root should not miss required root paths after creation.")
        try expect(FileManager.default.fileExists(atPath: root.globalPapersURL.path), "Global paper library directory should exist.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: "settings/agent.yaml").path), "Root agent settings should exist.")
        try expect(registry.lastOpenedProjectID == defaultProject.id, "Default project should become the last opened project.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: defaultProject.relativePath).path), "Default project directory should exist.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: defaultProject.relativePath + "/project.yaml").path), "Default project.yaml should exist.")
    }

    private func projectRegistryCreatesUpdatesAndCollapsesProjects() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("ProjectRegistryWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let createdProject = try await projectRegistryRepository.createProject(
            named: "Dark Matter Simulation",
            description: "Simulation campaign",
            colorHex: "#2A9D8F",
            iconName: "atom",
            in: root
        )

        var editedProject = createdProject
        editedProject.name = "Dark Matter Maps"
        editedProject.description = "Updated project scope"
        editedProject.colorHex = "#E76F51"
        editedProject.iconName = "chart.xyaxis.line"
        let updatedRegistry = try await projectRegistryRepository.updateProject(editedProject, in: root)
        let collapsedRegistry = try await projectRegistryRepository.setProjectCollapsed(createdProject.id, isCollapsed: true, in: root)
        let projectFileContents = try String(contentsOf: root.fileURL(for: createdProject.relativePath + "/project.yaml"), encoding: .utf8)

        try expect(updatedRegistry.projects.contains(where: { $0.id == createdProject.id && $0.name == "Dark Matter Maps" }), "Project registry should persist edited project metadata.")
        try expect(collapsedRegistry.projects.first(where: { $0.id == createdProject.id })?.isCollapsed == true, "Project registry should persist collapsed sidebar state.")
        try expect(projectFileContents.contains("Dark Matter Maps"), "Project yaml should be updated when project metadata changes.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: createdProject.relativePath + "/wiki").path), "Created projects should include a wiki directory.")
    }

    private func openLegacyWorkspaceCreatesResearchRootRegistry() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let projectRegistryRepository = ProjectRegistryRepository()
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore,
            projectRegistryRepository: projectRegistryRepository
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("LegacyWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("refs", isDirectory: true), withIntermediateDirectories: true)
        try "% legacy bibliography\n".write(to: workspaceURL.appendingPathComponent("refs/library.bib", isDirectory: false), atomically: true, encoding: .utf8)

        try expect(ResearchRoot.compatibility(at: workspaceURL) == .legacyWorkspace, "Existing single-workspace markers should be classified as legacy workspace before opening.")
        let workspace = try await workspaceService.openWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let registry = try await projectRegistryRepository.load(in: root)

        try expect(root.missingRequiredItems().isEmpty, "Opening a legacy workspace should backfill root paths.")
        try expect(registry.projects.first?.defaultTags.contains("legacy-workspace") == true, "Legacy workspace default project should record its compatibility tag.")
        try expect(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("raw/papers", isDirectory: true).path), "Legacy raw/papers data should stay in place.")
    }

    private func restoreLastWorkspaceClearsMissingBookmark() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("DeletedWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        _ = try await workspaceService.createWorkspace(at: workspaceURL)
        try FileManager.default.removeItem(at: workspaceURL)

        let restoredWorkspace = await workspaceService.restoreLastWorkspace()
        let restoredBookmarkURL = try await bookmarkStore.restoreBookmarkURL()

        try expect(restoredWorkspace == nil, "Restoring a deleted recent workspace should return nil instead of throwing.")
        try expect(restoredBookmarkURL == nil, "Restoring a deleted recent workspace should clear the stale bookmark.")
    }

    private func workspacePreferencesRoundTrip() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = WorkspacePreferences(
            libraryVisibleColumns: ["title", "tags", "doi"],
            librarySortState: LibrarySortState(field: .year, isAscending: false),
            defaultCollectionPath: "Dark-Matter",
            recentSection: "library"
        )
        preferences.updateLibraryVisibleColumns(from: "title,authors,bibtex")
        preferences.appLanguage = .simplifiedChinese
        preferences.agentChatFontSize = 17
        preferences.minerUCommand = "mineru"
        preferences.minerUAPIBaseURLString = "https://mineru.example.com"
        preferences.minerUAPILanguage = "zh"
        preferences.minerUOverwriteExistingMarkdown = false
        preferences.agentDisabledToolNamesByScope = [
            "project:test-workspace|thread:agent-thread-1": ["create_todo", "write_markdown_plan"]
        ]
        preferences.pinnedAgentThreadIDsByProject = [
            "test-workspace": ["agent-thread-1"]
        ]

        try await repository.save(preferences, in: workspace)
        let loadedPreferences = try await repository.load(in: workspace)

        try expect(loadedPreferences.libraryVisibleColumns == ["title", "authors", "bibtex"], "Workspace preferences should preserve column order.")
        try expect(loadedPreferences.librarySortState == LibrarySortState(field: .year, isAscending: false), "Workspace preferences should preserve Library sort state.")
        try expect(loadedPreferences.defaultCollectionPath == "Dark-Matter", "Workspace preferences should preserve default collection.")
        try expect(loadedPreferences.recentSection == "library", "Workspace preferences should preserve recent section.")
        try expect(loadedPreferences.appLanguage == .simplifiedChinese, "Workspace preferences should preserve app language.")
        try expect(loadedPreferences.agentChatFontSize == 17, "Workspace preferences should preserve AI Lab chat font size.")
        try expect(loadedPreferences.minerUCommand == "mineru", "Workspace preferences should preserve MinerU command.")
        try expect(loadedPreferences.minerUAPIBaseURLString == "https://mineru.example.com", "Workspace preferences should preserve MinerU API base URL.")
        try expect(loadedPreferences.minerUAPILanguage == "zh", "Workspace preferences should preserve MinerU API language.")
        try expect(loadedPreferences.minerUOverwriteExistingMarkdown == false, "Workspace preferences should preserve MinerU overwrite behavior.")
        try expect(loadedPreferences.agentDisabledToolNamesByScope["project:test-workspace|thread:agent-thread-1"] == ["create_todo", "write_markdown_plan"], "Workspace preferences should preserve scoped disabled tools.")
        try expect(loadedPreferences.pinnedAgentThreadIDsByProject["test-workspace"] == ["agent-thread-1"], "Workspace preferences should preserve project-scoped pinned threads.")
    }

    private func libraryBulkEditServiceUpdatesSelectedPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let service = LibraryBulkEditService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LibraryBulkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let firstPaper = try await repository.save(samplePaper(id: "bulk-first"), in: workspace)
        let secondPaper = try await repository.save(samplePaper(id: "bulk-second"), in: workspace)
        let targetIDs: Set<Paper.ID> = [firstPaper.id, secondPaper.id]

        _ = try await service.setStatus(.deepRead, for: targetIDs, in: workspace)
        _ = try await service.setPriority(.urgent, for: targetIDs, in: workspace)
        _ = try await service.setRating(5, for: targetIDs, in: workspace)
        _ = try await service.addTags(["dm", "dm", "capture"], for: targetIDs, in: workspace)
        _ = try await service.removeTags(["graph"], for: targetIDs, in: workspace)

        let loadedPapers = try await repository.loadPapers(in: workspace).filter { targetIDs.contains($0.id) }
        try expect(loadedPapers.count == 2, "Bulk edit should keep both target papers loadable.")
        try expect(loadedPapers.allSatisfy { $0.status == .deepRead }, "Bulk edit should update status for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.priority == .urgent }, "Bulk edit should update priority for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.rating == 5 }, "Bulk edit should update rating for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.tags.contains("dm") && $0.tags.contains("capture") }, "Bulk edit should add tags to all selected papers.")
        try expect(loadedPapers.allSatisfy { Set($0.tags).count == $0.tags.count }, "Bulk edit should not create duplicate tags.")
        try expect(loadedPapers.allSatisfy { !$0.tags.contains("graph") }, "Bulk edit should remove requested tags.")
    }

    private func librarySortStateSortsPapers() throws {
        var older = samplePaper(id: "older")
        older.title = "Beta Paper"
        older.authors = ["Zed Author"]
        older.year = 2020
        older.updatedAt = Date(timeIntervalSince1970: 10)
        older.rating = 2
        older.priority = .low
        older.status = .used

        var newer = samplePaper(id: "newer")
        newer.title = "Alpha Paper"
        newer.authors = ["Amy Author"]
        newer.year = 2024
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        newer.rating = 5
        newer.priority = .urgent
        newer.status = .unread

        let originalOrder = [older, newer]
        try expect(LibrarySortState().sorted(originalOrder).map(\.id) == ["older", "newer"], "Empty Library sort state should preserve original order.")
        try expect(LibrarySortState(field: .title, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Title sort should order papers alphabetically.")
        try expect(LibrarySortState(field: .year, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Year descending sort should put newer papers first.")
        try expect(LibrarySortState(field: .updated, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Updated descending sort should put recently updated papers first.")
        try expect(LibrarySortState(field: .rating, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Rating descending sort should put higher rated papers first.")
        try expect(LibrarySortState(field: .priority, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Priority sort should use reading priority order.")
        try expect(LibrarySortState(field: .status, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Status sort should use reading status order.")
    }

    private func markdownSnippetRepositoryLoadsWorkspaceSnippets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownSnippetRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("SnippetsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let defaultSnippets = try await repository.load(in: workspace)
        try expect(defaultSnippets.contains(where: { $0.trigger == ";eq" }), "Default snippets should include an equation trigger.")

        let customSnippets = """
        snippets:
          - trigger: ";thm"
            title: "Theorem"
            body: |
              **Theorem.** ${cursor}
        """
        try customSnippets.write(to: workspace.markdownSnippetsURL, atomically: true, encoding: .utf8)

        let loadedSnippets = try await repository.load(in: workspace)
        try expect(loadedSnippets == [MarkdownSnippet(trigger: ";thm", title: "Theorem", body: "**Theorem.** ${cursor}")], "Markdown snippet repository should load custom workspace snippets.")
    }

    private func workspaceMaterialRepositoryLoadsOnlyUserMaterials() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspaceMaterialRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MaterialsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        try "print('hello')\n".write(to: workspace.fileURL(for: "code/analysis.py"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: workspace.fileURL(for: "figures/result.png"), options: .atomic)
        try "private\n".write(to: workspace.fileURL(for: "settings/private.txt"), atomically: true, encoding: .utf8)
        try "hidden\n".write(to: workspace.fileURL(for: "code/.scratch.txt"), atomically: true, encoding: .utf8)

        let materials = try await repository.loadMaterials(in: workspace)
        let materialPaths = Set(materials.map(\.relativePath))
        let codeMaterial = try require(materials.first(where: { $0.relativePath == "code/analysis.py" }), "Expected code/analysis.py to be loaded as a material.")

        try expect(materialPaths.contains("code/analysis.py"), "Materials should include user code files.")
        try expect(codeMaterial.kind == .python, "Python files should be classified as Python materials.")
        try expect(materialPaths.contains("figures/result.png"), "Materials should include user figure files.")
        try expect(materialPaths.contains("shared_research.md"), "Materials should include shared research context.")
        try expect(!materialPaths.contains("settings/private.txt"), "Materials should hide settings files.")
        try expect(!materialPaths.contains("code/.scratch.txt"), "Materials should hide dot-prefixed files.")
        try expect(WorkspaceMaterialRepository.isVisibleMaterialPath("code/analysis.py"), "User material paths should be visible.")
        try expect(!WorkspaceMaterialRepository.isVisibleMaterialPath(".sci-station/cache.json"), "Dot-prefixed system paths should be hidden.")
    }

    private func batchImportInputParserSplitsMultipleIdentifiers() throws {
        let parser = BatchImportInputParser()
        let parsedInputs = parser.parse("""
        https://arxiv.org/abs/2401.12345, https://doi.org/10.1234/example
        inspire:2811054; https://example.org/paper.pdf https://arxiv.org/abs/2401.12345
        """)

        try expect(
            parsedInputs == [
                "https://arxiv.org/abs/2401.12345",
                "https://doi.org/10.1234/example",
                "inspire:2811054",
                "https://example.org/paper.pdf"
            ],
            "Batch parser should split common pasted separators and remove duplicates."
        )
    }

    private func vscodeBridgePreparesPythonRunTask() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspaceMaterialRepository()
        let bridgeService = VSCodeBridgeService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("VSCodeBridgeWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pythonURL = workspace.fileURL(for: "code/analysis.py")
        try "print('hello')\n".write(to: pythonURL, atomically: true, encoding: .utf8)

        let materials = try await repository.loadMaterials(in: workspace)
        let material = try require(materials.first(where: { $0.relativePath == "code/analysis.py" }), "Expected Python material for VS Code bridge test.")

        try await bridgeService.preparePythonRunTask(for: material, in: workspace, runtimeMode: .workspaceVenv)

        let tasksText = try String(contentsOf: workspace.fileURL(for: ".vscode/tasks.json"), encoding: .utf8)
        let bridgeText = try String(contentsOf: workspace.fileURL(for: ".sci-station/vscode/last_python_run.json"), encoding: .utf8)

        try expect(tasksText.contains("Sci-Station: Run Python Material"), "VS Code bridge should write a runnable task label.")
        try expect(tasksText.contains("code/analysis.py"), "VS Code bridge should point to the selected Python material.")
        try expect(tasksText.contains(".venv/bin/python"), "VS Code bridge should use the selected workspace venv command.")
        try expect(bridgeText.contains("workspaceVenv"), "VS Code bridge should record the selected runtime mode.")
    }

    private func citekeyGenerationUsesAuthorYearKeyword() throws {
        let citekey = PaperIdentityGenerator.citekey(
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith"],
            year: 2024,
            existing: []
        )

        try expect(citekey == "smith2024graph", "Citekey generation should follow firstAuthorYearKeyword.")
    }

    private func metadataCodecRoundTripKeepsEditableFields() throws {
        let codec = PaperMetadataCodec()
        let createdAt = Date(timeIntervalSince1970: 1_714_176_000)
        let updatedAt = Date(timeIntervalSince1970: 1_714_262_400)
        let originalPaper = Paper(
            id: "smith2024-graph-rag",
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            inspireID: "2811054",
            url: "https://arxiv.org/abs/2401.12345",
            pdfURL: "https://arxiv.org/pdf/2401.12345.pdf",
            abstract: "A graph-based RAG pipeline.",
            categories: ["cs.CL"],
            bibtex: """
            @article{smith2024graph,
                title = {Graph-based Retrieval Augmented Generation},
                author = {John Smith and Alice Wang},
                year = {2024}
            }
            """,
            collectionPath: "Dark-Matter/WIMPs",
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "graph-rag"],
            status: .summarized,
            priority: .high,
            rating: 4,
            useFor: ["related-work", "method-design"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastReadAt: Date(timeIntervalSince1970: 1_714_348_800),
            lastReadPage: 12,
            paperDirectoryRelativePath: "raw/papers/Dark-Matter/WIMPs/smith2024-graph-rag",
            notesSummaryRelativePath: "../../../../../wiki/papers/smith2024graph.md",
            annotationsRelativePath: "annotations.md"
        )

        let encoded = codec.encode(originalPaper)
        let decoded = codec.decode(
            encoded,
            directoryRelativePath: originalPaper.directoryRelativePath,
            fallbackTitle: "Fallback Title",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try expect(decoded.id == originalPaper.id, "Decoded paper id should match the encoded id.")
        try expect(decoded.citekey == originalPaper.citekey, "Decoded citekey should match the encoded citekey.")
        try expect(decoded.title == originalPaper.title, "Decoded title should match the encoded title.")
        try expect(decoded.authors == originalPaper.authors, "Decoded authors should match the encoded authors.")
        try expect(decoded.year == originalPaper.year, "Decoded year should match the encoded year.")
        try expect(decoded.inspireID == originalPaper.inspireID, "Decoded INSPIRE id should match the encoded INSPIRE id.")
        try expect(decoded.pdfURL == originalPaper.pdfURL, "Decoded pdf_url should match the encoded pdf_url.")
        try expect(decoded.abstract == originalPaper.abstract, "Decoded abstract should match the encoded abstract.")
        try expect(decoded.categories == originalPaper.categories, "Decoded categories should match the encoded categories.")
        try expect(decoded.bibtex == originalPaper.bibtex, "Decoded BibTeX should match the encoded BibTeX.")
        try expect(decoded.collectionPath == originalPaper.collectionPath, "Decoded collection_path should match the encoded collection path.")
        try expect(decoded.tags == originalPaper.tags, "Decoded tags should match the encoded tags.")
        try expect(decoded.status == originalPaper.status, "Decoded status should match the encoded status.")
        try expect(decoded.priority == originalPaper.priority, "Decoded priority should match the encoded priority.")
        try expect(decoded.rating == originalPaper.rating, "Decoded rating should match the encoded rating.")
        try expect(decoded.useFor == originalPaper.useFor, "Decoded use_for should match the encoded use_for values.")
        try expect(decoded.lastReadAt == originalPaper.lastReadAt, "Decoded last_read_at should match the encoded reading state.")
        try expect(decoded.lastReadPage == originalPaper.lastReadPage, "Decoded last_page should match the encoded reading progress.")
        try expect(decoded.notesSummaryRelativePath == originalPaper.notesSummaryRelativePath, "Decoded summary path should match the encoded summary path.")
    }

    private func paperRepositorySaveAndLoadRoundTripsPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RepositoryWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = Paper(
            id: "lee2022knowledge-graph-rag",
            citekey: "lee2022knowledge",
            title: "Knowledge Graph Retrieval for RAG",
            authors: ["Min Lee"],
            year: 2022,
            venue: "ACL",
            doi: nil,
            arxiv: nil,
            url: nil,
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "knowledge-graph"],
            status: .skimmed,
            priority: .medium,
            rating: 3,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/lee2022knowledge-graph-rag",
            notesSummaryRelativePath: "../../../../wiki/papers/lee2022knowledge.md",
            annotationsRelativePath: "annotations.md"
        )

        _ = try await repository.save(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)
        let loadedPaper = try require(
            loadedPapers.first(where: { $0.id == paper.id }),
            "Expected repository.loadPapers to return the saved paper."
        )

        try expect(loadedPaper.title == paper.title, "Loaded paper title should match the saved title.")
        try expect(loadedPaper.authors == paper.authors, "Loaded authors should match the saved authors.")
        try expect(loadedPaper.tags == paper.tags, "Loaded tags should match the saved tags.")
        try expect(loadedPaper.status == paper.status, "Loaded status should match the saved status.")
        try expect(loadedPaper.priority == paper.priority, "Loaded priority should match the saved priority.")
        try expect(loadedPaper.rating == paper.rating, "Loaded rating should match the saved rating.")
        try expect(
            loadedPaper.notesSummaryRelativePath == paper.notesSummaryRelativePath,
            "Loaded summary path should match the saved summary path."
        )
        try expect(
            loadedPaper.collectionPath == "Uncategorized",
            "Loaded collection path should be derived from the nested paper directory."
        )
    }

    private func paperRepositoryKeepsLegacyRawPapersLoadable() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyRawPaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var legacyPaper = samplePaper(id: "legacy-raw-paper")
        legacyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-raw-paper"
        legacyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: legacyPaper.citekey,
            paperDirectoryRelativePath: legacyPaper.paperDirectoryRelativePath
        )

        _ = try await repository.save(legacyPaper, in: workspace)
        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == legacyPaper.id }),
            "Expected repository to keep legacy raw/papers metadata loadable."
        )

        try expect(loadedPaper.paperDirectoryRelativePath.hasPrefix("raw/papers/"), "Legacy paper paths should remain in raw/papers.")
        try expect(loadedPaper.collectionPath == "Legacy", "Legacy raw/papers collections should still be derived correctly.")
    }

    private func legacyPaperMigrationPlanDetectsRawPaperConflicts() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationPlanWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let plan = try await migrationService.makePlan(in: workspace)
        let readyItem = try require(
            plan.items.first(where: { $0.paperID == readyPaper.id }),
            "Expected migration plan to include a ready legacy paper."
        )
        let conflictItem = try require(
            plan.items.first(where: { $0.paperID == conflictPaper.id }),
            "Expected migration plan to include a conflicting legacy paper."
        )

        try expect(plan.legacyPaperCount == 2, "Migration plan should count legacy raw/papers metadata files.")
        try expect(plan.readyCount == 1, "Migration plan should count ready-to-copy legacy papers.")
        try expect(plan.conflictCount == 1, "Migration plan should count conflicting legacy papers.")
        try expect(readyItem.status == .readyToCopy, "A legacy paper without a target conflict should be ready to copy.")
        try expect(readyItem.targetRelativePath == "library/papers/Legacy/legacy-ready-paper", "Migration plan should preserve collection paths under library/papers.")
        try expect(conflictItem.status == .conflict, "A legacy paper with a global duplicate should be marked as a conflict.")
        try expect(conflictItem.conflicts.contains(.targetDirectoryExists), "Migration plan should flag existing target directories.")
        try expect(conflictItem.conflicts.contains(.duplicatePaperIDInGlobalLibrary), "Migration plan should flag duplicate global paper ids.")
    }

    private func legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationCopyWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-copy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-copy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-copy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let report = try await migrationService.copyReadyItems(in: workspace)
        let reportRelativePath = try require(report.reportRelativePath, "Migration report should include its relative path.")
        let reportURL = workspace.fileURL(for: reportRelativePath)
        let copiedDirectoryURL = workspace.directoryURL(for: "library/papers/Legacy/legacy-copy-ready-paper")
        let legacyDirectoryURL = workspace.directoryURL(for: "raw/papers/Legacy/legacy-copy-ready-paper")
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        let loadedReadyPapers = loadedPapers.filter { $0.id == readyPaper.id }
        let loadedReadyPaper = try require(loadedReadyPapers.first, "Expected copied paper to be loadable.")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedReport = try decoder.decode(LegacyPaperMigrationReport.self, from: Data(contentsOf: reportURL))

        try expect(report.copiedCount == 1, "Copy migration should copy ready legacy papers.")
        try expect(report.skippedCount == 1, "Copy migration should skip conflicting legacy papers.")
        try expect(report.failedCount == 0, "Copy migration should not fail ready papers in the happy path.")
        try expect(FileManager.default.fileExists(atPath: reportURL.path), "Copy migration should write a JSON report.")
        try expect(decodedReport.items.count == 2, "Written migration report should include every planned legacy item.")
        try expect(FileManager.default.fileExists(atPath: copiedDirectoryURL.path), "Copy migration should create the global library paper directory.")
        try expect(FileManager.default.fileExists(atPath: legacyDirectoryURL.path), "Copy migration should keep the legacy raw/papers directory in place.")
        try expect(loadedReadyPapers.count == 1, "PaperRepository should not return duplicate ids after migration copy.")
        try expect(loadedReadyPaper.paperDirectoryRelativePath == "library/papers/Legacy/legacy-copy-ready-paper", "PaperRepository should prefer the global library copy after migration.")
        try expect(loadedReadyPaper.notesSummaryRelativePath == Paper.summaryRelativePath(for: loadedReadyPaper.citekey, paperDirectoryRelativePath: loadedReadyPaper.paperDirectoryRelativePath), "Copied metadata should be normalized to the new library path.")
    }

    private func projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "linked-paper"), in: workspace)
        try await linkRepository.save([
            ProjectPaperLink(
                projectID: "project-alpha",
                paperID: paper.id,
                isCore: true,
                folderPath: "Project-Folder",
                useFor: ["method-design"],
                isPinned: true,
                sortOrder: 3
            )
        ], in: workspace)

        let loadedLinks = try await linkRepository.links(forPaperID: paper.id, in: workspace)
        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }),
            "Expected project links to overlay loaded paper metadata."
        )

        try expect(loadedLinks.count == 1, "Project-paper link repository should load saved links.")
        try expect(loadedPaper.projectIDs == ["project-alpha"], "Loaded paper should expose project ids from the link repository.")
        try expect(loadedPaper.coreProjectIDs == ["project-alpha"], "Loaded paper should expose core project ids from the link repository.")
        try expect(loadedPaper.folderPath == "Project-Folder", "Loaded paper should expose the project folder from the link repository.")
        try expect(loadedPaper.useFor.contains("method-design"), "Loaded paper should merge project use cases from the link repository.")
        try expect(loadedLinks.first?.isPinned == true, "Project-paper link repository should round-trip pinned state.")
        try expect(loadedLinks.first?.sortOrder == 3, "Project-paper link repository should round-trip sort order.")
    }

    private func projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        try FileManager.default.createDirectory(at: workspace.projectPaperLinksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        links:
          - project_id: "project-alpha"
            paper_id: "paper-alpha"
            is_core: true
            folder_path: "Reading Queue"
            use_for:
              - "background"
            created_at: 2026-04-29T00:00:00Z
            updated_at: 2026-04-29T00:00:00Z
        """.write(to: workspace.projectPaperLinksURL, atomically: true, encoding: .utf8)

        let legacyLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected legacy project-paper link YAML to load without pin/order fields."
        )
        try expect(legacyLink.isPinned == false, "Legacy project-paper links should default to unpinned.")
        try expect(legacyLink.sortOrder == nil, "Legacy project-paper links should default to no explicit sort order.")

        let pinnedLink = try await linkRepository.setPinned(true, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let orderedLink = try await linkRepository.updateSortOrder(2, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let useForLink = try await linkRepository.updateUseFor(["method", "method", "comparison"], projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let folderLink = try await linkRepository.updateFolderPath("  Methods/Core  ", projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        _ = try await linkRepository.setCore(false, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)

        let editedLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected single-link edit APIs to keep the edited link loadable."
        )
        let encodedYAML = try String(contentsOf: workspace.projectPaperLinksURL, encoding: .utf8)

        try expect(pinnedLink.isPinned, "setPinned should return the updated pinned link.")
        try expect(orderedLink.sortOrder == 2, "updateSortOrder should return the updated sort order.")
        try expect(useForLink.useFor == ["method", "comparison"], "updateUseFor should normalize duplicate project usage values.")
        try expect(folderLink.folderPath == "Methods/Core", "updateFolderPath should trim project folder paths.")
        try expect(editedLink.isCore == false, "setCore should update the existing link.")
        try expect(editedLink.isPinned == true, "Edited link should persist pinned state.")
        try expect(editedLink.sortOrder == 2, "Edited link should persist sort order.")
        try expect(encodedYAML.contains("is_pinned: true"), "Encoded project-paper links should include pinned state.")
        try expect(encodedYAML.contains("sort_order: 2"), "Encoded project-paper links should include sort order.")

        let remainingLinks = try await linkRepository.remove(projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let removedLink = try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace)
        try expect(remainingLinks.isEmpty, "Removing a project-paper link should return no remaining links for that paper.")
        try expect(removedLink == nil, "Removed project-paper link should not load again.")
    }

    private func paperRepositoryKeepsLegacyProjectMetadataWithoutLinks() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let paperRepository = PaperRepository(projectPaperLinkRepository: linkRepository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyProjectMetadataWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "legacy-project-paper")
        paper.projectIDs = ["legacy-project"]
        paper.coreProjectIDs = ["legacy-project"]

        let savedPaper = try await paperRepository.save(paper, in: workspace)
        try await linkRepository.save([], in: workspace)

        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected legacy project metadata paper to remain loadable without relationship links."
        )

        try expect(loadedPaper.projectIDs == ["legacy-project"], "Legacy project_ids metadata should still bridge when no relationship links exist.")
        try expect(loadedPaper.coreProjectIDs == ["legacy-project"], "Legacy core_project_ids metadata should still bridge when no relationship links exist.")
    }

    private func paperRepositoryDeletesPaperDirectory() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("DeletePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "delete-test-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)

        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Saved paper directory should exist before deletion.")

        try await repository.delete(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)

        try expect(!FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Deleting a paper should remove its paper directory.")
        try expect(loadedPapers.isEmpty, "Deleted papers should no longer appear in repository loads.")
    }

    private func librarySearchMatchesExtendedMetadata() throws {
        var paper = samplePaper(id: "search-paper")
        paper.doi = "10.1234/searchable"
        paper.abstract = "This abstract discusses solar capture."
        paper.bibtex = """
        @article{smith2024graph,
          title = {Graph RAG},
          keyword = {neutrino telescope}
        }
        """

        let service = LibrarySearchService()

        try expect(service.matches(paper, query: "10.1234"), "Library search should match DOI.")
        try expect(service.matches(paper, query: "solar capture"), "Library search should match abstracts.")
        try expect(service.matches(paper, query: "neutrino telescope"), "Library search should match BibTeX contents.")
        try expect(service.matchingIDs(in: [paper], query: "2401.12345") == [paper.id], "Library search should return matching paper ids.")
    }

    private func paperAnnotationsRepositoryRoundTripsAnnotations() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let annotationsRepository = PaperAnnotationsRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AnnotationsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "annotations-paper"), in: workspace)
        try await annotationsRepository.saveAnnotations("# Notes\n\nImportant reading note.", for: paper, in: workspace)
        let loadedAnnotations = try await annotationsRepository.loadAnnotations(for: paper, in: workspace)

        try expect(loadedAnnotations.contains("Important reading note."), "Paper annotations repository should round-trip annotations.md contents.")
    }

    private func paperRepositoryLoadsNestedCollectionPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("NestedCollectionsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let nestedPaper = Paper(
            id: "garani2024dark",
            citekey: "garani2024dark",
            title: "Dark Matter Capture Review",
            authors: ["Jakob Garani"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["dark-matter"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Dark-Matter/Solar-Capture/garani2024dark",
            notesSummaryRelativePath: "../../../../../wiki/papers/garani2024dark.md",
            annotationsRelativePath: "annotations.md"
        )

        let savedPaper = try await repository.save(nestedPaper, in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: savedPaper.paperDirectoryRelativePath)
        let pdfURL = paperDirectoryURL.appendingPathComponent("paper.pdf")
        try Data("fake pdf".utf8).write(to: pdfURL, options: .atomic)
        let metadataURL = paperDirectoryURL.appendingPathComponent("meta.yaml")
        let staleMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
            .replacingOccurrences(of: "collection_path: \"Dark-Matter/Solar-Capture\"", with: "collection_path: \"Old-Folder\"")
        try staleMetadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected repository to find meta.yaml inside nested collection folders."
        )

        try expect(
            loadedPaper.paperDirectoryRelativePath == nestedPaper.paperDirectoryRelativePath,
            "Repository should preserve nested paper directory paths."
        )
        try expect(
            loadedPaper.collectionPath == "Dark-Matter/Solar-Capture",
            "Repository should derive the full nested collection path from the directory layout."
        )
    }

    private func tagRepositoryUpsertsAndDeletesDefinitions() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TagRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TagWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#B57EDC", textColorHex: "#4A235A"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Experiment", colorHex: "#85C1E9", textColorHex: "#154360"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#C39BD3", textColorHex: "#45235A"),
            in: workspace
        )

        let savedDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(savedDefinitions.count == 2, "Upserting a tag twice should replace the existing definition instead of duplicating it.")
        try expect(savedDefinitions.first(where: { $0.name == "Theory" })?.colorHex == "#C39BD3", "Upsert should update an existing tag color.")

        try await repository.deleteTag(named: "Experiment", in: workspace)
        let remainingDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(remainingDefinitions.map(\.name) == ["Theory"], "Deleting a tag should remove it from refs/tags.yaml.")
    }

    private func todoRepositoryCreatesCompletesAndDeletesTodos() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TodoRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TodoWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let todo = TodoItem(
            id: "todo-001",
            title: "Read dark matter capture review",
            status: .open,
            dueDate: Date(timeIntervalSince1970: 1_777_680_000),
            priority: .urgent,
            projectIDs: ["project-alpha"],
            tags: ["Dark-Matter"],
            relatedPaperIDs: ["garani2024dark"],
            notes: "Check bibliography and equations.",
            externalSource: "apple_reminders",
            externalIdentifier: "reminder-abc",
            externalUpdatedAt: Date(timeIntervalSince1970: 1_777_600_000),
            completedAt: nil,
            dueTime: "09:30",
            createdAt: Date(timeIntervalSince1970: 1_777_593_600),
            updatedAt: Date(timeIntervalSince1970: 1_777_593_600)
        )

        try await repository.upsert(todo, in: workspace)

        var savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.count == 1, "Saving a todo should persist it to tasks/todos.yaml.")
        try expect(savedTodos.first?.priority == .urgent, "Todo repository should preserve priority.")
        try expect(savedTodos.first?.projectIDs == ["project-alpha"], "Todo repository should preserve project ids.")
        try expect(savedTodos.first?.notes == "Check bibliography and equations.", "Todo repository should preserve notes.")
        try expect(savedTodos.first?.relatedPaperIDs == ["garani2024dark"], "Todo repository should preserve related paper ids.")
        try expect(savedTodos.first?.externalSource == "apple_reminders", "Todo repository should preserve external source.")
        try expect(savedTodos.first?.externalIdentifier == "reminder-abc", "Todo repository should preserve external identifier.")
        try expect(savedTodos.first?.dueTime == "09:30", "Todo repository should preserve due time.")

        var completedTodo = try require(savedTodos.first, "Expected the saved todo to be loadable.")
        completedTodo.status = .done
        completedTodo.updatedAt = Date(timeIntervalSince1970: 1_777_680_000)
        try await repository.upsert(completedTodo, in: workspace)

        savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.first?.status == .done, "Updating a todo should replace the stored todo instead of duplicating it.")

        try await repository.delete(todoID: todo.id, in: workspace)
        let remainingTodos = try await repository.loadTodos(in: workspace)
        try expect(remainingTodos.isEmpty, "Deleting a todo should remove it from tasks/todos.yaml.")

                let legacyContents = """
                todos:
                    - id: "legacy-todo"
                        title: "Legacy task"
                        status: open
                        due:
                        priority: medium
                        tags: []
                        related_papers: []
                        created: 2026-04-28
                        updated: 2026-04-28
                """
                try legacyContents.write(to: workspace.fileURL(for: "tasks/todos.yaml"), atomically: true, encoding: .utf8)
                let legacyTodos = try await repository.loadTodos(in: workspace)
                try expect(legacyTodos.first?.projectIDs == [], "Todo repository should treat legacy todos without project_ids as unassigned.")
    }

        private func identifierParserRecognizesSupportedKinds() throws {
                let parser = IdentifierParser()

                try expect(parser.parse("2401.12345").kind == .arxiv, "Parser should recognize bare arXiv ids.")
                try expect(parser.parse("arXiv:2604.22012").normalizedValue == "2604.22012", "Parser should normalize prefixed arXiv ids.")
                try expect(parser.parse("arXiv 2604.22012").normalizedValue == "2604.22012", "Parser should normalize arXiv ids with a space prefix.")
                try expect(parser.parse("https://arxiv.org/abs/2401.12345").normalizedValue == "2401.12345", "Parser should normalize arXiv URLs to ids.")
                try expect(parser.parse("10.48550/arXiv.2401.12345").kind == .doi, "Parser should recognize DOI inputs.")
                try expect(parser.parse("https://doi.org/10.48550/arXiv.2604.22012").kind == .doi, "Parser should recognize doi.org arXiv DOI links as DOI inputs.")
                try expect(parser.extractArxivID(from: "10.48550/arXiv.2604.22012") == "2604.22012", "Parser should detect arXiv ids embedded in arXiv DOI strings.")
                try expect(parser.parse("https://inspirehep.net/literature/2811054").kind == .inspire, "Parser should recognize INSPIRE literature URLs.")
                try expect(parser.parse("https://example.com/paper.pdf").kind == .pdfURL, "Parser should recognize PDF URLs.")
                try expect(parser.parse("https://example.com/article").kind == .url, "Parser should recognize normal web URLs.")
        }

            private func metadataProviderBuildsStableLookupURLs() throws {
                let arxivURL = try ArxivMetadataProvider.apiURL(for: "2604.22012")
                let arxivComponents = try require(URLComponents(url: arxivURL, resolvingAgainstBaseURL: false), "Expected arXiv lookup URL components.")
                let arxivQueryItems = arxivComponents.queryItems ?? []

                try expect(arxivComponents.host == "export.arxiv.org", "arXiv lookup should use the export API host.")
                try expect(arxivComponents.path == "/api/query", "arXiv lookup should target the API query path.")
                try expect(arxivQueryItems.first(where: { $0.name == "search_query" })?.value == "id:2604.22012", "arXiv lookup should preserve id: search queries.")

                let doiURL = try DOIMetadataProvider.crossrefWorksURL(for: "10.48550/arXiv.2604.22012")
                try expect(
                    doiURL.absoluteString == "https://api.crossref.org/works/10.48550%2FarXiv.2604.22012",
                    "Crossref lookup should percent-encode DOI path separators."
                )
            }

        private func arxivEntryParserExtractsMetadataDraft() throws {
                let parser = ArxivEntryParser()
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <feed xmlns="http://www.w3.org/2005/Atom">
                    <entry>
                        <id>https://arxiv.org/abs/2401.12345v1</id>
                        <updated>2024-01-20T00:00:00Z</updated>
                        <published>2024-01-10T00:00:00Z</published>
                        <title> Dark Matter Capture Review </title>
                        <summary> Overview of dark matter capture. </summary>
                        <author><name>Jane Doe</name><arxiv:affiliation>Example Institute</arxiv:affiliation></author>
                        <author><name>John Roe</name></author>
                        <link href="https://arxiv.org/abs/2401.12345v1" rel="alternate" type="text/html"/>
                        <link href="https://arxiv.org/pdf/2401.12345v1.pdf" rel="related" type="application/pdf" title="pdf"/>
                        <category term="hep-ph"/>
                    </entry>
                </feed>
                """

                let draft = try parser.parse(Data(xml.utf8))
                try expect(draft.title == "Dark Matter Capture Review", "arXiv parser should trim entry titles.")
                try expect(draft.authors == ["Jane Doe", "John Roe"], "arXiv parser should extract author names.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345v1.pdf", "arXiv parser should extract pdf links.")
                try expect(draft.categories == ["hep-ph"], "arXiv parser should extract category terms.")
        }

        private func inspireMetadataMapperExtractsMetadataDraft() throws {
                let mapper = InspireMetadataMapper()
                let json = """
                {
                    "metadata": {
                        "titles": [{"title": "Solar Dark Matter Limits"}],
                        "abstracts": [{"value": "An INSPIRE abstract."}],
                        "authors": [{"full_name": "Alice Smith"}],
                        "arxiv_eprints": [{"value": "2401.12345"}],
                        "dois": [{"value": "10.1234/example"}],
                        "documents": [{"url": "https://example.com/paper.pdf"}],
                        "publication_info": [{"year": 2024}],
                        "inspire_categories": [{"term": "Phenomenology"}]
                    }
                }
                """

                let draft = try mapper.map(data: Data(json.utf8), recordID: "2811054")
                try expect(draft.title == "Solar Dark Matter Limits", "INSPIRE mapper should extract titles.")
                try expect(draft.arxiv == "2401.12345", "INSPIRE mapper should extract linked arXiv ids.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345.pdf", "INSPIRE mapper should prefer arXiv PDF links when available.")
                try expect(draft.inspireID == "2811054", "INSPIRE mapper should preserve the record id.")
        }

            private func llmRequestBuildsExpectedPayload() throws {
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(
                    provider: .openAICompatible,
                    baseURLString: "https://api.example.com/v1",
                    model: "test-model",
                    temperature: 0.3,
                    maxTokens: 256
                )

                let request = try provider.buildRequest(configuration: configuration, apiKey: "secret-key", prompt: "Summarize this paper")
                let body = try require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected request body to be encoded.")
                try expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions", "Provider should target /chat/completions on the configured base URL.")
                try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key", "Provider should attach the API key as a bearer token.")
                try expect(body.contains("test-model"), "Provider request body should contain the configured model.")
                try expect(body.contains("Summarize this paper"), "Provider request body should contain the prompt content.")
            }

            private func llmConfigurationStorePersistsWithoutAPIKey() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let store = LLMConfigurationStore()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMSettingsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                try await store.save(
                    LLMConfiguration(
                        provider: .openAICompatible,
                        baseURLString: "https://api.example.com/v1",
                        model: "gpt-4.1-mini",
                        temperature: 0.2,
                        maxTokens: 1200
                    ),
                    in: workspace
                )

                let settingsContents = try String(contentsOf: workspace.fileURL(for: "settings.yaml"), encoding: .utf8)
                try expect(settingsContents.contains("base_url"), "LLM settings should be written to settings.yaml.")
                try expect(!settingsContents.lowercased().contains("api_key"), "API keys must not be written into settings.yaml.")
            }

            private func paperSummaryPromptBuilderIncludesContext() throws {
                var paper = samplePaper(id: "summary-context-paper")
                paper.doi = "10.1234/example"
                paper.abstract = "A compact abstract for testing prompt context."
                paper.tags = ["dark-matter", "review"]

                let prompt = PaperSummaryPromptBuilder().buildPrompt(
                    for: paper,
                    rawMarkdown: "# Raw Text\n\nImportant equation and method details.",
                    annotations: "# Annotations\n\nCheck the simulation setup.",
                    existingWiki: "# Existing Wiki\n\nPrior manual notes."
                )

                try expect(prompt.contains("10.1234/example"), "Prompt should include DOI metadata.")
                try expect(prompt.contains("Important equation and method details."), "Prompt should include raw markdown or extracted text.")
                try expect(prompt.contains("Check the simulation setup."), "Prompt should include annotations.")
                try expect(prompt.contains("Prior manual notes."), "Prompt should include existing wiki content.")
                try expect(prompt.contains("不要编造"), "Prompt should explicitly forbid invented claims.")
            }

            private func llmWritebackServiceKeepsDraftsSeparateFromWiki() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let service = LLMWritebackService()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMWritebackWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = samplePaper(id: "writeback-paper")
                let wikiURL = workspace.fileURL(for: "wiki/papers/\(paper.citekey).md")
                try "# Original Wiki\n\nManual note.".write(to: wikiURL, atomically: true, encoding: .utf8)

                let firstDraft = try await service.write("Draft summary", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let secondDraft = try await service.write("Second draft", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let wikiAfterDraft = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(!firstDraft.didModifyWiki, "Saving a draft should report that the canonical wiki page was not modified.")
                try expect(firstDraft.writtenURL != secondDraft.writtenURL, "Multiple draft saves should not overwrite older drafts.")
                try expect(wikiAfterDraft == "# Original Wiki\n\nManual note.", "Saving a draft should leave the canonical wiki page unchanged.")

                let appendResult = try await service.write("Appended summary", to: wikiURL, mode: .append, paper: paper, in: workspace)
                let appendedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(appendResult.didModifyWiki, "Appending should report that the canonical wiki page was modified.")
                try expect(appendedWiki.contains("## AI Summary"), "Append mode should add an AI Summary section.")
                try expect(appendedWiki.contains("Appended summary"), "Append mode should write generated content.")

                let replaceResult = try await service.write("Replacement summary", to: wikiURL, mode: .replace, paper: paper, in: workspace)
                let replacedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(replaceResult.didModifyWiki, "Replace should report that the canonical wiki page was modified.")
                try expect(replacedWiki == "Replacement summary", "Replace mode should replace the canonical wiki content.")
            }

            private func agentPlanParserExtractsJSONFromMarkdownFence() throws {
                let response = """
                ```json
                {
                  "summary": "Create a todo",
                  "tool_calls": [
                    {
                      "id": "call-1",
                      "tool_name": "create_todo",
                      "arguments_json": "{\\\"title\\\":\\\"Read the selected paper\\\"}"
                    }
                  ],
                  "final_response_draft": "Ready for approval."
                }
                ```
                """

                let plan = try AgentPlanParser().parse(response)

                try expect(plan.summary == "Create a todo", "Agent plan parser should decode the summary.")
                try expect(plan.toolCalls.first?.toolName == "create_todo", "Agent plan parser should decode tool calls.")
                try expect(plan.toolCalls.first?.argumentsJSON.contains("Read the selected paper") == true, "Agent plan parser should preserve encoded tool arguments.")
            }

            private func agentVisibleResponseExtractorHidesJSONEnvelope() throws {
                let jsonResponse = """
                {
                    "summary": "Internal summary",
                    "tool_calls": [],
                    "final_response_draft": "只显示这一段。"
                }
                """

                let visibleText = AgentVisibleResponseExtractor.visibleText(from: jsonResponse)
                let partialJSON = "{\"summary\": \"still streaming"
                let plainText = "普通 Markdown 回复"

                try expect(visibleText == "只显示这一段。", "Visible response extractor should return final_response_draft from JSON envelopes.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: partialJSON).isEmpty, "Visible response extractor should hide partial JSON while it is still streaming.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: plainText) == plainText, "Visible response extractor should preserve plain text responses.")
            }

            private func agentPlannerAcceptsPlainTextConversationResponse() async throws {
                let provider = StaticLLMProvider(response: "你好，我可以用 **Markdown** 回答。")
                let planner = AgentPlanner(provider: provider)
                let plan = try await planner.plan(
                    goal: "请用中文介绍当前项目",
                    workspaceSnapshot: AgentWorkspaceSnapshot(
                        workspaceName: "Test_Workspace",
                        selectedPaper: nil,
                        recentPapers: [],
                        openTodos: [],
                        paperCount: 0,
                        todoCount: 0
                    ),
                    tools: [],
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    modeInstructions: AgentInteractionMode.conversation.plannerInstructions,
                    allowsPlainTextResponse: true
                )

                try expect(plan.toolCalls.isEmpty, "Plain text conversation fallback should not create tool calls.")
                try expect(plan.finalResponseDraft?.contains("Markdown") == true, "Plain text conversation fallback should preserve the assistant response.")
            }

            private func agentToolExecutorRequiresApprovalForTodoWrites() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let todoRepository = TodoRepository()
                let registry = AgentToolRegistry(tools: [CreateTodoAgentTool(todoRepository: todoRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentTodoWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let plan = AgentPlan(
                    summary: "Create a follow-up todo",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Check agent framework\",\"priority\":\"high\",\"tags\":[\"agent\"]}"
                        )
                    ]
                )
                let context = AgentToolContext(workspace: workspace, selectedPaperID: "paper-001", currentProjectID: "project-alpha")

                let blockedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: [])
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(blockedResults.first?.requiresConfirmation == true, "Workspace-writing agent tools should require approval before execution.")
                try expect(todosBeforeApproval.isEmpty, "Unapproved agent tool calls should not modify todos.")

                let approvedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: ["call-1"])
                let todosAfterApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedResults.first?.succeeded == true, "Approved todo tool call should succeed.")
                try expect(approvedResults.first?.callID == "call-1", "Agent tool results should retain the originating call id.")
                try expect(todosAfterApproval.first?.title == "Check agent framework", "Approved todo tool call should persist a todo.")
                try expect(todosAfterApproval.first?.relatedPaperIDs == ["paper-001"], "Todo tool should link to the selected paper when no explicit related_paper_ids are provided.")
                try expect(todosAfterApproval.first?.projectIDs == ["project-alpha"], "Todo tool should default to the current project when project_ids are omitted.")
            }

            private func agentPaperClassificationToolUpdatesMetadata() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let registry = AgentToolRegistry(tools: [UpdatePaperClassificationAgentTool(paperRepository: paperRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await paperRepository.save(samplePaper(id: "agent-paper"), in: workspace)
                let plan = AgentPlan(
                    summary: "Classify selected paper",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "update_paper_classification",
                            argumentsJSON: "{\"tags\":[\"simulation\",\"dark-matter\"],\"categories\":[\"methods\"],\"mark_core_in_current_project\":true,\"priority\":\"urgent\",\"status\":\"skimmed\"}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: paper.id, currentProjectID: "project-alpha"),
                    approvedToolCallIDs: ["call-1"]
                )
                let updatedPaper = try require(try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }), "Expected updated paper to be loadable.")

                try expect(results.first?.succeeded == true, "Approved classification tool call should succeed.")
                try expect(updatedPaper.tags.contains("simulation"), "Classification tool should merge new tags.")
                try expect(updatedPaper.categories.contains("methods"), "Classification tool should merge new categories.")
                try expect(updatedPaper.projectIDs.contains("project-alpha"), "Classification tool should add the selected paper to the current project when requested.")
                try expect(updatedPaper.coreProjectIDs.contains("project-alpha"), "Classification tool should mark the selected paper as core in the current project when requested.")
                try expect(updatedPaper.priority == .urgent, "Classification tool should update priority.")
                try expect(updatedPaper.status == .skimmed, "Classification tool should update reading status.")
            }

            private func agentPaperReadToolsReturnSectionsAndSearchMatches() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperReadToolsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                var paper = samplePaper(id: "agent-readable-paper")
                paper.title = "Evaporation Rate Reference"
                paper.tags = ["dm"]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let markdown = """
                # Evaporation Rate Reference

                ## 1 Overview

                This section introduces the model.

                ## 5 Evaporation Rate

                The evaporation rate marker is E_sun_section_marker.

                $$
                E_{\\odot} = \\sum_i \\int s(r) n_\\chi(r) 4\\pi r^2 dr
                $$

                ## Appendix

                Extra material.
                """
                try markdown.write(to: savedPaper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let registry = AgentToolRegistry(tools: [
                    ListPapersAgentTool(paperRepository: paperRepository),
                    ReadPaperSectionAgentTool(paperRepository: paperRepository),
                    SearchPapersAgentTool(paperRepository: paperRepository)
                ])
                let executor = AgentToolExecutor(registry: registry)
                let plan = AgentPlan(
                    summary: "Read paper sections",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-section",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"5 Evaporation Rate\"}"
                        ),
                        AgentToolCall(
                            id: "call-search",
                            toolName: "search_papers",
                            argumentsJSON: "{\"query\":\"E_sun_section_marker\",\"paper_ids\":[\"\(savedPaper.id)\"]}"
                        ),
                        AgentToolCall(
                            id: "call-list",
                            toolName: "list_papers",
                            argumentsJSON: "{\"query\":\"Evaporation\"}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: savedPaper.id),
                    approvedToolCallIDs: []
                )
                let definitions = await SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}")
                ).toolDefinitions()
                let definitionNames = Set(definitions.map(\.name))

                try expect(results.allSatisfy(\.succeeded), "Read-only paper tools should run without approval.")
                try expect(results.first(where: { $0.callID == "call-section" })?.message.contains("E_sun_section_marker") == true, "read_paper_section should return the requested heading content.")
                try expect(results.first(where: { $0.callID == "call-search" })?.message.contains("#L") == true, "search_papers should return line-anchored matches.")
                try expect(results.first(where: { $0.callID == "call-list" })?.message.contains(savedPaper.id) == true, "list_papers should expose matching paper ids.")
                try expect(definitionNames.isSuperset(of: ["list_papers", "read_paper", "read_paper_section", "search_papers"]), "Default agent tool registry should expose paper read/search tools.")
            }

            private func agentWorkspaceSnapshotIncludesProjectContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let paperRepository = PaperRepository()
                let todoRepository = TodoRepository()
                let contextBuilder = AgentWorkspaceContextBuilder(
                    paperRepository: paperRepository,
                    todoRepository: todoRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for agent context.")
                var paper = samplePaper(id: "agent-project-paper")
                paper.projectIDs = [project.id]
                paper.coreProjectIDs = [project.id]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let todo = TodoItem(
                    id: "todo-agent-project",
                    title: "Read project paper",
                    status: .open,
                    dueDate: nil,
                    priority: .high,
                    projectIDs: [project.id],
                    tags: ["agent"],
                    relatedPaperIDs: [savedPaper.id],
                    notes: nil,
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
                )
                try await todoRepository.upsert(todo, in: workspace)

                let snapshot = try await contextBuilder.snapshot(
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    selectedPaperID: savedPaper.id
                )

                try expect(snapshot.rootName == root.displayName, "Agent snapshot should include the research root name.")
                try expect(snapshot.currentProjectID == project.id, "Agent snapshot should include current project id.")
                try expect(snapshot.currentProject?.paperCount == 1, "Agent snapshot should include current project paper count.")
                try expect(snapshot.projectPapers.map(\.id) == [savedPaper.id], "Agent snapshot should include project-associated papers.")
                try expect(snapshot.projectOpenTodos.map(\.id) == [todo.id], "Agent snapshot should include current project open todos.")
                try expect(snapshot.paperLibraryRelativePath == Paper.globalLibraryRootRelativePath, "Agent snapshot should advertise the global paper library path.")
            }

            private func agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentMetadataOnlyContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "metadata-only-paper"), in: workspace)
                let marker = "metadata_only_snapshot_should_not_embed_this_marker"
                try ("# Metadata Only Paper\n\n## Hidden Body\n\n\(marker)")
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    selectedPaperID: paper.id,
                    includedPaperIDs: [paper.id],
                    paperLimit: 5
                )
                let selectedPaper = try require(snapshot.selectedPaper, "Selected paper should be present in the snapshot.")
                let recentPaper = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Recent paper should be present in the snapshot.")
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "Explain the hidden body marker.",
                    workspaceSnapshot: snapshot,
                    tools: []
                )

                try expect(selectedPaper.sourceExcerpt == nil, "Default selected paper snapshot should not embed paper.md text.")
                try expect(recentPaper.sourceExcerpt == nil, "Default recent paper snapshot should not embed paper.md text.")
                try expect(recentPaper.rawMarkdownRelativePath?.hasSuffix("/paper.md") == true, "Metadata-only paper snapshots should still advertise converted paper.md paths.")
                try expect(!prompt.contains(marker), "Agent prompt should not contain paper markdown body text by default.")
            }

            private func agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLongPaperContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "long-context-paper"), in: workspace)
                let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
                try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)

                let earlyText = String(repeating: "Early context sentence for old cutoff testing.\n", count: 320)
                let deepMarker = "Section 5 evaporation-rate formula marker: E_sun_deep_context"
                try ("---\ntype: paper_raw_markdown\n---\n\n" + earlyText + "\n## 5 Evaporation Rate\n\n" + deepMarker)
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    includedPaperIDs: [paper.id],
                    paperContextPolicy: .legacyExcerpts,
                    paperLimit: 5
                )
                let paperSnapshot = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Included knowledge paper should be present in the snapshot.")
                try expect(paperSnapshot.sourceExcerpt?.contains(deepMarker) == true, "Legacy excerpt policy should preserve deeper Markdown sections beyond 10k characters.")
            }

            private func agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext() throws {
                var paper = samplePaper(id: "prompt-metadata-paper")
                paper.title = "Prompt Metadata Paper"
                let paperSnapshot = AgentPaperSnapshot(
                    paper: paper,
                    rawMarkdownRelativePath: "papers/prompt-metadata-paper/paper.md"
                )
                let snapshot = AgentWorkspaceSnapshot(
                    workspaceName: "Prompt Workspace",
                    selectedPaper: paperSnapshot,
                    recentPapers: [paperSnapshot],
                    openTodos: [],
                    paperCount: 1,
                    todoCount: 0
                )
                let paperRepository = PaperRepository()
                let tools = [
                    SearchPapersAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperSectionAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperAgentTool(paperRepository: paperRepository).definition
                ]
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "解释这篇论文第 5 节的公式。",
                    workspaceSnapshot: snapshot,
                    tools: tools
                )

                try expect(prompt.contains("Paper snapshots are metadata-first"), "Prompt should explain metadata-first paper snapshots.")
                try expect(prompt.contains("plan paper tool calls before answering"), "Prompt should direct the model to call paper tools before detailed answers.")
                try expect(prompt.contains("Prefer `search_papers`"), "Prompt should guide search_papers usage.")
                try expect(prompt.contains("Prefer `read_paper_section`"), "Prompt should guide read_paper_section usage.")
            }

            private func agentRunLoggerWritesWorkspaceFiles() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLogWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let run = AgentRun(
                    id: "agent-run-test",
                    goal: "Plan a todo",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: []
                )
                try await AgentRunLogger().append(run, in: workspace)
                let logContents = try String(contentsOf: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)
                try expect(logContents.contains("agent-run-test"), "Agent run logger should append JSONL entries.")
            }

            private func agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServicePlanWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for service agent tests.")
                let provider = StaticLLMProvider(
                    response: """
                    {
                      "title": "Todo plan",
                      "summary": "Create a project follow-up todo.",
                      "risk": "Writes one todo after approval.",
                      "steps": ["Review current project context", "Create one todo after approval"],
                      "tool_calls": [
                        {
                          "id": "call-1",
                          "tool_name": "create_todo",
                          "arguments_json": "{\\\"title\\\":\\\"Review agent plan\\\"}"
                        }
                      ],
                      "final_response_draft": "Ready for approval."
                    }
                    """
                )
                let service = SciStationAgentService(provider: provider)

                let run = try await service.run(
                    goal: "Create a project todo",
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    options: AgentExecutionOptions(mode: .planOnly)
                )
                let history = try await service.recentRuns(in: root, limit: 5)
                let logContents = try String(contentsOf: root.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)

                try expect(run.mode == .planOnly, "Agent service should support plan-only runs.")
                try expect(run.currentProjectID == project.id, "Plan-only run should record the current project id.")
                try expect(run.plan.title == "Todo plan", "Agent plan should decode the optional title field.")
                try expect(run.plan.steps.count == 2, "Agent plan should decode ordered steps.")
                try expect(history.first?.id == run.id, "Agent service should read recent run history with newest entries first.")
                try expect(logContents.contains(project.id), "Agent run log should include current_project_id.")
                let sessionEvents = try await service.sessionEvents(in: root, sessionID: run.id)
                try expect(sessionEvents.map(\.kind).contains(.permissionRequested), "Plan-only runs should append permission request session events for requested tools.")
            }

            private func agentServiceExecutesApprovedPlan() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let todoRepository = TodoRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServiceExecuteWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for approved execution tests.")
                let service = SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}"),
                    todoRepository: todoRepository
                )
                let plan = AgentPlan(
                    title: "Approved todo",
                    summary: "Create a todo after approval",
                    risk: "Writes tasks/todos.yaml",
                    steps: ["Create the approved todo"],
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Approved agent todo\",\"priority\":\"high\"}"
                        )
                    ]
                )

                let skippedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: []
                )
                try expect(skippedRun.toolResults.first?.requiresConfirmation == true, "Unapproved writing tools should be skipped with a confirmation result.")
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(todosBeforeApproval.isEmpty, "Unapproved service execution should not modify todos.")

                let approvedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: ["call-1"]
                )
                let todos = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedRun.mode == .executeApproved, "Approved execution should be logged as executeApproved.")
                try expect(approvedRun.toolResults.first?.succeeded == true, "Approved service tool execution should succeed.")
                try expect(todos.first?.title == "Approved agent todo", "Approved service tool execution should persist the todo.")
                try expect(todos.first?.projectIDs == [project.id], "Approved service tool execution should use the current project context.")
                let executionEvents = try await service.sessionEvents(in: root, sessionID: approvedRun.id)
                try expect(executionEvents.map(\.kind).contains(.toolCallCompleted), "Approved execution should append completed tool session events.")
            }

            private func agentLoopRunnerCallsReadOnlyToolThenContinues() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadOnlyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "最终回答包含 $E_{\\odot}$."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "section 5 says E_sun_section_marker")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-only",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-read-only")

                try expect(result.finalResponseMarkdown?.contains("E_{\\odot}") == true, "Loop should continue after a read-only tool and return the final assistant message.")
                try expect(result.toolResults.first?.message.contains("E_sun_section_marker") == true, "Loop should preserve read-only tool output.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Read-only tool should execute once.")
                try expect(events.map(\.kind).contains(.toolCallStarted), "Loop should append tool start events.")
                try expect(events.map(\.kind).contains(.toolCallCompleted), "Loop should append tool completion events.")
            }

            private func agentLoopRunnerPausesForWorkspaceWrite() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopWritePauseWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-write-pause",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let pending = try await AgentLoopCheckpointStore().pending(runID: "loop-write-pause", in: fixture.root)
                let events = try await logger.events(in: fixture.root, sessionID: "loop-write-pause")

                try expect(result.pauseReason?.kind == .approvalRequired, "Workspace writes should pause for approval.")
                try expect(result.pendingToolCall?.toolCall.toolName == "create_todo", "Paused result should include the pending tool call.")
                try expect(pending?.toolCall.id == "call-write", "Pending write tool call should be saved as a checkpoint.")
                try expect(events.map(\.kind).contains(.permissionRequested), "Loop should append a permissionRequested event.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Write tool must not run before approval.")
            }

            private func agentLoopRunnerStopsAtMaxSteps() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopMaxStepsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-repeat", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "same result")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-max-steps",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 2)
                ))

                try expect(result.pauseReason?.kind == .maxStepsExceeded, "Loop should stop when maxSteps is exceeded.")
            }

            private func agentLoopRunnerInjectsToolResultMessages() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopInjectsToolResultWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-inject", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Final"))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Injected evidence")
                ])
                let runner = AgentLoopRunner()

                _ = try await runner.run(loopRequest(
                    runID: "loop-inject",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let requests = await provider.recordedRequests()
                let secondRequestMessages = try require(requests.dropFirst().first?.messages, "Expected a second model request.")
                let toolMessage = try require(secondRequestMessages.first { $0.role == .tool }, "Second request should include a tool result message.")

                try expect(toolMessage.toolCallID == "call-inject", "Tool result message should preserve tool_call_id.")
                try expect(toolMessage.content.contains("schema_version"), "Tool result message should be stable JSON.")
                try expect(toolMessage.content.contains("Injected evidence"), "Tool result message should include tool content.")
            }

            private func agentLoopRunnerResumesPendingApproval() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopResumeWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Resume\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Created after approval."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-resume", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let resumed = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .allowOnce,
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(resumed.finalResponseMarkdown?.contains("approval") == true, "Approved pending call should continue to a final assistant message.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Approved write should execute exactly once.")
            }

            private func agentLoopRunnerDoesNotRepeatApprovedWriteOnResume() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopNoRepeatWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"No repeat\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done once.")),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done twice."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created once", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-no-repeat", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Write ledger should prevent repeat execution for an already approved fingerprint.")
            }

            private func agentLoopRunnerEditArgumentsRevalidatesBeforeExecution() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEditArgsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Original\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created edited")
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-edit-args", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let edited = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .editArguments,
                    editedArgumentsJSON: "{\"title\":\"Edited\"}",
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(edited.pauseReason?.kind == .approvalRequired, "Edited write arguments should be revalidated and return to approval instead of executing directly.")
                try expect(edited.pendingToolCall?.toolCall.argumentsJSON.contains("Edited") == true, "Edited arguments should be normalized into the new pending call.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Edited arguments should not execute before the fresh approval pass.")
            }

            private func agentLoopRunnerSafetyDenyIsFatal() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopSafetyDenyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-danger", toolName: "write_note", argumentsJSON: "{\"command\":\"git reset --hard\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "write_note", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "write_note", succeeded: true, message: "Should not run")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-safety-deny",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                try expect(result.pauseReason?.kind == .safetyPolicyBlocked, "Deterministic safety deny should stop the run.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Safety-denied tools should never execute.")
            }

            private func agentLoopRunnerCachesRepeatedReadOnlyToolCall() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadCacheWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let firstCall = AgentToolCall(id: "call-read-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let secondCall = AgentToolCall(id: "call-read-2", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [firstCall, secondCall]), toolCalls: [firstCall, secondCall]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Cached final."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Cached once")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-cache",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Repeated read-only fingerprint should reuse cache in the same run.")
                try expect(result.steps.first?.cachedToolCallIDs == Optional(["call-read-2"]), "Loop step should record cached read-only call ids.")
            }

            private func agentLoopRunnerStopsAtContextBudget() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopContextBudgetWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-large", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly, maxOutputCharacters: 2_000)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: String(repeating: "x", count: 1_600))
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-context-budget",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 4, maxAccumulatedToolResultCharacters: 1_000)
                ))

                try expect(result.pauseReason?.kind == .contextLimitExceeded, "Loop should stop when accumulated tool result budget is exceeded.")
            }

    private func externalAgentRuntimeStreamsLegacyLoopEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyRuntimeEventWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-runtime-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Runtime final."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let registry = AgentToolRegistry(tools: [
            RecordingAgentTool(definition: definition, results: [
                AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Runtime evidence")
            ])
        ])
        let runtime = LegacySwiftAgentRuntime()
        let stream = try await runtime.startRun(AgentRuntimeRequest(
            runID: "legacy-runtime-run",
            goal: "Runtime test goal",
            initialMessages: [LLMChatMessage(role: .user, content: "Read context")],
            provider: provider,
            toolDefinitions: [definition],
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        ))

        var envelopes: [AgentRuntimeEventEnvelope] = []
        for try await envelope in stream {
            envelopes.append(envelope)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "legacy-runtime-run", in: fixture.root)

        try expect(envelopes.contains { if case .runStarted = $0.event { return true }; return false }, "Legacy runtime should stream runStarted.")
        try expect(envelopes.contains { if case .toolCallRequested = $0.event { return true }; return false }, "Legacy runtime should map loop tool calls to runtime events.")
        try expect(envelopes.contains { if case .toolCallCompleted = $0.event { return true }; return false }, "Legacy runtime should map stable tool results to runtime events.")
        try expect(envelopes.contains { if case .finalResponse = $0.event { return true }; return false }, "Legacy runtime should stream finalResponse.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Persisted runtime events should use stable per-run host sequence.")
    }

    private func fakeExternalRuntimeDrivesAITimelineEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "FakeRuntimeTimelineWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = FakeExternalAgentRuntime(scriptedEvents: [
            .runStarted(AgentRunStarted(goal: "Fake timeline")),
            .approvalRequired(AgentApprovalRequest(runID: "fake-runtime-run", toolCallID: "fake-write", toolName: "write_markdown_plan", permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey, risk: .writesWorkspace, argumentsJSON: "{}", targetPaths: ["wiki/plans/fake.md"])),
            .finalResponse(AgentFinalResponse(markdown: "Fake done."))
        ])
        let provider = ScriptedChatProvider(responses: [])
        let request = AgentRuntimeRequest(
            runID: "fake-runtime-run",
            goal: "Fake timeline",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )

        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.contains { if case .approvalRequired = $0 { return true }; return false }, "Fake runtime should be able to drive approval timeline state.")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Fake runtime should be able to drive final response timeline state.")
    }

    private func langGraphRuntimePerformsInitializeHandshake() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphHandshakeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let request = sidecarRuntimeRequest(runID: "langgraph-handshake-run", fixture: fixture)
        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count >= 4, "LangGraph sidecar handshake should allow the run to emit lifecycle and runtime events.")
        try expect(events.contains { if case .sidecarStarting = $0 { return true }; return false }, "LangGraph runtime should emit sidecarStarting before initialize.")
        try expect(events.contains { if case .sidecarReady = $0 { return true }; return false }, "LangGraph runtime should emit sidecarReady after initialize/health.")
    }

    private func langGraphRuntimeReplaysGoldenFixtureRunSuccess() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphGoldenSuccessWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-success-run", goal: "精读 demo paper", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-success-run", in: fixture.root)

        try expect(events.contains { if case .runStarted = $0 { return true }; return false }, "Golden fixture should replay runStarted.")
        try expect(events.contains { if case .toolCallRequested = $0 { return true }; return false }, "Golden fixture should replay tool_call_requested.")
        try expect(events.contains { if case .artifactDraft = $0 { return true }; return false }, "Golden fixture should replay artifact_draft. Saw: \(events.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Golden fixture should replay final_response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "LangGraph runtime should persist host-canonical sequences for golden fixture replay.")
    }

    private func langGraphRuntimeReplaysGoldenFixtureApprovalResume() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphApprovalResumeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "write_markdown_plan", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "write_markdown_plan", succeeded: true, message: "Swift wrote the paper note once.", modifiedPaths: ["wiki/papers/demo-paper.md"])
        ])
        let runtime = sidecarRuntime(fixtureName: "run_approval_then_resume.jsonl")
        let request = sidecarRuntimeRequest(
            runID: "langgraph-approval-run",
            fixture: fixture,
            definitions: [definition],
            registry: AgentToolRegistry(tools: [tool])
        )
        let stream = try await runtime.startRun(request)
        var startEvents: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            startEvents.append(envelope.event)
        }

        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-approval-run", in: fixture.root)
        try expect(startEvents.contains { if case .approvalRequired = $0 { return true }; return false }, "Approval fixture should pause with approvalRequired. Saw: \(startEvents.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(pending?.approvalRequest.id == "approval-demo-write", "LangGraph runtime should persist sidecar approval as a run-directory checkpoint.")

        try await runtime.resumeRun(runID: "langgraph-approval-run", decision: AgentHumanDecision(action: .allowOnce))
        let invocationCount = await tool.invocationCount()
        let records = try await AgentRunDirectoryStore().toolCallRecords(runID: "langgraph-approval-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-approval-run", in: fixture.root)

        try expect(invocationCount == 1, "Allow once should execute the Swift-owned write exactly once.")
        try expect(records.contains { $0.status == .completed && $0.toolCallID == "call-write-note" }, "Approved sidecar write should be recorded in the persistent ledger.")
        try expect(persisted.contains { if case .finalResponse = $0.event { return true }; return false }, "agent.resume should persist the fixture final response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Approval/resume fixture should keep host-canonical sequences after resume.")
    }

    private func langGraphRuntimeRejectsInvalidFixtureSchemaVersion() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphInvalidSchemaWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "invalid_schema_version.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-invalid-schema-run", fixture: fixture))
        do {
            for try await _ in stream {}
            throw ValidationError(message: "Invalid sidecar event schema version should fail the runtime stream.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.message.contains("schema version"), "Invalid schema version should report a schema error.")
        }
    }

    private func langGraphRuntimeCanonicalizesSidecarLocalSequence() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphSequenceWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-sequence-run", fixture: fixture))
        for try await _ in stream {}
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-sequence-run", in: fixture.root)
        let eventIDs = persisted.map(\.id)

        try expect(eventIDs.contains("evt-fixture-success-node-load"), "Sequence test should include fixture events with intentionally shuffled local sequences.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Swift host should canonicalize sidecar local sequences to a stable per-run sequence.")
    }

    private func langGraphRuntimeFallsBackWhenInitializeTimesOut() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphTimeoutWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "handshake_timeout.jsonl", handshakeTimeout: 0.2)
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-timeout-run", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count == 3, "Handshake timeout without fallback runtime should emit only fixed lifecycle fallback events.")
        try expect(events[0].isSidecarStarting, "Handshake timeout should start with sidecarStarting.")
        try expect(events[1].isSidecarUnavailable, "Handshake timeout should emit sidecarUnavailable.")
        try expect(events[2].isFallbackToLegacyRuntime, "Handshake timeout should emit fallbackToLegacyRuntime.")
    }

    private func langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphCrashApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "sidecar_crash_after_approval.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-crash-run", fixture: fixture))
        for try await _ in stream {}
        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-crash-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-crash-run", in: fixture.root)

        try expect(pending?.approvalRequest.id == "approval-crash-write", "Sidecar crash after approval should not lose the pending approval checkpoint.")
        try expect(persisted.contains { if case .checkpointSaved = $0.event { return true }; return false }, "Crash fixture should persist checkpointSaved before the crash.")
    }

    private func sidecarLLMProxyDisablesProviderNativeToolCalling() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SidecarLLMProxyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "LLM proxy response."))
        ])
        let request = AgentRuntimeRequest(
            runID: "llm-proxy-run",
            goal: "LLM proxy",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
        let sidecarRequest = SidecarLLMRespondRequest(
            messages: [LLMChatMessage(role: .user, content: "Summarize.")],
            tools: [LLMToolSpecification(name: "read_note", description: "Read", inputSchemaJSON: "{}")],
            toolCallPolicy: .disabled,
            modelOptions: ["temperature": .number("0.1")]
        )
        _ = try await SidecarLLMProxy().respond(params: try SidecarJSONCodec.jsonValue(from: sidecarRequest), runtimeRequest: request)
        let recorded = await provider.recordedRequests()

        try expect(recorded.count == 1, "LLMProxy should call the Swift provider once.")
        try expect(recorded.first?.tools.isEmpty == true, "toolCallPolicy disabled should strip provider-native tool specifications.")
    }

    private func authorizedResourceProviderListsAndReadsDocuments() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AuthorizedResourcesWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/demo-paper/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nThis paper studies evaporation rate evidence.\n# Method\nThe method is line anchored.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let provider = AgentAuthorizedResourceProvider()
        let documents = try await provider.listIndexableDocuments(in: fixture.root)
        let snapshot = try require(documents.first(where: { $0.relativePath == "library/papers/demo-paper/paper.md" }), "Authorized resources should include converted paper.md.")
        let response = try await provider.read(AuthorizedResourceReadRequest(resourceID: snapshot.resourceID, maxBytes: 1_048_576, maxCharacters: 24), in: fixture.root)

        try expect(snapshot.sourceType == "paper", "paper.md should be classified as paper source type.")
        try expect(response.contentHash == snapshot.contentHash, "resources/read should return the snapshot content hash.")
        try expect(response.truncated, "resources/read should mark content truncated when maxCharacters is exceeded.")
    }

    private func agentEvidenceRefStableIDMarksStale() throws {
        let first = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let second = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let changed = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:b")

        try expect(first.id == second.id, "AgentEvidenceRef should generate stable ids for the same source line range and hash.")
        try expect(first.id != changed.id, "Changing source_hash should change the stable evidence id.")
        try expect(first.isStale(currentSourceHash: "sha256:b"), "Evidence should be stale when current source hash changes.")
    }

    private func runtimeEventEnvelopeSequencesAreStableAndDeduplicated() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeEventDedupeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        let first = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 1, event: .runStarted(AgentRunStarted(goal: "Deduplicate")))
        let duplicate = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 99, event: .runStarted(AgentRunStarted(goal: "Duplicate")))
        let second = AgentRuntimeEventEnvelope(id: "evt-dedupe-2", runID: "dedupe-run", sequence: 2, event: .finalResponse(AgentFinalResponse(markdown: "Done")))

        try await store.appendEvent(first, in: fixture.root)
        try await store.appendEvent(duplicate, in: fixture.root)
        try await store.appendEvent(second, in: fixture.root)
        let events = try await store.eventEnvelopes(runID: "dedupe-run", in: fixture.root)
        let nextSequence = try await store.nextSequence(runID: "dedupe-run", in: fixture.root)

        try expect(events.map(\.id) == ["evt-dedupe", "evt-dedupe-2"], "Run directory should ignore duplicate runtime event ids.")
        try expect(events.map(\.sequence) == [1, 2], "Deduplicated events should preserve committed host sequence.")
        try expect(nextSequence == 3, "nextSequence should continue after the latest committed event.")
    }

    private func agentHumanDecisionActionDecodesLegacyAliases() throws {
        let decoder = JSONDecoder()
        let deny = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""deny""#.utf8))
        let revise = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""askAgentToRevise""#.utf8))

        try expect(deny == .denyAndStop, "Legacy deny action should decode to denyAndStop.")
        try expect(revise == .reviseWithFeedback, "Legacy askAgentToRevise action should decode to reviseWithFeedback.")
    }

    private func agentToolRiskUnknownValueDecodesAsExternalSideEffect() throws {
        let decoded = try JSONDecoder().decode(AgentToolRisk.self, from: Data(#""unknownFutureRisk""#.utf8))

        try expect(decoded == .externalSideEffect, "Unknown tool risk values should decode to externalSideEffect.")
    }

    private func runtimeEventEnvelopeUsesExternalTaggedUnion() throws {
        let result = AgentToolResult(callID: "call-runtime", toolName: "read_note", succeeded: true, message: "Runtime evidence")
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: "call-runtime")
        let envelope = AgentRuntimeEventEnvelope(
            id: "evt-runtime",
            runID: "run-runtime",
            sequence: 7,
            timestamp: Date(timeIntervalSince1970: 0),
            event: .toolCallCompleted(AgentToolCallCompleted(tool: "read_note", toolCallID: "call-runtime", result: wireResult))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let encoded = String(data: data, encoding: .utf8) ?? ""
        let decoded = try AgentRunDirectoryStore.decoder().decode(AgentRuntimeEventEnvelope.self, from: data)

        try expect(encoded.contains(#""type":"tool_call_completed""#), "Runtime events should encode as event.type.")
        try expect(encoded.contains(#""payload""#), "Runtime events should encode payload alongside type.")
        if case let .toolCallCompleted(payload) = decoded.event {
            try expect(payload.result.schemaVersion == 1, "Decoded tool completion event should preserve the V1 tool result.")
        } else {
            throw ValidationError(message: "Decoded runtime event should be toolCallCompleted.")
        }
    }

    private func stableToolResultV1MapsToToolCallCompletedEvent() throws {
        let result = AgentToolResult(
            callID: "call-stable",
            toolName: "write_note",
            succeeded: true,
            message: "Created a note for audit.",
            modifiedPaths: ["wiki/notes/audit.md"]
        )
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: "call-stable")
        let json = try wireResult.stableJSON()
        let decoded = try AgentRunDirectoryStore.decoder().decode(AgentToolResultWireFormat.self, from: Data(json.utf8))
        let completed = AgentToolCallCompleted(tool: "write_note", toolCallID: "call-stable", result: wireResult)

        try expect(json.contains(#""schema_version":1"#), "Stable tool result JSON should include schema_version 1.")
        try expect(decoded.modifiedPaths == ["wiki/notes/audit.md"], "Stable tool result JSON should preserve modified paths.")
        try expect(completed.result.agentToolResult().modifiedPaths == ["wiki/notes/audit.md"], "Runtime tool completion should embed the stable tool result V1 payload.")
    }

    private func mcpGatewayListsAndCallsReadOnlySciStationTools() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPReadOnlyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "MCP evidence")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let listResponse = await gateway.handle(AgentMCPEnvelope(id: "mcp-list", method: "tools/list"), context: context)
        let listResult = try jsonObject(listResponse.result, "tools/list should return a JSON object.")
        let tools = try jsonArray(listResult["tools"], "tools/list should return tools array.")
        let toolObjects = try tools.map { try jsonObject($0, "Each listed MCP tool should be an object.") }

        let readOnlyTool = try require(
            toolObjects.first { object in
                object["name"]?.stringValue == "read_note"
                    && object["risk"]?.stringValue == AgentToolRisk.readOnly.rawValue
            },
            "MCP tools/list should expose the read_note tool."
        )
        let annotations = try jsonObject(readOnlyTool["annotations"], "MCP tool annotations should be an object.")
        try expect(annotations["readOnly"] == .bool(true), "MCP tools/list should expose read-only annotations.")

        let callResponse = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-read",
                method: "tools/call",
                params: .object([
                    "name": .string("read_note"),
                    "arguments": .object(["path": .string("paper.md")])
                ])
            ),
            context: context
        )
        let callResult = try jsonObject(callResponse.result, "Read-only tools/call should return a JSON object.")
        let invocationCount = await tool.invocationCount()

        try expect(callResponse.error == nil, "Read-only MCP tool call should not return JSON-RPC error.")
        try expect(callResult["structuredContent"] != nil, "Read-only MCP tool call should return structuredContent.")
        try expect(callResult["content"] != nil, "Read-only MCP tool call should return content array.")
        try expect(invocationCount == 1, "Read-only MCP tool call should invoke the tool once.")
    }

    private func mcpGatewayRequiresApprovalForWorkspaceWrites() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPWriteApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should wait for approval")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let response = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-write",
                method: "tools/call",
                params: .object([
                    "name": .string("create_todo"),
                    "arguments": .object(["title": .string("Review gateway approval")])
                ])
            ),
            context: context,
            runID: "mcp-write-run"
        )
        let result = try jsonObject(response.result, "Write tools/call should return a JSON object.")
        let approval = try jsonObject(result["approvalRequest"], "Approval-required MCP response should include approvalRequest.")
        let targetPaths = try jsonArray(approval["target_paths"], "Approval request should include target paths.").compactMap(\.stringValue)
        let invocationCount = await tool.invocationCount()

        try expect(response.error == nil, "Approval-required MCP tool call should be a normal result, not JSON-RPC error.")
        try expect(result["status"]?.stringValue == "approval_required", "Write MCP tool call should return approval_required status.")
        try expect(approval["fingerprint"]?.stringValue?.hasPrefix("sha256:") == true, "Approval request should carry an idempotency fingerprint.")
        try expect(targetPaths == ["tasks/todos.yaml"], "ToolHost should preview create_todo target path for MCP approval.")
        try expect(invocationCount == 0, "Write MCP tool call must not invoke the tool before approval.")
    }

    private func p32LegacyPendingCheckpointMigratesToRunDirectory() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyPendingMigrationWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "legacy-call", toolName: "write_note", argumentsJSON: #"{"path":"wiki/legacy.md"}"#)
        let approval = AgentApprovalRequest(
            runID: "legacy-run",
            toolCallID: call.id,
            toolName: call.toolName,
            permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey,
            risk: .writesWorkspace,
            argumentsJSON: call.argumentsJSON,
            targetPaths: ["wiki/legacy.md"]
        )
        let pending = AgentPendingToolCall(
            runID: "legacy-run",
            stepIndex: 3,
            toolCall: call,
            approvalRequest: approval,
            messagesBeforePause: [LLMChatMessage(role: .user, content: "Legacy pending")]
        )
        let checkpointStore = AgentLoopCheckpointStore()
        try await checkpointStore.saveLegacyFallback(pending, in: fixture.root)

        let migrated = try await checkpointStore.pending(runID: "legacy-run", in: fixture.root)
        let runDirectoryPending = try await AgentRunDirectoryStore().pending(runID: "legacy-run", in: fixture.root)

        try expect(migrated?.toolCall.id == "legacy-call", "Legacy pending call should remain readable.")
        try expect(runDirectoryPending?.toolCall.id == "legacy-call", "Reading legacy pending call should migrate it into the run directory checkpoint.")
    }

    private func persistentLedgerPreventsDuplicateApprovedWriteAfterRestart() async throws {
        let fixture = try await loopWorkspaceFixture(named: "PersistentLedgerWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-ledger-write", toolName: "create_todo", argumentsJSON: #"{"title":"Ledger once"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Created once."))
        ])
        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let firstTool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created once", modifiedPaths: ["tasks/todos.yaml"])
        ])
        let firstRegistry = AgentToolRegistry(tools: [firstTool])
        let firstRunner = AgentLoopRunner()
        let paused = try await firstRunner.run(loopRequest(runID: "ledger-run", provider: provider, definitions: [definition], registry: firstRegistry, fixture: fixture))
        let pending = try require(paused.pendingToolCall, "Expected ledger write to pause for approval.")

        _ = try await firstRunner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: firstRegistry, fixture: fixture))
        let firstInvocationCount = await firstTool.invocationCount()

        let secondTool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should not run", modifiedPaths: ["tasks/todos.yaml"])
        ])
        let secondProvider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Loaded from ledger."))
        ])
        let secondRunner = AgentLoopRunner()
        _ = try await secondRunner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: secondProvider, definitions: [definition], registry: AgentToolRegistry(tools: [secondTool]), fixture: fixture))
        let secondInvocationCount = await secondTool.invocationCount()
        let records = try await AgentRunDirectoryStore().toolCallRecords(runID: "ledger-run", in: fixture.root)

        try expect(firstInvocationCount == 1, "First approved write should execute once.")
        try expect(secondInvocationCount == 0, "A restarted runner should reuse the persistent ledger result instead of re-invoking the approved write.")
        try expect(records.contains(where: { $0.status == .completed && $0.toolCallID == "call-ledger-write" }), "Persistent ledger should record the completed write call.")
    }

    private func approvalRequestPersistsFingerprintForLedgerResume() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ApprovalFingerprintWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-approval-fingerprint", toolName: "create_todo", argumentsJSON: #"{"title":"Fingerprint"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
        ])
        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "approval-fingerprint-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture))
        let pending = try require(result.pendingToolCall, "Expected write call to pause for approval.")
        let storedPending = try await AgentRunDirectoryStore().pending(runID: "approval-fingerprint-run", in: fixture.root)
        let checkpointURL = fixture.root.fileURL(for: AgentRunDirectoryStore.runsRelativePath + "/approval-fingerprint-run/checkpoint.json")
        let checkpointText = try String(contentsOf: checkpointURL, encoding: .utf8)

        try expect(pending.approvalRequest.fingerprint.hasPrefix("sha256:"), "Approval request should include a stable fingerprint.")
        try expect(storedPending?.approvalRequest.fingerprint == pending.approvalRequest.fingerprint, "Run directory checkpoint should persist the approval fingerprint.")
        try expect(checkpointText.contains(pending.approvalRequest.fingerprint), "Checkpoint JSON should contain the approval fingerprint for resume/ledger use.")
    }

    private func toolHostBuildApprovalRequestHasNoSideEffects() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ToolHostPreviewWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should not run")
        ])
        let host = SciStationToolHost(legacyRegistry: AgentToolRegistry(tools: [tool]))
        let approval = try await host.buildApprovalRequest(
            for: AgentToolCall(id: "call-preview", toolName: "create_todo", argumentsJSON: #"{"title":"Preview only"}"#),
            runID: "preview-run",
            context: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)
        )
        let invocationCount = await tool.invocationCount()

        try expect(invocationCount == 0, "Building a ToolHost approval preview must not invoke the tool.")
        try expect(approval.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include expected target paths.")
        try expect(approval.diffPreview?.contains("Preview only") == true, "ToolHost approval preview should include a human-readable diff summary.")
        try expect(approval.rollbackHint?.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include rollback targets.")
    }

    private func readOnlyToolNotPausedByGenericPreToolUseReminder() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ReadOnlyHookReminderWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-read-reminder", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Read with reminder."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Reminder did not pause")
        ])
        let hookEngine = AgentHookEngine(hooks: [
            AgentHookDefinition(id: "pre-tool-reminder", eventName: .preToolUse, matcher: "*", message: "Audit read-only tool output.")
        ])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "read-reminder-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture, hookEngine: hookEngine))
        let invocationCount = await tool.invocationCount()

        try expect(result.pauseReason == nil, "Generic PreToolUse reminders without deny should not pause read-only tools.")
        try expect(result.finalResponseMarkdown == "Read with reminder.", "Loop should continue to final response after read-only tool reminder.")
        try expect(invocationCount == 1, "Read-only tool should still execute once with a reminder hook.")
    }

    private func deterministicSafetyPolicyBlocksSecretPromptBeforeLLM() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SecretPromptBlockWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Should not be called"))
        ])
        let runner = AgentLoopRunner()

        do {
            _ = try await runner.run(loopRequest(
                runID: "secret-prompt-run",
                goal: "Please use sk-1234567890abcdef for this request.",
                provider: provider,
                definitions: [definition],
                registry: AgentToolRegistry(tools: []),
                fixture: fixture
            ))
            throw ValidationError(message: "Secret-looking prompt should be blocked before model submission.")
        } catch AgentError.invalidArguments(let message) {
            try expect(message.contains("secret"), "Secret prompt denial should explain that a secret was detected.")
        }

        let requests = await provider.recordedRequests()
        try expect(requests.isEmpty, "Prompt safety block should happen before any LLM request is sent.")
    }

    private func hookDenyBlocksSensitivePathWrite() async throws {
        let fixture = try await loopWorkspaceFixture(named: "HookSensitivePathWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-hook-deny", toolName: "write_note", argumentsJSON: #"{"path":"workspace/secrets.txt"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
        ])
        let definition = loopToolDefinition(name: "write_note", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "write_note", succeeded: true, message: "Should not run")
        ])
        let hookEngine = AgentHookEngine(hooks: [
            AgentHookDefinition(id: "deny-secrets-path", eventName: .preToolUse, matcher: "secrets", permissionDecision: .deny, message: "blocked by hook")
        ])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "hook-deny-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture, hookEngine: hookEngine))
        let invocationCount = await tool.invocationCount()

        try expect(result.pauseReason?.kind == .safetyPolicyBlocked, "PreToolUse deny hook should block sensitive path writes.")
        try expect(result.pauseReason?.message.contains("blocked by hook") == true, "Hook denial message should be surfaced in the pause reason.")
        try expect(invocationCount == 0, "Hook-denied write tools should not execute.")
    }

    private func agentSkillLoaderProgressivelyLoadsMatchingSkill() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let skillDirectory = rootURL.appendingPathComponent(".claude/skills/paper-reading", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory.appendingPathComponent("references", isDirectory: true), withIntermediateDirectories: true)
        try "Checklist".write(to: skillDirectory.appendingPathComponent("references/checklist.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: paper-reading
        description: Paper evidence review
        version: 1.0.0
        author: Sci-Station
        capabilities: [paper, evidence]
        risk: readOnly
        allowed_tools: [read_paper, search_wiki]
        ---

        Use evidence before drafting conclusions.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let metadata = try await loader.loadMetadata(searchRoots: [rootURL.appendingPathComponent(".claude/skills", isDirectory: true)])
        let selected = try await loader.selectSkills(for: "Please do paper evidence review", from: metadata)

        try expect(metadata.first?.trustLevel == .untrusted, "Workspace skill metadata should default to untrusted.")
        try expect(metadata.first?.allowedTools == ["read_paper", "search_wiki"], "Skill metadata should expose allowed tools without loading the body.")
        try expect(selected.first?.body?.contains("Use evidence") == true, "Matching skills should load the body on selection.")
        try expect(selected.first?.resources == ["references/checklist.md"], "Matching skills should disclose adjacent resources on selection.")
    }

            private func openAIProviderPayloadIncludesToolChoiceAuto() throws {
                let provider = OpenAICompatibleProvider()
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Use tools."),
                        LLMChatMessage(role: .assistant, content: "", toolCalls: [
                            AgentToolCall(id: "call-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                        ]),
                        LLMChatMessage(role: .tool, content: "{\"schema_version\":1}", name: "read_note", toolCallID: "call-1")
                    ],
                    tools: [LLMToolSpecification(agentTool: definition)]
                )
                let chatRequest = try provider.buildChatRequest(
                    configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                    apiKey: "secret-key",
                    providerRequest: request
                )
                let body = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected chat body.")

                try expect(body.contains("tool_choice"), "Provider payload should include tool_choice when tools are present.")
                try expect(body.contains("auto"), "Provider payload should set tool_choice to auto.")
                try expect(body.contains("tool_calls"), "Assistant messages should serialize tool_calls.")
                try expect(body.contains("tool_call_id"), "Tool result messages should serialize tool_call_id.")
            }

            private func agentRunLoggerSkipsDamagedHistoryLines() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDamagedHistoryWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let firstRun = AgentRun(
                    id: "agent-run-valid-1",
                    goal: "First valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-alpha"
                )
                let secondRun = AgentRun(
                    id: "agent-run-valid-2",
                    goal: "Second valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                    mode: .executeApproved,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-beta"
                )

                try await logger.append(firstRun, in: root)
                let logURL = root.fileURL(for: ".sci-station/agent/runs.jsonl")
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondRun, in: root)

                let history = try await logger.recentRuns(in: root, limit: 5)
                try expect(history.map(\.id) == ["agent-run-valid-2", "agent-run-valid-1"], "Damaged JSONL lines should be skipped while valid runs remain readable newest-first.")
            }

            private func agentRunLoggerFiltersProjectConversations() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectConversationWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let runs = [
                    AgentRun(
                        id: "global-run",
                        goal: "Global conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Global", toolCalls: []),
                        toolResults: []
                    ),
                    AgentRun(
                        id: "alpha-run",
                        goal: "Alpha conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Alpha", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-alpha"
                    ),
                    AgentRun(
                        id: "beta-run",
                        goal: "Beta conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_020),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_021),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Beta", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-beta"
                    )
                ]

                for run in runs {
                    try await logger.append(run, in: root)
                }

                let alphaRuns = try await logger.recentRuns(in: root, projectID: "project-alpha", limit: 5)
                let globalRuns = try await logger.recentRuns(in: root, projectID: nil, limit: 5)

                try expect(alphaRuns.map(\.id) == ["alpha-run"], "Project conversation history should only include runs for that project.")
                try expect(globalRuns.map(\.id) == ["global-run"], "Global conversation history should only include runs without a project id.")
            }

            private func agentThreadRepositoryGlobalStoreFiltersByWorkspaceID() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadGlobalStoreSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstDate = Date(timeIntervalSince1970: 1_777_600_000)
                var thread = AgentThread(
                    id: "agent-thread-alpha",
                    projectID: "project-alpha",
                    title: "Alpha analysis",
                    runIDs: ["run-1"],
                    createdAt: firstDate,
                    updatedAt: firstDate
                )

                try await repository.upsert(thread, in: root)
                thread.appendRunID("run-2", updatedAt: firstDate.addingTimeInterval(10))
                try await repository.upsert(thread, in: root)
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-global",
                        title: "Global thread",
                        runIDs: ["global-run"],
                        createdAt: firstDate,
                        updatedAt: firstDate
                    ),
                    in: root
                )
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-beta",
                        projectID: "project-beta",
                        title: "Beta analysis",
                        runIDs: ["run-beta"],
                        createdAt: firstDate,
                        updatedAt: firstDate.addingTimeInterval(20)
                    ),
                    in: secondRoot
                )

                let projectThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let globalThreads = try await repository.threads(in: root, projectID: nil)
                let currentWorkspaceThreads = try await repository.allThreads(
                    in: secondRoot,
                    workspaceID: AgentThreadRepository.workspaceID(for: secondRoot),
                    includeArchived: false
                )
                let threadsURL = AgentThreadRepository.threadsFileURL(in: storeDirectory)
                let lines = try String(contentsOf: threadsURL, encoding: .utf8).split(whereSeparator: \.isNewline)

                try expect(projectThreads.map(\.id) == ["agent-thread-alpha"], "Project thread history should be filtered by project id.")
                try expect(projectThreads.first?.runIDs == ["run-1", "run-2"], "Upserting a thread should preserve ordered run ids.")
                try expect(globalThreads.map(\.id) == ["agent-thread-global"], "Global thread history should include only global threads.")
                try expect(currentWorkspaceThreads.map(\.id) == ["agent-thread-beta"], "Thread repository should filter the global store by workspace id.")
                try expect(projectThreads.first?.workspaceID == AgentThreadRepository.workspaceID(for: root), "Upserted threads should be tagged with their workspace id.")
                try expect(projectThreads.first?.workspaceName == root.displayName, "Upserted threads should be tagged with their workspace name.")
                try expect(lines.count == 3, "Thread upsert should replace existing records in the global store instead of duplicating them.")
                try expect(!FileManager.default.fileExists(atPath: root.fileURL(for: AgentThreadRepository.legacyRelativePath).path), "Upserting threads should no longer write workspace-local thread files.")
            }

            private func agentThreadRepositoryMigratesPerWorkspaceLegacy() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadLegacyMigrationSuite", isDirectory: true)
                let firstWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let firstWorkspace = try await workspaceService.createWorkspace(at: firstWorkspaceRoot)
                let firstRoot = ResearchRoot(rootURL: firstWorkspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let firstLegacyURL = firstRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let secondLegacyURL = secondRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let firstLegacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread-a","project_id":"project-alpha","run_ids":["run-a"],"title":"Legacy A","updated_at":"2026-04-29T00:00:01Z"}
                """
                let secondLegacyLine = """
                {"created_at":"2026-04-30T00:00:00Z","id":"legacy-thread-b","project_id":"project-beta","run_ids":["run-b"],"title":"Legacy B","updated_at":"2026-04-30T00:00:01Z"}
                """
                try firstLegacyLine.write(to: firstLegacyURL, atomically: true, encoding: .utf8)
                try secondLegacyLine.write(to: secondLegacyURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstMigration = try await repository.migrateLegacyThreads(from: firstRoot)
                let secondMigration = try await repository.migrateLegacyThreads(from: secondRoot)
                let allThreads = try await repository.allThreads(in: firstRoot, includeArchived: false)
                let threadsByID = Dictionary(uniqueKeysWithValues: allThreads.map { ($0.id, $0) })
                let firstArchiveURL = firstLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)
                let secondArchiveURL = secondLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)

                try expect(firstMigration.migratedCount == 1, "First workspace legacy migration should report one migrated thread.")
                try expect(secondMigration.migratedCount == 1, "Second workspace legacy migration should report one migrated thread.")
                try expect(Set(allThreads.map(\.id)) == ["legacy-thread-a", "legacy-thread-b"], "Legacy threads from multiple workspaces should merge into one global store.")
                try expect(threadsByID["legacy-thread-a"]?.workspaceID == AgentThreadRepository.workspaceID(for: firstRoot), "Migrated legacy A should keep a workspace tag.")
                try expect(threadsByID["legacy-thread-b"]?.workspaceID == AgentThreadRepository.workspaceID(for: secondRoot), "Migrated legacy B should keep a workspace tag.")
                try expect(FileManager.default.fileExists(atPath: firstArchiveURL.path), "First workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(FileManager.default.fileExists(atPath: secondArchiveURL.path), "Second workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(!FileManager.default.fileExists(atPath: firstLegacyURL.path), "First workspace legacy thread file should be removed after archival.")
                try expect(!FileManager.default.fileExists(atPath: secondLegacyURL.path), "Second workspace legacy thread file should be removed after archival.")
            }

            private func agentThreadRepositoryArchivesAndReadsLegacyThreads() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentArchivedThreadSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentArchivedThreadWorkspace", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let threadsURL = root.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let legacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread","project_id":"project-alpha","run_ids":["run-1"],"title":"Legacy thread","updated_at":"2026-04-29T00:00:01Z"}
                """
                try legacyLine.write(to: threadsURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let legacyThreads = try await repository.threads(in: root, projectID: "project-alpha")
                var archivedThread = try require(legacyThreads.first, "Legacy thread without archived_at should still decode.")
                archivedThread.archive(at: Date(timeIntervalSince1970: 1_777_600_100))
                try await repository.upsert(archivedThread, in: root)

                let activeThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let allThreads = try await repository.allThreads(in: root)

                try expect(activeThreads.isEmpty, "Archived threads should be hidden from the default active thread list.")
                try expect(allThreads.map(\.id).contains("legacy-thread"), "Archived threads should remain readable from all thread history.")
            }

            private func agentPromptDraftRepositoryPersistsDrafts() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDraftWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentPromptDraftRepository()

                try await repository.saveDraft("Review open papers", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Updated prompt", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Global prompt", projectID: nil, threadID: nil, in: root)

                let projectDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let globalDraft = try await repository.draft(projectID: nil, threadID: nil, in: root)
                let draftsURL = root.fileURL(for: ".sci-station/agent/drafts.json")

                try expect(projectDraft == "Updated prompt", "Prompt drafts should upsert by project/thread key.")
                try expect(globalDraft == "Global prompt", "Global prompt drafts should round-trip.")
                try expect(FileManager.default.fileExists(atPath: draftsURL.path), "Prompt drafts should persist to the agent drafts file.")

                try await repository.removeDraft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let removedDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)

                try expect(removedDraft == nil, "Prompt drafts should be removable when discarding an empty pending thread.")
            }

            private func agentToolDefinitionsExposePlatformMetadata() throws {
                let readDefinition = AgentToolDefinition(
                    name: "read_context",
                    summary: "Read current workspace context.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    displayName: "Write Note",
                    summary: "Write a note into the workspace.",
                    inputSchema: "{\"path\":\"string\"}",
                    inputSchemaVersion: 2,
                    risk: .writesWorkspace,
                    outputPolicy: AgentToolOutputPolicy(maxCharacters: 500, includeAttachments: true)
                )

                let encoded = try JSONEncoder().encode(writeDefinition)
                let decoded = try JSONDecoder().decode(AgentToolDefinition.self, from: encoded)

                try expect(readDefinition.permissionKey == "tool.read", "Read-only tools should default to the read permission key.")
                try expect(!readDefinition.requiresConfirmation, "Read-only tools should not require confirmation by default.")
                try expect(writeDefinition.identifier == "write_note", "Tool definitions should expose a stable identifier.")
                try expect(writeDefinition.permissionKey == "tool.write_workspace", "Workspace-writing tools should expose a write permission key.")
                try expect(writeDefinition.requiresConfirmation, "Workspace-writing tools should require confirmation by default.")
                try expect(decoded.inputSchemaVersion == 2, "Tool definition schema version should round-trip.")
                try expect(decoded.outputPolicy.maxCharacters == 500, "Tool output policy should round-trip.")
            }

            private func agentPermissionRulesEvaluateSafetyDecisions() throws {
                let evaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())

                let destructive = evaluator.evaluate(
                    AgentPermissionRequest(command: "rm -rf .derivedData", risk: .externalSideEffect)
                )
                let sensitivePath = evaluator.evaluate(
                    AgentPermissionRequest(path: "settings/private_api_token.yaml", risk: .writesWorkspace)
                )
                let defaultRead = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "list_papers", risk: .readOnly)
                )
                let defaultWrite = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "create_todo", risk: .writesWorkspace)
                )

                try expect(destructive.action == .deny, "Safety preset should deny recursive removal commands.")
                try expect(destructive.ruleID == "deny-recursive-removal", "Permission decisions should include the matching rule id.")
                try expect(sensitivePath.action == .ask, "Safety preset should ask before sensitive-looking path writes.")
                try expect(defaultRead.action == .allow, "Read-only requests should be allowed by default.")
                try expect(defaultWrite.action == .ask, "Workspace writes should ask by default.")
            }

            private func agentHookEngineEvaluatesLifecycleResults() throws {
                let hooks = AgentSafetyPreset.defaultHooks() + [
                    AgentHookDefinition(
                        id: "deny-shell-preview",
                        eventName: .preToolUse,
                        matcher: #"rm\s+-rf"#,
                        permissionDecision: .deny,
                        message: "Dangerous command blocked."
                    )
                ]
                let engine = AgentHookEngine(hooks: hooks)

                let sessionResults = engine.evaluate(AgentHookEvent(name: .sessionStart))
                let preToolResults = engine.evaluate(
                    AgentHookEvent(name: .preToolUse, toolName: "Bash", command: "rm -rf build")
                )
                let stopResults = engine.evaluate(
                    AgentHookEvent(name: .stop, modifiedPaths: ["Sci-Station/Agent/AgentModels.swift"], validationRecorded: false)
                )

                try expect(sessionResults.first?.additionalContext?.contains("Swift-native") == true, "SessionStart hooks should be able to inject context.")
                try expect(preToolResults.contains(where: { $0.permissionDecision == .deny }), "PreToolUse hooks should return permission decisions.")
                try expect(stopResults.first?.message?.contains("validation") == true, "Stop hooks should be able to remind about validation.")
            }

            private func agentPluginSkillAndMCPModelsValidate() throws {
                let skill = try AgentSkillManifest.parseFrontmatter(from: """
                ---
                name: proposal-draft
                description: Draft Sci-Station proposals from project context.
                version: 0.1.0
                ---

                # Proposal Draft
                """)
                let command = AgentCommandTemplate(
                    id: "proposal-draft",
                    slashCommand: "/proposal-draft",
                    title: "Proposal Draft",
                    promptTemplate: "Draft the next proposal from current project context.",
                    requiredSkillIDs: [skill.id]
                )
                let server = MCPServerConfiguration(
                    id: "sci-station-filesystem",
                    displayName: "Sci-Station Filesystem",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "npx",
                    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "${workspaceRoot}"],
                    allowedTools: ["read_file"],
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/filesystem/authorization")]
                )
                let manifest = AgentPluginManifest(
                    id: "research-core",
                    name: "Research Core",
                    description: "Default Sci-Station research workflow preset.",
                    commands: [command],
                    skills: [skill],
                    hooks: AgentSafetyPreset.defaultHooks(),
                    mcpServers: [server]
                )
                let invalidManifest = AgentPluginManifest(
                    id: "bad",
                    name: "Bad",
                    description: "Invalid command example.",
                    commands: [AgentCommandTemplate(id: "bad", slashCommand: "bad", title: "Bad", promptTemplate: "Bad")],
                    mcpServers: [MCPServerConfiguration(id: "remote", displayName: "Remote", transport: .remoteHTTP)]
                )

                let encodedServer = try JSONEncoder().encode(server)
                let encodedServerText = try require(String(data: encodedServer, encoding: .utf8), "Encoded MCP server should be UTF-8.")
                let issues = AgentPluginValidator().validate(manifest)
                let invalidIssues = AgentPluginValidator().validate(invalidManifest)

                try expect(skill.name == "proposal-draft", "Skill frontmatter parser should read the name.")
                try expect(issues.isEmpty, "Valid plugin manifests should pass validation.")
                try expect(invalidIssues.count == 2, "Validator should report invalid command and remote MCP URL.")
                try expect(encodedServerText.contains("value_reference"), "MCP headers should serialize credential references.")
                try expect(!encodedServerText.contains("Bearer "), "MCP config serialization should not include raw authorization values.")
            }

            private func sciAITrackedPresetManifestValidates() throws {
                let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".sci-ai/sci-station/presets/research-core/plugin.json", isDirectory: false)
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(AgentPluginManifest.self, from: data)
                let issues = AgentPluginValidator().validate(manifest)

                try expect(manifest.id == "research-core", "Tracked .sci-ai product preset should decode as research-core.")
                try expect(manifest.commands.contains(where: { $0.slashCommand == "/proposal-draft" }), "Tracked .sci-ai product preset should include proposal drafting.")
                try expect(manifest.mcpServers.allSatisfy { $0.secretReferences.isEmpty }, "Tracked .sci-ai product preset should not include raw secret values.")
                try expect(issues.isEmpty, "Tracked .sci-ai product preset should pass plugin validation.")
            }

            private func sciAIConfigurationBoundaryValidates() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let trackedPresetURL = repoURL.appendingPathComponent(".sci-ai/sci-station", isDirectory: true)
                let gitignoreURL = repoURL.appendingPathComponent(".gitignore", isDirectory: false)
                let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)
                let trackedFiles = try gitTrackedFiles(in: repoURL)

                try expect(!trackedSciAIContainsRawSecrets(at: trackedPresetURL), "Tracked .sci-ai/sci-station files should not contain raw secret-looking values.")
                try expect(gitignore.contains(".sci-ai/workspace.local/"), "Local .sci-ai workspace config path should be ignored by git.")
                try expect(gitignore.contains(".claude/"), "Root .claude bridge should be ignored by git.")
                try expect(gitignore.contains(".mcp.json"), "Root .mcp.json bridge should be ignored by git.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".sci-ai/workspace.local/") }, "Local .sci-ai workspace config should not be tracked.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".claude/") }, "Root .claude bridge directory should not be tracked.")
                try expect(!trackedFiles.contains(".mcp.json"), "Root .mcp.json bridge file should not be tracked.")
            }

            private func agentSessionEventLoggerAppendsAndReplaysEvents() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentSessionEventWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentSessionEventLogger()
                let firstEvent = AgentSessionEvent(
                    id: "event-1",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    kind: .userMessage,
                    summary: "User asked for a plan."
                )
                let secondEvent = AgentSessionEvent(
                    id: "event-2",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_001),
                    kind: .hookResult,
                    summary: "PreToolUse asked for confirmation.",
                    payloadJSON: "{\"decision\":\"ask\"}"
                )

                try await logger.append(firstEvent, in: root)
                let logURL = root.fileURL(for: AgentSessionEventLogger.relativePath)
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondEvent, in: root)

                let alphaEvents = try await logger.events(in: root, sessionID: "session-alpha")
                let missingEvents = try await logger.events(in: workspace, sessionID: "missing")

                try expect(alphaEvents.map(\.id) == ["event-1", "event-2"], "Session event logger should replay valid events in append order.")
                try expect(missingEvents.isEmpty, "Session event logger should filter by session id.")
            }

            private func openAIStreamDeltaParserIgnoresBadChunks() throws {
                let validChunk = #"{"choices":[{"delta":{"content":"Hello"}}]}"#.data(using: .utf8)!
                let emptyDeltaChunk = #"{"choices":[{"delta":{}}]}"#.data(using: .utf8)!
                let badChunk = Data("{not-json}".utf8)

                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: validChunk) == "Hello", "SSE parser should decode content deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: emptyDeltaChunk) == nil, "SSE parser should ignore empty deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: badChunk) == nil, "SSE parser should ignore malformed JSON chunks.")
            }

            private func llmProviderV2RequestModelsToolDefinitions() throws {
                let definition = AgentToolDefinition(
                    name: "create_todo",
                    summary: "Create a todo.",
                    inputSchema: "{\"title\":\"string\"}",
                    risk: .writesWorkspace
                )
                let tool = LLMToolSpecification(agentTool: definition)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Plan first."),
                        LLMChatMessage(role: .user, content: "Create a follow-up todo.")
                    ],
                    tools: [tool],
                    options: LLMProviderOptions(model: "gpt-4.1", temperature: 0.2)
                )
                let response = LLMProviderResponse(
                    message: LLMChatMessage(role: .assistant, content: "Ready."),
                    toolCalls: [AgentToolCall(id: "call-1", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")]
                )
                let adapterFlow = LLMProviderV2AdapterFlow(
                    messages: request.messages,
                    toolDefinitions: [definition],
                    options: request.options
                )
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "fallback-model")
                let chatRequest = try provider.buildChatRequest(
                    configuration: configuration,
                    apiKey: "secret-key",
                    providerRequest: adapterFlow.request
                )
                let chatBody = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Provider V2 chat body should encode as UTF-8.")

                let decodedRequest = try JSONDecoder().decode(LLMProviderRequest.self, from: JSONEncoder().encode(request))
                let decodedResponse = try JSONDecoder().decode(LLMProviderResponse.self, from: JSONEncoder().encode(response))

                try expect(decodedRequest.messages.count == 2, "Provider V2 requests should preserve message history.")
                try expect(decodedRequest.tools.first?.permissionKey == "tool.write_workspace", "Provider V2 tool specs should preserve permission keys.")
                try expect(decodedRequest.options.model == "gpt-4.1", "Provider V2 requests should preserve model options.")
                try expect(decodedResponse.toolCalls.first?.toolName == "create_todo", "Provider V2 responses should preserve tool calls.")
                try expect(adapterFlow.preservesLegacyCompletePath, "Provider V2 adapter flow should explicitly preserve the legacy complete path.")
                try expect(adapterFlow.supportsTaskCancellation, "Provider V2 adapter flow should document Task cancellation support.")
                try expect(chatBody.contains("tools"), "OpenAI-compatible Provider V2 wrapper should encode tool definitions.")
                try expect(chatBody.contains("gpt-4.1"), "OpenAI-compatible Provider V2 wrapper should use request model options.")
            }

            private func agentSessionTimelineItemsFilterCurrentSessions() throws {
                let events = [
                    AgentSessionEvent(
                        id: "timeline-1",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 10),
                        kind: .userMessage,
                        summary: "Review current papers."
                    ),
                    AgentSessionEvent(
                        id: "timeline-2",
                        sessionID: "run-other",
                        createdAt: Date(timeIntervalSince1970: 11),
                        kind: .assistantMessage,
                        summary: "Other run summary."
                    ),
                    AgentSessionEvent(
                        id: "timeline-3",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 12),
                        kind: .permissionRequested,
                        summary: "create_todo needs approval.",
                        payloadJSON: "{\"title\":\"Follow up\"}"
                    )
                ]

                let items = AgentSessionTimelineItem.items(from: events, sessionIDs: Set(["run-current"]))

                try expect(items.map(\.eventID) == ["timeline-1", "timeline-3"], "Timeline items should filter to the current run/session ids.")
                try expect(items.last?.title == "请求审批", "Timeline items should label permission request events.")
                try expect(items.last?.payloadPreview?.contains("Follow up") == true, "Timeline items should preserve payload previews for audit.")
            }

            private func agentPermissionDockSummarizesPolicies() throws {
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    summary: "Write a note.",
                    inputSchema: "{\"path\":\"string\"}",
                    risk: .writesWorkspace
                )
                let readDefinition = AgentToolDefinition(
                    name: "read_note",
                    summary: "Read a note.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let plan = AgentPlan(
                    summary: "Use two tools.",
                    toolCalls: [
                        AgentToolCall(id: "call-write", toolName: "write_note", argumentsJSON: "{\"path\":\"settings/token.yaml\"}"),
                        AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{}")
                    ]
                )
                let run = AgentRun(
                    id: "run-dock",
                    goal: "Test dock.",
                    createdAt: Date(timeIntervalSince1970: 1),
                    completedAt: nil,
                    mode: .planOnly,
                    plan: plan,
                    toolResults: []
                )
                let items = AgentPermissionDockItem.items(
                    for: run,
                    toolDefinitions: [readDefinition, writeDefinition],
                    state: AgentPermissionDockState(
                        approvedCallIDs: ["call-write"],
                        correctionFeedbackByCallID: ["call-write": "Use a safer path."]
                    )
                )

                let writeItem = try require(items.first { $0.id == "call-write" }, "Write dock item should exist.")
                let readItem = try require(items.first { $0.id == "call-read" }, "Read dock item should exist.")

                try expect(writeItem.permissionKey == "tool.write_workspace", "Permission dock should expose permission keys.")
                try expect(writeItem.approvalState == .allowedOnce, "Permission dock should show allow-once state.")
                try expect(writeItem.matchedPolicyDescription.contains("ask-sensitive-path"), "Permission dock should report matched policy rules.")
                try expect(writeItem.pathPreview == ["settings/token.yaml"], "Permission dock should extract path previews from structured arguments.")
                try expect(writeItem.correctionFeedback == "Use a safer path.", "Permission dock should preserve correction feedback.")
                try expect(readItem.approvalState == .autoAllowed, "Read-only tools should display auto-allow state.")
            }

            private func agentHookActivitySummaryReflectsTogglesAndResults() throws {
                let result = AgentHookResult(
                    hookID: "pre-tool-permission-reminder",
                    eventName: .preToolUse,
                    permissionDecision: .ask,
                    message: "Review write before running."
                )
                let payload = try require(String(data: JSONEncoder().encode(result), encoding: .utf8), "Hook result payload should encode.")
                let event = AgentSessionEvent(
                    id: "hook-event",
                    sessionID: "run-hook",
                    kind: .hookResult,
                    summary: "PreToolUse hook pre-tool-permission-reminder. Decision: ask.",
                    payloadJSON: payload
                )

                let summary = AgentHookActivitySummary(
                    hooks: AgentSafetyPreset.defaultHooks(),
                    events: [event],
                    disabledHookIDs: ["post-tool-audit-reminder"]
                )

                try expect(summary.enabledEventNames.contains(.sessionStart), "Hook activity should expose enabled SessionStart hooks.")
                try expect(summary.enabledEventNames.contains(.preToolUse), "Hook activity should expose enabled PreToolUse hooks.")
                try expect(!summary.hooks.first { $0.id == "post-tool-audit-reminder" }!.isEnabled, "Hook activity should reflect disabled hooks.")
                try expect(summary.results.first?.permissionDecision == .ask, "Hook activity should decode hook permission decisions.")
            }

            private func agentMCPServerStatusSummaryParsesProductAndLocal() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let root = ResearchRoot(rootURL: repoURL)
                let loader = AgentRuntimeConfigurationLoader()
                let preset = try require(try loader.loadProductPreset(in: root), "Tracked research-core preset should load.")
                let localJSON = """
                {
                  "mcpServers": {
                    "local-filesystem": {
                      "command": "npx",
                      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"],
                      "env": {
                        "API_TOKEN": "keychain:mcp/local/token",
                        "LOG_LEVEL": "info"
                      },
                      "allowed_tools": ["read_file"],
                      "timeout_seconds": 45
                    }
                  }
                }
                """
                let localStatuses = try AgentRuntimeConfigurationLoader.localMCPServerStatuses(from: Data(localJSON.utf8))
                let productStatus = try require(preset.mcpServers.first, "Product preset should expose MCP server status.")
                let localStatus = try require(localStatuses.first, "Local MCP status should parse from Claude-style config.")

                try expect(productStatus.source == .trackedProductTemplate, "Product MCP status should identify tracked template source.")
                try expect(productStatus.endpointSummary.contains("npx"), "Product MCP status should show local command.")
                try expect(localStatus.source == .localWorkspaceConfig, "Local MCP status should identify local source.")
                try expect(localStatus.allowedTools == ["read_file"], "Local MCP status should preserve allowed tools.")
                try expect(Int(localStatus.timeoutSeconds) == 45, "Local MCP status should preserve timeout.")
                try expect(localStatus.credentialReferenceCount == 1, "Local MCP status should count credential references without exposing values.")
                try expect(localStatus.sideEffectsRequirePermission, "MCP side-effect tools should remain routed through permission layer.")
            }

    private func pdfImportCreatesLibraryMarkdownAndFigures() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let importer = PDFImportService(repository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ImportWorkspace", isDirectory: true)
        let sourcePDFURL = temporaryDirectoryURL().appendingPathComponent("Example-2024.pdf", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: sourcePDFURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try Data("fake pdf".utf8).write(to: sourcePDFURL, options: .atomic)

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let importedPaper = try await importer.importPDF(from: sourcePDFURL, into: workspace, existingPapers: [])
        let paperDirectoryURL = workspace.directoryURL(for: importedPaper.directoryRelativePath)
        let paperMarkdownURL = paperDirectoryURL.appendingPathComponent("paper.md", isDirectory: false)
        let figuresURL = paperDirectoryURL.appendingPathComponent("figures", isDirectory: true)

        try expect(importedPaper.collectionPath == "Uncategorized", "Imported papers should default into the Uncategorized collection.")
        try expect(importedPaper.paperDirectoryRelativePath.hasPrefix("library/papers/"), "Imported papers should be stored in the global library.")
        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("paper.pdf").path), "Imported paper should include paper.pdf.")
        try expect(FileManager.default.fileExists(atPath: paperMarkdownURL.path), "Imported paper should include paper.md.")
        try expect(FileManager.default.fileExists(atPath: figuresURL.path), "Imported paper should include a figures directory.")

        let rawMarkdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(rawMarkdown.contains("type: raw-paper"), "paper.md should contain raw-paper frontmatter.")
        try expect(rawMarkdown.contains("status: not_extracted"), "paper.md should record extraction status.")
    }

    private func minerUAPIConversionCopiesImageAssets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MinerUAssetWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
            MinerUAPIMockURLProtocol.zipData = Data()
            MinerUAPIMockURLProtocol.requestLog = []
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders = []
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "mineru-images-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)
        try Data("%PDF-1.4\n% fake test pdf".utf8).write(to: paperDirectoryURL.appendingPathComponent("paper.pdf"), options: .atomic)

        MinerUAPIMockURLProtocol.zipData = try zipData(entries: [
            (
                "full.md",
                Data(
                    """
                    # MinerU Output

                    ![Figure](images/figure-1.png)

                    <img src="images/figure-2.webp" alt="Second">
                    """.utf8
                )
            ),
            ("images/figure-1.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("images/figure-2.webp", Data("WEBP".utf8))
        ])
        MinerUAPIMockURLProtocol.requestLog = []

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MinerUAPIMockURLProtocol.self]
        let service = PaperMarkdownConversionService(session: URLSession(configuration: sessionConfiguration))
        let results = try await service.convert(
            [paper],
            in: workspace,
            configuration: PaperMarkdownConversionConfiguration(
                minerUAPIToken: "test-token",
                minerUAPIBaseURLString: "https://mineru.test",
                overwriteExistingMarkdown: true,
                pollIntervalSeconds: 1,
                pollTimeoutSeconds: 5
            )
        )

        let result = try require(results.first, "MinerU conversion should return a result.")
        try expect(result.didWriteMarkdown, result.errorMessage ?? "MinerU conversion should write paper.md.")

        let paperMarkdownURL = paper.rawMarkdownURL(in: workspace)
        let markdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(markdown.contains("extraction_engine: mineru_api"), "MinerU conversion should record the API extraction engine.")
        try expect(markdown.contains("![Figure](figures/mineru/images/figure-1.png)"), "Markdown image links should point to copied MinerU assets.")
        try expect(markdown.contains("<img src=\"figures/mineru/images/figure-2.webp\""), "HTML image links should point to copied MinerU assets.")
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-1.png").path),
            "MinerU PNG assets should be copied into the paper figures directory."
        )
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-2.webp").path),
            "MinerU WebP assets should be copied into the paper figures directory."
        )
        try expect(
            MinerUAPIMockURLProtocol.requestLog.contains("PUT upload.test/upload/mineru-images-paper.pdf"),
            "MinerU conversion should upload the PDF to the signed upload URL."
        )
        try expect(
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders == [nil],
            "MinerU signed URL upload should not include a Content-Type header."
        )
    }

    private func movePaperToCollectionUpdatesMetadataAndPath() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let moveService = MovePaperToCollectionService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MovePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let originalPaper = try await repository.save(samplePaper(id: "move-test-paper"), in: workspace)
        let originalDirectoryURL = workspace.directoryURL(for: originalPaper.paperDirectoryRelativePath)
        try Data("fake pdf".utf8).write(to: originalDirectoryURL.appendingPathComponent("paper.pdf"), options: .atomic)

        let movedPaper = try await moveService.move(originalPaper, to: "Dark-Matter/WIMPs", in: workspace)

        try expect(
            movedPaper.paperDirectoryRelativePath == "library/papers/Dark-Matter/WIMPs/move-test-paper",
            "Moving a paper should update its nested directory path."
        )
        try expect(movedPaper.collectionPath == "Dark-Matter/WIMPs", "Moving a paper should update collection_path.")
        try expect(
            movedPaper.notesSummaryRelativePath == "../../../../../wiki/papers/smith2024graph.md",
            "Moving a paper should recompute the summary relative path from the new folder depth."
        )

        let movedMetadata = try String(
            contentsOf: workspace.directoryURL(for: movedPaper.paperDirectoryRelativePath).appendingPathComponent("meta.yaml"),
            encoding: .utf8
        )
        try expect(movedMetadata.contains("collection_path: \"Dark-Matter/WIMPs\""), "Moved metadata should persist the new collection_path.")
    }

    private func wikiPageGenerationWritesTemplateAndUpdatesMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        let result = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        try expect(FileManager.default.fileExists(atPath: result.fileURL.path), "Wiki page should be written to wiki/papers.")
        let wikiContents = try String(contentsOf: result.fileURL, encoding: .utf8)
        try expect(wikiContents.contains("type: paper"), "Wiki page should contain paper frontmatter.")
        try expect(wikiContents.contains("source_pdf: \"../../library/papers/Uncategorized/smith2024-graph-rag/paper.pdf\""), "Wiki page should contain source_pdf path.")
        try expect(wikiContents.contains("## TL;DR"), "Wiki page should contain summary sections.")

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected saved paper metadata to remain loadable after wiki generation."
        )
        try expect(
            loadedPaper.notesSummaryRelativePath == "../../../../wiki/papers/smith2024graph.md",
            "Wiki generation should persist notes.summary_file back to meta.yaml."
        )
    }

    private func wikiPageGenerationRejectsSilentOverwrite() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let generator = WikiPageGenerator(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("WikiConflictWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let savedPaper = try await repository.save(samplePaper(id: "smith2024-graph-rag"), in: workspace)
        _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)

        do {
            _ = try await generator.generatePaperWikiPage(for: savedPaper, in: workspace)
            throw ValidationError(message: "Generating an existing wiki page should not silently overwrite the file.")
        } catch let error as WikiPageGeneratorError {
            switch error {
            case let .alreadyExists(path):
                try expect(path == "wiki/papers/smith2024graph.md", "alreadyExists should report the existing wiki path.")
            }
        }
    }

    private func frontmatterParserParsesArraysAndBody() throws {
        let parser = FrontmatterParser()
        let result = parser.parse(
            """
            ---
            title: "Graph RAG"
            tags:
              - "rag"
              - "graph"
            ---

            # Graph RAG

            Body text.
            """
        )

        try expect(result.frontmatter["title"]?.stringValue == "Graph RAG", "FrontmatterParser should read string values.")
        try expect(result.frontmatter["tags"]?.arrayValue == ["rag", "graph"], "FrontmatterParser should read array values.")
        try expect(result.body.contains("# Graph RAG"), "FrontmatterParser should return the Markdown body after frontmatter.")
    }

    private func wikiLinkParserExtractsTargets() throws {
        let parser = WikiLinkParser()
        let links = parser.parse("See [[Retrieval Augmented Generation]] and [[Knowledge Graph|KG]] plus [[RAG#Overview]].")

        try expect(links.map(\.target) == ["Retrieval Augmented Generation", "Knowledge Graph", "RAG"], "WikiLinkParser should normalize aliases and anchors to page targets.")
    }

    private func backlinkIndexFindsIncomingReferences() throws {
        let targetDocument = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/concepts/rag.md"),
            relativePath: "wiki/concepts/rag.md",
            category: "concepts",
            title: "Retrieval Augmented Generation",
            frontmatter: [:],
            body: "# Retrieval Augmented Generation",
            rawContents: "# Retrieval Augmented Generation",
            outgoingLinks: [],
            pageKeys: [
                WikiLink.normalizePageKey("Retrieval Augmented Generation"),
                WikiLink.normalizePageKey("rag")
            ]
        )
        let sourceDocument = MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/wiki/papers/smith2024graph.md"),
            relativePath: "wiki/papers/smith2024graph.md",
            category: "papers",
            title: "Graph-based Retrieval Augmented Generation",
            frontmatter: [:],
            body: "See [[Retrieval Augmented Generation]].",
            rawContents: "See [[Retrieval Augmented Generation]].",
            outgoingLinks: [WikiLink(target: "Retrieval Augmented Generation", originalText: "[[Retrieval Augmented Generation]]")],
            pageKeys: [WikiLink.normalizePageKey("Graph-based Retrieval Augmented Generation")]
        )

        let index = BacklinkIndex(documents: [targetDocument, sourceDocument])
        let backlinks = index.backlinks(for: targetDocument)

        try expect(backlinks.count == 1, "BacklinkIndex should return referencing pages for the selected document.")
        try expect(backlinks.first?.relativePath == sourceDocument.relativePath, "BacklinkIndex should point back to the source page.")
    }

    private func markdownRepositoryLoadsAndSavesDocuments() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = MarkdownRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MarkdownWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pageRelativePath = "wiki/concepts/rag.md"
        let savedDocument = try await repository.saveContents(
            """
            ---
            title: "Retrieval Augmented Generation"
            tags:
              - "rag"
            ---

            # Retrieval Augmented Generation

            See [[Knowledge Graph]].
            """,
            relativePath: pageRelativePath,
            in: workspace
        )

        try expect(savedDocument.title == "Retrieval Augmented Generation", "MarkdownRepository should resolve titles from frontmatter.")
        try expect(savedDocument.outgoingLinks.map(\.target) == ["Knowledge Graph"], "MarkdownRepository should parse wikilinks when loading documents.")

        let loadedDocuments = try await repository.loadDocuments(in: workspace)
        try expect(loadedDocuments.contains(where: { $0.relativePath == pageRelativePath }), "MarkdownRepository should scan wiki/ for markdown files.")
    }

    private struct LoopWorkspaceFixture {
        let workspace: ResearchWorkspace
        let root: ResearchRoot
        let suiteName: String
        let containerURL: URL
    }

    private func loopWorkspaceFixture(named name: String) async throws -> LoopWorkspaceFixture {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let containerURL = temporaryDirectoryURL()
        let workspaceURL = containerURL.appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        return LoopWorkspaceFixture(
            workspace: workspace,
            root: ResearchRoot(rootURL: workspace.rootURL),
            suiteName: suiteName,
            containerURL: containerURL
        )
    }

    private func cleanupLoopWorkspaceFixture(_ fixture: LoopWorkspaceFixture) {
        try? FileManager.default.removeItem(at: fixture.containerURL)
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    private func loopToolDefinition(
        name: String,
        risk: AgentToolRisk,
        maxOutputCharacters: Int = 12_000
    ) -> AgentToolDefinition {
        AgentToolDefinition(
            name: name,
            summary: "Loop test tool \(name).",
            inputSchema: "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"command\":{\"type\":\"string\"}}}",
            risk: risk,
            outputPolicy: AgentToolOutputPolicy(maxCharacters: maxOutputCharacters)
        )
    }

    private func loopRequest(
        runID: String,
        goal: String = "Loop test goal",
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: []),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
    ) -> AgentLoopRequest {
        AgentLoopRequest(
            runID: runID,
            goal: goal,
            initialMessages: [
                LLMChatMessage(role: .system, content: "Use tools when useful."),
                LLMChatMessage(role: .user, content: "Please inspect the selected context.")
            ],
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: permissionEvaluator
        )
    }

    private func loopResumeRequest(
        pending: AgentPendingToolCall,
        action: AgentHumanDecisionAction,
        feedback: String? = nil,
        editedArgumentsJSON: String? = nil,
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: [])
    ) -> AgentLoopResumeRequest {
        AgentLoopResumeRequest(
            pending: pending,
            action: action,
            feedback: feedback,
            editedArgumentsJSON: editedArgumentsJSON,
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
        )
    }

    private func sidecarRuntime(
        fixtureName: String,
        handshakeTimeout: TimeInterval = 5
    ) -> LangGraphAgentRuntime {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runtimeURL = repositoryURL.appendingPathComponent("AgentRuntime", isDirectory: true)
        let fixtureURL = runtimeURL.appendingPathComponent("tests/fixtures/\(fixtureName)", isDirectory: false)
        let configuration = SidecarLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sci_station_agent.main", "--fixture", fixtureURL.path],
            environment: [
                "PYTHONPATH": runtimeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            workingDirectoryURL: repositoryURL,
            handshakeTimeout: handshakeTimeout,
            requestTimeout: 5
        )
        return LangGraphAgentRuntime(
            supervisor: SidecarProcessSupervisor(configuration: configuration),
            fallbackRuntime: nil
        )
    }

    private func sidecarRuntimeRequest(
        runID: String,
        goal: String = "P34 sidecar fixture run",
        fixture: LoopWorkspaceFixture,
        definitions: [AgentToolDefinition] = [],
        registry: AgentToolRegistry = AgentToolRegistry(tools: [])
    ) -> AgentRuntimeRequest {
        AgentRuntimeRequest(
            runID: runID,
            threadID: "thread-\(runID)",
            goal: goal,
            initialMessages: [LLMChatMessage(role: .user, content: goal)],
            provider: ScriptedChatProvider(responses: [
                LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Sidecar provider response."))
            ]),
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, selectedPaperID: "demo-paper", researchRoot: fixture.root, currentProjectID: "demo-project"),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
    }

    private func samplePaper(id: String) -> Paper {
        Paper(
            id: id,
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["rag"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    private func temporaryDirectoryURL() -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private func zipData(entries: [(path: String, data: Data)]) throws -> Data {
        let sourceDirectoryURL = temporaryDirectoryURL()
        let zipDirectoryURL = temporaryDirectoryURL()
        let zipURL = zipDirectoryURL.appendingPathComponent("archive.zip", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: sourceDirectoryURL)
            try? FileManager.default.removeItem(at: zipDirectoryURL)
        }

        for entry in entries {
            let fileURL = sourceDirectoryURL.appendingPathComponent(entry.path, isDirectory: false)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: fileURL, options: .atomic)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", zipURL.path, "."]
        process.currentDirectoryURL = sourceDirectoryURL

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown zip error"
            throw ValidationError(message: "zip failed: \(errorText)")
        }

        return try Data(contentsOf: zipURL)
    }

    private func gitTrackedFiles(in repoURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files"]
        process.currentDirectoryURL = repoURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown git error"
            throw ValidationError(message: "git ls-files failed: \(errorText)")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func trackedSciAIContainsRawSecrets(at directoryURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let secretPattern = #"(?i)(bearer\s+[A-Za-z0-9._\-]{12,}|sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\"(api[_-]?key|client[_-]?secret|refresh[_-]?token|private[_-]?key)\"\s*:\s*\"(?!\$\{|keychain:|env:|secret-ref:)[^\"]{8,}\")"#
        guard let expression = try? NSRegularExpression(pattern: secretPattern) else {
            return true
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ValidationError(message: message)
        }
    }

    private func jsonObject(_ value: JSONValue?, _ message: String) throws -> [String: JSONValue] {
        guard case let .object(object)? = value else {
            throw ValidationError(message: message)
        }
        return object
    }

    private func jsonArray(_ value: JSONValue?, _ message: String) throws -> [JSONValue] {
        guard case let .array(array)? = value else {
            throw ValidationError(message: message)
        }
        return array
    }

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw ValidationError(message: message)
        }
        return value
    }

    private func runtimeEventLabel(_ event: AgentRuntimeEvent) -> String {
        switch event {
        case .runStarted: return "runStarted"
        case .nodeStarted: return "nodeStarted"
        case .assistantDelta: return "assistantDelta"
        case .assistantMessage: return "assistantMessage"
        case .toolCallRequested: return "toolCallRequested"
        case .toolCallCompleted: return "toolCallCompleted"
        case .approvalRequired: return "approvalRequired"
        case .artifactDraft: return "artifactDraft"
        case .checkpointSaved: return "checkpointSaved"
        case .finalResponse: return "finalResponse"
        case .runCancelled: return "runCancelled"
        case .runFailed: return "runFailed"
        case .sidecarStarting: return "sidecarStarting"
        case .sidecarReady: return "sidecarReady"
        case .sidecarUnavailable: return "sidecarUnavailable"
        case .sidecarCrashed: return "sidecarCrashed"
        case .fallbackToLegacyRuntime: return "fallbackToLegacyRuntime"
        }
    }
}

private struct ValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private extension AgentRuntimeEvent {
    var isSidecarStarting: Bool {
        if case .sidecarStarting = self { return true }
        return false
    }

    var isSidecarUnavailable: Bool {
        if case .sidecarUnavailable = self { return true }
        return false
    }

    var isFallbackToLegacyRuntime: Bool {
        if case .fallbackToLegacyRuntime = self { return true }
        return false
    }
}

private struct StaticLLMProvider: LLMProvider {
    let response: String

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        response
    }
}

private actor ScriptedChatProvider: LLMProvider, LLMChatProvider {
    private var responses: [LLMProviderResponse]
    private var requests: [LLMProviderRequest] = []

    init(responses: [LLMProviderResponse]) {
        self.responses = responses
    }

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        responses.first?.message.content ?? ""
    }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        requests.append(request)
        if responses.count > 1 {
            return responses.removeFirst()
        }
        if let response = responses.first {
            return response
        }
        return LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
    }

    func recordedRequests() -> [LLMProviderRequest] {
        requests
    }
}

private actor RecordingAgentTool: AgentTool {
    nonisolated let definition: AgentToolDefinition
    private var results: [AgentToolResult]
    private var argumentsLog: [String] = []

    init(definition: AgentToolDefinition, results: [AgentToolResult]) {
        self.definition = definition
        self.results = results
    }

    func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        argumentsLog.append(argumentsJSON)
        if results.count > 1 {
            return results.removeFirst()
        }
        if let result = results.first {
            return result
        }
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: "Recorded tool result.")
    }

    func invocationCount() -> Int {
        argumentsLog.count
    }

    func invokedArguments() -> [String] {
        argumentsLog
    }
}

private final class MinerUAPIMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var zipData = Data()
    nonisolated(unsafe) static var requestLog: [String] = []
    nonisolated(unsafe) static var uploadContentTypeHeaders: [String?] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let host = url.host ?? ""
        let requestKey = "\(method) \(host)\(url.path)"
        Self.requestLog.append(requestKey)

        let statusCode: Int
        let contentType: String
        let data: Data

        switch requestKey {
        case "POST mineru.test/api/v4/file-urls/batch":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "batch_id": "batch-1",
                    "file_urls": ["https://upload.test/upload/mineru-images-paper.pdf"]
                  }
                }
                """.utf8
            )
        case "PUT upload.test/upload/mineru-images-paper.pdf":
            Self.uploadContentTypeHeaders.append(request.value(forHTTPHeaderField: "Content-Type"))
            statusCode = request.value(forHTTPHeaderField: "Content-Type") == nil ? 204 : 415
            contentType = "text/plain"
            data = Data()
        case "GET mineru.test/api/v4/extract-results/batch/batch-1":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "extract_result": [
                      {
                        "file_name": "mineru-images-paper.pdf",
                        "data_id": "mineru-images-paper",
                        "state": "done",
                        "full_zip_url": "https://download.test/mineru.zip"
                      }
                    ]
                  }
                }
                """.utf8
            )
        case "GET download.test/mineru.zip":
            statusCode = 200
            contentType = "application/zip"
            data = Self.zipData
        default:
            statusCode = 404
            contentType = "text/plain"
            data = Data("not found: \(requestKey)".utf8)
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
