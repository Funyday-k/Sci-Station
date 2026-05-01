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
        try await githubCopilotConfigurationStaysNonSensitive()
        try githubCopilotOAuthBuildsAuthorizeURLAndParsesCallback()
        try githubCopilotTokenExchangeRequestExcludesClientSecret()
        try githubCopilotTokenClassifierRecognizesSupportedPrefixes()
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
        try await agentToolExecutorRequiresApprovalForTodoWrites()
        try await agentPaperClassificationToolUpdatesMetadata()
        try await agentWorkspaceSnapshotIncludesProjectContext()
        try await agentRunLoggerAndCopilotBridgeExporterWriteWorkspaceFiles()
        try await agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory()
        try await agentServiceExecutesApprovedPlanAndExportsBridge()
        try await agentRunLoggerSkipsDamagedHistoryLines()
        try await agentRunLoggerFiltersProjectConversations()
        try await agentThreadRepositoryUpsertsProjectThreads()
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
        try llmProviderV2RequestModelsToolDefinitions()
        try await pdfImportCreatesLibraryMarkdownAndFigures()
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

        try await repository.save(preferences, in: workspace)
        let loadedPreferences = try await repository.load(in: workspace)

        try expect(loadedPreferences.libraryVisibleColumns == ["title", "authors", "bibtex"], "Workspace preferences should preserve column order.")
        try expect(loadedPreferences.librarySortState == LibrarySortState(field: .year, isAscending: false), "Workspace preferences should preserve Library sort state.")
        try expect(loadedPreferences.defaultCollectionPath == "Dark-Matter", "Workspace preferences should preserve default collection.")
        try expect(loadedPreferences.recentSection == "library", "Workspace preferences should preserve recent section.")
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

    private func githubCopilotConfigurationStaysNonSensitive() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let store = GitHubCopilotConfigurationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("GitHubCopilotSettingsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let configuration = GitHubCopilotConfiguration(
            isEnabled: true,
            clientID: "client-id",
            callbackURLString: "sci-station://github-copilot/callback",
            tokenExchangeURLString: "https://relay.example.com/github/copilot/token",
            requiredOrganization: "example-org",
            model: "gpt-4.1",
            scopeString: "read:user read:org"
        )
        try await store.save(configuration, in: workspace)
        let loadedConfiguration = try await store.load(in: workspace)
        let settingsContents = try String(contentsOf: workspace.fileURL(for: GitHubCopilotConfigurationStore.relativePath), encoding: .utf8)

        try expect(loadedConfiguration == configuration, "GitHub Copilot configuration should round trip non-sensitive fields.")
        try expect(!settingsContents.lowercased().contains("secret"), "GitHub Copilot config must not contain OAuth client secrets.")
        try expect(!settingsContents.contains("gho_"), "GitHub Copilot config must not contain user tokens.")
    }

    private func githubCopilotOAuthBuildsAuthorizeURLAndParsesCallback() throws {
        let configuration = GitHubCopilotConfiguration(
            isEnabled: true,
            clientID: "client-id",
            callbackURLString: "sci-station://github-copilot/callback",
            tokenExchangeURLString: "https://relay.example.com/github/copilot/token",
            model: "gpt-4.1",
            scopeString: "read:user read:org"
        )
        let url = try GitHubCopilotOAuthRequestBuilder().authorizationURL(configuration: configuration, state: "state-123")
        let components = try require(URLComponents(url: url, resolvingAgainstBaseURL: false), "Authorize URL should be parseable.")
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })

        try expect(url.scheme == "https", "Authorize URL should use HTTPS.")
        try expect(url.host == "github.com", "Authorize URL should target github.com.")
        try expect(components.path == "/login/oauth/authorize", "Authorize URL should use GitHub OAuth authorize path.")
        try expect(queryItems["client_id"] == "client-id", "Authorize URL should include client id.")
        try expect(queryItems["redirect_uri"] == "sci-station://github-copilot/callback", "Authorize URL should include callback URL.")
        try expect(queryItems["state"] == "state-123", "Authorize URL should include state.")
        try expect(queryItems["scope"] == "read:user read:org", "Authorize URL should include scopes.")

        let callbackURL = try require(URL(string: "sci-station://github-copilot/callback?code=abc&state=state-123"), "Callback URL should be constructible.")
        let callback = try GitHubCopilotOAuthCallback(url: callbackURL)
        try expect(callback.code == "abc", "Callback parser should extract code.")
        try expect(callback.state == "state-123", "Callback parser should extract state.")
    }

    private func githubCopilotTokenExchangeRequestExcludesClientSecret() throws {
        let configuration = GitHubCopilotConfiguration(
            isEnabled: true,
            clientID: "client-id",
            callbackURLString: "sci-station://github-copilot/callback",
            tokenExchangeURLString: "https://relay.example.com/github/copilot/token",
            model: "gpt-4.1"
        )
        let request = try GitHubCopilotOAuthTokenExchanger().buildRequest(
            code: "code-123",
            state: "state-123",
            configuration: configuration
        )
        let body = try require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Token exchange request should have JSON body.")

        try expect(request.url?.absoluteString == "https://relay.example.com/github/copilot/token", "Token exchange should target configured relay.")
        try expect(body.contains("\"client_id\""), "Token exchange body should include client id.")
        try expect(body.contains("\"code\""), "Token exchange body should include OAuth code.")
        try expect(body.contains("\"redirect_uri\""), "Token exchange body should include redirect URI.")
        try expect(!body.lowercased().contains("client_secret"), "Token exchange body must not include a client secret.")
    }

    private func githubCopilotTokenClassifierRecognizesSupportedPrefixes() throws {
        let classifier = GitHubCopilotTokenClassifier()
        try expect(classifier.classify("gho_abc") == .oauthUser, "gho_ should be classified as OAuth user token.")
        try expect(classifier.classify("ghu_abc") == .githubAppUser, "ghu_ should be classified as GitHub App user token.")
        try expect(classifier.classify("github_pat_abc") == .fineGrainedPAT, "github_pat_ should be classified as fine-grained PAT.")
        try expect(classifier.classify("ghp_abc") == .classicPAT, "ghp_ should be classified as classic PAT.")
        try expect(!classifier.classify("ghp_abc").isRecommended, "Classic PAT should not be recommended.")
        try expect(classifier.classify("unknown") == .unsupported, "Unknown token prefixes should be unsupported.")
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

            private func agentRunLoggerAndCopilotBridgeExporterWriteWorkspaceFiles() async throws {
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
                let toolDefinition = CreateTodoAgentTool(todoRepository: TodoRepository()).definition
                let snapshot = AgentWorkspaceSnapshot(
                    workspaceName: workspace.displayName,
                    selectedPaper: nil,
                    recentPapers: [],
                    openTodos: [],
                    paperCount: 0,
                    todoCount: 0
                )
                let export = try await AgentCopilotBridgeExporter().export(
                    goal: "Plan a todo",
                    workspaceSnapshot: snapshot,
                    tools: [toolDefinition],
                    in: workspace
                )

                try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: export.promptRelativePath).path), "Copilot bridge exporter should write a prompt file.")
                try expect(FileManager.default.fileExists(atPath: workspace.fileURL(for: export.manifestRelativePath).path), "Copilot bridge exporter should write a manifest file.")

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

            private func agentServiceExecutesApprovedPlanAndExportsBridge() async throws {
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

                let export = try await service.exportCopilotBridge(
                    goal: "Create approved todo",
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id
                )
                try expect(FileManager.default.fileExists(atPath: root.fileURL(for: export.promptRelativePath).path), "Agent service should export a Copilot Bridge prompt.")
                try expect(FileManager.default.fileExists(atPath: root.fileURL(for: export.manifestRelativePath).path), "Agent service should export a Copilot Bridge manifest.")
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

            private func agentThreadRepositoryUpsertsProjectThreads() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentThreadRepository()
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

                let projectThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let globalThreads = try await repository.threads(in: root, projectID: nil)
                let threadsURL = root.fileURL(for: ".sci-station/agent/threads.jsonl")
                let lines = try String(contentsOf: threadsURL, encoding: .utf8).split(whereSeparator: \.isNewline)

                try expect(projectThreads.map(\.id) == ["agent-thread-alpha"], "Project thread history should be filtered by project id.")
                try expect(projectThreads.first?.runIDs == ["run-1", "run-2"], "Upserting a thread should preserve ordered run ids.")
                try expect(globalThreads.map(\.id) == ["agent-thread-global"], "Global thread history should include only global threads.")
                try expect(lines.count == 2, "Thread upsert should replace the existing thread record instead of duplicating it.")
            }

            private func agentThreadRepositoryArchivesAndReadsLegacyThreads() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentArchivedThreadWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let threadsURL = root.fileURL(for: ".sci-station/agent/threads.jsonl")
                let legacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread","project_id":"project-alpha","run_ids":["run-1"],"title":"Legacy thread","updated_at":"2026-04-29T00:00:01Z"}
                """
                try legacyLine.write(to: threadsURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository()
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
                    AgentPermissionRequest(path: "settings/github_copilot_token.yaml", risk: .writesWorkspace)
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
                try expect(items.last?.title == "Permission Requested", "Timeline items should label permission request events.")
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

    private func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw ValidationError(message: message)
        }
        return value
    }
}

private struct ValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct StaticLLMProvider: LLMProvider {
    let response: String

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        response
    }
}