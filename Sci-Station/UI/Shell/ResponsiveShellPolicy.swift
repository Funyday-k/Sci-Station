import Foundation

public nonisolated enum ResponsiveWidthBucket: String, Codable, Hashable, Sendable {
    case expanded
    case regular
    case compact
    case narrow
}

public nonisolated struct ResponsiveShellModel: Codable, Hashable, Sendable {
    public var bucket: ResponsiveWidthBucket
    public var homeWidgetColumns: Int
    public var effectiveRightRailMode: RightRailMode
    public var shouldCollapseProjectTree: Bool
    public var maxVisibleProjectTabs: Int
    public var shouldMoveToolbarPageActionsToOverflow: Bool

    public init(
        bucket: ResponsiveWidthBucket,
        homeWidgetColumns: Int,
        effectiveRightRailMode: RightRailMode,
        shouldCollapseProjectTree: Bool,
        maxVisibleProjectTabs: Int,
        shouldMoveToolbarPageActionsToOverflow: Bool
    ) {
        self.bucket = bucket
        self.homeWidgetColumns = homeWidgetColumns
        self.effectiveRightRailMode = effectiveRightRailMode
        self.shouldCollapseProjectTree = shouldCollapseProjectTree
        self.maxVisibleProjectTabs = maxVisibleProjectTabs
        self.shouldMoveToolbarPageActionsToOverflow = shouldMoveToolbarPageActionsToOverflow
    }
}

public nonisolated enum ResponsiveShellPolicy {
    public static func bucket(for width: Double) -> ResponsiveWidthBucket {
        if width >= 1400 { return .expanded }
        if width >= 1000 { return .regular }
        if width >= 760 { return .compact }
        return .narrow
    }

    public static func resolve(
        width: Double,
        route: WorkspaceRoute,
        context: WorkspaceContextSnapshot,
        preferredRightRailMode: RightRailMode
    ) -> ResponsiveShellModel {
        let bucket = bucket(for: width)
        let suggestedRightRailMode = RightRailPolicy.suggestedMode(
            route: route,
            context: context,
            preferredMode: preferredRightRailMode
        )
        let rightRailMode: RightRailMode
        switch bucket {
        case .expanded:
            rightRailMode = suggestedRightRailMode
        case .regular:
            rightRailMode = preferredRightRailMode == .ai ? .ai : suggestedRightRailMode
        case .compact, .narrow:
            rightRailMode = .hidden
        }

        return ResponsiveShellModel(
            bucket: bucket,
            homeWidgetColumns: homeWidgetColumns(for: width),
            effectiveRightRailMode: rightRailMode,
            shouldCollapseProjectTree: bucket == .compact || bucket == .narrow,
            maxVisibleProjectTabs: maxVisibleProjectTabs(for: bucket),
            shouldMoveToolbarPageActionsToOverflow: bucket == .narrow
        )
    }

    public static func homeWidgetColumns(for width: Double) -> Int {
        switch bucket(for: width) {
        case .expanded, .regular:
            return 4
        case .compact:
            return 2
        case .narrow:
            return 1
        }
    }

    public static func maxVisibleProjectTabs(for bucket: ResponsiveWidthBucket) -> Int {
        switch bucket {
        case .expanded:
            return 8
        case .regular:
            return 6
        case .compact:
            return 4
        case .narrow:
            return 2
        }
    }

    public static func toolbarModel(_ model: ToolbarModel, width: Double) -> ToolbarModel {
        guard bucket(for: width) == .narrow, !model.pageActions.isEmpty else {
            return model
        }
        return ToolbarModel(
            globalActions: model.globalActions,
            pageActions: [],
            overflowActions: model.pageActions + model.overflowActions
        )
    }
}
