import Foundation

@MainActor
enum AppHostServicesFactory {
    static func make(appModel: AppViewModel) -> HostServices {
        let workspaceSnapshot = AppWorkspaceHostSnapshotService(snapshotValue: workspaceSnapshot(from: appModel))
        let paperService = AppPaperLibraryHostSnapshotService(paperIDs: appModel.papers.map(\.id))
        let wikiService = AppWikiHostSnapshotService(pagePathsValue: appModel.markdownDocuments.map(\.relativePath))
        let taskService = AppTaskHostSnapshotService(taskIDsValue: appModel.todos.map(\.id))
        let agentService = AppAgentHostSnapshotService(toolNames: appModel.agentToolDefinitions.map(\.name))
        let fileSystem = appModel.currentResearchRoot.map { WorkspaceFileSystem(root: $0) }

        return HostServices(
            workspace: workspaceSnapshot,
            papers: paperService,
            wiki: wikiService,
            tasks: taskService,
            agent: agentService,
            files: fileSystem
        )
    }

    private static func workspaceSnapshot(from appModel: AppViewModel) -> WorkspaceHostSnapshot? {
        guard let workspace = appModel.currentWorkspace else {
            return nil
        }
        let rootPath = appModel.currentResearchRoot?.rootURL.path ?? workspace.rootURL.path
        return WorkspaceHostSnapshot(
            workspaceID: workspace.id.path,
            displayName: workspace.displayName,
            rootPath: rootPath,
            selectedRouteDescription: appModel.currentWorkspaceContextSnapshot.displayTitle
        )
    }
}

@MainActor
extension AppViewModel {
    var hostServices: HostServices {
        AppHostServicesFactory.make(appModel: self)
    }
}

private struct AppWorkspaceHostSnapshotService: WorkspaceHostService {
    let snapshotValue: WorkspaceHostSnapshot?

    func snapshot() async throws -> WorkspaceHostSnapshot? {
        snapshotValue
    }
}

private struct AppPaperLibraryHostSnapshotService: PaperLibraryHostService {
    let paperIDs: [String]

    func allPaperIDs() async throws -> [String] {
        paperIDs
    }
}

private struct AppWikiHostSnapshotService: WikiHostService {
    let pagePathsValue: [String]

    func pagePaths() async throws -> [String] {
        pagePathsValue
    }
}

private struct AppTaskHostSnapshotService: TaskHostService {
    let taskIDsValue: [String]

    func taskIDs() async throws -> [String] {
        taskIDsValue
    }
}

private struct AppAgentHostSnapshotService: AgentHostService {
    let toolNames: [String]

    func availableToolNames() async throws -> [String] {
        toolNames
    }
}
