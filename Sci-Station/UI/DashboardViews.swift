import SwiftUI

struct DashboardView: View {
    let workspace: ResearchWorkspace

    var body: some View {
        HomeView(workspace: workspace)
    }
}

private struct ResearchProjectsWidget: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projects")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Research projects under \(appModel.currentResearchRoot?.displayName ?? workspace.displayName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    appModel.beginCreatingResearchProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(appModel.activeResearchProjects) { project in
                        ResearchProjectCard(
                            project: project,
                            isSelected: appModel.currentResearchProject?.id == project.id,
                            paperCount: paperCount(for: project),
                            openTodoCount: openTodoCount(for: project),
                            editAction: {
                                appModel.beginEditingResearchProject(project.id)
                            }
                        ) {
                            appModel.focusResearchProject(project.id)
                        } openAction: {
                            appModel.selectResearchProject(project.id)
                        }
                    }
                }
            }
        }
    }

    private func paperCount(for project: ResearchProject) -> String {
        "\(appModel.papers(for: project.id).count)"
    }

    private func openTodoCount(for project: ResearchProject) -> String {
        let scopedTodos = appModel.todos.filter { todo in
            todo.projectIDs.contains(project.id) || (todo.projectIDs.isEmpty && (isCurrent(project) || appModel.activeResearchProjects.count == 1))
        }
        let openCount = TodoQueries.openCount(scopedTodos)
        return "\(openCount)"
    }

    private func isCurrent(_ project: ResearchProject) -> Bool {
        appModel.currentResearchProject?.id == project.id
    }
}

private struct ResearchProjectCard: View {
    let project: ResearchProject
    let isSelected: Bool
    let paperCount: String
    let openTodoCount: String
    let editAction: () -> Void
    let action: () -> Void
    let openAction: () -> Void

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
                        .truncationMode(.tail)
                    Text(project.description.isEmpty ? project.relativePath : project.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                ProjectCardMetric(label: "Papers", value: paperCount)
                ProjectCardMetric(label: "Open", value: openTodoCount)
                ProjectCardMetric(label: "Updated", value: project.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onTapGesture(count: 2, perform: openAction)
        .contextMenu {
            Button("Open Project") {
                openAction()
            }
            Button("Edit Project Info") {
                editAction()
            }
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return Color(hex: project.colorHex).opacity(0.38)
        }

        return Color(hex: project.colorHex).opacity(0.18)
    }
}

private struct ProjectCardMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceManagementWidget: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Research Root")
                        .font(.headline)
                    Text("Create, open, and inspect the root that contains global library, projects, settings, and agent state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        appModel.createWorkspace()
                    } label: {
                        Label("Create", systemImage: "plus")
                    }

                    Button {
                        appModel.openWorkspace()
                    } label: {
                        Label("Open", systemImage: "folder.badge.plus")
                    }

                    Spacer()
                }
                .labelStyle(.titleAndIcon)

                Divider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 12) {
                    WorkspacePathRow(label: "Name", value: workspace.displayName)
                    WorkspacePathRow(label: "Projects", value: "\(appModel.activeResearchProjects.count)")
                    WorkspacePathRow(label: "Collections", value: "\(appModel.collections.count)")
                    WorkspacePathRow(label: "Tags", value: "\(appModel.availableTagDefinitions.count)")
                }

                if let message = appModel.rootCompatibilityMessage {
                    Label(message, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    appModel.revealCurrentWorkspaceInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.right.square")
                }
                .labelStyle(.titleAndIcon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashboardWorkspaceOverview: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        GroupBox("Workspace") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 12) {
                    WorkspacePathRow(label: "Name", value: workspace.displayName)
                    WorkspacePathRow(label: "Collections", value: "\(appModel.collections.count)")
                    WorkspacePathRow(label: "Tags", value: "\(appModel.availableTagDefinitions.count)")
                }

                let projectPages = appModel.markdownDocuments
                    .filter { $0.relativePath.hasPrefix("wiki/projects/") }
                    .prefix(5)

                if projectPages.isEmpty {
                    Text("No project pages yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Pages")
                            .font(.headline)
                        ForEach(Array(projectPages), id: \.id) { page in
                            Button {
                                appModel.openMarkdownDocument(relativePath: page.relativePath)
                            } label: {
                                Label(page.title, systemImage: "folder")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum TodoDashboardScope {
    case selectedDate
    case global
    case currentProject
}

private enum TodoDisplayMode: String, CaseIterable {
    case list
    case boxes

    var label: String {
        switch self {
        case .list:
            return "List"
        case .boxes:
            return "Boxes"
        }
    }
}

private struct TodoProjectColumn: Identifiable {
    let id: String
    let title: String
    let todos: [TodoItem]
}

struct TasksWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TodoDashboardWidget(scope: appModel.isViewingGlobalTodos ? .global : .currentProject)
            }
            .padding(16)
        }
    }
}

