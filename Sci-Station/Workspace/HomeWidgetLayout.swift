import Foundation

public nonisolated enum HomeWidgetSize: String, Codable, CaseIterable, Hashable, Sendable {
    /// 1 × 1 tile.
    case small
    /// 2 × 2 tile.
    case medium
    /// 3 × 3 tile.
    case large
    /// 4 × 4 tile (largest).
    case wide

    public var columnSpan: Int {
        switch self {
        case .small:
            return 1
        case .medium:
            return 2
        case .large:
            return 3
        case .wide:
            return 4
        }
    }

    public var rowSpan: Int {
        switch self {
        case .small:
            return 1
        case .medium:
            return 2
        case .large:
            return 3
        case .wide:
            return 4
        }
    }
}

public nonisolated enum HomeWidgetCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case research
    case ai
    case calendar
    case library
    case project
}

public nonisolated enum HomeWidgetID {
    public static let today = "today"
    public static let activeProjects = "active_projects"
    public static let aiReview = "ai_review"
    public static let calendar = "calendar"
    public static let recentPapers = "recent_papers"
    public static let readingPlan = "reading_plan"
    public static let projectHealth = "project_health"
    public static let quickActions = "quick_actions"
}

public nonisolated struct HomeWidgetDescriptor: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var titleKey: L10nKey
    public var category: HomeWidgetCategory
    public var defaultSize: HomeWidgetSize
    public var supportedSizes: Set<HomeWidgetSize>
    public var defaultOrder: Int
    public var requiredModuleIDs: [String]
    public var systemImage: String

    public init(
        id: String,
        titleKey: L10nKey,
        category: HomeWidgetCategory,
        defaultSize: HomeWidgetSize,
        supportedSizes: Set<HomeWidgetSize>,
        defaultOrder: Int,
        requiredModuleIDs: [String] = [],
        systemImage: String
    ) {
        self.id = id
        self.titleKey = titleKey
        self.category = category
        self.defaultSize = supportedSizes.contains(defaultSize) ? defaultSize : (supportedSizes.first ?? .medium)
        self.supportedSizes = supportedSizes
        self.defaultOrder = defaultOrder
        self.requiredModuleIDs = requiredModuleIDs
        self.systemImage = systemImage
    }

    public func isAvailable(in configuration: WorkspaceModuleConfiguration) -> Bool {
        let enabledIDs = configuration.enabledModuleIDs
        return requiredModuleIDs.allSatisfy { enabledIDs.contains($0) }
    }
}

public nonisolated enum HomeWidgetRegistry {
    public static let defaultDescriptors: [HomeWidgetDescriptor] = [
        HomeWidgetDescriptor(
            id: HomeWidgetID.today,
            titleKey: .homeWidgetToday,
            category: .research,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 0,
            requiredModuleIDs: ["tasks"],
            systemImage: "sun.max"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.activeProjects,
            titleKey: .homeWidgetActiveProjects,
            category: .project,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 1,
            requiredModuleIDs: ["projects"],
            systemImage: "folder"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.aiReview,
            titleKey: .homeWidgetAIReview,
            category: .ai,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 2,
            requiredModuleIDs: ["ai-lab"],
            systemImage: "brain"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.calendar,
            titleKey: .homeWidgetCalendar,
            category: .calendar,
            defaultSize: .large,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 3,
            requiredModuleIDs: ["calendar"],
            systemImage: "calendar"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.recentPapers,
            titleKey: .homeWidgetRecentPapers,
            category: .library,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 4,
            requiredModuleIDs: ["paper-library"],
            systemImage: "doc.richtext"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.readingPlan,
            titleKey: .homeWidgetReadingPlan,
            category: .library,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 5,
            requiredModuleIDs: ["paper-library"],
            systemImage: "books.vertical"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.projectHealth,
            titleKey: .homeWidgetProjectHealth,
            category: .project,
            defaultSize: .small,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 6,
            requiredModuleIDs: ["projects"],
            systemImage: "waveform.path.ecg"
        ),
        HomeWidgetDescriptor(
            id: HomeWidgetID.quickActions,
            titleKey: .homeWidgetQuickActions,
            category: .research,
            defaultSize: .medium,
            supportedSizes: [.small, .medium, .large, .wide],
            defaultOrder: 7,
            systemImage: "bolt"
        )
    ]

    public static func descriptor(id: String) -> HomeWidgetDescriptor? {
        defaultDescriptors.first { $0.id == id }
    }

    public static func availableDescriptors(in configuration: WorkspaceModuleConfiguration) -> [HomeWidgetDescriptor] {
        defaultDescriptors.filter { $0.isAvailable(in: configuration) }
    }
}

public nonisolated struct HomeWidgetLayoutItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String { widgetID }
    public var widgetID: String
    public var size: HomeWidgetSize
    public var column: Int
    public var row: Int
    public var isEnabled: Bool

    public init(widgetID: String, size: HomeWidgetSize, column: Int = 0, row: Int = 0, isEnabled: Bool = true) {
        self.widgetID = widgetID
        self.size = size
        self.column = column
        self.row = row
        self.isEnabled = isEnabled
    }
}

