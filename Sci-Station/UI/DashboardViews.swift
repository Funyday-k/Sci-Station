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

private enum TodoKindFilter: String, CaseIterable {
    case all
    case general
    case reading

    func includes(_ kind: TodoKind) -> Bool {
        switch self {
        case .all:
            return true
        case .general:
            return kind == .general
        case .reading:
            return kind == .reading
        }
    }

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .all:
            return appModel.localized("全部", "All")
        case .general:
            return appModel.localized(TodoKind.general.label, TodoKind.general.englishLabel)
        case .reading:
            return appModel.localized(TodoKind.reading.label, TodoKind.reading.englishLabel)
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

    @State private var newTodoTitle = ""
    @State private var newTodoHasDueDate = true
    @State private var newTodoDueDate = Calendar.current.startOfDay(for: Date())
    @State private var newTodoKind = TodoKind.general
    @State private var newTodoPriority = Priority.medium
    @State private var newTodoNotes = ""
    @State private var newTodoProjectIDs: [ResearchProject.ID] = []
    @State private var isShowingCompleted = false
    @State private var displayMode = TodoDisplayMode.list
    @State private var kindFilter = TodoKindFilter.all
    @State private var isShowingTodoComposer = false

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
                        isShowingTodoComposer = true
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
        .sheet(isPresented: $isShowingTodoComposer) {
            todoComposerSheet
        }
        .onAppear {
            newTodoHasDueDate = scope == .selectedDate
            newTodoDueDate = appModel.selectedDashboardDate
            newTodoProjectIDs = defaultProjectIDs
        }
        .onChange(of: appModel.selectedDashboardDate) { _, newDate in
            if scope == .selectedDate {
                newTodoDueDate = newDate
            }
        }
    }

    private var todoToolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            if scope == .global {
                Picker("View", selection: $displayMode) {
                    ForEach(TodoDisplayMode.allCases, id: \.self) { mode in
                        Text(mode == .list ? appModel.localized("列表", "List") : appModel.localized("卡片", "Boxes")).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            Picker(appModel.localized("类型", "Kind"), selection: $kindFilter) {
                ForEach(TodoKindFilter.allCases, id: \.self) { filter in
                    Text(filter.label(appModel: appModel)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 228)

            Button {
                isShowingCompleted.toggle()
            } label: {
                Label(
                    isShowingCompleted ? appModel.localized("打开中", "Open") : appModel.localized("已完成", "Completed"),
                    systemImage: isShowingCompleted ? "circle" : "checkmark.circle"
                )
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button {
                appModel.requestSystemCalendarAccess()
            } label: {
                Label(appModel.systemCalendarAccessState.label, systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
            .help(appModel.localized("连接 Apple 日历与提醒事项", "Connect Apple Calendar and Reminders"))
            .disabled(appModel.systemCalendarAccessState == .authorized)

            Button {
                appModel.refreshSystemSchedule(around: appModel.selectedDashboardDate)
            } label: {
                Label(appModel.localized("刷新", "Refresh"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(appModel.localized("刷新日历和提醒事项", "Refresh calendar and reminders"))
            .disabled(!appModel.systemCalendarAccessState.canReadSchedule)

            if appModel.isLoadingSystemSchedule {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                isShowingTodoComposer = true
            } label: {
                Label(appModel.localized("新建任务", "New Task"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }

    private var todoComposerSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(appModel.localized("新建任务", "New Task"))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    isShowingTodoComposer = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            todoComposer
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 720, alignment: .topLeading)
    }

    private var todoComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                TextField(appModel.localized("新任务", "New Todo"), text: $newTodoTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTodo)

                Button {
                    addTodo()
                } label: {
                    Label(appModel.localized("添加", "Add"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(addTodoDisabledReason != nil)
                .help(addTodoDisabledReason ?? appModel.localized("创建任务", "Create todo"))
            }

            HStack(alignment: .center, spacing: 12) {
                Toggle(appModel.localized("日期", "Date"), isOn: $newTodoHasDueDate)
                    .toggleStyle(.checkbox)

                HStack(spacing: 6) {
                    Text(appModel.localized("到期", "Due"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    DatePicker(appModel.localized("到期日期", "Due Date"), selection: $newTodoDueDate, displayedComponents: .date)
                        .labelsHidden()
                        .disabled(!newTodoHasDueDate)
                }

                Picker(appModel.localized("类型", "Kind"), selection: $newTodoKind) {
                    ForEach(TodoKind.allCases, id: \.self) { kind in
                        Text(appModel.localized(kind.label, kind.englishLabel)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120, alignment: .leading)

                Picker(appModel.localized("优先级", "Priority"), selection: $newTodoPriority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(appModel.localized(priority.label, priority.englishLabel)).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 150, alignment: .leading)

                Menu {
                    ForEach(appModel.activeResearchProjects) { project in
                        Button {
                            toggleNewTodoProject(project.id)
                        } label: {
                            Label(project.name, systemImage: newTodoProjectIDs.contains(project.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }

                    if !newTodoProjectIDs.isEmpty {
                        Divider()
                        Button(appModel.localized("清除项目归属", "Clear Project Assignment")) {
                            newTodoProjectIDs = []
                        }
                    }
                } label: {
                    Label(newTodoProjectMenuTitle, systemImage: "folder")
                }
                .help(appModel.localized("选择此任务所属项目", "Choose which project owns this todo"))
                .frame(minWidth: 150, alignment: .leading)
            }
            .controlSize(.small)

            HStack(alignment: .center, spacing: 10) {
                TextField(appModel.localized("备注", "Notes"), text: $newTodoNotes)
                    .textFieldStyle(.roundedBorder)

                if let addTodoDisabledReason {
                    Label(addTodoDisabledReason, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var addTodoDisabledReason: String? {
        if newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appModel.localized("请输入任务标题。", "Enter a todo title before adding.")
        }
        return nil
    }

    @ViewBuilder
    private var todoContent: some View {
        if scope == .global, appModel.activeResearchProjects.count > 1 {
            LazyVGrid(columns: globalColumns, alignment: .leading, spacing: 12) {
                ForEach(projectColumns) { column in
                    TodoProjectColumnView(title: column.title, todos: column.todos)
                }
            }
        } else if displayMode == .boxes {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(displayedTodos) { todo in
                    TodoCardView(todo: todo)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(displayedTodos) { todo in
                    TodoRowView(todo: todo)
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

        return baseTodos
            .filter { isShowingCompleted ? TodoQueries.isCompleted($0) : TodoQueries.isOpen($0) }
            .filter { kindFilter.includes($0.kind) }
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

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dueDate = newTodoHasDueDate ? newTodoDueDate : nil
        appModel.addTodo(
            title: trimmed,
            dueDate: dueDate,
            kind: newTodoKind,
            priority: newTodoPriority,
            notes: newTodoNotes,
            projectIDs: newTodoProjectIDs
        )
        newTodoTitle = ""
        newTodoNotes = ""
        isShowingTodoComposer = false
    }

    private var defaultProjectIDs: [ResearchProject.ID] {
        scope == .currentProject ? appModel.currentProjectID.map { [$0] } ?? [] : []
    }

    private func toggleNewTodoProject(_ projectID: ResearchProject.ID) {
        if newTodoProjectIDs.contains(projectID) {
            newTodoProjectIDs.removeAll { $0 == projectID }
        } else {
            newTodoProjectIDs.append(projectID)
        }
    }

    private var newTodoProjectMenuTitle: String {
        if newTodoProjectIDs.isEmpty {
            return appModel.localized("未分配", "Unassigned")
        }

        if newTodoProjectIDs.count == 1 {
            return appModel.projectName(for: newTodoProjectIDs[0])
        }

        return appModel.localized("\(newTodoProjectIDs.count) 个项目", "\(newTodoProjectIDs.count) Projects")
    }
}

private struct TodoRowView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let todo: TodoItem

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedKind: TodoKind
    @State private var editedStatus: TodoStatus
    @State private var editedHasDueDate: Bool
    @State private var editedDueDate: Date
    @State private var editedPriority: Priority
    @State private var editedProjectIDs: [ResearchProject.ID]
    @State private var editedNotes: String

    init(todo: TodoItem) {
        self.todo = todo
        _editedTitle = State(initialValue: todo.title)
        _editedKind = State(initialValue: todo.kind)
        _editedStatus = State(initialValue: todo.status)
        _editedHasDueDate = State(initialValue: todo.dueDate != nil)
        _editedDueDate = State(initialValue: todo.dueDate ?? Calendar.current.startOfDay(for: Date()))
        _editedPriority = State(initialValue: todo.priority)
        _editedProjectIDs = State(initialValue: todo.projectIDs)
        _editedNotes = State(initialValue: todo.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(appModel.localized("任务标题", "Todo title"), text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveEdits)

                    HStack(spacing: 12) {
                        Picker(appModel.localized("状态", "Status"), selection: $editedStatus) {
                            ForEach(TodoStatus.allCases, id: \.self) { status in
                                Text(appModel.localized(status.label, status.englishLabel)).tag(status)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(appModel.localized("类型", "Kind"), selection: $editedKind) {
                            ForEach(TodoKind.allCases, id: \.self) { kind in
                                Text(appModel.localized(kind.label, kind.englishLabel)).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle(appModel.localized("到期", "Due"), isOn: $editedHasDueDate)
                            .toggleStyle(.checkbox)

                        DatePicker(appModel.localized("到期日期", "Due Date"), selection: $editedDueDate, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!editedHasDueDate)

                        Picker(appModel.localized("优先级", "Priority"), selection: $editedPriority) {
                            ForEach(Priority.allCases, id: \.self) { priority in
                                Text(appModel.localized(priority.label, priority.englishLabel)).tag(priority)
                            }
                        }
                        .pickerStyle(.menu)

                        Menu {
                            ForEach(appModel.activeResearchProjects) { project in
                                Button {
                                    toggleEditedProject(project.id)
                                } label: {
                                    Label(project.name, systemImage: editedProjectIDs.contains(project.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }

                            if !editedProjectIDs.isEmpty {
                                Divider()
                                Button(appModel.localized("清除项目归属", "Clear Project Assignment")) {
                                    editedProjectIDs = []
                                }
                            }
                        } label: {
                            Label(projectMenuTitle, systemImage: "folder")
                        }

                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)

                    TextField(appModel.localized("备注", "Notes"), text: $editedNotes)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveEdits)

                    HStack {
                        Button(appModel.localized("保存", "Save"), action: saveEdits)
                            .buttonStyle(.borderedProminent)
                        Button(appModel.localized("取消", "Cancel")) {
                            resetEdits(from: todo)
                            isEditing = false
                        }
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        appModel.toggleTodo(todo)
                    } label: {
                        Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .help(todo.status == .done ? appModel.localized("标记为打开中", "Mark todo as open") : appModel.localized("标记为已完成", "Mark todo as done"))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(todo.title)
                                .fontWeight(.medium)
                                .strikethrough(todo.status == .done)
                            TodoKindBadge(kind: todo.kind)
                            TodoPriorityBadge(priority: todo.priority)
                        }

                        HStack(spacing: 8) {
                            ForEach(projectLabels, id: \.self) { label in
                                Text(label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.secondary)
                                    .background(Color.secondary.opacity(0.10), in: Capsule())
                            }
                            Text(appModel.localized(todo.status.label, todo.status.englishLabel))
                            if let dueDate = todo.dueDate {
                                Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let notes = todo.notes, !notes.isEmpty {
                                Text(notes)
                                    .lineLimit(1)
                            }
                            if todo.externalSource == "apple_reminders" {
                                Label(appModel.localized("提醒事项", "Reminder"), systemImage: "bell")
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
                            resetEdits(from: todo)
                            isEditing = true
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
                        .help(appModel.localized("更多操作", "More actions"))
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
        .onChange(of: todo) { _, newTodo in
            if !isEditing {
                resetEdits(from: newTodo)
            }
        }
    }

    private func saveEdits() {
        appModel.updateTodo(
            todo,
            title: editedTitle,
            kind: editedKind,
            status: editedStatus,
            dueDate: editedHasDueDate ? editedDueDate : nil,
            priority: editedPriority,
            notes: editedNotes,
            projectIDs: editedProjectIDs
        )
        isEditing = false
    }

    private func resetEdits(from todo: TodoItem) {
        editedTitle = todo.title
        editedKind = todo.kind
        editedStatus = todo.status
        editedHasDueDate = todo.dueDate != nil
        editedDueDate = todo.dueDate ?? Calendar.current.startOfDay(for: Date())
        editedPriority = todo.priority
        editedProjectIDs = todo.projectIDs
        editedNotes = todo.notes ?? ""
    }

    private func toggleEditedProject(_ projectID: ResearchProject.ID) {
        if editedProjectIDs.contains(projectID) {
            editedProjectIDs.removeAll { $0 == projectID }
        } else {
            editedProjectIDs.append(projectID)
        }
    }

    private var projectMenuTitle: String {
        if editedProjectIDs.isEmpty {
            return appModel.localized("未分配", "Unassigned")
        }

        if editedProjectIDs.count == 1,
           let projectName = appModel.researchProjects.first(where: { $0.id == editedProjectIDs[0] })?.name {
            return projectName
        }

        return appModel.localized("\(editedProjectIDs.count) 个项目", "\(editedProjectIDs.count) Projects")
    }

    private var projectLabels: [String] {
        guard !todo.projectIDs.isEmpty else {
            return [appModel.localized("未分配", "Unassigned")]
        }

        return todo.projectIDs.map { projectID in
            appModel.researchProjects.first(where: { $0.id == projectID })?.name ?? projectID
        }
    }
}

private struct TodoProjectColumnView: View {
    let title: String
    let todos: [TodoItem]

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
                    TodoRowView(todo: todo)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appModel.toggleTodo(todo)
                } label: {
                    Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(.headline)
                        .lineLimit(2)
                        .strikethrough(todo.status == .done)
                    if let notes = todo.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TodoKindBadge(kind: todo.kind)
                TodoPriorityBadge(priority: todo.priority)
                if let dueDate = todo.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if todo.externalSource == "apple_reminders" {
                    Label(appModel.localized("提醒事项", "Reminder"), systemImage: "bell")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(projectLabels, id: \.self) { label in
                    SciBadge(label)
                }
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

private struct TodoKindBadge: View {
    @EnvironmentObject private var appModel: AppViewModel

    let kind: TodoKind

    var body: some View {
        Label(appModel.localized(kind.label, kind.englishLabel), systemImage: kind == .reading ? "book" : "checklist")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(kind == .reading ? Color.blue : Color.secondary)
            .background((kind == .reading ? Color.blue : Color.secondary).opacity(0.12), in: Capsule())
            .labelStyle(.titleAndIcon)
    }
}

private struct TodoPriorityBadge: View {
    @EnvironmentObject private var appModel: AppViewModel

    let priority: Priority

    var body: some View {
        Text(appModel.localized(priority.label, priority.englishLabel))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(priorityColor)
            .background(priorityColor.opacity(0.12), in: Capsule())
    }

    private var priorityColor: Color {
        switch priority {
        case .low:
            return .secondary
        case .medium:
            return .accentColor
        case .high:
            return .orange
        case .urgent:
            return .red
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
