import Foundation

public nonisolated struct PluginContribution: Codable, Hashable, Sendable {
    public var workspaceModules: [WorkspaceModuleContribution]
    public var routes: [RouteContribution]
    public var commands: [CommandContribution]
    public var projectTabs: [ProjectTabContribution]
    public var workflows: [WorkflowContribution]
    public var agentTools: [AgentToolContribution]
    public var importers: [ImporterContribution]
    public var metadataProviders: [MetadataProviderContribution]

    public nonisolated init(
        workspaceModules: [WorkspaceModuleContribution] = [],
        routes: [RouteContribution] = [],
        commands: [CommandContribution] = [],
        projectTabs: [ProjectTabContribution] = [],
        workflows: [WorkflowContribution] = [],
        agentTools: [AgentToolContribution] = [],
        importers: [ImporterContribution] = [],
        metadataProviders: [MetadataProviderContribution] = []
    ) {
        self.workspaceModules = workspaceModules
        self.routes = routes
        self.commands = commands
        self.projectTabs = projectTabs
        self.workflows = workflows
        self.agentTools = agentTools
        self.importers = importers
        self.metadataProviders = metadataProviders
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceModules = "workspace_modules"
        case routes
        case commands
        case projectTabs = "project_tabs"
        case workflows
        case agentTools = "agent_tools"
        case importers
        case metadataProviders = "metadata_providers"
    }
}

public nonisolated struct WorkspaceModuleContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var module: WorkspaceModule

    public nonisolated init(module: WorkspaceModule) {
        self.id = module.id
        self.module = module
    }
}

public nonisolated struct ProjectTabContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var systemImage: String?
    public var requiredCapabilities: [String]

    public nonisolated init(id: String, title: String, systemImage: String? = nil, requiredCapabilities: [String] = []) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.requiredCapabilities = requiredCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case systemImage = "system_image"
        case requiredCapabilities = "required_capabilities"
    }
}

public nonisolated struct WorkflowContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var requiredCapabilities: [String]

    public nonisolated init(id: String, title: String, requiredCapabilities: [String] = []) {
        self.id = id
        self.title = title
        self.requiredCapabilities = requiredCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case requiredCapabilities = "required_capabilities"
    }
}

public nonisolated struct AgentToolContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var requiredCapabilities: [String]

    public nonisolated init(id: String, name: String, description: String = "", requiredCapabilities: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.requiredCapabilities = requiredCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case requiredCapabilities = "required_capabilities"
    }
}

public nonisolated struct ImporterContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var inputKinds: [String]
    public var requiredCapabilities: [String]

    public nonisolated init(id: String, title: String, inputKinds: [String] = [], requiredCapabilities: [String] = []) {
        self.id = id
        self.title = title
        self.inputKinds = inputKinds
        self.requiredCapabilities = requiredCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case inputKinds = "input_kinds"
        case requiredCapabilities = "required_capabilities"
    }
}

public nonisolated struct MetadataProviderContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var supportedIdentifiers: [String]
    public var networkHosts: [String]

    public nonisolated init(id: String, title: String, supportedIdentifiers: [String] = [], networkHosts: [String] = []) {
        self.id = id
        self.title = title
        self.supportedIdentifiers = supportedIdentifiers
        self.networkHosts = networkHosts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case supportedIdentifiers = "supported_identifiers"
        case networkHosts = "network_hosts"
    }
}
