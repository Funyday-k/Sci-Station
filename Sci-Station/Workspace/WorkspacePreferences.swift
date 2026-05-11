import Foundation

public nonisolated struct WorkspaceRoute: Codable, Hashable, Sendable {
    public enum Top: String, Codable, CaseIterable, Hashable, Sendable {
        case home
        case projects
        case library
        case calendar
        case aiLab = "ai-lab"
        case settings

        public nonisolated static let defaultOrder: [Top] = [.home, .projects, .library, .calendar, .aiLab, .settings]
    }

    public var top: Top
    public var projectID: String?
    public var projectTabID: String?
    public var secondarySelection: String?

    public nonisolated init(top: Top, projectID: String? = nil, projectTabID: String? = nil, secondarySelection: String? = nil) {
        self.top = top
        self.projectID = projectID
        self.projectTabID = projectTabID
        self.secondarySelection = secondarySelection
    }

    public nonisolated static let home = WorkspaceRoute(top: .home)
}

public struct WorkspacePreferences: Hashable, Sendable {
    public nonisolated static let currentSchemaVersion = 5
    public nonisolated static let defaultLibraryVisibleColumns = ["title", "authors", "year", "tags", "projects", "collection"]
    public nonisolated static let defaultAgentChatFontSize = 14.0
    public nonisolated static let defaultAgentLoopBudget = AgentLoopOptions()
    public nonisolated static let defaultPinnedTopLevelOrder = WorkspaceRoute.Top.defaultOrder.map(\.rawValue)

    public var schemaVersion: Int
    public var libraryVisibleColumns: [String]
    public var librarySortState: LibrarySortState
    public var defaultCollectionPath: String?
    public var recentSection: String?
    public var pinnedTopLevelOrder: [String]
    public var projectSpacePinnedOrder: [String]
    public var lastRoute: WorkspaceRoute?
    public var rightRailMode: RightRailMode
    public var isGlobalAIPanelOpen: Bool
    public var isProjectTreeExpanded: Bool
    public var homeWidgetLayout: HomeWidgetLayout
    public var pinnedProjectIDs: [String]
    public var syncTodosToAppleReminders: Bool
    public var appLanguage: AppLanguagePreference
    public var liquidGlassTint: LiquidGlassTintPreference
    public var agentChatFontSize: Double
    public var agentRuntimeSelection: AgentRuntimeSelection
    public var isSidecarDisabledForWorkspace: Bool
    public var agentDebugLoggingEnabled: Bool
    public var agentLoopBudget: AgentLoopOptions
    public var agentKnowledgePaperIDs: [String]?
    public var agentDisabledToolNamesByScope: [String: [String]]
    public var pinnedAgentThreadIDsByProject: [String: [String]]
    public var minerUCommand: String
    public var minerUAPIBaseURLString: String
    public var minerUAPILanguage: String
    public var minerUOverwriteExistingMarkdown: Bool

