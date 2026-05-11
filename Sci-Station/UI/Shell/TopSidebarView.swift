import SwiftUI

struct TopSidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    var body: some View {
        VStack(spacing: 12) {
            header

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(primarySidebarItems) { item in
                        TopSidebarRow(
                            item: item,
                            isSelected: isSelected(item),
                            showsProjectTreeToggle: item.top == .projects && workspace != nil,
                            showsProjectCreateButton: item.top == .projects && workspace != nil
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
                SidebarSettingsButton(isSelected: appModel.selectedSection == .settings)
                    .padding(.horizontal, 10)
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
        .background {
            Color(nsColor: .windowBackgroundColor)
            Color.secondary.opacity(0.055)
        }
        .task {
            appModel.recordSidebarRender()
        }
        .onChange(of: appModel.workspacePreferences.pinnedTopLevelOrder) { _, _ in
            appModel.recordSidebarRender()
        }
        .confirmationDialog(
            projectLifecycleConfirmationTitle,
            isPresented: $appModel.isShowingProjectDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(projectLifecycleConfirmationAction, role: .destructive) {
                appModel.confirmDeletePendingResearchProject()
            }
            Button(appModel.t(.appCancel), role: .cancel) {
                appModel.cancelDeleteResearchProject()
            }
        } message: {
            Text(projectDeleteConfirmationMessage)
        }
    }

    private var projectLifecycleConfirmationTitle: String {
        switch appModel.projectPendingLifecycleAction {
        case .archive:
            return appModel.t(.projectArchiveQuestion)
        case .deleteToTrash:
            return appModel.t(.projectTrashQuestion)
        }
    }

    private var projectLifecycleConfirmationAction: String {
        switch appModel.projectPendingLifecycleAction {
        case .archive:
            return appModel.t(.projectArchiveAction)
        case .deleteToTrash:
            return appModel.t(.projectTrashAction)
        }
    }

    private var projectDeleteConfirmationMessage: String {
        guard let project = appModel.projectPendingDeletion else {
            return appModel.t(.projectArchiveDefaultMessage)
        }
        switch appModel.projectPendingLifecycleAction {
        case .archive:
            return appModel.tf(.projectArchiveMessageFormat, project.name, project.relativePath)
        case .deleteToTrash:
            return appModel.tf(.projectTrashMessageFormat, project.name, project.relativePath)
        }
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
                Text(appModel.t(.sidebarResearchShell))
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

    private var primarySidebarItems: [TopSidebarItem] {
        appModel.topSidebarItems.filter { $0.top != .settings }
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

private struct SidebarProjectTreeSection: View {
    @EnvironmentObject private var appModel: AppViewModel

    private var isExpanded: Bool {
        if appModel.responsiveShellModel.shouldCollapseProjectTree {
            return false
        }
        return appModel.workspacePreferences.isProjectTreeExpanded
    }

    private var sortedProjects: [ResearchProject] {
        appModel.sidebarProjects(searchText: "", includeArchived: appModel.isShowingArchivedProjects)
            .sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
    }

    private var activeProjects: [ResearchProject] {
        sortedProjects.filter { !$0.isArchived }
    }

    private var archivedProjects: [ResearchProject] {
        sortedProjects.filter(\.isArchived)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    if sortedProjects.isEmpty {
                        Text(appModel.t(.sidebarNoProjects))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 34)
                    } else {
                        ForEach(activeProjects) { project in
                            SidebarProjectTreeRow(project: project)
                        }

                        if appModel.isShowingArchivedProjects, !archivedProjects.isEmpty {
                            SidebarProjectBucket(title: appModel.t(.sidebarArchivedSection), projects: archivedProjects)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.leading, 30)
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
            if !project.isArchived {
                Button(appModel.t(.sidebarOpenProject)) { appModel.selectResearchProject(project.id) }
            }
            Button(project.isCollapsed ? appModel.t(.sidebarExpandSections) : appModel.t(.sidebarCollapseSections)) { appModel.toggleResearchProjectCollapse(project.id) }
            Divider()
            if project.isArchived {
                Button(appModel.t(.projectsRestore)) { appModel.restoreResearchProject(project) }
                Button(appModel.t(.projectTrashAction), role: .destructive) { appModel.confirmTrashResearchProject(project) }
            } else {
                Button(appModel.t(.projectArchiveAction), role: .destructive) { appModel.confirmArchiveResearchProject(project) }
                Button(appModel.t(.projectTrashAction), role: .destructive) { appModel.confirmTrashResearchProject(project) }
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

private struct TopSidebarRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let item: TopSidebarItem
    let isSelected: Bool
    var showsProjectTreeToggle = false
    var showsProjectCreateButton = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if showsProjectTreeToggle {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appModel.toggleProjectTreeExpansion()
                    }
                } label: {
                    Image(systemName: isProjectTreeExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 15, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isProjectTreeExpanded ? appModel.t(.sidebarCollapseProjectTree) : appModel.t(.sidebarExpandProjectTree))
            }

            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: item.systemImage)
                        .frame(width: 18)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(appModel.t(L10n.key(for: item.top)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if showsProjectCreateButton {
                Button {
                    appModel.beginCreatingResearchProject()
                } label: {
                    Label(appModel.t(.toolbarNewProject), systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(appModel.t(.sidebarCreateResearchProject))
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .help(appModel.t(L10n.key(for: item.top)))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var isProjectTreeExpanded: Bool {
        if appModel.responsiveShellModel.shouldCollapseProjectTree {
            return false
        }
        return appModel.workspacePreferences.isProjectTreeExpanded
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

private struct SidebarSettingsButton: View {
    @EnvironmentObject private var appModel: AppViewModel

    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            appModel.selectTopLevelRoute(.settings)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(appModel.t(.routeSettings))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(appModel.t(.routeSettings))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}