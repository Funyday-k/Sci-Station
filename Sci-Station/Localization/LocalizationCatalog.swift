import Foundation

public nonisolated enum AppLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public nonisolated init(preference: AppLanguagePreference, preferredLanguages: [String] = Locale.preferredLanguages) {
        switch preference {
        case .simplifiedChinese:
            self = .simplifiedChinese
        case .english:
            self = .english
        case .system:
            self = preferredLanguages.first?.hasPrefix("zh") == true ? .simplifiedChinese : .english
        }
    }
}

public nonisolated enum L10nKey: String, Codable, CaseIterable, Hashable, Sendable {
    case routeHome
    case routeProjects
    case routeLibrary
    case routeCalendar
    case routeAILab
    case routeSettings
    case routePDFReader
    case routeWiki
    case routePapers
    case routeMaterials
    case routeGraph
    case routeTasks
    case routeOverview

    case toolbarWorkspace
    case toolbarCreateWorkspace
    case toolbarOpenWorkspace
    case toolbarRevealInFinder
    case toolbarSettings
    case toolbarAI
    case toolbarOpenAI
    case toolbarInspector
    case toolbarShowInspector
    case toolbarRefresh
    case toolbarNewProject
    case toolbarAllTodos
    case toolbarAddByIdentifier
    case toolbarImportPDF
    case toolbarSearch
    case toolbarPrevious
    case toolbarNext
    case toolbarAnnotations
    case toolbarWikiNewPage
    case toolbarSave
    case toolbarPreview
    case menuView

    case appErrorTitle
    case appOK
    case appCancel
    case appUnknownError

    case sidebarResearchShell
    case sidebarCreateResearchProject
    case sidebarCollapseProjectTree
    case sidebarExpandProjectTree
    case sidebarProjectTreeCollapsedByPolicy
    case sidebarSortUsage
    case sidebarSortName
    case sidebarSortProjects
    case sidebarSearchProjects
    case sidebarNoProjects
    case sidebarShowArchived
    case sidebarHideArchived
    case sidebarArchivedSection
    case sidebarRecentSection
    case sidebarPinnedSection
    case sidebarOpenProject
    case sidebarPin
    case sidebarUnpin
    case sidebarExpandSections
    case sidebarCollapseSections

    case projectSpaceBackToProjects
    case projectSpaceUnavailableTitle
    case projectSpaceUnavailableMessage
    case projectSpaceMoreTabs
    case projectsChooseProject
    case projectsEmptyTitle
    case projectsPapersMetric
    case projectsOpenMetric
    case projectsUpdatedMetric
    case projectsEditInfo
    case projectsArchivedTitle
    case projectsRestore

    case projectArchiveQuestion
    case projectArchiveAction
    case projectTrashQuestion
    case projectTrashAction
    case projectArchiveDefaultMessage
    case projectArchiveMessageFormat
    case projectTrashMessageFormat
    case projectArchiveStatusFormat
    case projectTrashStatusFormat
    case projectRestoreStatusFormat

    case settingsBasicSettings
    case settingsInterfaceLanguage
    case settingsLanguageHelp
    case settingsResearchRoot
    case settingsWorkspaceName
    case settingsCreateRoot
    case settingsOpenRoot
    case settingsRevealRoot
    case settingsRename
    case settingsWorkspaceModules
    case settingsProjects
    case settingsProjectsHelp
    case settingsEdit
    case settingsLibrary
    case settingsModules
    case settingsTasks
    case settingsAILab
    case settingsDeveloper
    case settingsWorkspaceSummary
    case settingsModulesSummary
    case settingsLibrarySummary
    case settingsTasksSummary
    case settingsAILabSummary
    case settingsDeveloperSummary

    case homeDashboardSubtitle
    case homeRefreshSnapshot
    case homeLoadingSnapshot
    case homeTemporarilyUnavailable
    case homeRetry
    case homeEditLayout
    case homeDoneEditing
    case homeWidgetGallery
    case homeResetDefault
    case homeHideWidget
    case homeShowWidget
    case homeMoveEarlier
    case homeMoveLater
    case homeNoEnabledWidgets
    case homeWidgetEnabled
    case homeWidgetDisabled
    case homeWidgetUnavailableModulesFormat
    case homeWidgetSizeSmall
    case homeWidgetSizeTall
    case homeWidgetSizeMedium
    case homeWidgetSizeLarge
    case homeWidgetSizeWide
    case homeWidgetToday
    case homeWidgetActiveProjects
    case homeWidgetAIReview
    case homeWidgetCalendar
    case homeWidgetRecentPapers
    case homeWidgetReading
    case homeWidgetProjectHealth
    case homeWidgetQuickActions
    case homeWidgetCategoryResearch
    case homeWidgetCategoryAI
    case homeWidgetCategoryCalendar
    case homeWidgetCategoryLibrary
    case homeWidgetCategoryProject
    case homeRecentlyAdded
    case homeRecentlyRead
    case homeReadingEmpty
    case homeProjectHealthSummaryFormat
    case homeQuickActionOpenLibrary
    case homeQuickActionOpenWiki
    case homeQuickActionOpenCalendar
}

