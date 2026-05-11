import SwiftUI

struct ProjectSpaceContentRouter: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject
    let tab: ProjectSpaceTab

    var body: some View {
        Group {
            switch tab.id {
            case "overview":
                ProjectOverviewView(workspace: workspace)
            case "papers":
                LibraryProjectView(workspace: workspace, project: project)
            case "wiki":
                WikiProjectView(workspace: workspace, project: project)
            case "tasks":
                TasksProjectView(workspace: workspace, project: project)
            case "calendar":
                CalendarProjectView(workspace: workspace, project: project)
            case "ai-drafts":
                AILabProjectWorkflowsView(workspace: workspace, project: project)
            case "materials":
                MaterialsView(workspace: workspace)
            case "pdf-reader":
                PDFReaderWorkspaceView(workspace: workspace)
            case "graph":
                ProjectSpacePlaceholderView(
                    title: "Graph",
                    systemImage: tab.systemImage,
                    message: "Graph data not built yet, see P44-P46."
                )
            case "code":
                ProjectSpacePlaceholderView(title: "Code", systemImage: tab.systemImage, message: "Project code workflows land in P55.")
            case "data":
                ProjectSpacePlaceholderView(title: "Data", systemImage: tab.systemImage, message: "Project data workflows land in P55.")
            case "experiments":
                ProjectSpacePlaceholderView(title: "Experiments", systemImage: tab.systemImage, message: "Experiment workflows land in P55.")
            case "recommendations":
                ProjectSpacePlaceholderView(title: "Recommendations", systemImage: tab.systemImage, message: "Recommendation workflows land after the graph foundation.")
            case "writing":
                ProjectSpacePlaceholderView(title: "Writing", systemImage: tab.systemImage, message: "Writing and manuscript workflows land in P56.")
            case "theory":
                ProjectSpacePlaceholderView(title: "Theory", systemImage: tab.systemImage, message: "Theory note workflows land in P54.")
            default:
                ProjectSpaceUnavailableView(
                    title: "Tab temporarily unavailable",
                    message: "No content router is registered for \(tab.id).",
                    retry: {
                        appModel.recordShellDebugEvent("route.persist.error", payload: .object([
                            "phase": .string("load"),
                            "message": .string("unknown_project_space_tab:\(tab.id)")
                        ]))
                        appModel.selectProjectSpaceTab(ProjectSpaceTabsBuilder.overviewTabID)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryProjectView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    var body: some View {
        LibraryListView(workspace: workspace)
            .onAppear {
                appModel.selectResearchProject(project.id, section: .library)
            }
    }
}

private struct WikiProjectView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    var body: some View {
        WikiWorkspaceView(workspace: workspace)
            .onAppear {
                appModel.selectResearchProject(project.id, section: .wiki)
            }
    }
}

private struct TasksProjectView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    var body: some View {
        TasksWorkspaceView(workspace: workspace)
            .onAppear {
                appModel.selectResearchProject(project.id, section: .tasks)
            }
    }
}

private struct CalendarProjectView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Project schedule for \(project.name).")
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        DashboardCalendarView(
                            selectedDate: Binding(
                                get: { appModel.selectedDashboardDate },
                                set: { appModel.selectDashboardDate($0) }
                            ),
                            projectID: project.id
                        )
                        .frame(minWidth: 420)

                        TodoDashboardWidget(scope: .currentProject)
                            .frame(minWidth: 340)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        DashboardCalendarView(
                            selectedDate: Binding(
                                get: { appModel.selectedDashboardDate },
                                set: { appModel.selectDashboardDate($0) }
                            ),
                            projectID: project.id
                        )

                        TodoDashboardWidget(scope: .currentProject)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            appModel.focusResearchProject(project.id)
        }
    }
}

private struct AILabProjectWorkflowsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    var body: some View {
        AILabWorkspaceView(workspace: workspace)
            .onAppear {
                appModel.focusResearchProject(project.id)
            }
    }
}

private struct ProjectSpacePlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.largeTitle.weight(.semibold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProjectSpaceUnavailableView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}