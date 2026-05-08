import Foundation
import Combine
import SwiftUI

@MainActor
final class ModuleSettingsViewModel: ObservableObject {
    @Published private(set) var configuration = WorkspaceModuleRegistry.defaultConfiguration()
    @Published private(set) var availableModules: [WorkspaceModule] = []
    @Published private(set) var pinnedOrder: [String] = []
    @Published private(set) var warningsByModuleID: [String: [WorkspaceModuleWarning]] = [:]
    @Published private(set) var directoryStatusesByModuleID: [String: [WorkspaceModuleDirectoryStatus]] = [:]
    @Published private(set) var projects: [ResearchProject] = []
    @Published private(set) var projectOverrides: [String: WorkspaceModuleOverride] = [:]
    @Published private(set) var statusSummary = ""
    @Published private(set) var isPersisting = false
    @Published var expandedModuleIDs: Set<String> = []
    @Published var pendingRepairStatus: WorkspaceModuleDirectoryStatus?
    @Published var errorMessage: String?

    private weak var appModel: AppViewModel?
    private var root: ResearchRoot?

    func configure(appModel: AppViewModel, root: ResearchRoot) {
        self.appModel = appModel
        self.root = root
        sync(from: appModel)
    }

    func sync(from appModel: AppViewModel) {
        configuration = appModel.workspaceModuleConfiguration
        projects = appModel.activeResearchProjects
        projectOverrides = appModel.workspaceModuleOverrides
        statusSummary = appModel.workspaceModuleStatusSummary
        refreshDerivedState(root: root)
    }

