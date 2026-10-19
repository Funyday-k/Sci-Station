import Foundation
import Testing
@testable import SciStationCore

@Suite("Plugin kit")
struct PluginKitTests {
    @Test("Plugin manifest validator rejects invalid IDs")
    func pluginManifestValidatorRejectsInvalidIDs() throws {
        let manifest = PluginManifest(
            id: "Bad Plugin",
            name: "",
            version: "",
            contributes: PluginContribution(commands: [
                CommandContribution(id: "paper.import", title: "Import", placement: .toolbar),
                CommandContribution(id: "paper.import", title: "Import Again", placement: .toolbar)
            ])
        )
        let issues = PluginManifestValidator().validate(manifest)
        let fields = Set(issues.map(\.field))

        try #require(fields.contains("id"), "Plugin validator should reject unstable plugin ids.")
        try #require(fields.contains("name"), "Plugin validator should require plugin names.")
        try #require(fields.contains("version"), "Plugin validator should require plugin versions.")
        try #require(fields.contains("contributes.commands"), "Plugin validator should reject duplicate command ids.")
    }

    @Test("Plugin registry resolves built-in workspace module adapters")
    func pluginRegistryResolvesBuiltInWorkspaceModuleAdapters() async throws {
        let manifests = WorkspaceModulePluginAdapter.builtInManifests()
        let registry = try PluginRegistry(manifests: manifests)
        let enabledIDs = try await registry.resolvedEnabledPluginIDs()
        let commands = try await registry.commandContributions()
        let modules = try await registry.workspaceModuleContributions().map(\.module)
        let tabs = try await registry.projectTabContributions()
        let workflows = try await registry.workflowContributions()
        let paperLibrary = try #require(manifests.first { $0.id == "sci.paper-library" }, "paper-library should adapt to a built-in plugin manifest.")

        try #require(enabledIDs.contains("sci.projects"), "Built-in plugin registry should expose enabled Projects plugin.")
        try #require(enabledIDs.contains("sci.paper-library"), "Built-in plugin registry should expose enabled Paper Library plugin.")
        try #require(!enabledIDs.contains("sci.code"), "Disabled workspace modules should remain disabled as plugin manifests.")
        try #require(commands.isEmpty, "Workspace module adapter should not invent command handlers before command migration.")
        try #require(modules.contains { $0.id == "paper-library" }, "Workspace module adapter should preserve module contribution payloads.")
        try #require(tabs.contains { $0.id == "papers" }, "Plugin registry should expose project tab contributions from enabled manifests.")
        try #require(workflows.contains { $0.id == "paper_reading" }, "Plugin registry should expose workflow contributions from enabled manifests.")
        try #require(paperLibrary.permissions.writePaths.contains("library/papers/"), "Workspace module adapter should preserve declared write paths.")
        try #require(paperLibrary.contributes.routes.contains { $0.id == "library" }, "Workspace module adapter should expose route contributions.")
    }

    @Test("Plugin workspace contribution catalog resolves built-in modules")
    func pluginWorkspaceContributionCatalogResolvesBuiltInModules() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(
            enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
        )
        let catalog = PluginWorkspaceContributionCatalog(configuration: configuration)
        let routeIDs = Set(catalog.availableRoutes().map(\.id))
        let tabIDs = Set(catalog.availableProjectTabs().map(\.id))
        let workflows = Set(catalog.availableWorkflows())
        let descriptor = catalog.artifactKindDescriptor(for: "research_plan")
        let unknownDescriptor = catalog.artifactKindDescriptor(for: "future_plugin_artifact")