public nonisolated struct HomeWidgetLayout: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [HomeWidgetLayoutItem]
    public var updatedAt: Date

    public init(schemaVersion: Int = Self.currentSchemaVersion, items: [HomeWidgetLayoutItem] = [], updatedAt: Date = Date()) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        self.items = items
        self.updatedAt = updatedAt
    }

    public static func defaultLayout(descriptors: [HomeWidgetDescriptor] = HomeWidgetRegistry.defaultDescriptors, columns: Int = 4, now: Date = Date()) -> HomeWidgetLayout {
        var layout = HomeWidgetLayout(
            items: descriptors.sorted { $0.defaultOrder < $1.defaultOrder }.map { descriptor in
                HomeWidgetLayoutItem(widgetID: descriptor.id, size: descriptor.defaultSize)
            },
            updatedAt: now
        )
        layout.repack(descriptors: descriptors, columns: columns, updatedAt: now)
        return layout
    }

    public func normalized(descriptors: [HomeWidgetDescriptor], columns: Int, now: Date = Date()) -> HomeWidgetLayout {
        var layout = self
        layout.normalizeInPlace(descriptors: descriptors, columns: columns, updatedAt: now)
        return layout
    }

    public func visibleItems(descriptors: [HomeWidgetDescriptor], columns: Int) -> [HomeWidgetLayoutItem] {
        normalized(descriptors: descriptors, columns: columns).items.filter(\.isEnabled).sorted(by: Self.positionSort)
    }

    public mutating func reset(descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date = Date()) {
        self = Self.defaultLayout(descriptors: descriptors, columns: columns, now: updatedAt)
    }

    public mutating func setWidget(_ widgetID: String, isEnabled: Bool, descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date = Date()) {
        normalizeInPlace(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
        guard let index = items.firstIndex(where: { $0.widgetID == widgetID }) else {
            return
        }
        items[index].isEnabled = isEnabled
        repack(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
    }

    public mutating func resizeWidget(_ widgetID: String, to size: HomeWidgetSize, descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date = Date()) {
        normalizeInPlace(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
        guard let descriptor = descriptors.first(where: { $0.id == widgetID }),
              descriptor.supportedSizes.contains(size),
              let index = items.firstIndex(where: { $0.widgetID == widgetID }) else {
            return
        }
        items[index].size = size
        repack(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
    }

    public mutating func moveWidget(_ sourceWidgetID: String, before targetWidgetID: String, descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date = Date()) {
        normalizeInPlace(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
        var ordered = items.sorted(by: Self.positionSort)
        guard let sourceIndex = ordered.firstIndex(where: { $0.widgetID == sourceWidgetID }),
              let targetIndex = ordered.firstIndex(where: { $0.widgetID == targetWidgetID }),
              sourceIndex != targetIndex else {
            return
        }
        let source = ordered.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        ordered.insert(source, at: insertionIndex)
        items = ordered
        repack(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
    }

    public mutating func moveWidget(_ widgetID: String, offset: Int, descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date = Date()) {
        normalizeInPlace(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
        var ordered = items.sorted(by: Self.positionSort)
        guard let sourceIndex = ordered.firstIndex(where: { $0.widgetID == widgetID }) else {
            return
        }
        let destinationIndex = max(0, min(ordered.count - 1, sourceIndex + offset))
        guard sourceIndex != destinationIndex else {
            return
        }
        let source = ordered.remove(at: sourceIndex)
        ordered.insert(source, at: destinationIndex)
        items = ordered
        repack(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
    }

    private mutating func normalizeInPlace(descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date) {
        let descriptorMap = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        var seen: Set<String> = []
        var normalizedItems: [HomeWidgetLayoutItem] = []

        for item in items where descriptorMap[item.widgetID] != nil && !seen.contains(item.widgetID) {
            guard let descriptor = descriptorMap[item.widgetID] else { continue }
            var next = item
            if !descriptor.supportedSizes.contains(next.size) {
                next.size = descriptor.defaultSize
            }
            next.column = max(0, next.column)
            next.row = max(0, next.row)
            normalizedItems.append(next)
            seen.insert(item.widgetID)
        }

        for descriptor in descriptors.sorted(by: { $0.defaultOrder < $1.defaultOrder }) where !seen.contains(descriptor.id) {
            normalizedItems.append(HomeWidgetLayoutItem(widgetID: descriptor.id, size: descriptor.defaultSize))
        }

        items = normalizedItems
        repack(descriptors: descriptors, columns: columns, updatedAt: updatedAt)
    }

    private mutating func repack(descriptors: [HomeWidgetDescriptor], columns: Int, updatedAt: Date) {
        let descriptorMap = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let planned = HomeWidgetGridPlanner.repackedItems(
            items.sorted(by: Self.positionSort),
            descriptorsByID: descriptorMap,
            columns: columns
        )
        items = planned
        self.updatedAt = updatedAt
    }

    private static func positionSort(_ first: HomeWidgetLayoutItem, _ second: HomeWidgetLayoutItem) -> Bool {
        if first.row != second.row { return first.row < second.row }
        if first.column != second.column { return first.column < second.column }
        return first.widgetID < second.widgetID
    }
}

public nonisolated struct HomeWidgetGridCell: Hashable, Sendable {
    public let item: HomeWidgetLayoutItem
    public let columnSpan: Int
    public let rowSpan: Int
}

public nonisolated enum HomeWidgetGridPlanner {
    public static func columns(for width: Double) -> Int {
        if width >= 1120 { return 4 }
        if width >= 840 { return 3 }
        if width >= 560 { return 2 }
        return 1
    }

    public static func cells(items: [HomeWidgetLayoutItem], descriptorsByID: [String: HomeWidgetDescriptor], columns: Int) -> [HomeWidgetGridCell] {
        repackedItems(items, descriptorsByID: descriptorsByID, columns: columns)
            .filter(\.isEnabled)
            .map { item in
                let descriptor = descriptorsByID[item.widgetID]
                let size = descriptor?.supportedSizes.contains(item.size) == true ? item.size : (descriptor?.defaultSize ?? item.size)
                return HomeWidgetGridCell(
                    item: item,
                    columnSpan: min(max(1, columns), max(1, size.columnSpan)),
                    rowSpan: size.rowSpan
                )
            }
    }

    public static func repackedItems(_ items: [HomeWidgetLayoutItem], descriptorsByID: [String: HomeWidgetDescriptor], columns: Int) -> [HomeWidgetLayoutItem] {
        let safeColumns = max(1, columns)
        var occupied: Set<GridCoordinate> = []
        var packed: [HomeWidgetLayoutItem] = []
        let enabled = items.filter(\.isEnabled)
        let disabled = items.filter { !$0.isEnabled }

        for var item in enabled {
            let descriptor = descriptorsByID[item.widgetID]
            let size = descriptor?.supportedSizes.contains(item.size) == true ? item.size : (descriptor?.defaultSize ?? item.size)
            let columnSpan = min(safeColumns, max(1, size.columnSpan))
            let rowSpan = max(1, size.rowSpan)
            var row = 0
            var column = 0

            while true {
                if column + columnSpan > safeColumns {
                    row += 1
                    column = 0
                    continue
                }
                if isFree(column: column, row: row, columnSpan: columnSpan, rowSpan: rowSpan, occupied: occupied) {
                    break
                }
                column += 1
            }

            item.size = size
            item.column = column
            item.row = row
            mark(column: column, row: row, columnSpan: columnSpan, rowSpan: rowSpan, occupied: &occupied)
            packed.append(item)
        }

        let disabledStartRow = (packed.map(\.row).max() ?? -1) + 1
        let normalizedDisabled = disabled.enumerated().map { offset, item in
            var next = item
            next.column = offset % safeColumns
            next.row = disabledStartRow + offset / safeColumns
            return next
        }
        return packed + normalizedDisabled
    }

    public static func hasOverlap(items: [HomeWidgetLayoutItem], descriptorsByID: [String: HomeWidgetDescriptor], columns: Int) -> Bool {
        var occupied: Set<GridCoordinate> = []
        for item in items where item.isEnabled {
            let descriptor = descriptorsByID[item.widgetID]
            let size = descriptor?.supportedSizes.contains(item.size) == true ? item.size : (descriptor?.defaultSize ?? item.size)
            let columnSpan = min(max(1, columns), max(1, size.columnSpan))
            let rowSpan = max(1, size.rowSpan)
            for row in item.row..<(item.row + rowSpan) {
                for column in item.column..<(item.column + columnSpan) {
                    let coordinate = GridCoordinate(column: column, row: row)
                    if occupied.contains(coordinate) {
                        return true
                    }
                    occupied.insert(coordinate)
                }
            }
        }
        return false
    }

    private static func isFree(column: Int, row: Int, columnSpan: Int, rowSpan: Int, occupied: Set<GridCoordinate>) -> Bool {
        for y in row..<(row + rowSpan) {
            for x in column..<(column + columnSpan) where occupied.contains(GridCoordinate(column: x, row: y)) {
                return false
            }
        }
        return true
    }

    private static func mark(column: Int, row: Int, columnSpan: Int, rowSpan: Int, occupied: inout Set<GridCoordinate>) {
        for y in row..<(row + rowSpan) {
            for x in column..<(column + columnSpan) {
                occupied.insert(GridCoordinate(column: x, row: y))
            }
        }
    }

    private nonisolated struct GridCoordinate: Hashable, Sendable {
        var column: Int
        var row: Int
    }
}