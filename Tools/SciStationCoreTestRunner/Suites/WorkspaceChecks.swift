import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runWorkspace() async {
        await runCheck("createWorkspaceInitializesExpectedStructure") { try await createWorkspaceInitializesExpectedStructure() }
        await runCheck("createWorkspaceInitializesResearchRootAndDefaultProject") { try await createWorkspaceInitializesResearchRootAndDefaultProject() }
        await runCheck("createWorkspaceInitializesAgentWorkspaceProfile") { try await createWorkspaceInitializesAgentWorkspaceProfile() }
        await runCheck("projectRegistryCreatesUpdatesAndCollapsesProjects") { try await projectRegistryCreatesUpdatesAndCollapsesProjects() }
        await runCheck("openWorkspaceBackfillsMissingStructure") { try await openWorkspaceBackfillsMissingStructure() }
        await runCheck("openLegacyWorkspaceCreatesResearchRootRegistry") { try await openLegacyWorkspaceCreatesResearchRootRegistry() }
        await runCheck("restoreLastWorkspaceClearsMissingBookmark") { try await restoreLastWorkspaceClearsMissingBookmark() }
        await runCheck("workspacePreferencesRoundTrip") { try await workspacePreferencesRoundTrip() }
        await runCheck("workspacePreferencesLanguageRoundTrips") { try await workspacePreferencesLanguageRoundTrips() }
        await runCheck("projectTreeArchiveFallsBackToProjectsRoute") { try await projectTreeArchiveFallsBackToProjectsRoute() }
        await runCheck("projectArchiveHidesProjectFromActiveList") { try await projectArchiveHidesProjectFromActiveList() }
        await runCheck("projectRestoreReturnsProjectToActiveList") { try await projectRestoreReturnsProjectToActiveList() }
        await runCheck("projectDeleteMovesToTrashOrArchive") { try await projectDeleteMovesToTrashOrArchive() }
        await runCheck("workspaceFileSystemRejectsEscapingPathsAndWritesAtomically") { try await workspaceFileSystemRejectsEscapingPathsAndWritesAtomically() }
        await runCheck("workspacePreferencesSchemaVersion2BackwardCompat") { try await workspacePreferencesSchemaVersion2BackwardCompat() }
        await runCheck("workspacePreferencesSchemaVersionForRightRail") { try await workspacePreferencesSchemaVersionForRightRail() }
        await runCheck("workspaceMaterialRepositoryLoadsOnlyUserMaterials") { try await workspaceMaterialRepositoryLoadsOnlyUserMaterials() }
        await runCheck("jsonlWriterAppendsDurableDedupedLines") { try await jsonlWriterAppendsDurableDedupedLines() }
        await runCheck("workspaceTemplateModuleConfigWritesAndLegacyMigration") { try await workspaceTemplateModuleConfigWritesAndLegacyMigration() }
        await runCheck("workspaceCreationWizardPreviewValidationAndSafety") { try await workspaceCreationWizardPreviewValidationAndSafety() }
        await runCheck("workspaceModuleRegistryV1GatesRoutesWorkflowsAndArtifacts") { try workspaceModuleRegistryV1GatesRoutesWorkflowsAndArtifacts() }
        await runCheck("workspaceModuleRegistryGatesGraphWorkflows") { try workspaceModuleRegistryGatesGraphWorkflows() }
        await runCheck("workspaceModuleRegistryDoesNotExposeRetiredReadingWorkflow") { try workspaceModuleRegistryDoesNotExposeRetiredReadingWorkflow() }
        await runCheck("workspaceModuleDirectoryRepairerSkipsWildcardPaths") { try await workspaceModuleDirectoryRepairerSkipsWildcardPaths() }
        await runCheck("workspaceModuleDirectoryRepairerRequiresPermissionApproval") { try await workspaceModuleDirectoryRepairerRequiresPermissionApproval() }
        await runCheck("workspaceModuleConfigurationStoreNotifiesObserversAtomically") { try await workspaceModuleConfigurationStoreNotifiesObserversAtomically() }
        await runCheck("templateAndSettingsRoundTripsAreIdentical") { try await templateAndSettingsRoundTripsAreIdentical() }
        await runCheck("stableToolResultV1MapsToToolCallCompletedEvent") { try stableToolResultV1MapsToToolCallCompletedEvent() }
        await runCheck("persistentLedgerPreventsDuplicateApprovedWriteAfterRestart") { try await persistentLedgerPreventsDuplicateApprovedWriteAfterRestart() }
        await runCheck("approvalRequestPersistsFingerprintForLedgerResume") { try await approvalRequestPersistsFingerprintForLedgerResume() }
        await runCheck("deterministicSafetyPolicyBlocksSecretPromptBeforeLLM") { try await deterministicSafetyPolicyBlocksSecretPromptBeforeLLM() }
        await runCheck("hookDenyBlocksSensitivePathWrite") { try await hookDenyBlocksSensitivePathWrite() }
    }

    func createWorkspaceInitializesExpectedStructure() async throws {
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

    func createWorkspaceInitializesResearchRootAndDefaultProject() async throws {
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

    func createWorkspaceInitializesAgentWorkspaceProfile() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let workspaceURL = temporaryDirectoryURL().appendingPathComponent("AgentProfileWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let profile = try await AgentWorkspaceProfileRepository().load(in: root)
        let profileURL = root.fileURL(for: AgentWorkspaceProfileRepository.relativePath)

        try expect(FileManager.default.fileExists(atPath: profileURL.path), "Workspace creation should seed an editable agent workspace profile.")
        try expect(profile.promptTemplates.isEmpty, "Seeded agent workspace profile should not contain prompt plaintext by default.")
        try expect(profile.skillToggles.isEmpty, "Seeded agent workspace profile should start without user skill overrides.")
        try expect(profile.mcpServers.isEmpty, "Seeded agent workspace profile should start without user MCP servers.")
        try expect(AgentWorkspaceProfileValidator().validate(profile).isEmpty, "Seeded agent workspace profile should validate.")
    }

    func projectRegistryCreatesUpdatesAndCollapsesProjects() async throws {
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

    func openWorkspaceBackfillsMissingStructure() async throws {
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

    func openLegacyWorkspaceCreatesResearchRootRegistry() async throws {
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

    func restoreLastWorkspaceClearsMissingBookmark() async throws {
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

    func workspacePreferencesRoundTrip() async throws {
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
        preferences.liquidGlassTint = .mint
        preferences.agentChatFontSize = 17
        preferences.agentDebugLoggingEnabled = true
        preferences.agentLoopBudget = AgentLoopOptions(
            maxSteps: 13,
            maxToolCalls: 34,
            maxContextCharacters: 222_000,
            maxToolResultCharactersPerCall: 55_000,
            maxAccumulatedToolResultCharacters: 333_000,
            autoApproveReadOnly: false,
            allowProviderNativeTools: false
        )
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
        try expect(loadedPreferences.liquidGlassTint == .mint, "Workspace preferences should preserve Liquid Glass tint.")
        try expect(loadedPreferences.agentChatFontSize == 17, "Workspace preferences should preserve AI Lab chat font size.")
        try expect(loadedPreferences.agentLoopBudget == preferences.agentLoopBudget, "Workspace preferences should preserve AI Lab loop budget.")
        try expect(loadedPreferences.agentDebugLoggingEnabled == true, "Workspace preferences should preserve debug logging mode.")
        try expect(loadedPreferences.minerUCommand == "mineru", "Workspace preferences should preserve MinerU command.")
        try expect(loadedPreferences.minerUAPIBaseURLString == "https://mineru.example.com", "Workspace preferences should preserve MinerU API base URL.")
        try expect(loadedPreferences.minerUAPILanguage == "zh", "Workspace preferences should preserve MinerU API language.")
        try expect(loadedPreferences.minerUOverwriteExistingMarkdown == false, "Workspace preferences should preserve MinerU overwrite behavior.")
        try expect(loadedPreferences.agentDisabledToolNamesByScope["project:test-workspace|thread:agent-thread-1"] == ["create_todo", "write_markdown_plan"], "Workspace preferences should preserve scoped disabled tools.")
        try expect(loadedPreferences.pinnedAgentThreadIDsByProject["test-workspace"] == ["agent-thread-1"], "Workspace preferences should preserve project-scoped pinned threads.")
    }

    func workspacePreferencesLanguageRoundTrips() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LanguagePreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.appLanguage = .english
        try await repository.save(preferences, in: workspace)

        let englishPreferences = try await repository.load(in: workspace)
        preferences.appLanguage = .simplifiedChinese
        try await repository.save(preferences, in: workspace)
        let chinesePreferences = try await repository.load(in: workspace)

        try expect(englishPreferences.appLanguage == .english, "Workspace preferences should round-trip English app language.")
        try expect(chinesePreferences.appLanguage == .simplifiedChinese, "Workspace preferences should round-trip Chinese app language.")
    }

    func projectTreeArchiveFallsBackToProjectsRoute() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectArchiveRouteWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let project = try await repository.createProject(named: "Archive Candidate", in: root)
        var archivedProject = project
        archivedProject.isArchived = true
        let registry = try await repository.updateProject(archivedProject, in: root)
        let activeProjectIDs = Set(registry.projects.filter { !$0.isArchived }.map(\.id))
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: project.id, projectTabID: "papers"),
            activeProjectIDs: activeProjectIDs,
            configuration: WorkspaceModuleRegistry.defaultConfiguration()
        )

        try expect(result.route == WorkspaceRoute(top: .projects), "Routes pointing at an archived project should fall back to the Projects list.")
        try expect(result.fallbackReason == .projectMissing, "Archived projects should be treated as unavailable for route restoration.")
    }

    func projectArchiveHidesProjectFromActiveList() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectArchiveWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let firstProject = try await repository.createProject(named: "Archive Candidate", in: root)
        let secondProject = try await repository.createProject(named: "Still Active", in: root)
        let result = try await repository.archiveProject(firstProject.id, in: root)
        let activeProjectIDs = result.registry.projects.filter { !$0.isArchived }.map(\.id)
        let projectFileContents = try String(contentsOf: root.fileURL(for: firstProject.relativePath + "/project.yaml"), encoding: .utf8)

        try expect(result.project.isArchived, "Archived projects should be marked archived.")
        try expect(!activeProjectIDs.contains(firstProject.id), "Archived projects should disappear from active project lists.")
        try expect(activeProjectIDs == [secondProject.id], "Only non-archived projects should remain active.")
        try expect(projectFileContents.contains("is_archived: true"), "Archived project.yaml should mirror archived lifecycle state.")
    }

    func projectRestoreReturnsProjectToActiveList() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectRestoreWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let project = try await repository.createProject(named: "Restore Candidate", in: root)

        _ = try await repository.archiveProject(project.id, in: root)
        let result = try await repository.restoreProject(project.id, in: root)
        let restoredProject = try require(result.registry.projects.first { $0.id == project.id }, "Restored project should remain in the registry.")

        try expect(!restoredProject.isArchived, "Restored projects should be active.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: restoredProject.relativePath).path), "Restored project directory should exist.")
        try expect(result.registry.lastOpenedProjectID == project.id, "Restored project should become the last opened project.")
    }

    func projectDeleteMovesToTrashOrArchive() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("ProjectTrashWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let repository = ProjectRegistryRepository()
        let project = try await repository.createProject(named: "Trash Candidate", in: root)
        let originalURL = root.directoryURL(for: project.relativePath)
        let result = try await repository.deleteProjectToTrash(project.id, in: root)
        let trashedProject = try require(result.registry.projects.first { $0.id == project.id }, "Trashed project should remain recoverable in the registry.")

        try expect(trashedProject.isArchived, "Trashed projects should be hidden from active lists.")
        try expect(trashedProject.relativePath.hasPrefix(".sci-station/trash/projects/"), "Trashed projects should move under the workspace trash.")
        try expect(!FileManager.default.fileExists(atPath: originalURL.path), "Original project directory should be moved out of projects/.")
        try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: trashedProject.relativePath).path), "Trashed project directory should exist in workspace trash.")
        let trashedProjectFile = try String(contentsOf: root.fileURL(for: trashedProject.relativePath + "/project.yaml"), encoding: .utf8)
        try expect(trashedProjectFile.contains("relative_path: \"\(trashedProject.relativePath)\""), "Trashed project.yaml should mirror the trash relative path.")
    }

    func workspaceFileSystemRejectsEscapingPathsAndWritesAtomically() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("WorkspaceFileSystem", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileSystem = WorkspaceFileSystem(rootURL: rootURL)
        let path = try WorkspaceRelativePath("projects/demo/wiki/note.md")

        try await fileSystem.writeText("hello", to: path)
        let loaded = try await fileSystem.readText(path)
        let exists = await fileSystem.exists(path)

        try expect(loaded == "hello", "WorkspaceFileSystem should write and read text within the research root.")
        try expect(exists, "WorkspaceFileSystem should report existing managed paths.")
        do {
            _ = try WorkspaceRelativePath("../escape.md")
            try expect(false, "WorkspaceRelativePath should reject parent traversal.")
        } catch WorkspaceFileSystemError.invalidRelativePath {
        }
        do {
            _ = try WorkspaceRelativePath("/tmp/escape.md")
            try expect(false, "WorkspaceRelativePath should reject absolute paths.")
        } catch WorkspaceFileSystemError.invalidRelativePath {
        }
    }

    func workspacePreferencesSchemaVersion2BackwardCompat() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("PreferencesV1Workspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        try FileManager.default.createDirectory(at: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "schema_version: 1\nlibrary_visible_columns:\n  - \"title\"\nrecent_section: \"library\"\n".write(to: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath), atomically: true, encoding: .utf8)

        let preferences = try await WorkspacePreferencesRepository().load(in: workspace)
        try expect(preferences.schemaVersion == WorkspacePreferences.currentSchemaVersion, "Loading v1 preferences should normalize to the current schema version.")
        try expect(preferences.liquidGlassTint == .system, "Loading old preferences should default Liquid Glass tint to system accent.")
        try expect(preferences.pinnedTopLevelOrder == WorkspacePreferences.defaultPinnedTopLevelOrder, "Loading v1 preferences should fill top-level pin defaults.")
        try expect(preferences.projectSpacePinnedOrder.isEmpty, "Loading v1 preferences should fill an empty ProjectSpace pin order.")
    }

    func workspacePreferencesSchemaVersionForRightRail() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("PreferencesRightRailSchemaWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let workspace = ResearchWorkspace(rootURL: rootURL)
        try FileManager.default.createDirectory(at: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try "schema_version: 2\nlibrary_visible_columns:\n  - \"title\"\nrecent_section: \"library\"\n".write(to: workspace.fileURL(for: WorkspacePreferencesRepository.relativePath), atomically: true, encoding: .utf8)

        let preferences = try await WorkspacePreferencesRepository().load(in: workspace)
        try expect(preferences.schemaVersion == WorkspacePreferences.currentSchemaVersion, "Loading pre-P43.5 preferences should normalize to the right-rail schema version.")
        try expect(preferences.rightRailMode == .inspector, "Pre-P43.5 preferences should default to inspector mode for context-rich routes.")
        try expect(!preferences.isGlobalAIPanelOpen, "Pre-P43.5 preferences should default the global AI panel to closed.")
        try expect(preferences.isProjectTreeExpanded, "Pre-P43.5 preferences should default the project tree to expanded.")
        try expect(preferences.pinnedProjectIDs.isEmpty, "Pre-P43.5 preferences should default pinned project ids to empty.")
    }

    func workspaceMaterialRepositoryLoadsOnlyUserMaterials() async throws {
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

    func jsonlWriterAppendsDurableDedupedLines() async throws {
        let url = temporaryDirectoryURL().appendingPathComponent("jsonl/events.jsonl")
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent())
        }

        struct DummyEvent: Codable, Hashable {
            var id: String
            var sequence: Int
        }

        let writer = JSONLWriter(url: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String else {
                return nil
            }
            return id
        }
        _ = try await writer.append(DummyEvent(id: "e1", sequence: 1), id: "e1")
        _ = try await writer.append(DummyEvent(id: "e1", sequence: 1), id: "e1")
        _ = try await writer.append(DummyEvent(id: "e2", sequence: 2), id: "e2")

        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        try expect(lines.count == 2, "Duplicate id should be skipped by the writer dedup cache.")
    }

    func workspaceTemplateModuleConfigWritesAndLegacyMigration() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("SciStationTemplateTest-\(UUID().uuidString)", isDirectory: true)
        let minimalURL = baseURL.appendingPathComponent("Minimal", isDirectory: true)
        let legacyURL = baseURL.appendingPathComponent("Legacy", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let service = WorkspaceService()
        let minimalWorkspace = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.minimal)
        let minimalTemplate = try String(contentsOf: minimalWorkspace.fileURL(for: WorkspaceTemplateRepository.templateRelativePath), encoding: .utf8)
        let minimalModules = try String(contentsOf: minimalWorkspace.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)
                let repository = WorkspaceTemplateRepository()
                let minimalConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: try repository.decodeConfiguration(minimalModules))

        try expect(minimalTemplate.contains(#"id: "minimal-workspace""#), "Minimal workspace should write workspace_template.yaml.")
                try expect(minimalModules.contains("schema_version: 1"), "Workspace module config should write schema_version 1.")
        try expect(minimalModules.contains(#"id: "paper-library""#), "Workspace module config should include built-in paper-library declaration.")
        try expect(minimalModules.contains(#"enabled: false"#), "Minimal template should keep disabled built-in modules declared without deleting data.")
                try expect(minimalConfiguration.modules.count == 15, "V1 module registry should declare the deterministic built-in module set.")
                try expect(minimalConfiguration.module(id: "code")?.enabled == false, "Future modules should be present but disabled by default.")
                try expect(WorkspaceModuleRegistry.availableRoutes(in: minimalConfiguration).contains { $0.id == "ai-lab" }, "Enabled AI Lab module should expose its route.")

        try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("raw/papers", isDirectory: true), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("settings", isDirectory: true), withIntermediateDirectories: true)
                try """
                schema_version: 0
                modules:
                    - id: "projects"
                        title: "Projects"
                        version: "0.1.0"
                        enabled: true
                        directories:
                            - "projects"
                        routes:
                            - "/projects"
                        workflows:
                            - "gap_planning"
                        permission_scope:
                            write_paths:
                                - "projects/*/wiki/"
                """.write(to: legacyURL.appendingPathComponent(WorkspaceTemplateRepository.modulesRelativePath, isDirectory: false), atomically: true, encoding: .utf8)
        _ = try await service.openWorkspace(at: legacyURL)
        let legacyTemplateURL = legacyURL.appendingPathComponent(WorkspaceTemplateRepository.templateRelativePath, isDirectory: false)
        let legacyModulesURL = legacyURL.appendingPathComponent(WorkspaceTemplateRepository.modulesRelativePath, isDirectory: false)
                let migratedModules = try String(contentsOf: legacyModulesURL, encoding: .utf8)
        try expect(FileManager.default.fileExists(atPath: legacyTemplateURL.path), "Opening legacy workspace should backfill workspace_template.yaml.")
        try expect(FileManager.default.fileExists(atPath: legacyModulesURL.path), "Opening legacy workspace should backfill workspace_modules.yaml.")
                try expect(migratedModules.contains("schema_version: 1"), "Opening legacy module config should migrate it to schema_version 1.")
        try expect(FileManager.default.fileExists(atPath: legacyURL.appendingPathComponent("raw/papers", isDirectory: true).path), "Legacy migration should not delete existing user data.")
    }

    func workspaceCreationWizardPreviewValidationAndSafety() async throws {
        let baseURL = temporaryDirectoryURL().appendingPathComponent("P40Wizard", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let minimalDraft = WorkspaceCreationWizard.draft(selecting: WorkspaceTemplateRegistry.minimal)
        let minimalPreview = WorkspaceCreationWizard.preview(for: minimalDraft)
        let minimalEnabledIDs = Set(minimalPreview.enabledModules.map(\.id))
        let minimalRoutes = Set(minimalPreview.routes.map(\.id))
        let safeDirectories = WorkspaceCreationWizard.safeDirectoryPathsToCreate(for: WorkspaceTemplateRegistry.minimal)

        try expect(minimalPreview.configuration.schemaVersion == 1, "Workspace creation preview should use module schema_version 1.")
        try expect(minimalEnabledIDs == Set(WorkspaceTemplateRegistry.minimal.enabledModuleIDs), "Wizard preview should derive enabled modules from the selected template.")
        try expect(minimalRoutes.contains("ai-lab"), "Minimal wizard preview should expose the AI Lab route.")
        try expect(!minimalRoutes.contains("library"), "Minimal wizard preview should hide Library when paper-library is disabled.")
        try expect(minimalPreview.directoryItems.contains { $0.path == "projects/*/wiki" && !$0.willCreate && $0.isWildcard }, "Wildcard project directories should be preview-only and not created directly.")
        try expect(safeDirectories.contains("settings") && safeDirectories.contains(".sci-station/agent"), "Safe directory resolver should include settings and AI Lab agent state directories.")
        try expect(!safeDirectories.contains { $0.contains("*") || $0.hasSuffix(".yaml") || !WorkspaceModuleSchema.isSafeRelativePathPattern($0) }, "Safe directory resolver should filter wildcard, settings files, and unsafe relative paths.")

        let newRootURL = baseURL.appendingPathComponent("NewRoot", isDirectory: true)
        let newValidation = WorkspaceCreationWizard.validateTargetURL(newRootURL)
        try expect(newValidation.canCreate && newValidation.state == .newFolder, "Wizard validation should allow a new folder under an existing parent.")

        let emptyRootURL = baseURL.appendingPathComponent("EmptyRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRootURL, withIntermediateDirectories: true)
        let emptyValidation = WorkspaceCreationWizard.validateTargetURL(emptyRootURL)
        try expect(emptyValidation.canCreate && emptyValidation.state == .emptyFolder, "Wizard validation should allow an empty folder.")

        let fileURL = baseURL.appendingPathComponent("not-a-root.txt", isDirectory: false)
        try "not a folder".write(to: fileURL, atomically: true, encoding: .utf8)
        let fileValidation = WorkspaceCreationWizard.validateTargetURL(fileURL)
        try expect(!fileValidation.canCreate && fileValidation.state == .blockedFile, "Wizard validation should reject file destinations.")

        let nonEmptyURL = baseURL.appendingPathComponent("NonEmpty", isDirectory: true)
        try FileManager.default.createDirectory(at: nonEmptyURL, withIntermediateDirectories: true)
        try "user data".write(to: nonEmptyURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let nonEmptyValidation = WorkspaceCreationWizard.validateTargetURL(nonEmptyURL)
        try expect(!nonEmptyValidation.canCreate && nonEmptyValidation.state == .blockedNonEmptyFolder, "Wizard validation should block non-empty folders that are not compatible workspaces.")

        let legacyURL = baseURL.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL.appendingPathComponent("settings", isDirectory: true), withIntermediateDirectories: true)
        try "schema_version: 1\n".write(to: legacyURL.appendingPathComponent("settings/workspace_preferences.yaml"), atomically: true, encoding: .utf8)
        let legacyValidation = WorkspaceCreationWizard.validateTargetURL(legacyURL)
        try expect(legacyValidation.canCreate && legacyValidation.state == .legacyWorkspace, "Wizard validation should allow compatible legacy workspaces.")

        let service = WorkspaceService()
        let minimalURL = baseURL.appendingPathComponent("ExistingMinimal", isDirectory: true)
        let workspace = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.minimal)
        let moduleConfigURL = workspace.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath)
        let beforeModules = try String(contentsOf: moduleConfigURL, encoding: .utf8)
        _ = try await service.createWorkspace(at: minimalURL, template: WorkspaceTemplateRegistry.literatureReview)
        let afterModules = try String(contentsOf: moduleConfigURL, encoding: .utf8)
        let repository = WorkspaceTemplateRepository()
        let afterConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: try repository.decodeConfiguration(afterModules))

        try expect(beforeModules == afterModules, "Re-running create on an existing Research Root should not overwrite workspace_modules.yaml.")
        try expect(afterConfiguration.module(id: "paper-library")?.enabled == false, "Existing module choices should be preserved when a compatible root is opened through the wizard path.")

        let generatedSettingsText = [
            afterModules,
            try String(contentsOf: workspace.fileURL(for: WorkspaceTemplateRepository.templateRelativePath), encoding: .utf8),
            try String(contentsOf: workspace.fileURL(for: "settings/llm.yaml"), encoding: .utf8),
            try String(contentsOf: workspace.fileURL(for: "settings/agent.yaml"), encoding: .utf8)
        ].joined(separator: "\n")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("api_key"), "Workspace creation should not write API key placeholders into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("provider_raw_config"), "Workspace creation should not write provider raw config into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("prompt:"), "Workspace creation should not write prompt plaintext into generated settings files.")
        try expect(!generatedSettingsText.localizedCaseInsensitiveContains("response:"), "Workspace creation should not write response plaintext into generated settings files.")
    }

        func workspaceModuleRegistryV1GatesRoutesWorkflowsAndArtifacts() throws {
                let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let defaultRoutes = Set(WorkspaceModuleRegistry.availableRoutes(in: defaultConfiguration).map(\.id))
                let defaultProjectTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: defaultConfiguration).map(\.id))
                let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))

                try expect(defaultConfiguration.modules.map(\.id) == [
                        "projects",
                        "paper-library",
                        "wiki",
                        "materials",
                        "tasks",
                        "calendar",
                        "pdf-reader",
                        "ai-lab",
                        "code",
                        "datasets",
                        "experiments",
                        "citation-graph",
                        "recommendation",
                        "writing",
                        "theory-notes"
                ], "Built-in module registry order should be deterministic.")
                try expect(defaultRoutes.contains("projects") && defaultRoutes.contains("library") && defaultRoutes.contains("ai-lab"), "Default modules should expose core routes.")
                try expect(!defaultRoutes.contains("code") && !defaultRoutes.contains("experiments"), "Future modules should stay hidden until enabled.")
                try expect(defaultProjectTabs.contains("overview") && defaultProjectTabs.contains("papers") && defaultProjectTabs.contains("tasks"), "Default project tabs should be registry-driven.")
                try expect(defaultWorkflows.contains("paper_reading") && defaultWorkflows.contains("related_work") && defaultWorkflows.contains("gap_planning"), "Default AI workflows should be available when required modules are enabled.")

                let noLibraryConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                        enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
                )
                let noLibraryRoutes = Set(WorkspaceModuleRegistry.availableRoutes(in: noLibraryConfiguration).map(\.id))
                let noLibraryWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noLibraryConfiguration))
                try expect(!noLibraryRoutes.contains("library"), "Disabled paper-library module should hide the Library route.")
                try expect(!noLibraryRoutes.contains("pdf-reader"), "Modules with disabled dependencies should hide their routes.")
                try expect(!noLibraryWorkflows.contains("paper_reading"), "Workflow requirements should hide paper_reading when paper-library is disabled.")
                try expect(!noLibraryWorkflows.contains("related_work"), "Workflow requirements should hide related_work when paper-library is disabled.")
                try expect(!noLibraryWorkflows.contains("gap_planning"), "gap_planning should hide when citation-graph is unavailable through paper-library dependency.")

                let descriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "paper_reading_note", in: defaultConfiguration)
                let unknownDescriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "future_artifact", in: defaultConfiguration)
                try expect(descriptor.isKnown && descriptor.moduleID == "paper-library", "Known artifact kinds should resolve to their declaring module.")
                try expect(!unknownDescriptor.isKnown && unknownDescriptor.title == "Future Artifact", "Unknown artifact kinds should fall back to a readable descriptor.")

                let codeWithoutAILab = WorkspaceModuleRegistry.defaultConfiguration(enabledModuleIDs: ["projects", "wiki", "code"])
                let warnings = WorkspaceModuleRegistry.warnings(for: codeWithoutAILab)
                try expect(warnings.contains { $0.id == "disabled-dependency:code:ai-lab" }, "Enabled modules with disabled dependencies should produce registry warnings.")

                let scopeDescription = WorkspaceModuleRegistry.moduleScopeDescription(for: ["projects/demo/wiki/research_plan.md"], in: defaultConfiguration)
                try expect(scopeDescription?.contains("Wiki") == true || scopeDescription?.contains("Projects") == true, "Module approval scope should explain matching module write paths.")
        }

            func workspaceModuleRegistryGatesGraphWorkflows() throws {
                let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))
                try expect(defaultWorkflows.contains("graph_insight"), "Default configuration should expose graph_insight when AI Lab and Citation Graph are enabled.")
                try expect(defaultWorkflows.contains("related_work"), "related_work should remain available when Citation Graph is enabled.")
                try expect(defaultWorkflows.contains("gap_planning"), "gap_planning should remain available when Citation Graph is enabled.")

                let noGraphConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["citation-graph"])
                )
                let noGraphWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noGraphConfiguration))
                try expect(!noGraphWorkflows.contains("graph_insight"), "graph_insight should be gated by Citation Graph.")
                try expect(!noGraphWorkflows.contains("related_work"), "related_work should be gated by Citation Graph.")
                try expect(!noGraphWorkflows.contains("gap_planning"), "gap_planning should be gated by Citation Graph.")

                let noAILabConfiguration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["ai-lab"])
                )
                let noAILabWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: noAILabConfiguration))
                try expect(!noAILabWorkflows.contains("graph_insight"), "graph_insight should also require AI Lab.")
            }

    func workspaceModuleRegistryDoesNotExposeRetiredReadingWorkflow() throws {
        let defaultConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
        let defaultWorkflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: defaultConfiguration))
        try expect(!defaultWorkflows.contains("reading_queue_curate"), "The retired reading_queue_curate workflow should no longer be available.")
        try expect(!defaultWorkflows.contains("research_queue_update"), "The retired research_queue_update workflow should no longer be available.")

        let availableProjectTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: defaultConfiguration).map(\.id))
        try expect(!availableProjectTabs.contains("reading"), "Reading tab should not remain available after it is merged into Tasks.")
        try expect(availableProjectTabs.contains("tasks"), "Tasks tab should remain the project-space destination for reading todos.")
        try expect(!availableProjectTabs.contains("queue"), "Queue tab should not remain available after Reading consolidation.")
        try expect(!availableProjectTabs.contains("reading-plan"), "Reading Plan tab should not remain available after Reading consolidation.")

        try expect(WorkspaceModuleRegistry.workflowRequirements["reading_queue_curate"] == nil, "The retired reading_queue_curate workflow should no longer declare requirements.")
    }

            func workspaceModuleDirectoryRepairerSkipsWildcardPaths() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRepairWildcardWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let status = WorkspaceModuleDirectoryStatus(moduleID: "wiki", moduleTitle: "Wiki", path: "projects/*/wiki/", required: true, repairable: true, exists: false)
                let repairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .allow)
                }
                let outcome = await repairer.repair(status, in: root, activeProjects: [])

                try expect(outcome == .skippedWildcard(path: "projects/*/wiki/"), "Wildcard repair should be skipped when no active project instance exists.")
            }

            func workspaceModuleDirectoryRepairerRequiresPermissionApproval() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRepairApprovalWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let status = WorkspaceModuleDirectoryStatus(moduleID: "tasks", moduleTitle: "Tasks", path: "tasks", required: true, repairable: true, exists: false)
                let deniedRepairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .deny, message: "test deny")
                }
                let deniedOutcome = await deniedRepairer.repair(status, in: root)
                try expect(deniedOutcome == .denied(path: "tasks", reason: "test deny"), "Repair should not create directories without approval.")
                try expect(!FileManager.default.fileExists(atPath: root.directoryURL(for: "tasks").path), "Denied repair should not write the workspace.")

                let approvedRepairer = WorkspaceModuleDirectoryRepairer { _ in
                    AgentPermissionDecision(action: .allow)
                }
                let approvedOutcome = await approvedRepairer.repair(status, in: root)
                try expect(approvedOutcome == .created(paths: ["tasks"]), "Approved repair should create the missing directory.")
                try expect(FileManager.default.fileExists(atPath: root.directoryURL(for: "tasks").path), "Approved repair should create tasks/.")
            }

            func workspaceModuleConfigurationStoreNotifiesObserversAtomically() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleStoreWatchWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                try WorkspaceTemplateRepository().overwriteTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: root)
                let store = WorkspaceModuleConfigurationStore()
                let stream = store.subscribeChanges(in: root)

                async let observedConfiguration: WorkspaceModuleConfiguration = firstModuleConfiguration(from: stream)
                var configuration = try await store.load(in: root)
                configuration = try WorkspaceModuleSettingsMutation.setModule("code", enabled: true, in: configuration)
                try await store.save(configuration, in: root)
                let observed = try await observedConfiguration

                try expect(observed.module(id: "code")?.enabled == true, "Store watcher should publish the atomically saved module configuration.")
            }

            func templateAndSettingsRoundTripsAreIdentical() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModuleRoundTripWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let repository = WorkspaceTemplateRepository()
                try repository.overwriteTemplateConfiguration(WorkspaceTemplateRegistry.minimal, in: root)
                let originalYAML = try String(contentsOf: root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)
                let loadedConfiguration = try repository.loadConfiguration(in: root)
                try await WorkspaceModuleConfigurationStore().save(loadedConfiguration, in: root)
                let savedYAML = try String(contentsOf: root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath), encoding: .utf8)

                try expect(savedYAML == originalYAML, "Wizard and Module Settings should use identical workspace_modules.yaml serialization.")
            }

    func stableToolResultV1MapsToToolCallCompletedEvent() throws {
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

    func persistentLedgerPreventsDuplicateApprovedWriteAfterRestart() async throws {
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

    func approvalRequestPersistsFingerprintForLedgerResume() async throws {
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

    func deterministicSafetyPolicyBlocksSecretPromptBeforeLLM() async throws {
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

    func hookDenyBlocksSensitivePathWrite() async throws {
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
}
