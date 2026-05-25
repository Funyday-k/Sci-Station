import Foundation

public nonisolated enum RoutePlacement: String, Codable, CaseIterable, Hashable, Sendable {
    case topLevel = "top_level"
    case projectTab = "project_tab"
    case rightRail = "right_rail"
}

public nonisolated struct RouteContribution: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var path: String
    public var title: String
    public var systemImage: String?
    public var placement: RoutePlacement
    public var routePredicate: RoutePredicate?
    public var requiredCapabilities: [String]

    public nonisolated init(
        id: String,
        path: String,
        title: String,
        systemImage: String? = nil,
        placement: RoutePlacement = .topLevel,
        routePredicate: RoutePredicate? = nil,
        requiredCapabilities: [String] = []
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.systemImage = systemImage
        self.placement = placement
        self.routePredicate = routePredicate
        self.requiredCapabilities = requiredCapabilities
    }

    public nonisolated func isVisible(in context: WorkspaceContextSnapshot) -> Bool {
        routePredicate?.matches(context) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case title
        case systemImage = "system_image"
        case placement
        case routePredicate = "route_predicate"
        case requiredCapabilities = "required_capabilities"
    }
}