    public nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        libraryVisibleColumns: [String] = Self.defaultLibraryVisibleColumns,
        librarySortState: LibrarySortState = LibrarySortState(),
        defaultCollectionPath: String? = nil,
        recentSection: String? = "library",
        pinnedTopLevelOrder: [String] = Self.defaultPinnedTopLevelOrder,
        projectSpacePinnedOrder: [String] = [],
        lastRoute: WorkspaceRoute? = nil,
        rightRailMode: RightRailMode = .inspector,
        isGlobalAIPanelOpen: Bool = false,
        isProjectTreeExpanded: Bool = true,
        homeWidgetLayout: HomeWidgetLayout = HomeWidgetLayout.defaultLayout(),
        pinnedProjectIDs: [String] = [],
        syncTodosToAppleReminders: Bool = true,
        appLanguage: AppLanguagePreference = .system,
        liquidGlassTint: LiquidGlassTintPreference = .system,
        agentChatFontSize: Double = Self.defaultAgentChatFontSize,
        agentRuntimeSelection: AgentRuntimeSelection = .autoFallback,
        isSidecarDisabledForWorkspace: Bool = false,
        agentDebugLoggingEnabled: Bool = false,
        agentLoopBudget: AgentLoopOptions = Self.defaultAgentLoopBudget,
        agentKnowledgePaperIDs: [String]? = nil,
        agentDisabledToolNamesByScope: [String: [String]] = [:],
        pinnedAgentThreadIDsByProject: [String: [String]] = [:],
        minerUCommand: String = "mineru",
        minerUAPIBaseURLString: String = "https://mineru.net",
        minerUAPILanguage: String = "en",
        minerUOverwriteExistingMarkdown: Bool = true
    ) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        self.libraryVisibleColumns = libraryVisibleColumns.isEmpty ? Self.defaultLibraryVisibleColumns : libraryVisibleColumns
        self.librarySortState = librarySortState
        self.defaultCollectionPath = defaultCollectionPath
        self.recentSection = recentSection
        self.pinnedTopLevelOrder = pinnedTopLevelOrder.isEmpty ? Self.defaultPinnedTopLevelOrder : pinnedTopLevelOrder
        self.projectSpacePinnedOrder = projectSpacePinnedOrder
        self.lastRoute = lastRoute
        self.rightRailMode = rightRailMode
        self.isGlobalAIPanelOpen = isGlobalAIPanelOpen
        self.isProjectTreeExpanded = isProjectTreeExpanded
        self.homeWidgetLayout = homeWidgetLayout.normalized(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 4)
        self.pinnedProjectIDs = pinnedProjectIDs
        self.syncTodosToAppleReminders = syncTodosToAppleReminders
        self.appLanguage = appLanguage
        self.liquidGlassTint = liquidGlassTint
        let normalizedFontSize = agentChatFontSize.isFinite ? agentChatFontSize : Self.defaultAgentChatFontSize
        self.agentChatFontSize = min(max(normalizedFontSize, 11), 22)
        self.agentRuntimeSelection = agentRuntimeSelection
        self.isSidecarDisabledForWorkspace = isSidecarDisabledForWorkspace
        self.agentDebugLoggingEnabled = agentDebugLoggingEnabled
        self.agentLoopBudget = agentLoopBudget
        self.agentKnowledgePaperIDs = agentKnowledgePaperIDs
        self.agentDisabledToolNamesByScope = agentDisabledToolNamesByScope
        self.pinnedAgentThreadIDsByProject = pinnedAgentThreadIDsByProject
        self.minerUCommand = minerUCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mineru" : minerUCommand
        self.minerUAPIBaseURLString = minerUAPIBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "https://mineru.net" : minerUAPIBaseURLString
        self.minerUAPILanguage = minerUAPILanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "en" : minerUAPILanguage
        self.minerUOverwriteExistingMarkdown = minerUOverwriteExistingMarkdown
    }

    public nonisolated var libraryVisibleColumnsStorageValue: String {
        libraryVisibleColumns.joined(separator: ",")
    }

    public nonisolated mutating func updateLibraryVisibleColumns(from storageValue: String) {
        let columns = storageValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        libraryVisibleColumns = columns.isEmpty ? Self.defaultLibraryVisibleColumns : columns
    }
}

public enum LiquidGlassTintPreference: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case system
    case blue
    case mint
    case lavender
    case rose
    case amber
    case graphite

    public nonisolated var id: String { rawValue }
}