    @discardableResult
    func enableModule(id: String) async -> Result<Void, ModuleSettingsError> {
        do {
            let before = configuration.module(id: id)?.enabled ?? false
            let nextConfiguration = try WorkspaceModuleSettingsMutation.setModule(id, enabled: true, in: configuration)
            return await persist(nextConfiguration, event: "module_settings.toggle", payload: .object([
                "id": .string(id),
                "enabled": .bool(true),
                "before": .bool(before),
                "dependencies_satisfied": .bool(true),
                "persisted_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]))
        } catch let error as ModuleSettingsError {
            if case let .dependencyMissing(missing) = error {
                appModel?.recordModuleSettingsDebugEvent("module_settings.dependency_warning_shown", payload: .object([
                    "id": .string(id),
                    "missing": jsonStringArray(missing)
                ]))
            }
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func disableModule(id: String) async -> Result<Void, ModuleSettingsError> {
        do {
            let before = configuration.module(id: id)?.enabled ?? false
            let nextConfiguration = try WorkspaceModuleSettingsMutation.setModule(id, enabled: false, in: configuration)
            return await persist(nextConfiguration, event: "module_settings.toggle", payload: .object([
                "id": .string(id),
                "enabled": .bool(false),
                "before": .bool(before),
                "dependencies_satisfied": .bool(true),
                "persisted_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]))
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func enableDependencies(for id: String) async -> Result<Void, ModuleSettingsError> {
        do {
            let result = try WorkspaceModuleSettingsMutation.enableModuleAndDependencies(id, in: configuration)
            return await persist(result.configuration, event: "module_settings.toggle_chain", payload: .object([
                "enabled_chain": jsonStringArray(result.enabledChain),
                "reason": .string("enable_dependencies")
            ]))
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func togglePin(id: String) async -> Result<Void, ModuleSettingsError> {
        do {
            let nextConfiguration = try WorkspaceModuleSettingsMutation.togglePin(id, in: configuration)
            let isPinned = nextConfiguration.module(id: id)?.pinned ?? false
            let position = WorkspaceModuleSettingsMutation.pinnedOrder(in: nextConfiguration).firstIndex(of: id) ?? -1
            return await persist(nextConfiguration, event: "module_settings.pin", payload: .object([
                "id": .string(id),
                "pinned": .bool(isPinned),
                "position": .number(String(position))
            ]))
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func movePin(id: String, offset: Int) async -> Result<Void, ModuleSettingsError> {
        guard let currentIndex = pinnedOrder.firstIndex(of: id) else {
            return .success(())
        }
        do {
            let nextConfiguration = try WorkspaceModuleSettingsMutation.movePin(id, newIndex: currentIndex + offset, in: configuration)
            let position = WorkspaceModuleSettingsMutation.pinnedOrder(in: nextConfiguration).firstIndex(of: id) ?? currentIndex
            return await persist(nextConfiguration, event: "module_settings.pin", payload: .object([
                "id": .string(id),
                "pinned": .bool(true),
                "position": .number(String(position))
            ]))
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func projectOverride(projectID: String, moduleID: String, enabled: Bool) async -> Result<Void, ModuleSettingsError> {
        guard let appModel else {
            return .failure(.persistFailed("App model is not available."))
        }
        isPersisting = true
        defer { isPersisting = false }
        do {
            _ = try await appModel.setProjectModuleOverride(projectID: projectID, moduleID: moduleID, enabled: enabled)
            sync(from: appModel)
            return .success(())
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func clearProjectOverride(projectID: String, moduleID: String) async -> Result<Void, ModuleSettingsError> {
        guard let appModel else {
            return .failure(.persistFailed("App model is not available."))
        }
        isPersisting = true
        defer { isPersisting = false }
        do {
            _ = try await appModel.setProjectModuleOverride(projectID: projectID, moduleID: moduleID, enabled: nil)
            sync(from: appModel)
            return .success(())
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    @discardableResult
    func repairDirectory(_ status: WorkspaceModuleDirectoryStatus, approved: Bool) async -> Result<Void, ModuleSettingsError> {
        guard let appModel else {
            return .failure(.persistFailed("App model is not available."))
        }
        isPersisting = true
        defer { isPersisting = false }
        let outcome = await appModel.repairWorkspaceModuleDirectory(status, approved: approved)
        sync(from: appModel)
        switch outcome {
        case .created:
            return .success(())
        case let .skippedWildcard(path):
            let error = ModuleSettingsError.repairFailed(path: path, reason: "No active project directory is available for this wildcard path.")
            errorMessage = error.localizedDescription
            return .failure(error)
        case let .denied(path, reason), let .failed(path, reason):
            let error = ModuleSettingsError.repairFailed(path: path, reason: reason)
            errorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    @discardableResult
    func resetToTemplateDefault() async -> Result<Void, ModuleSettingsError> {
        guard let appModel else {
            return .failure(.persistFailed("App model is not available."))
        }
        isPersisting = true
        defer { isPersisting = false }
        do {
            try await appModel.resetWorkspaceModulesToTemplateDefault()
            sync(from: appModel)
            return .success(())
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    func warningDependencies(for module: WorkspaceModule) -> [String] {
        let enabledIDs = configuration.enabledModuleIDs
        return module.dependencies.filter { !enabledIDs.contains($0) }.sorted()
    }

    func projectOverrideValue(projectID: String, moduleID: String) -> Bool? {
        projectOverrides[projectID]?.override(for: moduleID)
    }

    func projectEffectiveEnabled(projectID: String, moduleID: String) -> Bool {
        ModuleOverrideMerger.effectiveConfiguration(
            workspace: configuration,
            override: projectOverrides[projectID]
        ).module(id: moduleID)?.enabled ?? false
    }

    private func persist(_ nextConfiguration: WorkspaceModuleConfiguration, event: String, payload: JSONValue) async -> Result<Void, ModuleSettingsError> {
        guard let appModel else {
            return .failure(.persistFailed("App model is not available."))
        }
        isPersisting = true
        defer { isPersisting = false }
        do {
            try await appModel.saveWorkspaceModuleConfiguration(nextConfiguration)
            appModel.recordModuleSettingsDebugEvent(event, payload: payload)
            sync(from: appModel)
            return .success(())
        } catch let error as ModuleSettingsError {
            errorMessage = error.localizedDescription
            return .failure(error)
        } catch {
            let wrapped = ModuleSettingsError.persistFailed(error.localizedDescription)
            errorMessage = wrapped.localizedDescription
            return .failure(wrapped)
        }
    }

    private func refreshDerivedState(root: ResearchRoot?) {
        availableModules = WorkspaceModuleRegistry.availableModules(in: configuration)
        pinnedOrder = WorkspaceModuleSettingsMutation.pinnedOrder(in: configuration)
        warningsByModuleID = Dictionary(grouping: WorkspaceModuleRegistry.warnings(for: configuration)) { warning in
            warning.moduleID ?? "_workspace"
        }
        if let root {
            directoryStatusesByModuleID = Dictionary(grouping: WorkspaceModuleRegistry.directoryStatuses(for: configuration, in: root)) { status in
                status.moduleID
            }
        } else {
            directoryStatusesByModuleID = [:]
        }
    }

    private func jsonStringArray(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }
}