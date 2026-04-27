import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Track reading tasks, due dates, and the freshest papers in \(workspace.displayName).")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    StatCard(title: "Open Todos", value: "\(appModel.todos.filter { $0.status != .done }.count)", systemImage: "checklist")
                    StatCard(title: "Due Today", value: "\(appModel.selectedDateTodos.count)", systemImage: "calendar")
                    StatCard(title: "Papers", value: "\(appModel.papers.count)", systemImage: "books.vertical")
                }

                QuickImportWidget()

                HStack(alignment: .top, spacing: 20) {
                    DashboardCalendarView(selectedDate: Binding(
                        get: { appModel.selectedDashboardDate },
                        set: { appModel.selectDashboardDate($0) }
                    ))
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    TodoDashboardWidget()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                HStack(alignment: .top, spacing: 20) {
                    DashboardPaperList(title: "Recently Added", papers: appModel.recentPapers)
                    DashboardPaperList(title: "Recently Read", papers: appModel.recentlyReadPapers)
                }
            }
            .padding(24)
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
    @State private var newTodoDueDate = Calendar.current.startOfDay(for: Date())

    var showAllTodos = false

    var body: some View {
        GroupBox(showAllTodos ? "All Todos" : "Todos for Selected Day") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Add a todo", text: $newTodoTitle)
                        .textFieldStyle(.roundedBorder)

                    DatePicker("Due", selection: $newTodoDueDate, displayedComponents: .date)
                        .labelsHidden()

                    Button("Add") {
                        appModel.addTodo(title: newTodoTitle, dueDate: newTodoDueDate)
                        newTodoTitle = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                if displayedTodos.isEmpty {
                    Text("No todos yet for this view.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedTodos) { todo in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                appModel.toggleTodo(todo)
                            } label: {
                                Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .strikethrough(todo.status == .done)
                                Text(todo.status.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let dueDate = todo.dueDate {
                                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Delete") {
                                appModel.deleteTodo(todo)
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displayedTodos: [TodoItem] {
        showAllTodos ? appModel.todos : appModel.selectedDateTodos
    }
}

struct DashboardCalendarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    @Binding var selectedDate: Date
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
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

                    Button {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(monthGridDates, id: \.self) { date in
                        CalendarDayCellView(
                            date: date,
                            isCurrentMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            taskCount: taskCount(for: date)
                        ) {
                            selectedDate = date
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func taskCount(for date: Date) -> Int {
        let todoCount = appModel.todos.filter { todo in
            guard let dueDate = todo.dueDate else {
                return false
            }
            return calendar.isDate(dueDate, inSameDayAs: date)
        }.count

        let eventCount = appModel.calendarEvents.filter { event in
            calendar.isDate(event.date, inSameDayAs: date)
        }.count

        return todoCount + eventCount
    }
}

struct CalendarDayCellView: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let taskCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(date.formatted(.dateTime.day()))
                    .font(.callout)
                    .fontWeight(isToday ? .semibold : .regular)

                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(6)
            .foregroundStyle(isCurrentMonth ? .primary : .secondary)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
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

private struct QuickImportWidget: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var quickInput = ""

    var body: some View {
        GroupBox("Quick Import") {
            HStack(spacing: 12) {
                TextField("DOI, arXiv ID, INSPIRE URL, PDF URL or page URL", text: $quickInput)
                    .textFieldStyle(.roundedBorder)

                Button("Open Import Sheet") {
                    appModel.beginIdentifierImport(with: quickInput)
                    quickInput = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}