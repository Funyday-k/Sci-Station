import SwiftUI

struct ProjectSpaceContainer: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    private var tabs: [ProjectSpaceTab] {
        appModel.projectSpaceTabs(for: project.id)
    }

    private var selectedTab: ProjectSpaceTab? {
        tabs.first { $0.id == appModel.selectedProjectSpaceTabID } ?? tabs.first
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            ProjectSpaceTabStrip(
                tabs: tabs,
                selectedTabID: appModel.selectedProjectSpaceTabID,
                select: appModel.selectProjectSpaceTab,
                move: appModel.moveProjectSpaceTab
            )

            if let selectedTab {
                ProjectSpaceContentRouter(
                    workspace: workspace,
                    project: project,
                    tab: selectedTab
                )
            } else {
                ProjectSpaceUnavailableView(
                    title: appModel.t(.projectSpaceUnavailableTitle),
                    message: appModel.t(.projectSpaceUnavailableMessage),
                    retry: { appModel.selectProjectSpaceTab(ProjectSpaceTabsBuilder.overviewTabID) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(ProjectSpaceBackground())
        .onAppear {
            if !tabs.contains(where: { $0.id == appModel.selectedProjectSpaceTabID }) {
                appModel.selectProjectSpaceTab(ProjectSpaceTabsBuilder.overviewTabID)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                appModel.selectTopLevelRoute(.projects)
            } label: {
                Label(appModel.t(.routeProjects), systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(appModel.t(.projectSpaceBackToProjects))

            Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                .font(.title3)
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.primary.opacity(0.75))
                .background(Color(hex: project.colorHex).opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(project.description.isEmpty ? project.relativePath : project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            StageBadge(stage: stageDecision.stage, rule: stageDecision.rule)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.045)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.7)
        }
    }

    private var stageDecision: ProjectStageDecision {
        ProjectStageProvider().stage(for: ProjectStageSignal(
            projectID: project.id,
            papersCount: appModel.papers(for: project.id).count,
            wikiPageCount: appModel.markdownDocuments.filter { $0.relativePath.hasPrefix(project.relativePath + "/wiki/") }.count,
            openGapsCount: appModel.openTodos(for: project.id).count,
            artifactKinds: [],
            unsupportedClaimCount: 0,
            lastActivityAt: project.updatedAt
        ))
    }
}

struct ProjectsListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appModel.t(.routeProjects))
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text(appModel.t(.projectsChooseProject))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        appModel.isShowingArchivedProjects.toggle()
                    } label: {
                        Label(
                            appModel.isShowingArchivedProjects ? appModel.t(.sidebarHideArchived) : appModel.t(.sidebarShowArchived),
                            systemImage: appModel.isShowingArchivedProjects ? "archivebox.fill" : "archivebox"
                        )
                    }
                    .buttonStyle(.glass)
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                        Label(appModel.t(.toolbarNewProject), systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }

                if appModel.activeResearchProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appModel.t(.projectsEmptyTitle))
                            .foregroundStyle(.secondary)
                        Button {
                            appModel.beginCreatingResearchProject()
                        } label: {
                            Label(appModel.t(.toolbarNewProject), systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.04)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.14), lineWidth: 0.7)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(appModel.activeResearchProjects) { project in
                            ProjectListCard(
                                project: project,
                                isSelected: appModel.currentProjectID == project.id,
                                paperCount: appModel.papers(for: project.id).count,
                                openTodoCount: appModel.openTodos(for: project.id).count
                            ) {
                                appModel.focusResearchProject(project.id)
                            } open: {
                                appModel.selectResearchProject(project.id)
                            } edit: {
                                appModel.beginEditingResearchProject(project.id)
                            } restore: {
                                appModel.restoreResearchProject(project)
                            } archive: {
                                appModel.confirmArchiveResearchProject(project)
                            } trash: {
                                appModel.confirmTrashResearchProject(project)
                            }
                        }
                    }
                }

                if appModel.isShowingArchivedProjects, !appModel.archivedResearchProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appModel.t(.projectsArchivedTitle))
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(appModel.archivedResearchProjects) { project in
                                ProjectListCard(
                                    project: project,
                                    isSelected: false,
                                    paperCount: appModel.papers(for: project.id).count,
                                    openTodoCount: appModel.openTodos(for: project.id).count
                                ) {
                                    appModel.focusResearchProject(project.id)
                                } open: {
                                    appModel.selectResearchProject(project.id)
                                } edit: {
                                    appModel.beginEditingResearchProject(project.id)
                                } restore: {
                                    appModel.restoreResearchProject(project)
                                } archive: {
                                    appModel.confirmArchiveResearchProject(project)
                                } trash: {
                                    appModel.confirmTrashResearchProject(project)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProjectSpaceBackground())
    }
}

