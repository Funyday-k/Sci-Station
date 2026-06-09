import SwiftUI

enum TaskTypeFilter: String, CaseIterable, Identifiable {
    case all
    case general
    case reading

    var id: String { rawValue }

    func includes(_ kind: TodoKind) -> Bool {
        switch self {
        case .all: return true
        case .general: return kind == .general
        case .reading: return kind == .reading
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .general: return TodoKind.general.systemImage
        case .reading: return TodoKind.reading.systemImage
        }
    }

    func label(_ appModel: AppViewModel) -> String {
        switch self {
        case .all: return appModel.localized("全部", "All")
        case .general: return appModel.localized(TodoKind.general.label, TodoKind.general.englishLabel)
        case .reading: return appModel.localized(TodoKind.reading.label, TodoKind.reading.englishLabel)
        }
    }
}

/// Project filter for the Tasks view. `current` resolves against the project
/// being viewed; `project` pins a specific other project.
enum TaskProjectScope: Hashable {
    case all
    case current
    case project(String)
}

struct TaskFilter {
    var type: TaskTypeFilter = .all
    var tags: Set<String> = []
    var projectScope: TaskProjectScope = .current

    var isActive: Bool {
        type != .all || !tags.isEmpty || projectScope != .current
    }
}

/// Filter icon button that opens an inline popover (not a full page).
struct TaskFilterButton: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var filter: TaskFilter
    /// Whether to expose project-scope switching (hidden on the global view).
    var showsProjectScope: Bool = true

    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filter.isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(appModel.localized("筛选任务", "Filter tasks"))
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
            popover.environmentObject(appModel)
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(appModel.localized("类型", "Type")) {
                Picker("", selection: $filter.type) {
                    ForEach(TaskTypeFilter.allCases) { option in
                        Label(option.label(appModel), systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if showsProjectScope {
                section(appModel.localized("项目", "Project")) {
                    Picker("", selection: $filter.projectScope) {
                        Text(appModel.localized("本项目", "This Project")).tag(TaskProjectScope.current)
                        Text(appModel.localized("全部项目", "All Projects")).tag(TaskProjectScope.all)
                        ForEach(appModel.activeResearchProjects) { project in
                            Text(project.name).tag(TaskProjectScope.project(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            section(appModel.localized("标签", "Tags")) {
                if appModel.availableTodoTagDefinitions.isEmpty {
                    Text(appModel.localized("暂无标签", "No tags yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        TaskFlowLayout(spacing: 6) {
                            ForEach(appModel.availableTodoTagDefinitions) { tag in
                                Button {
                                    toggleTag(tag.name)
                                } label: {
                                    TodoTagChip(tag: tag, isSelected: filter.tags.contains(tag.name), showsCheck: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 130)
                }
            }

            if filter.isActive {
                Divider()
                Button {
                    filter = TaskFilter()
                } label: {
                    Label(appModel.localized("清除筛选", "Clear Filters"), systemImage: "arrow.counterclockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func toggleTag(_ name: String) {
        if filter.tags.contains(name) {
            filter.tags.remove(name)
        } else {
            filter.tags.insert(name)
        }
    }
}

extension TaskFilter {
    /// Applies the filter to a todo collection. `viewingProjectID` is the
    /// project currently in context (used to resolve `.current`).
    func apply(to todos: [TodoItem], viewingProjectID: String?) -> [TodoItem] {
        todos.filter { todo in
            guard type.includes(todo.kind) else { return false }
            if !tags.isEmpty, tags.isDisjoint(with: Set(todo.tags)) { return false }
            switch projectScope {
            case .all:
                return true
            case .current:
                guard let viewingProjectID else { return true }
                return todo.projectIDs.contains(viewingProjectID)
            case .project(let id):
                return todo.projectIDs.contains(id)
            }
        }
    }
}
