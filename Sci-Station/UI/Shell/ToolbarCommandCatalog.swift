import Foundation

public nonisolated enum ToolbarCommandCatalog {
    public static func commandID(for actionID: ToolbarActionID) -> String {
        switch actionID {
        case .workspaceMenu:
            return "workspace.menu"
        case .aiPanel:
            return "shell.aiPanel"
        case .inspector:
            return "shell.inspector"
        case .refresh:
            return "workspace.refresh"
        case .allTodos:
            return "task.showAll"
        case .newProject:
            return "project.new"
        case .importPDF:
            return "paper.importPDF"
        case .addByIdentifier:
            return "paper.importByIdentifier"
        case .pdfSearch:
            return "pdf.search"
        case .pdfFindPrevious:
            return "pdf.findPrevious"
        case .pdfFindNext:
            return "pdf.findNext"
        case .pdfAnnotationPlaceholder:
            return "pdf.showAnnotations"
        case .wikiNewPage:
            return "wiki.newPage"
        case .wikiSave:
            return "wiki.save"
        case .wikiPreviewMode:
            return "wiki.previewMode"
        case .graphSearch:
            return "graph.search"
        case .graphDepth:
            return "graph.depth"
        case .graphLayoutMode:
            return "graph.layoutMode"
        case .graphFilterKinds:
            return "graph.filterKinds"
        case .graphResetView:
            return "graph.resetView"
        }
    }

    public static func toolbarActionID(for commandID: String) -> ToolbarActionID? {
        ToolbarActionID.allCases.first { self.commandID(for: $0) == commandID }
    }

    public static func contribution(for action: ToolbarAction, placement: CommandPlacement = .toolbar) -> CommandContribution {
        CommandContribution(
            id: commandID(for: action.id),
            title: action.title,
            systemImage: action.systemImage,
            placement: placement,
            isEnabledByDefault: action.isEnabled
        )
    }

    public static func contributions(for actions: [ToolbarAction], placement: CommandPlacement = .toolbar) -> [CommandContribution] {
        actions.map { contribution(for: $0, placement: placement) }
    }
}

public extension ToolbarAction {
    var commandID: String {
        ToolbarCommandCatalog.commandID(for: id)
    }

    var commandContribution: CommandContribution {
        ToolbarCommandCatalog.contribution(for: self)
    }
}

public extension ToolbarModel {
    var primaryActions: [ToolbarAction] {
        globalActions + pageActions
    }

    var primaryCommandContributions: [CommandContribution] {
        ToolbarCommandCatalog.contributions(for: primaryActions)
    }

    var overflowCommandContributions: [CommandContribution] {
        ToolbarCommandCatalog.contributions(for: overflowActions)
    }
}
