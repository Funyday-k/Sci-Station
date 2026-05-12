import Foundation

/// Single source of truth for project-space tab icons. Both the sidebar
/// (`WorkspaceSection.systemImage`) and the tab bar
/// (`ProjectSpaceTabsBuilder.systemImage(for:)`) should call through here so
/// that icon changes only need to happen in one place.
///
/// See DOC/comment.md §6.3.
public enum ProjectSpaceTabIcon {
    public nonisolated static func systemImage(for tabID: String) -> String {
        switch tabID {
        case "overview":
            return "square.grid.2x2"
        case "papers":
            return "books.vertical"
        case "wiki":
            return "doc.text"
        case "tasks":
            return "checklist"
        case "calendar":
            return "calendar"
        case "ai-drafts":
            return "brain"
        case "graph":
            return "point.3.connected.trianglepath.dotted"
        case "code":
            return "chevron.left.forwardslash.chevron.right"
        case "data":
            return "externaldrive"
        case "experiments":
            return "testtube.2"
        case "recommendations":
            return "sparkles"
        case "materials":
            return "shippingbox"
        case "pdf-reader":
            return "doc.viewfinder"
        case "writing":
            return "pencil.and.outline"
        case "theory":
            return "function"
        default:
            return "square"
        }
    }
}
