import Foundation

public nonisolated enum WorkspaceModulePluginAdapter {
    public static func pluginID(for moduleID: String) -> String {
        "sci.\(moduleID)"
    }

    public static func manifest(for module: WorkspaceModule) -> PluginManifest {
        let pluginID = pluginID(for: module.id)
        let routes = module.routes.map { route in
            RouteContribution(id: route.id, path: route.path, title: module.title)
        }
        let projectTabs = module.projectTabs.map { tab in
            ProjectTabContribution(id: tab.id, title: tab.title)
        }
        let workflows = module.workflows.map { workflowID in
            WorkflowContribution(id: workflowID, title: title(from: workflowID))
        }
        let contribution = PluginContribution(
            workspaceModules: [WorkspaceModuleContribution(module: module)],
            routes: routes,
            projectTabs: projectTabs,
            workflows: workflows
        )
        return PluginManifest(
            id: pluginID,
            name: module.title,
            version: String(module.version),
            kind: .builtIn,
            source: .bundled,
            dependencies: module.dependencies.map(pluginID(for:)).sorted(),
            capabilities: module.permissions.writePaths.isEmpty ? [] : [.workspaceWrite],
            permissions: PluginPermissionSet(writePaths: module.permissions.writePaths),
            contributes: contribution,
            isEnabledByDefault: module.enabled
        )
    }

    public static func builtInManifests() -> [PluginManifest] {
        WorkspaceModuleRegistry.builtInModules.map(manifest(for:))
    }

    public static func workspaceModuleConfiguration(from manifests: [PluginManifest]) -> WorkspaceModuleConfiguration {
        WorkspaceModuleConfiguration(
            schemaVersion: WorkspaceModuleSchema.currentVersion,
            modules: manifests.flatMap { manifest in
                manifest.contributes.workspaceModules.map(\.module)
            }
        )
    }

    private static func title(from identifier: String) -> String {
        identifier.split(separator: "_").map { part in
            part.prefix(1).uppercased() + String(part.dropFirst())
        }.joined(separator: " ")
    }
}
