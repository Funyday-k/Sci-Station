import SwiftUI

private enum SidebarMotion {
    static let selection = Animation.easeOut(duration: 0.14)
    static let expansion = Animation.easeInOut(duration: 0.18)
}

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel
    let workspace: ResearchWorkspace?
    @State private var isAllPapersExpanded = true
    @State private var isAILabExpanded = true

    var body: some View {
        TopSidebarView(workspace: workspace)
    }

    private func isSelected(_ section: WorkspaceSection) -> Bool {
        if section == .library {
            return appModel.selectedSection == .library && appModel.selectedLibraryProjectID == nil && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil
        }

        return appModel.selectedSection == section
    }

    private var rootCollections: [PaperCollection] {
        appModel.collections.filter { $0.parentPath == nil }
    }
}

private struct SidebarAILabGroup: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var isExpanded: Bool

    private var visibleThreads: [AgentThread] {
        isExpanded ? appModel.agentThreads : appModel.agentThreads.filter { appModel.isAgentThreadPinned($0.id) }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(SidebarMotion.expansion) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 14, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse AI Lab" : "Expand AI Lab")

                HStack(spacing: 8) {
                    Image(systemName: WorkspaceSection.llmLab.systemImage)
                        .frame(width: 16)
                        .foregroundStyle(appModel.selectedSection == .llmLab ? Color.accentColor : Color.secondary)
                    Text("AI Lab")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("\(appModel.agentThreads.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        withAnimation(SidebarMotion.selection) {
                            appModel.startNewAgentConversation()
                            appModel.selectSection(.llmLab)
                            isExpanded = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New Chat")
                    Button {
                        withAnimation(SidebarMotion.selection) {
                            appModel.selectSection(.llmLab)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open AI Lab")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(appModel.selectedSection == .llmLab ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(SidebarMotion.selection) {
                        appModel.selectSection(.llmLab)
                        if !isExpanded {
                            isExpanded = true
                        }
                    }
                }
                .help("Open the global AI Lab")
                .contextMenu {
                    Button("New Chat") {
                        appModel.startNewAgentConversation()
                        appModel.selectSection(.llmLab)
                    }
                }
            }

            if isExpanded || !visibleThreads.isEmpty {
                VStack(spacing: 2) {
                    if let pendingThread = appModel.pendingAgentThread {
                        AgentSidebarThreadRow(
                            thread: pendingThread,
                            subtitle: "Draft",
                            isActive: appModel.activeAgentThreadID == pendingThread.id,
                            isPinned: false,
                            openAction: {
                                appModel.selectSection(.llmLab)
                            },
                            pinAction: {},
                            archiveAction: {
                                appModel.discardPendingAgentThread()
                            }
                        )
                        .contextMenu {
                            Button("Discard Draft", role: .destructive) {
                                appModel.discardPendingAgentThread()
                            }
                        }
                    }

                    ForEach(visibleThreads) { thread in
                        AgentSidebarThreadRow(
                            thread: thread,
                            subtitle: appModel.agentThreadSubtitle(for: thread),
                            isActive: appModel.activeAgentThreadID == thread.id,
                            isPinned: appModel.isAgentThreadPinned(thread.id),
                            openAction: {
                                appModel.selectAgentThread(thread)
                                appModel.selectSection(.llmLab)
                            },
                            pinAction: {
                                appModel.toggleAgentThreadPin(thread)
                            },
                            archiveAction: {
                                appModel.confirmArchiveAgentThread(thread)
                            }
                        )
                        .contextMenu {
                            Button("Open") {
                                appModel.selectAgentThread(thread)
                                appModel.selectSection(.llmLab)
                            }
                            Button("Rename") {
                                appModel.beginRenameAgentThread(thread)
                            }
                            Button("Duplicate Prompt") {
                                appModel.duplicateAgentThreadPromptToNewChat(thread)
                                appModel.selectSection(.llmLab)
                            }
                            Button("Archive", role: .destructive) {
                                appModel.confirmArchiveAgentThread(thread)
                            }
                        }
                    }

                    if appModel.agentThreads.isEmpty, appModel.pendingAgentThread == nil {
                        Text("暂无对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 36)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(SidebarMotion.expansion, value: isExpanded)
        .animation(SidebarMotion.selection, value: appModel.activeAgentThreadID)
        .animation(SidebarMotion.selection, value: appModel.pendingAgentThread?.id)
        .confirmationDialog(
            "归档这个对话？",
            isPresented: $appModel.isShowingAgentThreadArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("归档", role: .destructive) {
                appModel.archiveConfirmedAgentThread()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(appModel.agentThreadPendingArchive?.title ?? "归档后会从当前对话列表中隐藏。")
        }
    }
}

private struct AgentSidebarThreadRow: View {
    let thread: AgentThread
    var subtitle: String? = nil
    let isActive: Bool
    let isPinned: Bool
    let openAction: () -> Void
    let pinAction: () -> Void
    let archiveAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: pinAction) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.caption)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .opacity(isHovering || isPinned ? 1 : 0)
            .help(isPinned ? "Unpin chat" : "Pin chat")

            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle ?? "\(thread.runIDs.count) runs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: archiveAction) {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Archive chat")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isActive ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: openAction)
        .onHover { isHovering = $0 }
        .animation(SidebarMotion.selection, value: isHovering)
        .animation(SidebarMotion.selection, value: isActive)
        .animation(SidebarMotion.selection, value: isPinned)
    }
}