private struct ProjectListCard: View {
    @EnvironmentObject private var appModel: AppViewModel

    let project: ResearchProject
    let isSelected: Bool
    let paperCount: Int
    let openTodoCount: Int
    let focus: () -> Void
    let open: () -> Void
    let edit: () -> Void
    let restore: () -> Void
    let archive: () -> Void
    let trash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                    .font(.title3)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(project.description.isEmpty ? project.relativePath : project.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                ProjectListMetric(label: appModel.t(.projectsPapersMetric), value: "\(paperCount)")
                ProjectListMetric(label: appModel.t(.projectsOpenMetric), value: "\(openTodoCount)")
                ProjectListMetric(label: appModel.t(.projectsUpdatedMetric), value: project.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .glassEffect(.regular.tint(Color(hex: project.colorHex).opacity(isSelected ? 0.12 : 0.055)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.secondary.opacity(0.16), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .onTapGesture(count: 2, perform: open)
        .contextMenu {
            if project.isArchived {
                Button(appModel.t(.projectsRestore), action: restore)
                Button(appModel.t(.projectTrashAction), role: .destructive, action: trash)
            } else {
                Button(appModel.t(.sidebarOpenProject), action: open)
                Button(appModel.t(.projectsEditInfo), action: edit)
                Divider()
                Button(appModel.t(.projectArchiveAction), role: .destructive, action: archive)
                Button(appModel.t(.projectTrashAction), role: .destructive, action: trash)
            }
        }
    }
}

private struct ProjectListMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectSpaceTabStrip: View {
    @EnvironmentObject private var appModel: AppViewModel

    let tabs: [ProjectSpaceTab]
    let selectedTabID: String
    let select: (String) -> Void
    let move: (String, String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                ProjectSpaceTabButton(tab: tab, isSelected: tab.id == selectedTabID) {
                    select(tab.id)
                }
                .draggable(tab.id)
                .dropDestination(for: String.self) { droppedIDs, _ in
                    guard let droppedID = droppedIDs.first else { return false }
                    move(droppedID, tab.id)
                    return true
                }
            }
            if !overflowTabs.isEmpty {
                Menu {
                    ForEach(overflowTabs) { tab in
                        Button {
                            select(tab.id)
                        } label: {
                            Label(localizedTitle(for: tab), systemImage: tab.systemImage)
                        }
                    }
                } label: {
                    Label(appModel.t(.projectSpaceMoreTabs), systemImage: "ellipsis.circle")
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .menuStyle(.borderlessButton)
                .help(appModel.t(.projectSpaceMoreTabs))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.035)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
        }
    }

    private var visibleTabs: [ProjectSpaceTab] {
        guard tabs.count > 8 else {
            return tabs
        }
        let selectedOverflowTab = tabs.dropFirst(7).first { $0.id == selectedTabID }
        if let selectedOverflowTab {
            return Array(tabs.prefix(7)) + [selectedOverflowTab]
        }
        return Array(tabs.prefix(8))
    }

    private var overflowTabs: [ProjectSpaceTab] {
        guard tabs.count > 8 else {
            return []
        }
        let visibleIDs = Set(visibleTabs.map(\.id))
        return tabs.filter { !visibleIDs.contains($0.id) }
    }

    private func localizedTitle(for tab: ProjectSpaceTab) -> String {
        guard let key = L10n.key(for: tab.id) else {
            return tab.title
        }
        return appModel.t(key)
    }
}

private struct ProjectSpaceBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.secondary.opacity(0.05)
        }
        .ignoresSafeArea()
    }
}

private struct ProjectSpaceTabButton: View {
    @EnvironmentObject private var appModel: AppViewModel

    let tab: ProjectSpaceTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(localizedTitle, systemImage: tab.systemImage)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .help(localizedTitle)
    }

    private var localizedTitle: String {
        guard let key = L10n.key(for: tab.id) else {
            return tab.title
        }
        return appModel.t(key)
    }
}