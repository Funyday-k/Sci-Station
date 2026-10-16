#if DEBUG
import Foundation
import SwiftUI

/// Lightweight fixtures for SwiftUI `#Preview` blocks.
///
/// Page-level views require a `ResearchWorkspace` (and sometimes a
/// `ResearchProject`). These fixtures build in-memory model values pointing at a
/// throwaway temporary directory so previews can render their default/empty
/// states in Xcode Previews without a real workspace on disk.
enum PreviewFixtures {
    static var workspace: ResearchWorkspace {
        ResearchWorkspace(
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SciStationPreviewWorkspace", isDirectory: true)
        )
    }

    static var project: ResearchProject {
        ResearchProject(
            id: "preview-project",
            name: "Preview Project",
            description: "Sample project used for SwiftUI previews.",
            relativePath: "projects/preview-project"
        )
    }
}

#Preview("AI Management Panel") {
    let appModel = AppViewModel()
    AIManagementPanelView(workspace: PreviewFixtures.workspace)
        .environmentObject(appModel)
        .environmentObject(appModel.navigationStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
}

#Preview("AI Lab Regular Width") {
    let appModel = AppViewModel()
    AgentPanelView(agentStreamStore: appModel.agentStreamStore, workspace: PreviewFixtures.workspace)
        .environmentObject(appModel)
        .environmentObject(appModel.workspaceStore)
        .environmentObject(appModel.libraryStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
        .frame(width: 980, height: 720)
}

#Preview("AI Lab Compact Width") {
    let appModel = AppViewModel()
    AgentPanelView(agentStreamStore: appModel.agentStreamStore, workspace: PreviewFixtures.workspace)
        .environmentObject(appModel)
        .environmentObject(appModel.workspaceStore)
        .environmentObject(appModel.libraryStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
        .frame(width: 640, height: 720)
}

#Preview("AI Lab Narrow Width") {
    let appModel = AppViewModel()
    AILabWorkspaceView(workspace: PreviewFixtures.workspace)
        .environmentObject(appModel)
        .environmentObject(appModel.workspaceStore)
        .environmentObject(appModel.libraryStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
        .frame(width: 460, height: 680)
}

#Preview("Settings AI Lab") {
    let appModel = AppViewModel()
    SettingsView(workspace: PreviewFixtures.workspace, fixedCategory: .aiLab)
        .environmentObject(appModel)
        .environmentObject(appModel.navigationStore)
        .environmentObject(appModel.libraryStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
        .frame(width: 1180, height: 780)
}

#Preview("Settings AI Lab Compact") {
    let appModel = AppViewModel()
    SettingsView(workspace: PreviewFixtures.workspace, fixedCategory: .aiLab)
        .environmentObject(appModel)
        .environmentObject(appModel.navigationStore)
        .environmentObject(appModel.libraryStore)
        .environmentObject(appModel.agentStore)
        .environmentObject(appModel.graphStore)
        .frame(width: 720, height: 720)
}

#Preview("Citation Graph Failure") {
    CitationGraphFailurePreview()
}

@MainActor
private struct CitationGraphFailurePreview: View {
    @StateObject private var appModel: AppViewModel

    init() {
        let appModel = AppViewModel()
        let error = PreviewGraphError.initializationFailed
        let retry: GraphStore.LoadOperation = { throw error }
        appModel.graphStore.restore(GraphStore.Snapshot(
            state: .failed(GraphFailureDiagnostic(error: error)),
            repository: nil,
            loadOperation: retry
        ))
        _appModel = StateObject(wrappedValue: appModel)
    }

    var body: some View {
        GraphView(workspace: PreviewFixtures.workspace)
            .environmentObject(appModel)
            .environmentObject(appModel.graphStore)
            .frame(width: 920, height: 680)
    }
}

private enum PreviewGraphError: LocalizedError {
    case initializationFailed

    var errorDescription: String? { "The preview graph database could not be opened." }
    var failureReason: String? { "The preview fixture simulates a failed graph initialization." }
    var recoverySuggestion: String? { "Retry to verify that the failure remains visible and actionable." }
}
#endif
