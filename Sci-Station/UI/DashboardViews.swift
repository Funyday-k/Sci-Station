import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Global overview for \(workspace.displayName): papers, projects, tasks, and recent reading activity.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatCard(title: "Open Todos", value: "\(appModel.todos.filter { $0.status != .done }.count)", systemImage: "checklist")
                    StatCard(title: "Due Today", value: "\(appModel.selectedDateTodos.count)", systemImage: "calendar")
                    StatCard(title: "Papers", value: "\(appModel.papers.count)", systemImage: "books.vertical")
                }

                DashboardCalendarView(selectedDate: Binding(
                    get: { appModel.selectedDashboardDate },
                    set: { appModel.selectDashboardDate($0) }
                ))
                .frame(maxWidth: .infinity, alignment: .topLeading)

                TodoDashboardWidget()
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                WorkspaceManagementWidget(workspace: workspace)

                DashboardWorkspaceOverview(workspace: workspace)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], alignment: .leading, spacing: 16) {
                    DashboardPaperList(title: "Recently Added", papers: appModel.recentPapers)
                    DashboardPaperList(title: "Recently Read", papers: appModel.recentlyReadPapers)
                }
            }
            .padding(24)
        }
    }
}

private struct WorkspaceManagementWidget: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workspace Management")
                        .font(.headline)
                    Spacer()
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

                HStack(alignment: .center, spacing: 10) {
                    Label(workspace.displayName, systemImage: "folder")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        appModel.revealCurrentWorkspaceInFinder()
                    } label: {
                        Label("Reveal", systemImage: "arrow.up.right.square")
                    }
                    .labelStyle(.titleAndIcon)
                }
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

struct TasksWorkspaceView: View {
    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Manage due dates and reading todos linked to your workspace.")
                        .foregroundStyle(.secondary)
                }

                TodoDashboardWidget(showAllTodos: true)
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

    var showAllTodos = false

    var body: some View {
        GroupBox(showAllTodos ? "All Todos" : todoListTitle) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Add a todo", text: $newTodoTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTodo)

                        Button("Add", action: addTodo)
                            .buttonStyle(.borderedProminent)
                            .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    HStack(spacing: 12) {
                        Toggle("Due", isOn: $newTodoHasDueDate)
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

                        TextField("Notes", text: $newTodoNotes)
                            .textFieldStyle(.roundedBorder)
                    }
                    .controlSize(.small)
                }

                HStack(spacing: 10) {
                    Toggle("Apple Reminders", isOn: $appModel.addTodosToAppleReminders)
                        .toggleStyle(.checkbox)

                    Button {
                        appModel.requestSystemCalendarAccess()
                    } label: {
                        Label(appModel.systemCalendarAccessState.label, systemImage: "calendar.badge.plus")
                    }
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
                    Text("No todos yet for this view.")
                        .foregroundStyle(.secondary)
                } else if !displayedTodos.isEmpty {
                    ForEach(displayedTodos) { todo in
                        TodoRowView(todo: todo)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            newTodoHasDueDate = !showAllTodos
            newTodoDueDate = appModel.selectedDashboardDate
        }
        .onChange(of: appModel.selectedDashboardDate) { _, newDate in
            if !showAllTodos {
                newTodoDueDate = newDate
            }
        }
    }

    private var displayedTodos: [TodoItem] {
        showAllTodos ? appModel.todos : appModel.selectedDateTodos
    }

    private var displayedWorkspaceEvents: [CalendarEvent] {
        showAllTodos ? [] : appModel.selectedDateWorkspaceEvents
    }

    private var displayedSystemItems: [SystemScheduleItem] {
        showAllTodos ? [] : appModel.selectedDateSystemScheduleItems
    }

    private var todoListTitle: String {
        let formatted = appModel.selectedDashboardDate.formatted(date: .abbreviated, time: .omitted)
        return "Todos for \(formatted)"
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dueDate = newTodoHasDueDate ? newTodoDueDate : nil
        appModel.addTodo(
            title: trimmed,
            dueDate: dueDate,
            priority: newTodoPriority,
            notes: newTodoNotes
        )
        newTodoTitle = ""
        newTodoNotes = ""
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
    @State private var editedNotes: String

    init(todo: TodoItem) {
        self.todo = todo
        _editedTitle = State(initialValue: todo.title)
        _editedStatus = State(initialValue: todo.status)
        _editedHasDueDate = State(initialValue: todo.dueDate != nil)
        _editedDueDate = State(initialValue: todo.dueDate ?? Calendar.current.startOfDay(for: Date()))
        _editedPriority = State(initialValue: todo.priority)
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

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(todo.title)
                                .fontWeight(.medium)
                                .strikethrough(todo.status == .done)
                            TodoPriorityBadge(priority: todo.priority)
                        }

                        HStack(spacing: 8) {
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
            notes: editedNotes
        )
        isEditing = false
    }

    private func resetEdits(from todo: TodoItem) {
        editedTitle = todo.title
        editedStatus = todo.status
        editedHasDueDate = todo.dueDate != nil
        editedDueDate = todo.dueDate ?? Calendar.current.startOfDay(for: Date())
        editedPriority = todo.priority
        editedNotes = todo.notes ?? ""
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
                        .foregroundStyle(Color.accentColor)
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
                    Text("Workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            ForEach(systemItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(item.kind == .event ? Color.blue : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .fontWeight(.medium)
                        Text([item.kind.label, item.calendarTitle].compactMap { $0 }.joined(separator: " / "))
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        GroupBox("Calendar") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)

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
                }

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

            return CalendarDisplayItem(
                id: "workspace-\(event.id)",
                title: event.title,
                subtitle: "Workspace",
                color: .accentColor,
                sortDate: event.date,
                sortPriority: 10
            )
        }

        let systemItems = appModel.systemScheduleItems.compactMap { item -> CalendarDisplayItem? in
            guard calendar.isDate(item.displayDate, inSameDayAs: date) else {
                return nil
            }

            return CalendarDisplayItem(
                id: "system-\(item.id)",
                title: item.title,
                subtitle: item.kind.label,
                color: item.kind == .event ? .blue : .orange,
                sortDate: item.displayDate,
                sortPriority: item.kind == .event ? 20 : 30
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

private struct DashboardPaperList: View {
    let title: String
    let papers: [Paper]

    var body: some View {
        GroupBox(title) {
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String

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
    }
}
