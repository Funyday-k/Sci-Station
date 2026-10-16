import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runPlugins() async {
        await runCheck("pluginManifestValidatorRejectsInvalidIDs") { try pluginManifestValidatorRejectsInvalidIDs() }
        await runCheck("pluginRegistryResolvesBuiltInWorkspaceModuleAdapters") { try await pluginRegistryResolvesBuiltInWorkspaceModuleAdapters() }
        await runCheck("pluginWorkspaceContributionCatalogResolvesBuiltInModules") { try pluginWorkspaceContributionCatalogResolvesBuiltInModules() }
        await runCheck("commandRegistryExecutesRegisteredContribution") { try await commandRegistryExecutesRegisteredContribution() }
        await runCheck("declarativePermissionBrokerEnforcesManifestPermissions") { try await declarativePermissionBrokerEnforcesManifestPermissions() }
        await runCheck("vscodeBridgePreparesPythonRunTask") { try await vscodeBridgePreparesPythonRunTask() }
        await runCheck("moduleSettingsViewModelEnableModuleRequiresDependencies") { try moduleSettingsViewModelEnableModuleRequiresDependencies() }
        await runCheck("moduleSettingsViewModelEnableDependenciesEnablesAllAncestors") { try moduleSettingsViewModelEnableDependenciesEnablesAllAncestors() }
        await runCheck("moduleSettingsViewModelTogglePinPersistsOrder") { try await moduleSettingsViewModelTogglePinPersistsOrder() }
        await runCheck("moduleSettingsViewModelDisablingDependencyHidesRoutes") { try moduleSettingsViewModelDisablingDependencyHidesRoutes() }
        await runCheck("moduleSettingsViewModelOverrideOnlyAffectsTargetProject") { try moduleSettingsViewModelOverrideOnlyAffectsTargetProject() }
        await runCheck("moduleOverrideMergerOnlyMutatesEnabledField") { try moduleOverrideMergerOnlyMutatesEnabledField() }
        await runCheck("moduleOverrideMergerLeavesUnknownIDsAsNoOp") { try moduleOverrideMergerLeavesUnknownIDsAsNoOp() }
    }

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

        try expect(fields.contains("id"), "Plugin validator should reject unstable plugin ids.")
        try expect(fields.contains("name"), "Plugin validator should require plugin names.")
        try expect(fields.contains("version"), "Plugin validator should require plugin versions.")
        try expect(fields.contains("contributes.commands"), "Plugin validator should reject duplicate command ids.")
    }

    func pluginRegistryResolvesBuiltInWorkspaceModuleAdapters() async throws {
        let manifests = WorkspaceModulePluginAdapter.builtInManifests()
        let registry = try PluginRegistry(manifests: manifests)
        let enabledIDs = try await registry.resolvedEnabledPluginIDs()
        let commands = try await registry.commandContributions()
        let modules = try await registry.workspaceModuleContributions().map(\.module)
        let tabs = try await registry.projectTabContributions()
        let workflows = try await registry.workflowContributions()
        let paperLibrary = try require(manifests.first { $0.id == "sci.paper-library" }, "paper-library should adapt to a built-in plugin manifest.")

        try expect(enabledIDs.contains("sci.projects"), "Built-in plugin registry should expose enabled Projects plugin.")
        try expect(enabledIDs.contains("sci.paper-library"), "Built-in plugin registry should expose enabled Paper Library plugin.")
        try expect(!enabledIDs.contains("sci.code"), "Disabled workspace modules should remain disabled as plugin manifests.")
        try expect(commands.isEmpty, "Workspace module adapter should not invent command handlers before command migration.")
        try expect(modules.contains { $0.id == "paper-library" }, "Workspace module adapter should preserve module contribution payloads.")
        try expect(tabs.contains { $0.id == "papers" }, "Plugin registry should expose project tab contributions from enabled manifests.")
        try expect(workflows.contains { $0.id == "paper_reading" }, "Plugin registry should expose workflow contributions from enabled manifests.")
        try expect(paperLibrary.permissions.writePaths.contains("library/papers/"), "Workspace module adapter should preserve declared write paths.")
        try expect(paperLibrary.contributes.routes.contains { $0.id == "library" }, "Workspace module adapter should expose route contributions.")
    }

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

        try expect(routeIDs.contains("projects"), "Plugin workspace catalog should expose enabled built-in routes.")
        try expect(!routeIDs.contains("library"), "Plugin workspace catalog should hide disabled module routes.")
        try expect(!routeIDs.contains("pdf-reader"), "Plugin workspace catalog should hide routes whose dependencies are disabled.")
        try expect(tabIDs.contains("overview"), "Plugin workspace catalog should expose project tabs from enabled modules.")
        try expect(!workflows.contains("paper_reading"), "Plugin workspace catalog should gate workflows by module requirements.")
        try expect(descriptor.isKnown && descriptor.moduleID == "projects", "Plugin workspace catalog should resolve known artifact descriptors.")
        try expect(!unknownDescriptor.isKnown && unknownDescriptor.title == "Future Plugin Artifact", "Plugin workspace catalog should fall back for unknown artifact descriptors.")
    }

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

        try expect(visible.map(\.id) == ["paper.importPDF"], "Command registry should expose route-matched toolbar commands.")
        try expect(hidden.isEmpty, "Command registry should hide commands when route predicates do not match.")
        try expect(result.succeeded && result.message == "ok", "Command registry should invoke registered command handlers.")
    }

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

        try expect(allowedRead.kind == .allow, "Permission broker should allow manifest-declared read paths.")
        try expect(allowedWrite.kind == .allow, "Permission broker should allow manifest-declared wildcard write paths.")
        try expect(allowedNetwork.kind == .allow, "Permission broker should allow manifest-declared network hosts.")
        try expect(deniedWrite.kind == .deny, "Permission broker should deny undeclared write paths when fallback is deny.")
        try expect(deniedSecret.kind == .deny, "Permission broker should deny undeclared secrets when fallback is deny.")
    }

    func vscodeBridgePreparesPythonRunTask() async throws {
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

            func moduleSettingsViewModelEnableModuleRequiresDependencies() throws {
                let configuration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library"])
                )
                do {
                    _ = try WorkspaceModuleSettingsMutation.setModule("recommendation", enabled: true, in: configuration)
                    try expect(false, "Enabling recommendation should require paper-library first.")
                } catch ModuleSettingsError.dependencyMissing(let missing) {
                    try expect(missing == ["paper-library"], "Recommendation should report paper-library as the missing dependency.")
                } catch {
                    throw error
                }
            }

            func moduleSettingsViewModelEnableDependenciesEnablesAllAncestors() throws {
                let configuration = WorkspaceModuleRegistry.defaultConfiguration(
                    enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["paper-library", "recommendation"])
                )
                let result = try WorkspaceModuleSettingsMutation.enableModuleAndDependencies("recommendation", in: configuration)
                let enabledIDs = result.configuration.enabledModuleIDs

                try expect(enabledIDs.contains("paper-library"), "Enable Dependencies should enable recommendation ancestors.")
                try expect(enabledIDs.contains("recommendation"), "Enable Dependencies should enable the requested module.")
                try expect(result.enabledChain == ["paper-library", "recommendation"], "Dependency chain should be deterministic and dependency-first.")
            }

            func moduleSettingsViewModelTogglePinPersistsOrder() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("ModulePinWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let repository = WorkspaceTemplateRepository()
                try repository.overwriteTemplateConfiguration(WorkspaceTemplateRegistry.literatureReview, in: root)

                var configuration = try repository.loadConfiguration(in: root)
                configuration = try WorkspaceModuleSettingsMutation.togglePin("tasks", in: configuration)
                configuration = try WorkspaceModuleSettingsMutation.movePin("tasks", newIndex: 0, in: configuration)

                let store = WorkspaceModuleConfigurationStore()
                try await store.save(configuration, in: root)
                let reloadedConfiguration = try await store.load(in: root)

                try expect(reloadedConfiguration.module(id: "tasks")?.pinned == true, "Pinned module should persist to workspace_modules.yaml.")
                try expect(WorkspaceModuleSettingsMutation.pinnedOrder(in: reloadedConfiguration).first == "tasks", "Pinned order should persist through the YAML round trip.")
            }

            func moduleSettingsViewModelDisablingDependencyHidesRoutes() throws {
                let configuration = try WorkspaceModuleSettingsMutation.setModule("wiki", enabled: false, in: WorkspaceModuleRegistry.defaultConfiguration())
                let routes = Set(WorkspaceModuleRegistry.availableRoutes(in: configuration).map(\.id))
                let workflows = Set(WorkspaceModuleRegistry.availableWorkflows(in: configuration))
                let warnings = WorkspaceModuleRegistry.warnings(for: configuration)

                try expect(!routes.contains("wiki"), "Disabling wiki should hide the Wiki route.")
                try expect(!workflows.contains("related_work"), "Workflows requiring wiki should be hidden.")
                try expect(warnings.contains { $0.id == "disabled-dependency:ai-lab:projects" } == false, "Unrelated dependency warnings should not be invented.")
                try expect(warnings.contains { $0.id == "disabled-dependency:code:wiki" } == false, "Disabled modules should not emit dependency-hidden warnings until enabled.")
            }

            func moduleSettingsViewModelOverrideOnlyAffectsTargetProject() throws {
                let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let override = WorkspaceModuleOverride(
                    projectID: "project-a",
                    moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)]
                )
                let projectAConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)
                let projectBConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: nil)

                try expect(projectAConfiguration.module(id: "calendar")?.enabled == false, "Project A override should disable calendar.")
                try expect(projectBConfiguration.module(id: "calendar")?.enabled == true, "Project B should keep the workspace calendar setting.")
                try expect(projectAConfiguration.module(id: "calendar")?.title == workspaceConfiguration.module(id: "calendar")?.title, "Override should not replace registry metadata.")
            }

            func moduleOverrideMergerOnlyMutatesEnabledField() throws {
                var workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                workspaceConfiguration = try WorkspaceModuleSettingsMutation.togglePin("calendar", in: workspaceConfiguration)
                let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "calendar", enabled: false)])
                let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

                try expect(effectiveConfiguration.module(id: "calendar")?.enabled == false, "Override should update enabled.")
                try expect(effectiveConfiguration.module(id: "calendar")?.pinned == true, "Override should not mutate pinned.")
                try expect(effectiveConfiguration.module(id: "calendar")?.routes == workspaceConfiguration.module(id: "calendar")?.routes, "Override should not mutate registry routes.")
            }

            func moduleOverrideMergerLeavesUnknownIDsAsNoOp() throws {
                let workspaceConfiguration = WorkspaceModuleRegistry.defaultConfiguration()
                let override = WorkspaceModuleOverride(projectID: "project-a", moduleOverrides: [WorkspaceModuleOverrideEntry(id: "third-party-module", enabled: true)])
                let effectiveConfiguration = ModuleOverrideMerger.effectiveConfiguration(workspace: workspaceConfiguration, override: override)

                try expect(effectiveConfiguration == workspaceConfiguration, "Unknown override module ids should be ignored.")
            }
}
