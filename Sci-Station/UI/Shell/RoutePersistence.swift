import Foundation

public nonisolated enum RoutePersistenceFallbackReason: String, Codable, Hashable, Sendable {
    case moduleDisabled = "module_disabled"
    case projectMissing = "project_missing"
    case schemaInvalid = "schema_invalid"
}

public nonisolated struct RouteRestoreResult: Hashable, Sendable {
    public let route: WorkspaceRoute
    public let fallbackReason: RoutePersistenceFallbackReason?

    public nonisolated init(route: WorkspaceRoute, fallbackReason: RoutePersistenceFallbackReason? = nil) {
        self.route = route
        self.fallbackReason = fallbackReason
    }
}

public actor RoutePersistence {
    private let preferencesRepository: WorkspacePreferencesRepository
    private let debugLogger: AppDebugEventLogger

    public init(
        preferencesRepository: WorkspacePreferencesRepository = WorkspacePreferencesRepository(),
        debugLogger: AppDebugEventLogger = AppDebugEventLogger()
    ) {
        self.preferencesRepository = preferencesRepository
        self.debugLogger = debugLogger
    }

    public func save(_ route: WorkspaceRoute, in workspace: ResearchWorkspace, root: ResearchRoot? = nil) async throws {
        var preferences = try await preferencesRepository.load(in: workspace)
        preferences.lastRoute = route
        try await preferencesRepository.save(preferences, in: workspace)
        try await debugLogger.append(routeDebugEvent("route.persist", route: route), in: root ?? ResearchRoot(rootURL: workspace.rootURL))
    }

    public func restore(
        in workspace: ResearchWorkspace,
        activeProjectIDs: Set<String>,
        configuration: WorkspaceModuleConfiguration,
        root: ResearchRoot? = nil
    ) async throws -> WorkspaceRoute {
        let preferences = try await preferencesRepository.load(in: workspace)
        let result = Self.restoreResult(
            candidate: preferences.lastRoute,
            activeProjectIDs: activeProjectIDs,
            configuration: configuration
        )
        if let reason = result.fallbackReason {
            try await debugLogger.append(AppDebugEvent(
                event: "route.persist.fallback",
                payload: .object(["reason": .string(reason.rawValue)])
            ), in: root ?? ResearchRoot(rootURL: workspace.rootURL))
        }
        return result.route
    }

    public nonisolated static func restoreResult(
        candidate: WorkspaceRoute?,
        activeProjectIDs: Set<String>,
        configuration: WorkspaceModuleConfiguration
    ) -> RouteRestoreResult {
        guard let candidate else {
            return RouteRestoreResult(route: .home)
        }

        guard let projectID = candidate.projectID else {
            return RouteRestoreResult(route: candidate)
        }

        guard activeProjectIDs.contains(projectID) else {
            return RouteRestoreResult(route: WorkspaceRoute(top: .projects), fallbackReason: .projectMissing)
        }

        let availableTabs = Set(WorkspaceModuleRegistry.availableProjectTabs(in: configuration).map(\.id))
        if let tabID = candidate.projectTabID, !availableTabs.contains(tabID), tabID != ProjectSpaceTabsBuilder.overviewTabID {
            return RouteRestoreResult(
                route: WorkspaceRoute(top: .projects, projectID: projectID, projectTabID: ProjectSpaceTabsBuilder.overviewTabID),
                fallbackReason: .moduleDisabled
            )
        }

        return RouteRestoreResult(route: candidate)
    }

    private nonisolated func routeDebugEvent(_ event: String, route: WorkspaceRoute) -> AppDebugEvent {
        AppDebugEvent(event: event, payload: .object([
            "top": .string(route.top.rawValue),
            "project_id_present": .bool(route.projectID != nil),
            "tab_id": .string(route.projectTabID ?? "")
        ]))
    }
}