private struct SidebarCollectionTree: View {
    @EnvironmentObject private var appModel: AppViewModel

    let collection: PaperCollection
    let allCollections: [PaperCollection]
    let level: Int

    private var children: [PaperCollection] {
        allCollections.filter { $0.parentPath == collection.relativePath }
    }

    private var isCollapsed: Bool {
        appModel.collapsedCollectionPaths.contains(collection.relativePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if children.isEmpty {
                    Color.clear
                        .frame(width: 14, height: 20)
                } else {
                    Button {
                        withAnimation(SidebarMotion.expansion) {
                            appModel.toggleCollectionCollapse(collection.relativePath)
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption)
                            .frame(width: 14, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isCollapsed ? "Expand folder" : "Collapse folder")
                    .accessibilityLabel(isCollapsed ? "Expand folder" : "Collapse folder")
                }

                Button {
                    if children.isEmpty {
                        withAnimation(SidebarMotion.selection) {
                            appModel.selectCollection(collection.relativePath)
                        }
                    } else {
                        withAnimation(SidebarMotion.expansion) {
                            appModel.toggleCollectionCollapse(collection.relativePath)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(collection.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text("\(collection.paperCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(appModel.selectedCollectionPath == collection.relativePath ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open Folder") {
                        appModel.selectCollection(collection.relativePath)
                    }
                    Button("Create Subfolder") {
                        appModel.createSubfolder(in: collection.relativePath)
                    }
                }
            }
            .padding(.leading, CGFloat(level * 14))

            if !isCollapsed {
                ForEach(children) { child in
                    SidebarCollectionTree(collection: child, allCollections: allCollections, level: level + 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(SidebarMotion.expansion, value: isCollapsed)
    }
}

private struct SidebarProjectGroup: View {
    @EnvironmentObject private var appModel: AppViewModel

    let project: ResearchProject

    var isCurrentProject: Bool {
        appModel.currentResearchProject?.id == project.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(SidebarMotion.expansion) {
                        appModel.toggleResearchProjectCollapse(project.id)
                    }
                } label: {
                    Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .frame(width: 14, height: 20)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(project.isCollapsed ? "Expand project" : "Collapse project")
                .accessibilityLabel(project.isCollapsed ? "Expand project" : "Collapse project")

                HStack(spacing: 8) {
                    Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                        .frame(width: 16)
                        .foregroundStyle(isCurrentProject ? Color.accentColor : Color.secondary)
                    Text(project.name)
                        .fontWeight(isCurrentProject ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(projectBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrentProject ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(SidebarMotion.expansion) {
                        appModel.toggleResearchProjectCollapse(project.id)
                    }
                }
                .onTapGesture(count: 2) {
                    withAnimation(SidebarMotion.selection) {
                        appModel.selectResearchProject(project.id, section: .projects)
                    }
                }
            }
            .contextMenu {
                Button("Open Project") {
                    withAnimation(SidebarMotion.selection) {
                        appModel.selectResearchProject(project.id, section: .projects)
                    }
                }
                Button(project.isCollapsed ? "Expand" : "Collapse") {
                    withAnimation(SidebarMotion.expansion) {
                        appModel.toggleResearchProjectCollapse(project.id)
                    }
                }
                Divider()
                Button("Edit Project Info") {
                    appModel.beginEditingResearchProject(project.id)
                }
            }

            if !project.isCollapsed {
                VStack(spacing: 1) {
                    ForEach(appModel.visibleProjectSidebarSections(for: project.id)) { section in
                        SidebarActionRow(
                            title: section == .projects ? "Overview" : section.title,
                            systemImage: section.systemImage,
                            isSelected: isSelected(section),
                            badgeText: badgeText(for: section)
                        ) {
                            appModel.selectResearchProject(project.id, section: section)
                        }
                        .padding(.leading, 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(SidebarMotion.expansion, value: project.isCollapsed)
    }

    private var projectBackground: Color {
        if isCurrentProject {
            return Color(hex: project.colorHex).opacity(0.35)
        }

        return Color(hex: project.colorHex).opacity(0.14)
    }

    private func isSelected(_ section: WorkspaceSection) -> Bool {
        guard isCurrentProject else {
            return false
        }

        if section == .library {
            return appModel.selectedSection == .library && appModel.selectedLibraryProjectID == project.id && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil
        }

        return appModel.selectedSection == section
    }

    private func badgeText(for section: WorkspaceSection) -> String? {
        switch section {
        case .library:
            return "\(appModel.papers(for: project.id).count)"
        case .tasks:
            let projectTodos = appModel.todos.filter { todo in
                todo.projectIDs.contains(project.id) || (todo.projectIDs.isEmpty && (isCurrentProject || appModel.activeResearchProjects.count == 1))
            }
            return "\(projectTodos.filter { $0.status != .done && $0.status != .cancelled }.count)"
        default:
            return nil
        }
    }
}

private struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

private struct SidebarIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(SidebarMotion.selection) {
                action()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 30)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(SidebarMotion.selection, value: isSelected)
        .animation(SidebarMotion.selection, value: isHovering)
            .accessibilityLabel(accessibilityLabel)
    }

    private var iconBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

private struct SidebarTagRow: View {
    let tag: TagDefinition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(SidebarMotion.selection) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                TagChipView(tag: tag)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(SidebarMotion.selection, value: isSelected)
        .animation(SidebarMotion.selection, value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

struct WorkspaceContentView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?
    let selectedSection: WorkspaceSection?
    let isWorking: Bool
    let createWorkspace: () -> Void
    let openWorkspace: () -> Void

    var body: some View {
        Group {
            if let workspace {
                if selectedSection == .dashboard {
                    DashboardView(workspace: workspace)
                } else if selectedSection == .library {
                    LibraryListView(workspace: workspace)
                } else if selectedSection == .settings {
                    SettingsView(workspace: workspace)
                } else if selectedSection == .wiki {
                    WikiWorkspaceView(workspace: workspace)
                } else if selectedSection == .projects {
                    if let project = appModel.selectedProjectSpaceProject {
                        ProjectSpaceContainer(workspace: workspace, project: project)
                    } else {
                        ProjectsListView(workspace: workspace)
                    }
                } else if selectedSection == .materials {
                    MaterialsView(workspace: workspace)
                } else if selectedSection == .tasks {
                    TasksWorkspaceView(workspace: workspace)
                } else if selectedSection == .calendar {
                    WorkspaceCalendarView(workspace: workspace)
                } else if selectedSection == .llmLab {
                    AILabWorkspaceView(workspace: workspace)
                } else {
                    WorkspaceSectionOverview(
                        workspace: workspace,
                        section: selectedSection ?? .library,
                        isWorking: isWorking
                    )
                }
            } else {
                EmptyWorkspaceView(
                    isWorking: isWorking,
                    createWorkspace: createWorkspace,
                    openWorkspace: openWorkspace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .bottom) {
            if let message = appModel.shellStatusMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

private struct WorkspaceCalendarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Workspace-wide schedule for \(workspace.displayName).")
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        DashboardCalendarView(selectedDate: Binding(
                            get: { appModel.selectedDashboardDate },
                            set: { appModel.selectDashboardDate($0) }
                        ))
                        .frame(minWidth: 420)

                        CalendarSelectedDateDetailView(projectID: nil)
                            .frame(minWidth: 340)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        DashboardCalendarView(selectedDate: Binding(
                            get: { appModel.selectedDashboardDate },
                            set: { appModel.selectDashboardDate($0) }
                        ))

                        CalendarSelectedDateDetailView(projectID: nil)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CalendarSelectedDateDetailView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let projectID: ResearchProject.ID?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDateTitle)
                            .font(.title3.weight(.semibold))
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        if let projectID {
                            appModel.selectResearchProject(projectID, section: .tasks)
                        } else {
                            appModel.selectGlobalTodos()
                        }
                    } label: {
                        Label("Open Tasks", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if todos.isEmpty, workspaceEvents.isEmpty, systemItems.isEmpty {
                    Label("No items for this date.", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    detailSection(title: "Todos", systemImage: "checklist", count: todos.count) {
                        ForEach(todos.prefix(6)) { todo in
                            CalendarTodoDetailRow(todo: todo)
                        }
                    }

                    detailSection(title: "Project Events", systemImage: "flag", count: workspaceEvents.count) {
                        ForEach(workspaceEvents.prefix(6)) { event in
                            CalendarEventDetailRow(event: event)
                        }
                    }

                    detailSection(title: "System Schedule", systemImage: "calendar.badge.clock", count: systemItems.count) {
                        ForEach(systemItems.prefix(6)) { item in
                            CalendarSystemScheduleRow(item: item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Selected Date", systemImage: "calendar")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(title: String, systemImage: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(title) · \(count)", systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
            }
        }
    }

    private var todos: [TodoItem] {
        appModel.selectedDateTodos.filter { todo in
            guard let projectID else {
                return true
            }
            return todo.projectIDs.contains(projectID)
        }
    }

    private var workspaceEvents: [CalendarEvent] {
        appModel.selectedDateWorkspaceEvents.filter { event in
            guard let projectID else {
                return true
            }
            return event.projectID == projectID
        }
    }

    private var systemItems: [SystemScheduleItem] {
        guard projectID == nil else {
            return []
        }
        return appModel.selectedDateSystemScheduleItems
    }

    private var selectedDateTitle: String {
        appModel.selectedDashboardDate.formatted(date: .complete, time: .omitted)
    }

    private var summaryText: String {
        let count = todos.count + workspaceEvents.count + systemItems.count
        return count == 1 ? "1 scheduled item" : "\(count) scheduled items"
    }
}

private struct CalendarTodoDetailRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let todo: TodoItem

    var body: some View {
        Button {
            appModel.toggleTodo(todo)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.status == .done ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text([todo.priority.label, projectText].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: SciStationDesign.rowCornerRadius, style: .continuous))
    }

    private var projectText: String {
        todo.projectIDs.map(appModel.projectName(for:)).joined(separator: ", ")
    }
}

private struct CalendarEventDetailRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: event.colorHex ?? "#5E6AD2"))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text([event.category, event.projectID.map(appModel.projectName(for:))].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: SciStationDesign.rowCornerRadius, style: .continuous))
    }
}

private struct CalendarSystemScheduleRow: View {
    let item: SystemScheduleItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.isCompleted ? Color.secondary : Color.accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(item.categoryName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: SciStationDesign.rowCornerRadius, style: .continuous))
    }
}

private struct SidebarActionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badgeText: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(SidebarMotion.selection) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let badgeText {
                    Text(badgeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(SidebarMotion.selection, value: isSelected)
        .animation(SidebarMotion.selection, value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}

struct WorkspaceSectionOverview: View {
    let workspace: ResearchWorkspace
    let section: WorkspaceSection
    let isWorking: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text(section.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if isWorking {
                    ProgressView("Preparing workspace…")
                }

                GroupBox("Workspace Snapshot") {
                    VStack(alignment: .leading, spacing: 12) {
                        WorkspacePathRow(label: "Root", value: workspace.rootURL.path)
                        WorkspacePathRow(label: "Shared Context", value: workspace.sharedResearchURL.path)
                        WorkspacePathRow(label: "Bibliography", value: workspace.libraryBibURL.path)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Core Directories") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workspace.quickAccessLocations, id: \.name) { location in
                            WorkspacePathRow(label: location.name, value: location.url.path)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Trial Notes") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sci-Station keeps papers, Markdown pages, tasks, settings, and agent logs inside the selected research root.")
                        Text("API keys are stored in macOS Keychain. Share a research root only after checking that it contains no private papers, unpublished data, or local credentials.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WorkspaceInspectorView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?
    let selectedSection: WorkspaceSection?
    let revealInFinder: () -> Void

    var body: some View {
        Group {
            if let workspace {
                if selectedSection == .library {
                    PaperInspectorView(workspace: workspace)
                } else if selectedSection == .wiki {
                    WikiInspectorView(workspace: workspace)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Inspector")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text(selectedSection?.title ?? "Workspace")
                                    .foregroundStyle(.secondary)
                            }

                            GroupBox("Actions") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button {
                                        revealInFinder()
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Workspace Summary") {
                                VStack(alignment: .leading, spacing: 8) {
                                    WorkspacePathRow(label: "Papers", value: "\(appModel.papers.count)")
                                    WorkspacePathRow(label: "Collections", value: "\(appModel.collections.count)")
                                    WorkspacePathRow(label: "Tags", value: "\(appModel.availableTagDefinitions.count)")
                                    WorkspacePathRow(label: "Open Todos", value: "\(appModel.todos.filter { $0.status != .done }.count)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Workspace") {
                                WorkspacePathRow(label: "Name", value: workspace.displayName)
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create or open a ResearchWorkspace to see paths, actions, and validation details here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
        }
    }
}

private struct EmptyWorkspaceView: View {
    let isWorking: Bool
    let createWorkspace: () -> Void
    let openWorkspace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sci-Station")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text("Local-first research workstation for PDFs, Markdown knowledge pages, and LLM-assisted synthesis.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Create Workspace", action: createWorkspace)
                    .buttonStyle(.borderedProminent)
                Button("Open Existing Workspace", action: openWorkspace)
                    .buttonStyle(.bordered)
            }

            if isWorking {
                ProgressView("Preparing workspace…")
            }

            GroupBox("Quick Start") {
                VStack(alignment: .leading, spacing: 12) {
                    TrialStepRow(
                        index: "1",
                        title: "Create a Research Root",
                        detail: "Choose an empty local folder outside this source repo. Sci-Station creates the library, projects, wiki, tasks, settings, and agent state there."
                    )
                    TrialStepRow(
                        index: "2",
                        title: "Import Papers",
                        detail: "Use Import PDF, drag in a PDF, or paste DOI/arXiv/PDF links with Add by Identifier."
                    )
                    TrialStepRow(
                        index: "3",
                        title: "Work In Projects",
                        detail: "Create a project, edit its Project Brief, collect core papers, and keep data, code, figures, and outputs under Materials."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("All workspace files stay in the selected Research Root.", systemImage: "folder")
                    Label("LLM and MinerU tokens are optional and saved to macOS Keychain.", systemImage: "key")
                    Label("Before sharing a Research Root, check papers, notes, data, and agent logs for private content.", systemImage: "checkmark.shield")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TrialStepRow: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WorkspacePathRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}