public nonisolated enum L10n {
    public static func text(_ key: L10nKey, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return simplifiedChinese[key] ?? english[key] ?? key.rawValue
        case .english:
            return english[key] ?? key.rawValue
        }
    }

    public static func format(_ key: L10nKey, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), locale: locale(for: language), arguments: arguments)
    }

    public static func missingKeys(language: AppLanguage) -> [L10nKey] {
        let catalog = language == .simplifiedChinese ? simplifiedChinese : english
        return L10nKey.allCases.filter { catalog[$0] == nil }
    }

    public static func resolve(rawKey: String, language: AppLanguage) -> LocalizationResolution {
        guard let key = L10nKey(rawValue: rawKey) else {
            return LocalizationResolution(key: rawKey, language: language, text: rawKey, usedFallback: true)
        }
        let catalog = language == .simplifiedChinese ? simplifiedChinese : english
        return LocalizationResolution(key: rawKey, language: language, text: text(key, language: language), usedFallback: catalog[key] == nil)
    }

    public static func key(for top: WorkspaceRoute.Top) -> L10nKey {
        switch top {
        case .home:
            return .routeHome
        case .projects:
            return .routeProjects
        case .library:
            return .routeLibrary
        case .calendar:
            return .routeCalendar
        case .aiLab:
            return .routeAILab
        case .settings:
            return .routeSettings
        }
    }

    public static func key(for section: String) -> L10nKey? {
        switch section {
        case "overview":
            return .routeOverview
        case "papers":
            return .routePapers
        case "wiki":
            return .routeWiki
        case "tasks":
            return .routeTasks
        case "calendar":
            return .routeCalendar
        case "ai-drafts":
            return .routeAILab
        case "graph":
            return .routeGraph
        case "materials":
            return .routeMaterials
        case "pdf-reader":
            return .routePDFReader
        default:
            return nil
        }
    }

    private static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: language.rawValue)
    }

    private static let english: [L10nKey: String] = [
        .routeHome: "Home",
        .routeProjects: "Projects",
        .routeLibrary: "Library",
        .routeCalendar: "Calendar",
        .routeAILab: "AI Lab",
        .routeSettings: "Settings",
        .routePDFReader: "PDF Reader",
        .routeWiki: "Wiki",
        .routePapers: "Papers",
        .routeMaterials: "Materials",
        .routeGraph: "Graph",
        .routeTasks: "Tasks",
        .routeOverview: "Overview",

        .toolbarWorkspace: "Workspace",
        .toolbarCreateWorkspace: "Create Workspace",
        .toolbarOpenWorkspace: "Open Workspace",
        .toolbarRevealInFinder: "Reveal in Finder",
        .toolbarSettings: "Settings",
        .toolbarAI: "AI",
        .toolbarOpenAI: "Open AI",
        .toolbarInspector: "Inspector",
        .toolbarShowInspector: "Show inspector",
        .toolbarRefresh: "Refresh",
        .toolbarNewProject: "New Project",
        .toolbarAllTodos: "All Todos",
        .toolbarAddByIdentifier: "Add by Identifier",
        .toolbarImportPDF: "Import PDF",
        .toolbarSearch: "Search",
        .toolbarPrevious: "Previous",
        .toolbarNext: "Next",
        .toolbarAnnotations: "Annotations",
        .toolbarWikiNewPage: "New Page",
        .toolbarSave: "Save",
        .toolbarPreview: "Preview",
        .menuView: "View",

        .appErrorTitle: "Sci-Station Error",
        .appOK: "OK",
        .appCancel: "Cancel",
        .appUnknownError: "An unknown error occurred.",

        .sidebarResearchShell: "Research Shell",
        .sidebarCreateResearchProject: "Create a research project",
        .sidebarCollapseProjectTree: "Collapse project tree",
        .sidebarExpandProjectTree: "Expand project tree",
        .sidebarProjectTreeCollapsedByPolicy: "Project tree is collapsed because the window is too narrow. Widen the window to expand.",
        .sidebarSortUsage: "Usage",
        .sidebarSortName: "Name",
        .sidebarSortProjects: "Sort projects",
        .sidebarSearchProjects: "Search projects",
        .sidebarNoProjects: "No projects",
        .sidebarShowArchived: "Show Archived",
        .sidebarHideArchived: "Hide Archived",
        .sidebarArchivedSection: "Archived",
        .sidebarRecentSection: "Recent",
        .sidebarPinnedSection: "Pinned",
        .sidebarOpenProject: "Open Project",
        .sidebarPin: "Pin",
        .sidebarUnpin: "Unpin",
        .sidebarExpandSections: "Expand Sections",
        .sidebarCollapseSections: "Collapse Sections",

        .projectSpaceBackToProjects: "Back to projects",
        .projectSpaceUnavailableTitle: "ProjectSpace temporarily unavailable",
        .projectSpaceUnavailableMessage: "No available project tabs were resolved for this project.",
        .projectSpaceMoreTabs: "More",
        .projectsChooseProject: "Choose a project to enter its ProjectSpace tabs.",
        .projectsEmptyTitle: "No projects have been registered yet.",
        .projectsPapersMetric: "Papers",
        .projectsOpenMetric: "Open",
        .projectsUpdatedMetric: "Updated",
        .projectsEditInfo: "Edit Project Info",
        .projectsArchivedTitle: "Archived Projects",
        .projectsRestore: "Restore",

        .projectArchiveQuestion: "Archive project?",
        .projectArchiveAction: "Archive Project",
        .projectTrashQuestion: "Move project to trash?",
        .projectTrashAction: "Move to Trash",
        .projectArchiveDefaultMessage: "This will archive the project and keep workspace files in place.",
        .projectArchiveMessageFormat: "%@ will be hidden from active Projects. Files under %@ stay in the workspace.",
        .projectTrashMessageFormat: "%@ will be hidden and moved from %@ to the workspace trash.",
        .projectArchiveStatusFormat: "Archived project: %@. Workspace files were left in place.",
        .projectTrashStatusFormat: "Moved project to workspace trash: %@.",
        .projectRestoreStatusFormat: "Restored project: %@.",

        .settingsBasicSettings: "Basic Settings",
        .settingsInterfaceLanguage: "Interface Language",
        .settingsLanguageHelp: "The language setting is used for newly unified interface text.",
        .settingsResearchRoot: "Research Root",
        .settingsWorkspaceName: "Workspace name",
        .settingsCreateRoot: "Create Root",
        .settingsOpenRoot: "Open Root",
        .settingsRevealRoot: "Reveal in Finder",
        .settingsRename: "Rename",
        .settingsWorkspaceModules: "Workspace Modules",
        .settingsProjects: "Projects",
        .settingsProjectsHelp: "Edit project names, descriptions, icons, and colors.",
        .settingsEdit: "Edit",
        .settingsLibrary: "Library",
        .settingsModules: "Modules",
        .settingsTasks: "Tasks",
        .settingsAILab: "AI Lab",
        .settingsDeveloper: "Developer",
        .settingsWorkspaceSummary: "Manage the research root and workspace identity.",
        .settingsModulesSummary: "Enable, pin, repair, and override built-in workspace modules.",
        .settingsLibrarySummary: "Control paper import defaults, MinerU conversion, migration, and library table behavior.",
        .settingsTasksSummary: "Configure todo sync with Apple Reminders.",
        .settingsAILabSummary: "Configure API provider, runtime, hooks, MCP, and knowledge context.",
        .settingsDeveloperSummary: "Inspect settings files and generated agent paths.",

        .homeDashboardSubtitle: "Today's research command center",
        .homeRefreshSnapshot: "Refresh Home snapshot",
        .homeLoadingSnapshot: "Building Home snapshot...",
        .homeTemporarilyUnavailable: "Home temporarily unavailable",
        .homeRetry: "Retry",
        .homeEditLayout: "Edit Layout",
        .homeDoneEditing: "Done",
        .homeWidgetGallery: "Widget Gallery",
        .homeResetDefault: "Reset Default",
        .homeHideWidget: "Hide widget",
        .homeShowWidget: "Show widget",
        .homeMoveEarlier: "Move earlier",
        .homeMoveLater: "Move later",
        .homeNoEnabledWidgets: "No widgets are enabled. Open the widget gallery or reset the layout.",
        .homeWidgetEnabled: "Enabled",
        .homeWidgetDisabled: "Disabled",
        .homeWidgetUnavailableModulesFormat: "Requires modules: %@",
        .homeWidgetSizeSmall: "Small (1×1)",
        .homeWidgetSizeTall: "Tall (2×1)",
        .homeWidgetSizeMedium: "Medium (2×2)",
        .homeWidgetSizeLarge: "Large (3×3)",
        .homeWidgetSizeWide: "Wide (1×2)",
        .homeWidgetToday: "Today",
        .homeWidgetActiveProjects: "Active Projects",
        .homeWidgetAIReview: "AI Review",
        .homeWidgetCalendar: "Calendar",
        .homeWidgetRecentPapers: "Recent Papers",
        .homeWidgetReading: "Reading",
        .homeWidgetProjectHealth: "Project Health",
        .homeWidgetQuickActions: "Quick Actions",
        .homeWidgetCategoryResearch: "Research",
        .homeWidgetCategoryAI: "AI",
        .homeWidgetCategoryCalendar: "Calendar",
        .homeWidgetCategoryLibrary: "Library",
        .homeWidgetCategoryProject: "Project",
        .homeRecentlyAdded: "Recently Added",
        .homeRecentlyRead: "Recently Read",
        .homeReadingEmpty: "No papers to read yet.",
        .homeProjectHealthSummaryFormat: "%d projects, %d papers, %d open todos, %d AI review items",
        .homeQuickActionOpenLibrary: "Open Library",
        .homeQuickActionOpenWiki: "Open Wiki",
        .homeQuickActionOpenCalendar: "Open Calendar"
    ]

    private static let simplifiedChinese: [L10nKey: String] = [
        .routeHome: "首页",
        .routeProjects: "项目",
        .routeLibrary: "论文库",
        .routeCalendar: "日历",
        .routeAILab: "AI 实验室",
        .routeSettings: "设置",
        .routePDFReader: "PDF 阅读器",
        .routeWiki: "Wiki",
        .routePapers: "论文",
        .routeMaterials: "材料",
        .routeGraph: "图谱",
        .routeTasks: "任务",
        .routeOverview: "概览",

        .toolbarWorkspace: "工作区",
        .toolbarCreateWorkspace: "创建工作区",
        .toolbarOpenWorkspace: "打开工作区",
        .toolbarRevealInFinder: "在 Finder 中显示",
        .toolbarSettings: "设置",
        .toolbarAI: "AI",
        .toolbarOpenAI: "打开 AI",
        .toolbarInspector: "检查器",
        .toolbarShowInspector: "显示检查器",
        .toolbarRefresh: "刷新",
        .toolbarNewProject: "新建项目",
        .toolbarAllTodos: "全部待办",
        .toolbarAddByIdentifier: "按标识添加",
        .toolbarImportPDF: "导入 PDF",
        .toolbarSearch: "搜索",
        .toolbarPrevious: "上一个",
        .toolbarNext: "下一个",
        .toolbarAnnotations: "标注",
        .toolbarWikiNewPage: "新建页面",
        .toolbarSave: "保存",
        .toolbarPreview: "预览",
        .menuView: "视图",

        .appErrorTitle: "Sci-Station 错误",
        .appOK: "好",
        .appCancel: "取消",
        .appUnknownError: "发生未知错误。",

        .sidebarResearchShell: "研究工作台",
        .sidebarCreateResearchProject: "创建研究项目",
        .sidebarCollapseProjectTree: "折叠项目树",
        .sidebarExpandProjectTree: "展开项目树",
        .sidebarProjectTreeCollapsedByPolicy: "窗口宽度不足，项目树已自动折叠。请拉宽窗口以展开。",
        .sidebarSortUsage: "最近使用",
        .sidebarSortName: "名称",
        .sidebarSortProjects: "项目排序",
        .sidebarSearchProjects: "搜索项目",
        .sidebarNoProjects: "暂无项目",
        .sidebarShowArchived: "显示归档",
        .sidebarHideArchived: "隐藏归档",
        .sidebarArchivedSection: "已归档",
        .sidebarRecentSection: "最近",
        .sidebarPinnedSection: "固定",
        .sidebarOpenProject: "打开项目",
        .sidebarPin: "固定",
        .sidebarUnpin: "取消固定",
        .sidebarExpandSections: "展开分区",
        .sidebarCollapseSections: "折叠分区",

        .projectSpaceBackToProjects: "返回项目",
        .projectSpaceUnavailableTitle: "ProjectSpace 暂时不可用",
        .projectSpaceUnavailableMessage: "没有为该项目解析到可用标签页。",
        .projectSpaceMoreTabs: "更多",
        .projectsChooseProject: "选择一个项目进入 ProjectSpace 标签页。",
        .projectsEmptyTitle: "还没有注册项目。",
        .projectsPapersMetric: "论文",
        .projectsOpenMetric: "待办",
        .projectsUpdatedMetric: "更新",
        .projectsEditInfo: "编辑项目信息",
        .projectsArchivedTitle: "已归档项目",
        .projectsRestore: "恢复",

        .projectArchiveQuestion: "归档项目？",
        .projectArchiveAction: "归档项目",
        .projectTrashQuestion: "将项目移入废纸篓？",
        .projectTrashAction: "移入废纸篓",
        .projectArchiveDefaultMessage: "这会归档项目，并保留工作区文件。",
        .projectArchiveMessageFormat: "%@ 将从活跃项目中隐藏。%@ 下的文件会继续保留在工作区中。",
        .projectTrashMessageFormat: "%@ 将被隐藏，并从 %@ 移入工作区废纸篓。",
        .projectArchiveStatusFormat: "已归档项目：%@。工作区文件保持不变。",
        .projectTrashStatusFormat: "已将项目移入工作区废纸篓：%@。",
        .projectRestoreStatusFormat: "已恢复项目：%@。",

        .settingsBasicSettings: "基本设置",
        .settingsInterfaceLanguage: "界面语言",
        .settingsLanguageHelp: "语言设置会用于已经统一的新界面文案。",
        .settingsResearchRoot: "研究根目录",
        .settingsWorkspaceName: "工作区名称",
        .settingsCreateRoot: "创建根目录",
        .settingsOpenRoot: "打开根目录",
        .settingsRevealRoot: "在 Finder 中显示",
        .settingsRename: "重命名",
        .settingsWorkspaceModules: "工作区模块",
        .settingsProjects: "项目",
        .settingsProjectsHelp: "编辑项目名称、描述、图标和颜色。",
        .settingsEdit: "编辑",
        .settingsLibrary: "论文库",
        .settingsModules: "模块",
        .settingsTasks: "任务",
        .settingsAILab: "AI 实验室",
        .settingsDeveloper: "开发者",
        .settingsWorkspaceSummary: "管理研究根目录和工作区身份。",
        .settingsModulesSummary: "启用、固定、修复和覆盖内置工作区模块。",
        .settingsLibrarySummary: "控制论文导入默认值、MinerU 转换、迁移和论文库表格行为。",
        .settingsTasksSummary: "配置待办与 Apple Reminders 的同步。",
        .settingsAILabSummary: "配置 API provider、运行时、hooks、MCP 和知识上下文。",
        .settingsDeveloperSummary: "检查设置文件和生成的 agent 路径。",

        .homeDashboardSubtitle: "今天的研究主控台",
        .homeRefreshSnapshot: "刷新 Home 快照",
        .homeLoadingSnapshot: "正在构建 Home 快照...",
        .homeTemporarilyUnavailable: "Home 暂时不可用",
        .homeRetry: "重试",
        .homeEditLayout: "编辑布局",
        .homeDoneEditing: "完成",
        .homeWidgetGallery: "小组件库",
        .homeResetDefault: "恢复默认",
        .homeHideWidget: "隐藏小组件",
        .homeShowWidget: "显示小组件",
        .homeMoveEarlier: "前移",
        .homeMoveLater: "后移",
        .homeNoEnabledWidgets: "当前没有启用的小组件。请打开小组件库或恢复默认布局。",
        .homeWidgetEnabled: "已启用",
        .homeWidgetDisabled: "未启用",
        .homeWidgetUnavailableModulesFormat: "需要模块：%@",
        .homeWidgetSizeSmall: "小 (1×1)",
        .homeWidgetSizeTall: "竖向 (2×1)",
        .homeWidgetSizeMedium: "中 (2×2)",
        .homeWidgetSizeLarge: "大 (3×3)",
        .homeWidgetSizeWide: "宽 (1×2)",
        .homeWidgetToday: "今日",
        .homeWidgetActiveProjects: "活跃项目",
        .homeWidgetAIReview: "AI 审核",
        .homeWidgetCalendar: "日历",
        .homeWidgetRecentPapers: "最近论文",
        .homeWidgetReading: "阅读",
        .homeWidgetProjectHealth: "项目健康",
        .homeWidgetQuickActions: "快速操作",
        .homeWidgetCategoryResearch: "研究",
        .homeWidgetCategoryAI: "AI",
        .homeWidgetCategoryCalendar: "日历",
        .homeWidgetCategoryLibrary: "论文库",
        .homeWidgetCategoryProject: "项目",
        .homeRecentlyAdded: "最近添加",
        .homeRecentlyRead: "最近阅读",
        .homeReadingEmpty: "还没有待读论文。",
        .homeProjectHealthSummaryFormat: "%d 个项目，%d 篇论文，%d 个未完成待办，%d 项 AI 审核",
        .homeQuickActionOpenLibrary: "打开论文库",
        .homeQuickActionOpenWiki: "打开 Wiki",
        .homeQuickActionOpenCalendar: "打开日历"
    ]
}

