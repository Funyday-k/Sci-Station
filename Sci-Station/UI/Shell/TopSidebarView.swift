import SwiftUI

struct TopSidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    var body: some View {
        VStack(spacing: 12) {
            header

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(appModel.topSidebarItems) { item in
                        TopSidebarRow(
                            item: item,
                            isSelected: isSelected(item)
                        ) {
                            appModel.selectTopLevelRoute(item.top)
                        }
                        .draggable(item.id)
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            guard let droppedID = droppedIDs.first else { return false }
                            appModel.moveTopSidebarItem(droppedID, before: item.id)
                            return true
                        }

                        if item.top == .projects, workspace != nil {
                            SidebarProjectTreeSection()
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            if workspace != nil {
                Button {
                    appModel.beginCreatingResearchProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.horizontal, 18)
                .help("Create a research project")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(workspace?.displayName ?? "Sci-Station")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(appModel.workspaceModuleStatusSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            appModel.recordSidebarRender()
        }
        .onChange(of: appModel.workspacePreferences.pinnedTopLevelOrder) { _, _ in
            appModel.recordSidebarRender()
        }
        .confirmationDialog(
            "Archive project?",
            isPresented: $appModel.isShowingProjectDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Project", role: .destructive) {
                appModel.confirmDeletePendingResearchProject()
            }
            Button("Cancel", role: .cancel) {
                appModel.cancelDeleteResearchProject()
            }
        } message: {
            Text(projectDeleteConfirmationMessage)
        }
    }

    private var projectDeleteConfirmationMessage: String {
        guard let project = appModel.projectPendingDeletion else {
            return "This will archive the project and keep workspace files in place."
        }
        return "\(project.name) will be hidden from active Projects. Files under \(project.relativePath) stay in the workspace; physical deletion is not performed in this step."
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3)
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sci-Station")
                    .font(.headline)
                Text("Research Shell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func isSelected(_ item: TopSidebarItem) -> Bool {
        if item.top == .projects {
            return appModel.selectedSection == .projects
        }
        return appModel.selectedSection == workspaceSection(for: item.top)
    }

    private func workspaceSection(for top: WorkspaceRoute.Top) -> WorkspaceSection {
        switch top {
        case .home:
            return .dashboard
        case .projects:
            return .projects
        case .library:
            return .library
        case .calendar:
            return .calendar
        case .aiLab:
            return .llmLab
        case .settings:
            return .settings
        }
    }
}

private enum SidebarProjectSortMode: String, CaseIterable, Identifiable {
    case usage
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage:
            return "Usage"
        case .name:
            return "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .usage:
            return "clock.arrow.circlepath"
        case .name:
            return "textformat.abc"
        }
    }
}

private struct SidebarProjectTreeSection: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var sortMode = SidebarProjectSortMode.usage

    private var isExpanded: Bool {
        appModel.workspacePreferences.isProjectTreeExpanded
    }

    private var sortedProjects: [ResearchProject] {
        switch sortMode {
        case .usage:
            return appModel.activeResearchProjects.sorted { first, second in
                if first.updatedAt == second.updatedAt {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.updatedAt > second.updatedAt
            }
        case .name:
            return appModel.activeResearchProjects.sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appModel.toggleProjectTreeExpansion()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 14, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse project tree" : "Expand project tree")

                Text("Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Menu {
                    ForEach(SidebarProjectSortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            Label(mode.title, systemImage: sortMode == mode ? "checkmark" : mode.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: sortMode.systemImage)
                        .font(.caption)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Sort projects by \(sortMode.title.lowercased())")

                Text("\(appModel.activeResearchProjects.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 8)
            .padding(.top, 2)

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    if sortedProjects.isEmpty {
                        Text("No projects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 22)
                    } else {
                        ForEach(sortedProjects) { project in
                            SidebarProjectTreeRow(project: project)
                        }
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 4)
    }
}

private struct SidebarProjectBucket: View {
    let title: String
    let projects: [ResearchProject]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.leading, 6)

            ForEach(projects) { project in
                SidebarProjectTreeRow(project: project)
            }
        }
    }
}

private struct SidebarProjectTreeRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let project: ResearchProject
    @State private var isHovering = false

    private var isSelected: Bool {
        appModel.selectedProjectSpaceProject?.id == project.id
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                .frame(width: 15)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(project.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                appModel.toggleResearchProjectPin(project)
            } label: {
                Label(appModel.isResearchProjectPinned(project.id) ? "Unpin" : "Pin", systemImage: appModel.isResearchProjectPinned(project.id) ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .opacity(isHovering || appModel.isResearchProjectPinned(project.id) ? 1 : 0)
            .help(appModel.isResearchProjectPinned(project.id) ? "Unpin project" : "Pin project")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            appModel.focusResearchProject(project.id)
        }
        .onTapGesture(count: 2) {
            appModel.selectResearchProject(project.id)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Project") { appModel.selectResearchProject(project.id) }
            Button(appModel.isResearchProjectPinned(project.id) ? "Unpin" : "Pin") { appModel.toggleResearchProjectPin(project) }
            Button(project.isCollapsed ? "Expand Sections" : "Collapse Sections") { appModel.toggleResearchProjectCollapse(project.id) }
            Divider()
            Button("Archive", role: .destructive) { appModel.confirmDeleteResearchProject(project) }
            Button("Delete...", role: .destructive) { appModel.confirmDeleteResearchProject(project) }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

private struct TopSidebarRow: View {
    let item: TopSidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if item.isPinFixed {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(item.title)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}