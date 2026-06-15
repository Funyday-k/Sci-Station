import Foundation

public nonisolated struct WorkspaceContextSnapshot: Codable, Hashable, Sendable {
    public var topLevelSectionID: String
    public var projectID: String?
    public var projectTitle: String?
    public var projectTabID: String?
    public var selectedPaperID: String?
    public var selectedPaperTitle: String?
    public var selectedPaperMarkdownPath: String?
    public var selectedMarkdownPath: String?
    public var selectedTodoID: String?
    public var calendarDateRange: DateInterval?
    public var pdfPageIndex: Int?
    public var selectedTextPreview: String?

    public nonisolated init(
        topLevelSectionID: String,
        projectID: String? = nil,
        projectTitle: String? = nil,
        projectTabID: String? = nil,
        selectedPaperID: String? = nil,
        selectedPaperTitle: String? = nil,
        selectedPaperMarkdownPath: String? = nil,
        selectedMarkdownPath: String? = nil,
        selectedTodoID: String? = nil,
        calendarDateRange: DateInterval? = nil,
        pdfPageIndex: Int? = nil,
        selectedTextPreview: String? = nil
    ) {
        self.topLevelSectionID = topLevelSectionID
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.projectTabID = projectTabID
        self.selectedPaperID = selectedPaperID
        self.selectedPaperTitle = selectedPaperTitle
        self.selectedPaperMarkdownPath = selectedPaperMarkdownPath
        self.selectedMarkdownPath = selectedMarkdownPath
        self.selectedTodoID = selectedTodoID
        self.calendarDateRange = calendarDateRange
        self.pdfPageIndex = pdfPageIndex
        self.selectedTextPreview = selectedTextPreview
    }

    public nonisolated var displayTitle: String {
        if let selectedPaperTitle, !selectedPaperTitle.isEmpty {
            return "Paper: \(selectedPaperTitle)"
        }
        if let selectedMarkdownPath, !selectedMarkdownPath.isEmpty {
            return "Wiki: \(selectedMarkdownPath)"
        }
        if let projectTitle, !projectTitle.isEmpty {
            return "Project: \(projectTitle)"
        }
        return topLevelSectionID
    }
}

public nonisolated enum RightRailMode: String, Codable, CaseIterable, Hashable, Sendable {
    case inspector
    case ai
    case hidden
}

public nonisolated enum RightRailPolicy {
    /// User preference is now the single source of truth for the right rail
    /// mode. The toolbar Inspector / AI buttons mutate `preferences.rightRailMode`
    /// via `setRightRailMode`, and this policy simply echoes it back so the
    /// ResponsiveShellPolicy uses the user's choice verbatim.
    ///
    /// Why we removed route-driven overrides
    /// =====================================
    /// Pre-2026-05-17 this function returned `.inspector` on Library / Wiki /
    /// PDF routes and `.hidden` on Home / Calendar / task-style tabs. That
    /// felt magical in demos but produced a real bug in the field: when the
    /// user explicitly clicked the toolbar Inspector toggle on a task tab
    /// to hide / show the rail, the next `applyRightRailRouteSuggestion()`
    /// pass would overwrite their preference with the route's suggestion.
    /// The result was that the rail either bounced back open after collapse
    /// or refused to open at all on tabs whose route hint was `.hidden`.
    ///
    /// `defaultMode(for:)` keeps the legacy hint available for callers that
    /// want to seed a workspace's initial preference (see `applyRightRailRouteSuggestion`).
    public static func suggestedMode(
        route: WorkspaceRoute,
        context: WorkspaceContextSnapshot,
        preferredMode: RightRailMode
    ) -> RightRailMode {
        preferredMode
    }

    /// Initial default for a workspace that has never been touched. Used at
    /// workspace open to seed a sensible starting state; never used to
    /// override a user-set preference at runtime.
    public static func defaultMode(
        route: WorkspaceRoute,
        context: WorkspaceContextSnapshot
    ) -> RightRailMode {
        switch route.top {
        case .library:
            return .inspector
        case .projects:
            if context.projectTabID == "pdf-reader" {
                return .inspector
            }
            return ["papers", "wiki"].contains(context.projectTabID) ? .inspector : .hidden
        case .home, .calendar, .aiLab, .settings:
            return .hidden
        }
    }
}

public nonisolated enum ToolbarActionID: String, Codable, CaseIterable, Hashable, Sendable {
    case workspaceMenu = "workspace_menu"
    case projectActions = "project_actions"
    case aiPanel = "ai_panel"
    case inspector
    case refresh
    case allTodos = "all_todos"
    case newProject = "new_project"
    case importPDF = "import_pdf"
    case addByIdentifier = "add_by_identifier"
    case pdfSearch = "pdf_search"
    case pdfFindPrevious = "pdf_find_previous"
    case pdfFindNext = "pdf_find_next"
    case pdfAnnotationPlaceholder = "pdf_annotation_placeholder"
    case wikiNewPage = "wiki_new_page"
    case wikiSave = "wiki_save"
    case wikiPreviewMode = "wiki_preview_mode"
    // Graph toolbar actions.
    case graphSearch = "graph_search"
    case graphDepth = "graph_depth"
    case graphLayoutMode = "graph_layout_mode"
    case graphFilterKinds = "graph_filter_kinds"
    case graphResetView = "graph_reset_view"
}

