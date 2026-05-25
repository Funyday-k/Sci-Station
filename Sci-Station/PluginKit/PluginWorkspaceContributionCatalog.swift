import Foundation

public nonisolated struct PluginWorkspaceContributionCatalog: Sendable {
    public var moduleContributions: [WorkspaceModuleContribution]
    public var workflowRequirements: [String: Set<String>]

    public nonisolated init(
        moduleContributions: [WorkspaceModuleContribution],
        workflowRequirements: [String: Set<String>] = WorkspaceModuleRegistry.workflowRequirements
    ) {
        self.moduleContributions = moduleContributions
        self.workflowRequirements = workflowRequirements
    }

    public nonisolated init(
        configuration: WorkspaceModuleConfiguration,
        workflowRequirements: [String: Set<String>] = WorkspaceModuleRegistry.workflowRequirements
    ) {
        self.init(
            moduleContributions: configuration.modules.map(WorkspaceModuleContribution.init(module:)),
            workflowRequirements: workflowRequirements
        )
    }

    public nonisolated init(
        manifests: [PluginManifest],
        workflowRequirements: [String: Set<String>] = WorkspaceModuleRegistry.workflowRequirements
    ) {
        self.init(
            moduleContributions: manifests.flatMap(\.contributes.workspaceModules),
            workflowRequirements: workflowRequirements
        )
    }

    public nonisolated var modules: [WorkspaceModule] {
        moduleContributions.map(\.module)
    }

    public nonisolated func availableModules() -> [WorkspaceModule] {
        let enabledIDs = Set(modules.filter(\.enabled).map(\.id))
        return modules.filter { module in
            module.enabled && module.dependencies.allSatisfy { enabledIDs.contains($0) }
        }
    }

    public nonisolated func availableRoutes() -> [WorkspaceModuleRoute] {
        availableModules().flatMap(\.routes)
    }

    public nonisolated func availableProjectTabs() -> [WorkspaceModuleProjectTab] {
        availableModules().flatMap(\.projectTabs)
    }

    public nonisolated func availableWorkflows() -> [String] {
        let modules = availableModules()
        let availableIDs = Set(modules.map(\.id))
        let declaredWorkflows = modules.flatMap(\.workflows)
        let filteredWorkflows = declaredWorkflows.filter { workflowID in
            guard let requirements = workflowRequirements[workflowID] else {
                return true
            }
            return requirements.isSubset(of: availableIDs)
        }
        return Array(Set(filteredWorkflows)).sorted()
    }

    public nonisolated func artifactKindDescriptors() -> [WorkspaceModuleArtifactKindDescriptor] {
        availableModules()
            .flatMap { module in
                module.artifactKinds.map { kind in
                    WorkspaceModuleArtifactKindDescriptor(
                        kind: kind,
                        title: WorkspaceModuleRegistry.artifactKindTitle(kind),
                        moduleID: module.id,
                        moduleTitle: module.title,
                        isKnown: true
                    )
                }
            }
            .uniquedByKind()
            .sorted { $0.kind < $1.kind }
    }

    public nonisolated func artifactKindDescriptor(for kind: String) -> WorkspaceModuleArtifactKindDescriptor {
        artifactKindDescriptors().first { $0.kind == kind } ?? WorkspaceModuleArtifactKindDescriptor(
            kind: kind,
            title: WorkspaceModuleRegistry.artifactKindTitle(kind),
            moduleID: nil,
            moduleTitle: nil,
            isKnown: false
        )
    }

}

private extension Array where Element == WorkspaceModuleArtifactKindDescriptor {
    nonisolated func uniquedByKind() -> [WorkspaceModuleArtifactKindDescriptor] {
        var seenKinds: Set<String> = []
        var descriptors: [WorkspaceModuleArtifactKindDescriptor] = []
        for descriptor in self where !seenKinds.contains(descriptor.kind) {
            seenKinds.insert(descriptor.kind)
            descriptors.append(descriptor)
        }
        return descriptors
    }
}
