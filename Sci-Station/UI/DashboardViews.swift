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
        let openCount = scopedTodos.filter { $0.status != .done && $0.status != .cancelled }.count
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
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text(appModel.isViewingGlobalTodos ? "Review todos across all projects." : "Manage due dates and reading todos for \(appModel.currentResearchProject?.name ?? "the active project").")
                        .foregroundStyle(.secondary)
                }

                TodoDashboardWidget(scope: appModel.isViewingGlobalTodos ? .global : .currentProject)
            }
            .padding(24)
        }
    }
}

struct TodoDashboardWidget: View {
    @EnvironmentObject private var appModel: AppViewModel

    @State private var newTodoTitle = ""
    @State private var newTodoHasDueDate = true
    @State private var newTodoDueDate = Calendar.current.startOfDay(for: Date())
    @State private var newTodoPriority = Priority.medium
    @State private var newTodoNotes = ""
    @State private var newTodoProjectIDs: [ResearchProject.ID] = []
    @State private var isShowingCompleted = false
    @State private var displayMode = TodoDisplayMode.list

    var scope: TodoDashboardScope = .selectedDate

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                todoComposer

                HStack(spacing: 10) {
                    Button {
                        appModel.requestSystemCalendarAccess()
                    } label: {
                        Label(appModel.systemCalendarAccessState.label, systemImage: "calendar.badge.plus")
                    }
                    .help("Request access to Apple Calendar and Reminders")
                    .disabled(appModel.systemCalendarAccessState == .authorized)

                    Button {
                        appModel.refreshSystemSchedule(around: appModel.selectedDashboardDate)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Apple Calendar and Reminders")
                    .disabled(!appModel.systemCalendarAccessState.canReadSchedule)

                    if appModel.isLoadingSystemSchedule {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }
                .controlSize(.small)

                if !displayedWorkspaceEvents.isEmpty || !displayedSystemItems.isEmpty {
                    ScheduleAgendaView(
                        workspaceEvents: displayedWorkspaceEvents,
                        systemItems: displayedSystemItems
                    )
                }

                if displayedTodos.isEmpty && displayedWorkspaceEvents.isEmpty && displayedSystemItems.isEmpty {
                    Text(isShowingCompleted ? "No completed todos in this view." : "No open todos in this view.")
                        .foregroundStyle(.secondary)
                } else {
                    todoContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                if scope == .global {
                    Picker("View", selection: $displayMode) {
                        ForEach(TodoDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                Button(isShowingCompleted ? "Open Todos" : "Completed") {
                    isShowingCompleted.toggle()
                }
                .buttonStyle(.bordered)
            }
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

    private var todoComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("New Reminder", text: $newTodoTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTodo)

                Button {
                    addTodo()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 12) {
                Toggle("Date", isOn: $newTodoHasDueDate)
                    .toggleStyle(.checkbox)

                DatePicker("Due Date", selection: $newTodoDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!newTodoHasDueDate)

                Picker("Priority", selection: $newTodoPriority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

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
                        Button("Clear Project Assignment") {
                            newTodoProjectIDs = []
                        }
                    }
                } label: {
                    Label(newTodoProjectMenuTitle, systemImage: "folder")
                }
                .help("Choose which project owns this todo")

                TextField("Notes", text: $newTodoNotes)
                    .textFieldStyle(.roundedBorder)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
            .filter { isShowingCompleted ? isCompleted($0) : !isCompleted($0) }
            .sorted(by: todoSort)
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
            columns.append(TodoProjectColumn(id: "unassigned", title: "Unassigned", todos: unassignedTodos))
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

    private var title: String {
        switch scope {
        case .selectedDate:
            let formatted = appModel.selectedDashboardDate.formatted(date: .abbreviated, time: .omitted)
            return "Todos for \(formatted)"
        case .global:
            return "All Project Todos"
        case .currentProject:
            return "\(appModel.currentResearchProject?.name ?? "Current Project") Todos"
        }
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dueDate = newTodoHasDueDate ? newTodoDueDate : nil
        appModel.addTodo(
            title: trimmed,
            dueDate: dueDate,
            priority: newTodoPriority,
            notes: newTodoNotes,
            projectIDs: newTodoProjectIDs
        )
        newTodoTitle = ""
        newTodoNotes = ""
    }

    private func isCompleted(_ todo: TodoItem) -> Bool {
        todo.status == .done || todo.status == .cancelled
    }

    private func todoSort(_ first: TodoItem, _ second: TodoItem) -> Bool {
        if first.status != second.status {
            return first.status.rawValue.localizedStandardCompare(second.status.rawValue) == .orderedAscending
        }
        if first.dueDate != second.dueDate {
            return (first.dueDate ?? .distantFuture) < (second.dueDate ?? .distantFuture)
        }
        if first.priority != second.priority {
            return prioritySortValue(first.priority) < prioritySortValue(second.priority)
        }
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }

    private func prioritySortValue(_ priority: Priority) -> Int {
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
            return "Unassigned"
        }

        if newTodoProjectIDs.count == 1 {
            return appModel.projectName(for: newTodoProjectIDs[0])
        }

        return "\(newTodoProjectIDs.count) Projects"
    }
}

private struct TodoRowView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let todo: TodoItem

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedStatus: TodoStatus
    @State private var editedHasDueDate: Bool
    @State private var editedDueDate: Date
    @State private var editedPriority: Priority
    @State private var editedProjectIDs: [ResearchProject.ID]
    @State private var editedNotes: String

    init(todo: TodoItem) {
        self.todo = todo
        _editedTitle = State(initialValue: todo.title)
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
                    TextField("Todo title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveEdits)

                    HStack(spacing: 12) {
                        Picker("Status", selection: $editedStatus) {
                            ForEach(TodoStatus.allCases, id: \.self) { status in
                                Text(status.label).tag(status)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Due", isOn: $editedHasDueDate)
                            .toggleStyle(.checkbox)

                        DatePicker("Due Date", selection: $editedDueDate, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!editedHasDueDate)

                        Picker("Priority", selection: $editedPriority) {
                            ForEach(Priority.allCases, id: \.self) { priority in
                                Text(priority.label).tag(priority)
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
                                Button("Clear Project Assignment") {
                                    editedProjectIDs = []
                                }
                            }
                        } label: {
                            Label(projectMenuTitle, systemImage: "folder")
                        }

                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)

                    TextField("Notes", text: $editedNotes)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveEdits)

                    HStack {
                        Button("Save", action: saveEdits)
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") {
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
                    .help(todo.status == .done ? "Mark todo as open" : "Mark todo as done")

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(todo.title)
                                .fontWeight(.medium)
                                .strikethrough(todo.status == .done)
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
                            Text(todo.status.label)
                            if let dueDate = todo.dueDate {
                                Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let notes = todo.notes, !notes.isEmpty {
                                Text(notes)
                                    .lineLimit(1)
                            }
                            if todo.externalSource == "apple_reminders" {
                                Label("Reminder", systemImage: "bell")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if todo.externalIdentifier == nil {
                        Button("Publish") {
                            appModel.publishTodoToAppleReminders(todo)
                        }
                        .buttonStyle(.link)
                    }

                    Button("Edit") {
                        resetEdits(from: todo)
                        isEditing = true
                    }
                    .buttonStyle(.link)

                    Button("Delete") {
                        appModel.deleteTodo(todo)
                    }
                    .buttonStyle(.link)
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
            return "Unassigned"
        }

        if editedProjectIDs.count == 1,
           let projectName = appModel.researchProjects.first(where: { $0.id == editedProjectIDs[0] })?.name {
            return projectName
        }

        return "\(editedProjectIDs.count) Projects"
    }

    private var projectLabels: [String] {
        guard !todo.projectIDs.isEmpty else {
            return ["Unassigned"]
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
                TodoPriorityBadge(priority: todo.priority)
                if let dueDate = todo.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if todo.externalSource == "apple_reminders" {
                    Label("Reminder", systemImage: "bell")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(projectLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
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
            return ["Unassigned"]
        }

        return todo.projectIDs.map { projectID in
            appModel.projectName(for: projectID)
        }
    }
}

private struct TodoPriorityBadge: View {
    let priority: Priority

    var body: some View {
        Text(priority.label)
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
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedAppleCategories: Set<String> = []
    @State private var selectedProjectCategories: Set<String> = []

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
                .font(.title2)
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
        Array(Set(appModel.systemScheduleItems.map(\.categoryName))).sorted()
    }

    private var projectCalendarCategories: [String] {
        Array(Set(appModel.calendarEvents.map(\.category))).sorted()
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
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(date.formatted(.dateTime.day()))
                        .font(.callout)
                        .fontWeight(isToday ? .semibold : .regular)
                    if isToday {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                }

                ForEach(items.prefix(3)) { item in
                    CalendarItemPill(item: item)
                }

                if items.count > 3 {
                    Text("+\(items.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(8)
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
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
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
