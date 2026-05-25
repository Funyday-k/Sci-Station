import Foundation

public nonisolated enum PluginRegistryError: LocalizedError, Sendable {
    case duplicatePlugin(String)
    case missingDependency(pluginID: String, dependencyID: String)
    case dependencyCycle([String])

    public var errorDescription: String? {
        switch self {
        case let .duplicatePlugin(id):
            return "Plugin '\(id)' is already registered."
        case let .missingDependency(pluginID, dependencyID):
            return "Plugin '\(pluginID)' depends on missing plugin '\(dependencyID)'."
        case let .dependencyCycle(ids):
            return "Plugin dependency cycle detected: \(ids.joined(separator: " -> "))."
        }
    }
}

public actor PluginRegistry {
    private var manifestsByID: [String: PluginManifest] = [:]
    private var enabledPluginIDs: Set<String> = []

    public init(manifests: [PluginManifest] = []) throws {
        var nextManifestsByID: [String: PluginManifest] = [:]
        var nextEnabledPluginIDs: Set<String> = []
        for manifest in manifests {
            guard nextManifestsByID[manifest.id] == nil else {
                throw PluginRegistryError.duplicatePlugin(manifest.id)
            }
            nextManifestsByID[manifest.id] = manifest
            if manifest.isEnabledByDefault {
                nextEnabledPluginIDs.insert(manifest.id)
            }
        }
        self.manifestsByID = nextManifestsByID
        self.enabledPluginIDs = nextEnabledPluginIDs
    }

    public func register(_ manifest: PluginManifest, enabled: Bool? = nil) throws {
        guard manifestsByID[manifest.id] == nil else {
            throw PluginRegistryError.duplicatePlugin(manifest.id)
        }
        manifestsByID[manifest.id] = manifest
        if enabled ?? manifest.isEnabledByDefault {
            enabledPluginIDs.insert(manifest.id)
        }
    }

    public func unregister(_ id: String) {
        manifestsByID[id] = nil
        enabledPluginIDs.remove(id)
    }

    public func setEnabled(_ id: String, enabled: Bool) {
        if enabled {
            enabledPluginIDs.insert(id)
        } else {
            enabledPluginIDs.remove(id)
        }
    }

    public func manifest(id: String) -> PluginManifest? {
        manifestsByID[id]
    }

    public func allManifests() -> [PluginManifest] {
        manifestsByID.values.sorted { $0.id < $1.id }
    }

    public func resolvedEnabledPluginIDs() throws -> [String] {
        let enabledIDs = enabledPluginIDs.filter { manifestsByID[$0] != nil }
        var resolved: [String] = []
        var visiting: [String] = []
        var visited: Set<String> = []

        func visit(_ id: String) throws {
            if visited.contains(id) {
                return
            }
            if let cycleIndex = visiting.firstIndex(of: id) {
                throw PluginRegistryError.dependencyCycle(Array(visiting[cycleIndex...]) + [id])
            }
            guard let manifest = manifestsByID[id] else {
                return
            }
            visiting.append(id)
            for dependencyID in manifest.dependencies where enabledIDs.contains(dependencyID) || manifestsByID[dependencyID] != nil {
                guard manifestsByID[dependencyID] != nil else {
                    throw PluginRegistryError.missingDependency(pluginID: id, dependencyID: dependencyID)
                }
                try visit(dependencyID)
            }
            visiting.removeLast()
            visited.insert(id)
            if enabledIDs.contains(id) {
                resolved.append(id)
            }
        }

        for id in enabledIDs.sorted() {
            try visit(id)
        }
        return resolved
    }

    public func enabledManifests() throws -> [PluginManifest] {
        try resolvedEnabledPluginIDs().compactMap { manifestsByID[$0] }
    }

    public func contributions() throws -> [PluginContribution] {
        try enabledManifests().map(\.contributes)
    }

    public func commandContributions(placement: CommandPlacement? = nil, context: WorkspaceContextSnapshot? = nil) throws -> [CommandContribution] {
        try enabledManifests().flatMap(\.contributes.commands)
            .filter { contribution in
                if let placement, contribution.placement != placement {
                    return false
                }
                if let context, !contribution.isVisible(in: context) {
                    return false
                }
                return true
            }
            .sorted { $0.id < $1.id }
    }

    public func routeContributions(context: WorkspaceContextSnapshot? = nil) throws -> [RouteContribution] {
        try enabledManifests().flatMap(\.contributes.routes)
            .filter { contribution in
                if let context, !contribution.isVisible(in: context) {
                    return false
                }
                return true
            }
            .sorted { $0.id < $1.id }
    }

    public func projectTabContributions() throws -> [ProjectTabContribution] {
        try enabledManifests().flatMap(\.contributes.projectTabs)
            .sorted { $0.id < $1.id }
    }

    public func workflowContributions() throws -> [WorkflowContribution] {
        try enabledManifests().flatMap(\.contributes.workflows)
            .sorted { $0.id < $1.id }
    }

    public func importerContributions() throws -> [ImporterContribution] {
        try enabledManifests().flatMap(\.contributes.importers)
            .sorted { $0.id < $1.id }
    }

    public func metadataProviderContributions() throws -> [MetadataProviderContribution] {
        try enabledManifests().flatMap(\.contributes.metadataProviders)
            .sorted { $0.id < $1.id }
    }

    public func workspaceModuleContributions() throws -> [WorkspaceModuleContribution] {
        try enabledManifests().flatMap(\.contributes.workspaceModules)
    }
}
