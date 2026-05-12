import Foundation

public nonisolated struct WorkspaceContentRoute: Codable, Hashable, Sendable {
    public let top: WorkspaceRoute.Top
    public let projectID: String?
    public let tabID: String
    public let secondarySelection: String?

    public nonisolated init(top: WorkspaceRoute.Top = .projects, projectID: String?, tabID: String, secondarySelection: String? = nil) {
        self.top = top
        self.projectID = projectID
        self.tabID = tabID
        self.secondarySelection = secondarySelection
    }
}

public nonisolated struct ProjectSpaceTab: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let originModuleID: String?
    public let contentRoute: WorkspaceContentRoute
    public let isPinFixed: Bool

    public nonisolated init(id: String, title: String, systemImage: String, originModuleID: String?, contentRoute: WorkspaceContentRoute, isPinFixed: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.originModuleID = originModuleID
        self.contentRoute = contentRoute
        self.isPinFixed = isPinFixed
    }
}

public nonisolated enum ProjectSpaceTabsBuilder {
    public static let overviewTabID = "overview"

    public static let defaultOrder: [String] = [
        "overview", "papers", "wiki", "tasks", "calendar", "ai-drafts", "graph",
        "code", "data", "experiments", "recommendations", "materials", "pdf-reader", "writing", "theory"
    ]

    public static func tabs(
        for projectID: String,
        configuration: WorkspaceModuleConfiguration,
        pinnedOrder: [String]
    ) -> [ProjectSpaceTab] {
        var uniqueTabs: [ProjectSpaceTab] = []
        var seenIDs: Set<String> = []

        for module in WorkspaceModuleRegistry.availableModules(in: configuration) {
            for moduleTab in module.projectTabs where !seenIDs.contains(moduleTab.id) {
                seenIDs.insert(moduleTab.id)
                uniqueTabs.append(ProjectSpaceTab(
                    id: moduleTab.id,
                    title: title(for: moduleTab),
                    systemImage: systemImage(for: moduleTab.id),
                    originModuleID: module.id,
                    contentRoute: WorkspaceContentRoute(projectID: projectID, tabID: moduleTab.id),
                    isPinFixed: moduleTab.id == overviewTabID
                ))
            }
        }

        if !seenIDs.contains(overviewTabID) {
            uniqueTabs.insert(ProjectSpaceTab(
                id: overviewTabID,
                title: "Overview",
                systemImage: systemImage(for: overviewTabID),
                originModuleID: nil,
                contentRoute: WorkspaceContentRoute(projectID: projectID, tabID: overviewTabID),
                isPinFixed: true
            ), at: 0)
        }

        let ordered = uniqueTabs.sorted { first, second in
            let firstRank = defaultOrder.firstIndex(of: first.id) ?? Int.max
            let secondRank = defaultOrder.firstIndex(of: second.id) ?? Int.max
            if firstRank == secondRank {
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
            return firstRank < secondRank
        }
        return reorder(ordered, by: pinnedOrder)
    }

    public static func reorder(_ tabs: [ProjectSpaceTab], by pinnedOrder: [String]) -> [ProjectSpaceTab] {
        let fixed = tabs.filter(\.isPinFixed)
        let movable = tabs.filter { !$0.isPinFixed }
        let pinned = pinnedOrder.compactMap { id in movable.first { $0.id == id } }
        let pinnedIDs = Set(pinned.map(\.id))
        let leftover = movable.filter { !pinnedIDs.contains($0.id) }
        return fixed + pinned + leftover
    }

    public static func systemImage(for tabID: String) -> String {
        ProjectSpaceTabIcon.systemImage(for: tabID)
    }

    private static func title(for moduleTab: WorkspaceModuleProjectTab) -> String {
        switch moduleTab.id {
        case "ai-drafts":
            return "AI Workflows"
        case "data":
            return "Data"
        default:
            return moduleTab.title
        }
    }
}