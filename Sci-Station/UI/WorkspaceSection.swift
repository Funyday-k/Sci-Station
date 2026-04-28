import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case dashboard
    case library
    case pdfReader
    case inbox
    case wiki
    case papers
    case concepts
    case methods
    case gaps
    case projects
    case materials
    case graph
    case llmLab
    case tasks
    case settings

    var id: String {
        rawValue
    }

    static var sidebarSections: [WorkspaceSection] {
        [.projects, .materials, .library, .inbox, .wiki, .tasks, .llmLab]
    }

    static var projectSidebarSections: [WorkspaceSection] {
        [.projects, .library, .wiki, .tasks, .materials]
    }

    var title: String {
        switch self {
        case .dashboard:
            return "Home"
        case .library:
            return "Library"
        case .pdfReader:
            return "PDF Reader"
        case .inbox:
            return "Inbox"
        case .wiki:
            return "Wiki"
        case .papers:
            return "Papers"
        case .concepts:
            return "Concepts"
        case .methods:
            return "Methods"
        case .gaps:
            return "Gaps"
        case .projects:
            return "Projects"
        case .materials:
            return "Materials"
        case .graph:
            return "Graph"
        case .llmLab:
            return "AI Lab"
        case .tasks:
            return "Tasks"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "house"
        case .library:
            return "books.vertical"
        case .pdfReader:
            return "doc.viewfinder"
        case .inbox:
            return "tray"
        case .wiki:
            return "doc.text"
        case .papers:
            return "doc.richtext"
        case .concepts:
            return "lightbulb"
        case .methods:
            return "square.stack.3d.up"
        case .gaps:
            return "scope"
        case .projects:
            return "folder"
        case .materials:
            return "shippingbox"
        case .graph:
            return "point.3.connected.trianglepath.dotted"
        case .llmLab:
            return "brain"
        case .tasks:
            return "checklist"
        case .settings:
            return "gearshape"
        }
    }

    var summary: String {
        switch self {
        case .dashboard:
            return "Global workspace overview for papers, projects, tasks, and recent activity."
        case .library:
            return "Track papers, reading state, tags, and import status."
        case .pdfReader:
            return "Focus on a selected paper with a dedicated in-app PDF reader."
        case .inbox:
            return "Stage incoming PDFs before they are normalized into raw/papers."
        case .wiki:
            return "Browse and edit Markdown knowledge pages across the project workspace."
        case .papers:
            return "Open paper summaries, annotations, and bibliography links."
        case .concepts:
            return "Capture reusable concepts and backlinks across the workspace."
        case .methods:
            return "Document methods, experiments, and reusable analysis patterns."
        case .gaps:
            return "Collect candidate research gaps and evidence trails."
        case .projects:
            return "Keep the research proposal, core papers, data, code, figures, outputs, and milestones in one project workspace."
        case .materials:
            return "Read project files such as data, code, figures, scripts, prompts, and outputs without exposing system settings."
        case .graph:
            return "Visualize or inspect knowledge relationships when graph support lands."
        case .llmLab:
            return "Run structured prompts and AI-assisted research workflows for the active project."
        case .tasks:
            return "Track due dates, complete reading tasks, and connect todo items back to papers."
        case .settings:
            return "Configure workspace, PDF, LLM, and external tool settings."
        }
    }
}