        try #require(routeIDs.contains("projects"), "Plugin workspace catalog should expose enabled built-in routes.")
        try #require(!routeIDs.contains("library"), "Plugin workspace catalog should hide disabled module routes.")
        try #require(!routeIDs.contains("pdf-reader"), "Plugin workspace catalog should hide routes whose dependencies are disabled.")
        try #require(tabIDs.contains("overview"), "Plugin workspace catalog should expose project tabs from enabled modules.")
        try #require(!workflows.contains("paper_reading"), "Plugin workspace catalog should gate workflows by module requirements.")
        try #require(descriptor.isKnown && descriptor.moduleID == "projects", "Plugin workspace catalog should resolve known artifact descriptors.")
        try #require(!unknownDescriptor.isKnown && unknownDescriptor.title == "Future Plugin Artifact", "Plugin workspace catalog should fall back for unknown artifact descriptors.")
    }

    @Test("Command registry executes registered contribution")
    func commandRegistryExecutesRegisteredContribution() async throws {
        let registry = CommandRegistry()
        let contribution = CommandContribution(
            id: "paper.importPDF",
            title: "Import PDF",
            systemImage: "doc.badge.plus",
            placement: .toolbar,
            routePredicate: RoutePredicate(topLevelSectionIDs: ["library"])
        )
        try await registry.register(contribution, pluginID: "sci.paper-library") { context in
            CommandExecutionResult(
                succeeded: context.pluginID == "sci.paper-library" && context.commandID == "paper.importPDF",
                message: "ok"
            )
        }
        let visible = await registry.contributions(
            placement: .toolbar,
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let hidden = await registry.contributions(
            placement: .toolbar,
            context: WorkspaceContextSnapshot(topLevelSectionID: "home")
        )
        let result = try await registry.execute(id: "paper.importPDF")

        try #require(visible.map(\.id) == ["paper.importPDF"], "Command registry should expose route-matched toolbar commands.")
        try #require(hidden.isEmpty, "Command registry should hide commands when route predicates do not match.")
        try #require(result.succeeded && result.message == "ok", "Command registry should invoke registered command handlers.")
    }

    @Test("Declarative permission broker enforces manifest permissions")
    func declarativePermissionBrokerEnforcesManifestPermissions() async throws {
        let manifest = PluginManifest(
            id: "sci.openalex",
            name: "OpenAlex",
            permissions: PluginPermissionSet(
                readPaths: ["library/papers/"],
                writePaths: ["projects/*/outputs/"],
                networkHosts: ["api.openalex.org"],
                secrets: ["openalex_api_key"]
            )
        )
        let broker = DeclarativePermissionBroker(manifests: [manifest], fallbackDecision: .deny)
        let allowedRead = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .readFile, target: "library/papers/p1/paper.md", reason: "Read paper"))
        let allowedWrite = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .writeFile, target: "projects/demo/outputs/openalex.json", reason: "Write output"))
        let allowedNetwork = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .networkRequest, target: "https://api.openalex.org/works", reason: "Fetch metadata"))
        let deniedWrite = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .writeFile, target: "wiki/escape.md", reason: "Write wiki"))
        let deniedSecret = try await broker.authorize(PermissionRequest(pluginID: "sci.openalex", action: .readSecret, target: "other_key", reason: "Read secret"))

        try #require(allowedRead.kind == .allow, "Permission broker should allow manifest-declared read paths.")
        try #require(allowedWrite.kind == .allow, "Permission broker should allow manifest-declared wildcard write paths.")
        try #require(allowedNetwork.kind == .allow, "Permission broker should allow manifest-declared network hosts.")
        try #require(deniedWrite.kind == .deny, "Permission broker should deny undeclared write paths when fallback is deny.")
        try #require(deniedSecret.kind == .deny, "Permission broker should deny undeclared secrets when fallback is deny.")
    }

    @Test("VS Code bridge prepares Python run task")
    func vscodeBridgePreparesPythonRunTask() async throws {
        let suiteName = "SciStationCoreTests.PluginKit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspaceMaterialRepository()
        let bridgeService = VSCodeBridgeService()
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceRoot = containerURL.appendingPathComponent("VSCodeBridgeWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: containerURL)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let pythonURL = workspace.fileURL(for: "code/analysis.py")
        try "print('hello')\n".write(to: pythonURL, atomically: true, encoding: .utf8)

        let materials = try await repository.loadMaterials(in: workspace)
        let material = try #require(materials.first(where: { $0.relativePath == "code/analysis.py" }), "Expected Python material for VS Code bridge test.")

        try await bridgeService.preparePythonRunTask(for: material, in: workspace, runtimeMode: .workspaceVenv)

        let tasksText = try String(contentsOf: workspace.fileURL(for: ".vscode/tasks.json"), encoding: .utf8)
        let bridgeText = try String(contentsOf: workspace.fileURL(for: ".sci-station/vscode/last_python_run.json"), encoding: .utf8)

        try #require(tasksText.contains("Sci-Station: Run Python Material"), "VS Code bridge should write a runnable task label.")
        try #require(tasksText.contains("code/analysis.py"), "VS Code bridge should point to the selected Python material.")
        try #require(tasksText.contains(".venv/bin/python"), "VS Code bridge should use the selected workspace venv command.")
        try #require(bridgeText.contains("workspaceVenv"), "VS Code bridge should record the selected runtime mode.")
    }

    @Test("Module settings view model enable module requires dependencies")
    func moduleSettingsViewModelEnableModuleRequiresDependencies() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(
            enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
        )
        do {
            _ = try WorkspaceModuleSettingsMutation.setModule("recommendation", enabled: true, in: configuration)
            Issue.record("Enabling recommendation should require paper-library first.")
        } catch ModuleSettingsError.dependencyMissing(let missing) {
            try #require(missing == ["paper-library"], "Recommendation should report paper-library as the missing dependency.")
        } catch {
            throw error
        }
    }

    @Test("Module settings view model enable dependencies enables all ancestors")
    func moduleSettingsViewModelEnableDependenciesEnablesAllAncestors() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(
            enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library", "recommendation"])
        )
        let result = try WorkspaceModuleSettingsMutation.enableModuleAndDependencies("recommendation", in: configuration)
        let enabledIDs = result.configuration.enabledModuleIDs

        try #require(enabledIDs.contains("paper-library"), "Enable Dependencies should enable recommendation ancestors.")
        try #require(enabledIDs.contains("recommendation"), "Enable Dependencies should enable the requested module.")
        try #require(result.enabledChain == ["paper-library", "recommendation"], "Dependency chain should be deterministic and dependency-first.")
    }

    @Test("Module settings view model toggle pin persists order")
    func moduleSettingsViewModelTogglePinPersistsOrder() async throws {
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootURL = containerURL.appendingPathComponent("ModulePinWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let root = ResearchRoot(rootURL: rootURL)
        let repository = WorkspaceTemplateRepository()
        try repository.overwriteTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: root)

        var configuration = try repository.loadConfiguration(in: root)
        configuration = try WorkspaceModuleSettingsMutation.togglePin("tasks", in: configuration)
        configuration = try WorkspaceModuleSettingsMutation.movePin("tasks", newIndex: 0, in: configuration)

        let store = WorkspaceModuleConfigurationStore()
        try await store.save(configuration, in: root)
        let reloadedConfiguration = try await store.load(in: root)

        try #require(reloadedConfiguration.module(id: "tasks")?.pinned == true, "Pinned module should persist to workspace_modules.yaml.")
        try #require(WorkspaceModuleSettingsMutation.pinnedOrder(in: reloadedConfiguration).first == "tasks", "Pinned order should persist through the YAML round trip.")
    }

    @Test("Module settings view model disabling dependency hides routes")
    func moduleSettingsViewModelDisablingDependencyHidesRoutes() throws {
        let configuration = try WorkspaceModuleSettingsMutation.setModule("wiki", enabled: false, in: WorkspaceModuleRegistry.defaultConfiguration())
        let routes = Set(WorkspaceModuleRegistry.availableRoutes(in: configuration).map(\.id))
        let workflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: configuration))
        let warnings = WorkspaceModuleRegistry.warnings(for: configuration)

        try #require(!routes.contains("wiki"), "Disabling wiki should hide the Wiki route.")
        try #require(!workflows.contains("related_work"), "Workflows requiring wiki should be hidden.")
        try #require(warnings.contains { $0.id == "disabled-dependency:ai-lab:projects" } == false, "Unrelated dependency warnings should not be invented.")
        try #require(warnings.contains { $0.id == "disabled-dependency:code:wiki" } == false, "Disabled modules should not emit dependency-hidden warnings until enabled.")
    }

    @Test("Module settings view model override only affects target project")
    func moduleSettingsViewModelOverrideOnlyAffectsTargetProject() throws {
        let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
        let override = WorkspaceModuleOverride(
            projectID: "project-a",
            moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)]
        )
        let projectAConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)
        let projectBConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: nil)

        try #require(projectAConfiguration.module(id: "calendar")?.enabled == false, "Project A override should disable calendar.")
        try #require(projectBConfiguration.module(id: "calendar")?.enabled == true, "Project B should keep the workspace calendar setting.")
        try #require(projectAConfiguration.module(id: "calendar")?.title == workspaceConfiguration.module(id: "calendar")?.title, "Override should not replace registry metadata.")
    }

    @Test("Module override merger only mutates enabled field")
    func moduleOverrideMergerOnlyMutatesEnabledField() throws {
        var workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
        workspaceConfiguration = try WorkspaceModuleSettingsMutation.togglePin("calendar", in: workspaceConfiguration)
        let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)])
        let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

        try #require(effectiveConfiguration.module(id: "calendar")?.enabled == false, "Override should update enabled.")
        try #require(effectiveConfiguration.module(id: "calendar")?.pinned == true, "Override should not mutate pinned.")
        try #require(effectiveConfiguration.module(id: "calendar")?.routes == workspaceConfiguration.module(id: "calendar")?.routes, "Override should not mutate registry routes.")
    }

    @Test("Module override merger leaves unknown IDs as no-op")
    func moduleOverrideMergerLeavesUnknownIDsAsNoOp() throws {
        let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
        let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "third-party-module", enabled: true)])
        let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

        try #require(effectiveConfiguration == workspaceConfiguration, "Unknown override module ids should be ignored.")
    }
}
