import Foundation

public nonisolated struct WorkspaceHostSnapshot: Codable, Hashable, Sendable {
    public var workspaceID: String?
    public var displayName: String?
    public var rootPath: String?
    public var selectedRouteDescription: String?

    public nonisolated init(workspaceID: String? = nil, displayName: String? = nil, rootPath: String? = nil, selectedRouteDescription: String? = nil) {
        self.workspaceID = workspaceID
        self.displayName = displayName
        self.rootPath = rootPath
        self.selectedRouteDescription = selectedRouteDescription
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case displayName = "display_name"
        case rootPath = "root_path"
        case selectedRouteDescription = "selected_route_description"
    }
}

public protocol WorkspaceHostService: Sendable {
    func snapshot() async throws -> WorkspaceHostSnapshot?
}

public protocol PaperLibraryHostService: Sendable {
    func allPaperIDs() async throws -> [String]
}

public protocol WikiHostService: Sendable {
    func pagePaths() async throws -> [String]
}

public protocol TaskHostService: Sendable {
    func taskIDs() async throws -> [String]
}

public protocol AgentHostService: Sendable {
    func availableToolNames() async throws -> [String]
}

public protocol SecretBroker: Sendable {
    func readSecret(named name: String, requesterPluginID: String) async throws -> String?
}

public nonisolated struct HostServices: Sendable {
    public var workspace: (any WorkspaceHostService)?
    public var papers: (any PaperLibraryHostService)?
    public var wiki: (any WikiHostService)?
    public var tasks: (any TaskHostService)?
    public var agent: (any AgentHostService)?
    public var files: WorkspaceFileSystem?
    public var permissions: (any PermissionBroker)?
    public var secrets: (any SecretBroker)?

    public nonisolated init(
        workspace: (any WorkspaceHostService)? = nil,
        papers: (any PaperLibraryHostService)? = nil,
        wiki: (any WikiHostService)? = nil,
        tasks: (any TaskHostService)? = nil,
        agent: (any AgentHostService)? = nil,
        files: WorkspaceFileSystem? = nil,
        permissions: (any PermissionBroker)? = nil,
        secrets: (any SecretBroker)? = nil
    ) {
        self.workspace = workspace
        self.papers = papers
        self.wiki = wiki
        self.tasks = tasks
        self.agent = agent
        self.files = files
        self.permissions = permissions
        self.secrets = secrets
    }
}

public nonisolated struct PluginContext: Sendable {
    public var pluginID: String
    public var services: HostServices

    public nonisolated init(pluginID: String, services: HostServices = HostServices()) {
        self.pluginID = pluginID
        self.services = services
    }
}