public enum AgentRuntimeSelection: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case swiftLoop = "swift_loop"
    case langGraphSidecar = "langgraph_sidecar"
    case autoFallback = "auto_fallback"

    public nonisolated var id: String { rawValue }

    public nonisolated var label: String {
        switch self {
        case .swiftLoop:
            return "Swift Loop"
        case .langGraphSidecar:
            return "LangGraph Sidecar"
        case .autoFallback:
            return "Auto fallback"
        }
    }

    public nonisolated func effectiveRuntime(sidecarAvailable: Bool, sidecarDisabled: Bool = false) -> AgentRuntimeSelection {
        if sidecarDisabled {
            return .swiftLoop
        }
        switch self {
        case .swiftLoop:
            return .swiftLoop
        case .langGraphSidecar:
            return sidecarAvailable ? .langGraphSidecar : .swiftLoop
        case .autoFallback:
            return sidecarAvailable ? .langGraphSidecar : .swiftLoop
        }
    }

    public nonisolated func fallbackReason(sidecarAvailable: Bool, sidecarDisabled: Bool = false) -> String? {
        if sidecarDisabled {
            return "Sidecar disabled for this workspace."
        }
        guard effectiveRuntime(sidecarAvailable: sidecarAvailable) == .swiftLoop else {
            return nil
        }
        switch self {
        case .swiftLoop:
            return nil
        case .langGraphSidecar:
            return sidecarAvailable ? nil : "LangGraph sidecar unavailable; falling back to Swift Loop."
        case .autoFallback:
            return sidecarAvailable ? nil : "Auto fallback selected Swift Loop because sidecar health is unavailable."
        }
    }
}

public enum AppLanguagePreference: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public nonisolated var id: String { rawValue }
}

public enum LibrarySortField: String, CaseIterable, Hashable, Sendable {
    case title
    case authors
    case year
    case updated
    case rating
    case priority
    case status

    public nonisolated var label: String {
        switch self {
        case .title:
            return "Title"
        case .authors:
            return "Authors"
        case .year:
            return "Year"
        case .updated:
            return "Updated"
        case .rating:
            return "Rating"
        case .priority:
            return "Priority"
        case .status:
            return "Status"
        }
    }
}

public struct LibrarySortState: Hashable, Sendable {
    public var field: LibrarySortField?
    public var isAscending: Bool

    public nonisolated init(field: LibrarySortField? = nil, isAscending: Bool = true) {
        self.field = field
        self.isAscending = isAscending
    }

    public nonisolated func sorted(_ papers: [Paper]) -> [Paper] {
        guard let field else {
            return papers
        }

        return papers.enumerated()
            .sorted { first, second in
                let comparison = compare(first.element, second.element, by: field)
                if comparison == .orderedSame {
                    return first.offset < second.offset
                }

                return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            .map(\.element)
    }

    private nonisolated func compare(_ first: Paper, _ second: Paper, by field: LibrarySortField) -> ComparisonResult {
        switch field {
        case .title:
            return compareStrings(first.displayTitle, second.displayTitle)
        case .authors:
            return compareStrings(first.authorsDisplay, second.authorsDisplay)
        case .year:
            return compareOptionalInts(first.year, second.year)
        case .updated:
            return compareDates(first.updatedAt, second.updatedAt)
        case .rating:
            return compareOptionalInts(first.rating, second.rating)
        case .priority:
            return compareInts(prioritySortValue(first.priority), prioritySortValue(second.priority))
        case .status:
            return compareInts(statusSortValue(first.status), statusSortValue(second.status))
        }
    }

    private nonisolated func compareStrings(_ first: String, _ second: String) -> ComparisonResult {
        first.localizedStandardCompare(second)
    }

    private nonisolated func compareDates(_ first: Date, _ second: Date) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private nonisolated func compareOptionalInts(_ first: Int?, _ second: Int?) -> ComparisonResult {
        switch (first, second) {
        case let (first?, second?):
            return compareInts(first, second)
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private nonisolated func compareInts(_ first: Int, _ second: Int) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private nonisolated func prioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent:
            return 0
        case .high:
            return 1
        case .medium:
            return 2
        case .low:
            return 3
        }
    }

    private nonisolated func statusSortValue(_ status: ReadingStatus) -> Int {
        ReadingStatus.allCases.firstIndex(of: status) ?? ReadingStatus.allCases.count
    }
}
