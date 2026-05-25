import Foundation

public nonisolated enum CommandPlacement: String, Codable, CaseIterable, Hashable, Sendable {
    case toolbar
    case menu
    case contextMenu = "context_menu"
    case commandPalette = "command_palette"
    case keyboardShortcut = "keyboard_shortcut"
}

public nonisolated struct RoutePredicate: Codable, Hashable, Sendable {
    public var topLevelSectionIDs: [String]
    public var projectTabIDs: [String]
    public var requiresProject: Bool?
    public var requiresSelectedPaper: Bool

    public nonisolated init(
        topLevelSectionIDs: [String] = [],
        projectTabIDs: [String] = [],
        requiresProject: Bool? = nil,
        requiresSelectedPaper: Bool = false
    ) {
        self.topLevelSectionIDs = topLevelSectionIDs
        self.projectTabIDs = projectTabIDs
        self.requiresProject = requiresProject
        self.requiresSelectedPaper = requiresSelectedPaper
    }

    public nonisolated func matches(_ context: WorkspaceContextSnapshot) -> Bool {
        if !topLevelSectionIDs.isEmpty && !topLevelSectionIDs.contains(context.topLevelSectionID) {
            return false
        }
        if !projectTabIDs.isEmpty && !projectTabIDs.contains(context.projectTabID ?? "") {
            return false
        }
        if let requiresProject, requiresProject != (context.projectID != nil) {
            return false
        }
        if requiresSelectedPaper && context.selectedPaperID == nil {
            return false
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case topLevelSectionIDs = "top_level_section_ids"
        case projectTabIDs = "project_tab_ids"
        case requiresProject = "requires_project"
        case requiresSelectedPaper = "requires_selected_paper"
    }
}

public nonisolated struct CommandContribution: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var systemImage: String?
    public var placement: CommandPlacement
    public var routePredicate: RoutePredicate?
    public var requiredCapabilities: [String]
    public var isEnabledByDefault: Bool

    public nonisolated init(
        id: String,
        title: String,
        systemImage: String? = nil,
        placement: CommandPlacement,
        routePredicate: RoutePredicate? = nil,
        requiredCapabilities: [String] = [],
        isEnabledByDefault: Bool = true
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.placement = placement
        self.routePredicate = routePredicate
        self.requiredCapabilities = requiredCapabilities
        self.isEnabledByDefault = isEnabledByDefault
    }

    public nonisolated func isVisible(in context: WorkspaceContextSnapshot) -> Bool {
        guard isEnabledByDefault else {
            return false
        }
        return routePredicate?.matches(context) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case systemImage = "system_image"
        case placement
        case routePredicate = "route_predicate"
        case requiredCapabilities = "required_capabilities"
        case isEnabledByDefault = "is_enabled_by_default"
    }
}

public nonisolated struct CommandExecutionContext: Sendable {
    public var pluginID: String
    public var commandID: String
    public var services: HostServices
    public var parameters: [String: JSONValue]

    public nonisolated init(pluginID: String, commandID: String, services: HostServices = HostServices(), parameters: [String: JSONValue] = [:]) {
        self.pluginID = pluginID
        self.commandID = commandID
        self.services = services
        self.parameters = parameters
    }
}

public nonisolated struct CommandExecutionResult: Codable, Hashable, Sendable {
    public var succeeded: Bool
    public var message: String
    public var payload: JSONValue?

    public nonisolated init(succeeded: Bool = true, message: String = "", payload: JSONValue? = nil) {
        self.succeeded = succeeded
        self.message = message
        self.payload = payload
    }
}

public typealias CommandHandler = @Sendable (CommandExecutionContext) async throws -> CommandExecutionResult

public nonisolated enum CommandRegistryError: LocalizedError, Sendable {
    case duplicateCommand(String)
    case commandNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .duplicateCommand(id):
            return "Command '\(id)' is already registered."
        case let .commandNotFound(id):
            return "Command '\(id)' is not registered."
        }
    }
}

public actor CommandRegistry {
    private struct Entry: Sendable {
        var pluginID: String
        var contribution: CommandContribution
        var handler: CommandHandler
    }

    private var entriesByID: [String: Entry] = [:]

    public init() {}

    public func register(_ contribution: CommandContribution, pluginID: String, handler: @escaping CommandHandler) throws {
        guard entriesByID[contribution.id] == nil else {
            throw CommandRegistryError.duplicateCommand(contribution.id)
        }
        entriesByID[contribution.id] = Entry(pluginID: pluginID, contribution: contribution, handler: handler)
    }

    public func unregister(_ id: String) {
        entriesByID[id] = nil
    }

    public func contribution(id: String) -> CommandContribution? {
        entriesByID[id]?.contribution
    }

    public func contributions(placement: CommandPlacement? = nil, context: WorkspaceContextSnapshot? = nil) -> [CommandContribution] {
        entriesByID.values.map(\.contribution)
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

    public func execute(id: String, services: HostServices = HostServices(), parameters: [String: JSONValue] = [:]) async throws -> CommandExecutionResult {
        guard let entry = entriesByID[id] else {
            throw CommandRegistryError.commandNotFound(id)
        }
        return try await entry.handler(CommandExecutionContext(pluginID: entry.pluginID, commandID: id, services: services, parameters: parameters))
    }
}