public nonisolated struct LocalizationResolution: Hashable, Sendable {
    public let key: String
    public let language: AppLanguage
    public let text: String
    public let usedFallback: Bool
}

public nonisolated struct LocalizationAuditFinding: Identifiable, Hashable, Sendable {
    public var id: String { "\(filePath):\(line):\(literal)" }
    public let filePath: String
    public let line: Int
    public let literal: String
}

public nonisolated enum LocalizationAudit {
    public static let defaultAllowedLiterals: Set<String> = [
        "", " ", "-", "_", "/", ".", ",", ":", ";", "...",
        "folder", "plus", "sparkles", "sidebar.right", "arrow.clockwise",
        "magnifyingglass", "chevron.up", "chevron.down", "highlighter", "doc.badge.plus",
        "square.and.arrow.down", "eye", "house", "books.vertical", "calendar", "brain", "gearshape"
    ]

    public static func findings(in source: String, filePath: String, allowedLiterals: Set<String> = defaultAllowedLiterals) -> [LocalizationAuditFinding] {
        source.components(separatedBy: .newlines).enumerated().flatMap { offset, line in
            stringLiterals(in: line).compactMap { literal in
                guard shouldFlag(literal, allowedLiterals: allowedLiterals) else {
                    return nil
                }
                return LocalizationAuditFinding(filePath: filePath, line: offset + 1, literal: literal)
            }
        }
    }

    private static func shouldFlag(_ literal: String, allowedLiterals: Set<String>) -> Bool {
        if allowedLiterals.contains(literal) { return false }
        if L10nKey(rawValue: literal) != nil { return false }
        if literal.hasPrefix("system:") || literal.hasPrefix("sf:") { return false }
        if literal.hasPrefix("#") || literal.hasPrefix(".") || literal.hasPrefix("/") { return false }
        if literal.contains("%@") || literal.contains("%d") { return false }
        if literal.range(of: #"^[a-z0-9_\-./]+$"#, options: .regularExpression) != nil { return false }
        return literal.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
    }

    private static func stringLiterals(in line: String) -> [String] {
        var results: [String] = []
        var current = ""
        var isInsideLiteral = false
        var isEscaped = false

        for character in line {
            if isInsideLiteral {
                if isEscaped {
                    current.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    results.append(current)
                    current = ""
                    isInsideLiteral = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                isInsideLiteral = true
            }
        }

        return results
    }
}
