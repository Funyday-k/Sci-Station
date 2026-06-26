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
    AIManagementPanelView(workspace: PreviewFixtures.workspace)
        .environmentObject(AppViewModel())
}

#Preview("AI Lab Regular Width") {
    let appModel = AppViewModel()
    AgentPanelView(agentStreamStore: appModel.agentStreamStore, workspace: PreviewFixtures.workspace)
        .environmentObject(appModel)
        .frame(width: 980, height: 720)
}

#Preview("Settings AI Lab") {
    let appModel = AppViewModel()
    SettingsView(workspace: PreviewFixtures.workspace, fixedCategory: .aiLab)
        .environmentObject(appModel)
        .frame(width: 1180, height: 780)
}
#endif