struct TodoDashboardWidget: View {
    @EnvironmentObject private var appModel: AppViewModel

    @State private var isShowingCompleted = false
    @State private var displayMode = TodoDisplayMode.list
    @State private var filter = TaskFilter()
    @State private var isShowingComposer = false
    @State private var editingTodo: TodoItem?
    @State private var isShowingTagManager = false
    @State private var didInitFilter = false

    var scope: TodoDashboardScope = .selectedDate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            todoToolbar

            if !displayedWorkspaceEvents.isEmpty || !displayedSystemItems.isEmpty {
                ScheduleAgendaView(
                    workspaceEvents: displayedWorkspaceEvents,
                    systemItems: displayedSystemItems
                )
            }

            if displayedTodos.isEmpty && displayedWorkspaceEvents.isEmpty && displayedSystemItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isShowingCompleted ? appModel.localized("当前视图没有已完成任务。", "No completed todos in this view.") : appModel.localized("当前视图没有打开中的任务。", "No open todos in this view."))
                        .foregroundStyle(.secondary)
                    Button {
                        isShowingComposer = true
                    } label: {
                        Label(appModel.localized("新建任务", "New Task"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                todoContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .sheet(isPresented: $isShowingComposer) {
            TaskComposerView(scope: composerScope)
                .environmentObject(appModel)
        }
        .sheet(item: $editingTodo) { todo in
            TaskComposerView(scope: composerScope, editingTodo: todo)
                .environmentObject(appModel)
        }
        .sheet(isPresented: $isShowingTagManager) {
            TodoTagManagerView()
                .environmentObject(appModel)
        }
        .onAppear {
            if !didInitFilter {
                didInitFilter = true
                if scope == .global { filter.projectScope = .all }
            }
        }
    }

    private var todoToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            TaskFilterButton(filter: $filter, showsProjectScope: scope != .selectedDate)

            if scope == .global {
                Picker("View", selection: $displayMode) {
                    Image(systemName: "list.bullet").tag(TodoDisplayMode.list)
                    Image(systemName: "square.grid.2x2").tag(TodoDisplayMode.boxes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
            }

            Button {
                isShowingCompleted.toggle()
            } label: {
                Image(systemName: isShowingCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isShowingCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isShowingCompleted ? appModel.localized("查看打开中", "Show open") : appModel.localized("查看已完成", "Show completed"))

            Button {
                isShowingTagManager = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(appModel.localized("管理任务标签", "Manage task tags"))

            Spacer(minLength: 0)

            Button {
                appModel.requestSystemCalendarAccess()
            } label: {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appModel.systemCalendarAccessState == .authorized ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(appModel.systemCalendarAccessState.label)
            .disabled(appModel.systemCalendarAccessState == .authorized)

            Button {
                appModel.refreshSystemSchedule(around: appModel.selectedDashboardDate)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(appModel.localized("刷新日历和提醒事项", "Refresh calendar and reminders"))
            .disabled(!appModel.systemCalendarAccessState.canReadSchedule)

            if appModel.isLoadingSystemSchedule {
                ProgressView().controlSize(.small)
            }

            Button {
                isShowingComposer = true
            } label: {
                Label(appModel.localized("新建任务", "New Task"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var composerScope: TodoComposerScope {
        switch scope {
        case .selectedDate:
            return .selectedDate(appModel.selectedDashboardDate)
        case .currentProject:
            return .currentProject(appModel.currentProjectID)
        case .global:
            return .global
        }
    }

    private var viewingProjectID: String? {
        switch scope {
        case .currentProject:
            return appModel.currentProjectID
        case .global, .selectedDate:
            return nil
        }
    }

    @ViewBuilder
    private var todoContent: some View {
        if scope == .global, appModel.activeResearchProjects.count > 1 {
            LazyVGrid(columns: globalColumns, alignment: .leading, spacing: 12) {
                ForEach(projectColumns) { column in
                    TodoProjectColumnView(title: column.title, todos: column.todos, onEdit: { editingTodo = $0 })
                }
            }
        } else if displayMode == .boxes {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(displayedTodos) { todo in
                    TodoCardView(todo: todo, onEdit: { editingTodo = $0 })
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(displayedTodos) { todo in
                    TodoRowView(todo: todo, onEdit: { editingTodo = $0 })
                    if todo.id != displayedTodos.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var displayedTodos: [TodoItem] {
        let baseTodos: [TodoItem]
        switch scope {
        case .selectedDate:
            baseTodos = appModel.selectedDateTodos
        case .global:
            baseTodos = appModel.todos
        case .currentProject:
            baseTodos = appModel.currentProjectTodos
        }

        let statusFiltered = baseTodos.filter { isShowingCompleted ? TodoQueries.isCompleted($0) : TodoQueries.isOpen($0) }
        return filter.apply(to: statusFiltered, viewingProjectID: viewingProjectID)
            .sorted(by: TodoQueries.listSort)
    }

    private var projectColumns: [TodoProjectColumn] {
        var columns: [TodoProjectColumn] = appModel.activeResearchProjects.compactMap { project in
            let todos = displayedTodos.filter { $0.projectIDs.contains(project.id) || ($0.projectIDs.isEmpty && appModel.activeResearchProjects.count <= 1) }
            guard !todos.isEmpty else {
                return nil
            }
            return TodoProjectColumn(id: project.id, title: project.name, todos: todos)
        }

        let unassignedTodos = displayedTodos.filter(\.projectIDs.isEmpty)
        if !unassignedTodos.isEmpty, appModel.activeResearchProjects.count > 1 {
            columns.append(TodoProjectColumn(id: "unassigned", title: appModel.localized("未分配", "Unassigned"), todos: unassignedTodos))
        }

        return columns
    }

    private var globalColumns: [GridItem] {
        let columnCount = min(max(projectColumns.count, 1), 3)
        return Array(repeating: GridItem(.flexible(minimum: 230), spacing: 12, alignment: .top), count: columnCount)
    }

    private var displayedWorkspaceEvents: [CalendarEvent] {
        scope == .selectedDate ? appModel.selectedDateWorkspaceEvents : []
    }

    private var displayedSystemItems: [SystemScheduleItem] {
        scope == .selectedDate ? appModel.selectedDateSystemScheduleItems : []
    }

}

private struct TodoRowView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let todo: TodoItem

    var onEdit: (TodoItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                appModel.toggleTodo(todo)
            } label: {
                Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(todo.status == .done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(todo.status == .done ? appModel.localized("标记为打开中", "Mark as open") : appModel.localized("标记为已完成", "Mark as done"))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: todo.kind.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(todo.kind == .reading ? Color.blue : Color.secondary)
                    Text(todo.title)
                        .fontWeight(.medium)
                        .strikethrough(todo.status == .done)
                    TodoPriorityFlagsBadge(priority: todo.priority)
                }

                HStack(spacing: 10) {
                    if let dateSummary {
                        Label(dateSummary, systemImage: "calendar").labelStyle(.titleAndIcon)
                    }
                    if !todo.tags.isEmpty {
                        TodoTagChipGroup(tags: todo.tags)
                    }
                    ForEach(projectLabels, id: \.self) { label in
                        Label(label, systemImage: "folder").labelStyle(.titleAndIcon)
                    }
                    if todo.kind == .reading, !todo.relatedPaperIDs.isEmpty {
                        Label("\(todo.relatedPaperIDs.count)", systemImage: "book").labelStyle(.titleAndIcon)
                    }
                    if let notes = todo.notes, !notes.isEmpty {
                        Label(notes, systemImage: "text.alignleft").labelStyle(.titleAndIcon).lineLimit(1)
                    }
                    if todo.externalSource == "apple_reminders" {
                        Image(systemName: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                if todo.externalIdentifier == nil {
                    Button {
                        appModel.publishTodoToAppleReminders(todo)
                    } label: {
                        Image(systemName: "arrow.up.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(appModel.localized("发布到提醒事项", "Publish to Reminders"))
                }

                Button {
                    onEdit(todo)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(appModel.localized("编辑任务", "Edit task"))

                Menu {
                    Button(role: .destructive) {
                        appModel.deleteTodo(todo)
                    } label: {
                        Label(appModel.localized("删除", "Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(appModel.localized("更多操作", "More actions"))
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var dateSummary: String? {
        TodoDateSummary.text(for: todo)
    }

    private var projectLabels: [String] {
        todo.projectIDs.map { appModel.projectName(for: $0) }
    }
}

/// Formats a todo's date or date range for compact display.
enum TodoDateSummary {
    static func text(for todo: TodoItem) -> String? {
        guard let due = todo.dueDate else { return nil }
        if let start = todo.startDate, todo.hasDateRange {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            return "\(formatter.string(from: start)) – \(formatter.string(from: due))"
        }
        return due.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TodoProjectColumnView: View {
    let title: String
    let todos: [TodoItem]
    var onEdit: (TodoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                Text("\(todos.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(todos) { todo in
                    TodoRowView(todo: todo, onEdit: onEdit)
                    if todo.id != todos.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TodoCardView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let todo: TodoItem
    var onEdit: (TodoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appModel.toggleTodo(todo)
                } label: {
                    Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(todo.status == .done ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: todo.kind.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(todo.kind == .reading ? Color.blue : Color.secondary)
                        Text(todo.title)
                            .font(.headline)
                            .lineLimit(2)
                            .strikethrough(todo.status == .done)
                        Spacer(minLength: 0)
                        TodoPriorityFlagsBadge(priority: todo.priority)
                    }
                    if let notes = todo.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }

            if !todo.tags.isEmpty {
                TodoTagChipGroup(tags: todo.tags, limit: 4)
            }

            HStack(spacing: 8) {
                if let dateSummary = TodoDateSummary.text(for: todo) {
                    Label(dateSummary, systemImage: "calendar")
                }
                if todo.kind == .reading, !todo.relatedPaperIDs.isEmpty {
                    Label("\(todo.relatedPaperIDs.count)", systemImage: "book")
                }
                if todo.externalSource == "apple_reminders" {
                    Image(systemName: "bell")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(projectLabels, id: \.self) { label in
                    SciBadge(label)
                }
                Spacer(minLength: 0)
                Button {
                    onEdit(todo)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(appModel.localized("编辑任务", "Edit task"))

                Menu {
                    Button(role: .destructive) {
                        appModel.deleteTodo(todo)
                    } label: {
                        Label(appModel.localized("删除", "Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var projectLabels: [String] {
        guard !todo.projectIDs.isEmpty else {
            return [appModel.localized("未分配", "Unassigned")]
        }

        return todo.projectIDs.map { projectID in
            appModel.projectName(for: projectID)
        }
    }
}

private struct ScheduleAgendaView: View {
    let workspaceEvents: [CalendarEvent]
    let systemItems: [SystemScheduleItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(workspaceEvents) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(event.colorHex.map(Color.init(hex:)) ?? Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .fontWeight(.medium)
                        if let notes = event.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Text(event.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            ForEach(systemItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(item.calendarColorHex.map(Color.init(hex:)) ?? (item.isHoliday ? Color.red : (item.kind == .event ? Color.blue : Color.orange)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .fontWeight(.medium)
                        Text([item.kind.label, item.categoryName].compactMap { $0 }.joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DashboardCalendarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    @Binding var selectedDate: Date
    var projectID: ResearchProject.ID? = nil
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedAppleCategories: Set<String> = []
    @State private var selectedProjectCategories: Set<String> = []
    @State private var includeAllProjects = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("Previous month")

                    Spacer()

                    Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                        .font(.headline)

                    Spacer()

                    Button("Today") {
                        let today = Calendar.current.startOfDay(for: Date())
                        displayedMonth = today
                        selectedDate = today
                    }
                    .controlSize(.small)

                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .help("Next month")
                }

                HStack(spacing: 10) {
                    if projectID != nil {
                        Toggle("All Projects", isOn: $includeAllProjects)
                            .toggleStyle(.checkbox)
                    }
                    categoryFilterMenu(
                        title: "Apple",
                        categories: appleCalendarCategories,
                        selection: $selectedAppleCategories
                    )
                    categoryFilterMenu(
                        title: "Project",
                        categories: projectCalendarCategories,
                        selection: $selectedProjectCategories
                    )
                    Spacer(minLength: 0)
                }
                .controlSize(.small)

                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthGridDates, id: \.self) { date in
                        CalendarDayCellView(
                            date: date,
                            isCurrentMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            items: calendarItems(for: date)
                        ) {
                            selectedDate = date
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Calendar")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .onAppear {
            appModel.refreshSystemSchedule(around: displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newMonth in
            appModel.refreshSystemSchedule(around: newMonth)
        }
    }

    private var monthGridDates: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.start),
              let lastWeekReference = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastWeekReference)
        else {
            return []
        }

        var dates: [Date] = []
        var currentDate = firstWeek.start
        while currentDate < lastWeek.end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }

    private func calendarItems(for date: Date) -> [CalendarDisplayItem] {
        let todoItems = appModel.todos.compactMap { todo -> CalendarDisplayItem? in
            guard includesProject(todo.projectIDs) else {
                return nil
            }
            guard let dueDate = todo.dueDate else {
                return nil
            }
            guard calendar.isDate(dueDate, inSameDayAs: date) else {
                return nil
            }

            return CalendarDisplayItem(
                id: "todo-\(todo.id)",
                title: todo.title,
                subtitle: todo.status == .done ? "Done" : "Todo",
                color: color(for: todo.priority),
                sortDate: dueDate,
                sortPriority: prioritySortValue(for: todo.priority)
            )
        }

        let workspaceEvents = appModel.calendarEvents.compactMap { event -> CalendarDisplayItem? in
            guard includesProject(event.projectID.map { [$0] } ?? []) else {
                return nil
            }
            guard calendar.isDate(event.date, inSameDayAs: date) else {
                return nil
            }
            guard includes(category: event.category, selected: selectedProjectCategories) else {
                return nil
            }

            return CalendarDisplayItem(
                id: "workspace-\(event.id)",
                title: event.title,
                subtitle: event.category,
                color: color(for: event),
                sortDate: event.date,
                sortPriority: 10
            )
        }

        let systemItems = appModel.systemScheduleItems.compactMap { item -> CalendarDisplayItem? in
            guard projectID == nil || includeAllProjects else {
                return nil
            }
            guard calendar.isDate(item.displayDate, inSameDayAs: date) else {
                return nil
            }
            guard includes(category: item.categoryName, selected: selectedAppleCategories) else {
                return nil
            }

            return CalendarDisplayItem(
                id: "system-\(item.id)",
                title: item.title,
                subtitle: item.categoryName,
                color: color(for: item),
                sortDate: item.displayDate,
                sortPriority: item.isHoliday ? 5 : (item.kind == .event ? 20 : 30)
            )
        }

        return (todoItems + workspaceEvents + systemItems).sorted { first, second in
            if first.sortDate == second.sortDate {
                return first.sortPriority < second.sortPriority
            }
            return first.sortDate < second.sortDate
        }
    }

    private func color(for priority: Priority) -> Color {
        switch priority {
        case .low:
            return .gray
        case .medium:
            return .accentColor
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }

    private func color(for event: CalendarEvent) -> Color {
        if let colorHex = event.colorHex {
            return Color(hex: colorHex)
        }
        if let projectID = event.projectID,
           let project = appModel.researchProjects.first(where: { $0.id == projectID }) {
            return Color(hex: project.colorHex)
        }
        return .accentColor
    }

    private func color(for item: SystemScheduleItem) -> Color {
        if let colorHex = item.calendarColorHex {
            return Color(hex: colorHex)
        }
        if item.isHoliday {
            return .red
        }
        return item.kind == .event ? .blue : .orange
    }

    private var appleCalendarCategories: [String] {
        guard projectID == nil || includeAllProjects else {
            return []
        }
        return Array(Set(appModel.systemScheduleItems.map(\.categoryName))).sorted()
    }

    private var projectCalendarCategories: [String] {
        return Array(Set(appModel.calendarEvents.filter { event in
            includesProject(event.projectID.map { [$0] } ?? [])
        }.map(\.category))).sorted()
    }

    private func includesProject(_ projectIDs: [ResearchProject.ID]) -> Bool {
        guard let projectID, !includeAllProjects else {
            return true
        }
        return projectIDs.contains(projectID)
    }

    private func includes(category: String, selected: Set<String>) -> Bool {
        selected.isEmpty || selected.contains(category)
    }

    @ViewBuilder
    private func categoryFilterMenu(title: String, categories: [String], selection: Binding<Set<String>>) -> some View {
        Menu {
            Button("All \(title) Calendars") {
                selection.wrappedValue = []
            }

            if !categories.isEmpty {
                Divider()
            }

            ForEach(categories, id: \.self) { category in
                Button {
                    toggle(category: category, selection: selection)
                } label: {
                    Label(category, systemImage: selection.wrappedValue.contains(category) ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label(filterTitle(title: title, selection: selection.wrappedValue), systemImage: title == "Apple" ? "apple.logo" : "folder")
        }
        .help("Filter \(title.lowercased()) calendar categories")
    }

    private func toggle(category: String, selection: Binding<Set<String>>) {
        var nextSelection = selection.wrappedValue
        if nextSelection.contains(category) {
            nextSelection.remove(category)
        } else {
            nextSelection.insert(category)
        }
        selection.wrappedValue = nextSelection
    }

    private func filterTitle(title: String, selection: Set<String>) -> String {
        selection.isEmpty ? "\(title): All" : "\(title): \(selection.count)"
    }

    private func prioritySortValue(for priority: Priority) -> Int {
        switch priority {
        case .urgent:
            return 0
        case .high:
            return 1
        case .medium:
            return 2
        case .low:
            return 3
        }
    }
}

private struct CalendarDisplayItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let color: Color
    let sortDate: Date
    let sortPriority: Int
}

private struct CalendarDayCellView: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let items: [CalendarDisplayItem]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(date.formatted(.dateTime.day()))
                        .font(.caption)
                        .fontWeight(isToday ? .semibold : .regular)
                    if isToday {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                }

                ForEach(items.prefix(2)) { item in
                    CalendarItemPill(item: item)
                }

                if items.count > 2 {
                    Text("+\(items.count - 2) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(6)
            .foregroundStyle(isCurrentMonth ? .primary : .secondary)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isToday {
            return Color.accentColor.opacity(0.10)
        }
        return Color.secondary.opacity(0.06)
    }
}

private struct CalendarItemPill: View {
    let item: CalendarDisplayItem

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.color)
                .frame(width: 3)
            Text(item.title)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
        .padding(.horizontal, 4)
        .background(item.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
        .help("\(item.subtitle): \(item.title)")
    }
}

struct DashboardPaperList: View {
    let title: String
    let papers: [Paper]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if papers.isEmpty {
                    Text("No papers in this list yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(papers) { paper in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paper.displayTitle)
                                .fontWeight(.medium)
                            Text(paper.authorsDisplay)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var action: (() -> Void)? = nil

    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}
