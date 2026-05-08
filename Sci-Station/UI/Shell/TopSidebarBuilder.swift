import Foundation

public nonisolated struct TopSidebarItem: Identifiable, Hashable, Sendable {
    public var id: String { top.rawValue }
    public let top: WorkspaceRoute.Top
    public let title: String
    public let systemImage: String
    public let isPinFixed: Bool

    public nonisolated init(top: WorkspaceRoute.Top, title: String, systemImage: String, isPinFixed: Bool = false) {
        self.top = top
        self.title = title
        self.systemImage = systemImage
        self.isPinFixed = isPinFixed
    }
}

public nonisolated enum TopSidebarBuilder {
    public static let builtInItems: [TopSidebarItem] = [
        TopSidebarItem(top: .home, title: "Home", systemImage: "house"),
        TopSidebarItem(top: .projects, title: "Projects", systemImage: "folder"),
        TopSidebarItem(top: .library, title: "Library", systemImage: "books.vertical"),
        TopSidebarItem(top: .calendar, title: "Calendar", systemImage: "calendar"),
        TopSidebarItem(top: .aiLab, title: "AI Lab", systemImage: "brain"),
        TopSidebarItem(top: .settings, title: "Settings", systemImage: "gearshape", isPinFixed: true)
    ]

    public static func items(pinnedOrder: [String]) -> [TopSidebarItem] {
        let knownIDs = Set(builtInItems.map(\.id))
        let sanitizedOrder = pinnedOrder.filter { knownIDs.contains($0) && $0 != WorkspaceRoute.Top.settings.rawValue }
        let pinned = sanitizedOrder.compactMap { id in builtInItems.first { $0.id == id && !$0.isPinFixed } }
        let pinnedIDs = Set(pinned.map(\.id))
        let remaining = builtInItems.filter { !$0.isPinFixed && !pinnedIDs.contains($0.id) }
        let fixed = builtInItems.filter(\.isPinFixed)
        return pinned + remaining + fixed
    }
}