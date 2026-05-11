import Foundation

public nonisolated enum ProjectLifecycleAction: String, Codable, Hashable, Sendable {
    case archive
    case deleteToTrash = "delete_to_trash"
}

public nonisolated struct ProjectLifecycleResult: Hashable, Sendable {
    public let registry: ProjectRegistry
    public let project: ResearchProject
    public let previousRelativePath: String
    public let nextRelativePath: String

    public nonisolated init(registry: ProjectRegistry, project: ResearchProject, previousRelativePath: String, nextRelativePath: String) {
        self.registry = registry
        self.project = project
        self.previousRelativePath = previousRelativePath
        self.nextRelativePath = nextRelativePath
    }
}