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
        VStack(spacing: 0) {
            header
            Divider()
            ProjectSpaceTabStrip(
                tabs: tabs,
                selectedTabID: appModel.selectedProjectSpaceTabID,
                select: appModel.selectProjectSpaceTab,
                move: appModel.moveProjectSpaceTab
            )
            Divider()

            if let selectedTab {
                ProjectSpaceContentRouter(
                    workspace: workspace,
                    project: project,
                    tab: selectedTab
                )
            } else {
                ProjectSpaceUnavailableView(
                    title: "ProjectSpace temporarily unavailable",
                    message: "No available project tabs were resolved for this project.",
                    retry: { appModel.selectProjectSpaceTab(ProjectSpaceTabsBuilder.overviewTabID) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Label("Projects", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Back to projects")

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
        .background(Color(nsColor: .windowBackgroundColor))
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
                        Text("Projects")
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text("Choose a project to enter its ProjectSpace tabs.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appModel.activeResearchProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No projects have been registered yet.")
                            .foregroundStyle(.secondary)
                        Button {
                            appModel.beginCreatingResearchProject()
                        } label: {
                            Label("New Project", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectListCard: View {
    let project: ResearchProject
    let isSelected: Bool
    let paperCount: Int
    let openTodoCount: Int
    let focus: () -> Void
    let open: () -> Void
    let edit: () -> Void

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
                ProjectListMetric(label: "Papers", value: "\(paperCount)")
                ProjectListMetric(label: "Open", value: "\(openTodoCount)")
                ProjectListMetric(label: "Updated", value: project.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(Color(hex: project.colorHex).opacity(isSelected ? 0.34 : 0.16), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.secondary.opacity(0.16), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .onTapGesture(count: 2, perform: open)
        .contextMenu {
            Button("Open Project", action: open)
            Button("Edit Project Info", action: edit)
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
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .menuStyle(.borderlessButton)
                .help("More project tabs")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
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
}

private struct ProjectSpaceTabButton: View {
    let tab: ProjectSpaceTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.systemImage)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .help(tab.title)
    }
}