public nonisolated struct ToolbarAction: Identifiable, Codable, Hashable, Sendable {
    public var id: ToolbarActionID
    public var title: String
    public var systemImage: String
    public var isEnabled: Bool

    public nonisolated init(id: ToolbarActionID, title: String, systemImage: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
    }
}

public nonisolated struct ToolbarModel: Codable, Hashable, Sendable {
    public var globalActions: [ToolbarAction]
    public var pageActions: [ToolbarAction]
    public var overflowActions: [ToolbarAction]

    public nonisolated init(globalActions: [ToolbarAction] = [], pageActions: [ToolbarAction] = [], overflowActions: [ToolbarAction] = []) {
        self.globalActions = globalActions
        self.pageActions = pageActions
        self.overflowActions = overflowActions
    }

    public nonisolated func contains(_ id: ToolbarActionID) -> Bool {
        (globalActions + pageActions + overflowActions).contains { $0.id == id }
    }

    public nonisolated func action(_ id: ToolbarActionID) -> ToolbarAction? {
        (globalActions + pageActions + overflowActions).first { $0.id == id }
    }
}

public nonisolated enum ToolbarPolicy {
    public static func resolve(route: WorkspaceRoute, context: WorkspaceContextSnapshot, language: AppLanguage = .english) -> ToolbarModel {
        var globalActions: [ToolbarAction] = [
            ToolbarAction(id: .workspaceMenu, title: L10n.text(.toolbarWorkspace, language: language), systemImage: "folder"),
            ToolbarAction(id: .aiPanel, title: L10n.text(.toolbarAI, language: language), systemImage: "sparkles"),
            ToolbarAction(id: .inspector, title: L10n.text(.toolbarInspector, language: language), systemImage: "sidebar.right")
        ]
        var pageActions: [ToolbarAction] = []
        var overflowActions: [ToolbarAction] = []

        switch route.top {
        case .home:
            break
        case .projects:
            if context.projectID == nil {
                pageActions.append(ToolbarAction(id: .newProject, title: L10n.text(.toolbarNewProject, language: language), systemImage: "plus"))
            } else if context.projectTabID == "papers" {
                pageActions.append(contentsOf: paperImportActions(language: language))
            } else if context.projectTabID == "wiki" {
                pageActions.append(contentsOf: wikiActions(language: language))
            } else if context.projectTabID == "pdf-reader" {
                pageActions.append(contentsOf: pdfReaderActions(language: language))
            }
        case .library:
            pageActions.append(contentsOf: paperImportActions(language: language))
        case .calendar:
            pageActions.append(ToolbarAction(id: .allTodos, title: L10n.text(.toolbarAllTodos, language: language), systemImage: "checklist"))
        case .aiLab:
            globalActions.removeAll { $0.id == .inspector }
        case .settings:
            globalActions.removeAll { $0.id == .inspector }
        }

        if route.top == .projects, context.projectTabID == nil {
            overflowActions.append(ToolbarAction(id: .allTodos, title: L10n.text(.toolbarAllTodos, language: language), systemImage: "checklist"))
        }

        if route.top == .projects, context.projectID != nil {
            let title = language == .simplifiedChinese ? "项目" : "Project"
            globalActions.insert(ToolbarAction(id: .projectActions, title: title, systemImage: "ellipsis.circle"), at: 1)
        }

        return ToolbarModel(globalActions: globalActions, pageActions: pageActions, overflowActions: overflowActions)
    }

    public static func showsPaperImportActions(route: WorkspaceRoute, context: WorkspaceContextSnapshot) -> Bool {
        route.top == .library || (route.top == .projects && context.projectTabID == "papers")
    }

    private static func paperImportActions(language: AppLanguage) -> [ToolbarAction] {
        [
            ToolbarAction(id: .addByIdentifier, title: L10n.text(.toolbarAddByIdentifier, language: language), systemImage: "number"),
            ToolbarAction(id: .importPDF, title: L10n.text(.toolbarImportPDF, language: language), systemImage: "doc.badge.plus")
        ]
    }

    private static func pdfReaderActions(language: AppLanguage) -> [ToolbarAction] {
        [
            ToolbarAction(id: .pdfSearch, title: L10n.text(.toolbarSearch, language: language), systemImage: "magnifyingglass"),
            ToolbarAction(id: .pdfFindPrevious, title: L10n.text(.toolbarPrevious, language: language), systemImage: "chevron.up"),
            ToolbarAction(id: .pdfFindNext, title: L10n.text(.toolbarNext, language: language), systemImage: "chevron.down"),
            ToolbarAction(id: .pdfAnnotationPlaceholder, title: L10n.text(.toolbarAnnotations, language: language), systemImage: "highlighter")
        ]
    }

    private static func wikiActions(language: AppLanguage) -> [ToolbarAction] {
        [
            ToolbarAction(id: .wikiNewPage, title: L10n.text(.toolbarWikiNewPage, language: language), systemImage: "doc.badge.plus"),
            ToolbarAction(id: .wikiSave, title: L10n.text(.toolbarSave, language: language), systemImage: "square.and.arrow.down"),
            ToolbarAction(id: .wikiPreviewMode, title: L10n.text(.toolbarPreview, language: language), systemImage: "eye")
        ]
    }
}
