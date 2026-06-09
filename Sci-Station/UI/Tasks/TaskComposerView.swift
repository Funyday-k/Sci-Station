import SwiftUI

/// Type-first task composer. The user picks a task kind, then a progressively
/// disclosed set of icon-forward controls: date (presets + range), tags,
/// project, priority flags, notes, and — for reading tasks — a paper picker.
struct TaskComposerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// Scope used to seed defaults (project + initial date).
    var scope: TodoComposerScope = .global
    /// When set, the composer edits an existing todo instead of creating one.
    var editingTodo: TodoItem?

    @State private var title = ""
    @State private var kind: TodoKind = .general
    @State private var startDate: Date?
    @State private var dueDate: Date?
    @State private var priority: Priority = .medium
    @State private var selectedTags: [String] = []
    @State private var projectIDs: [String] = []
    @State private var notes = ""
    @State private var relatedPaperIDs: [String] = []
    @State private var isShowingPaperPicker = false
    @State private var didSeed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            TaskKindSelector(kind: $kind)
            titleField
            controlRow
            if kind == .reading {
                paperSection
            }
            if kind == .general {
                notesField
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: seedIfNeeded)
        .sheet(isPresented: $isShowingPaperPicker) {
            TaskPaperPickerView(selectedPaperIDs: $relatedPaperIDs, defaultProjectID: defaultProjectID)
                .environmentObject(appModel)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text(editingTodo == nil ? appModel.localized("新建任务", "New Task") : appModel.localized("编辑任务", "Edit Task"))
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var titleField: some View {
        TextField(appModel.localized("任务标题", "Task title"), text: $title)
            .textFieldStyle(.plain)
            .font(.title3)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onSubmit(save)
    }

    private var controlRow: some View {
        TaskFlowLayout(spacing: 8) {
            TaskDateField(startDate: $startDate, dueDate: $dueDate)
            TaskTagPickerField(selectedTags: $selectedTags)
            projectMenu
            priorityControl
        }
    }

    private var priorityControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TodoPriorityFlagsView(priority: $priority)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(SciStationDesign.subtleSurface))
        .overlay(Capsule().stroke(SciStationDesign.hairline, lineWidth: 0.7))
    }

    private var projectMenu: some View {
        Menu {
            ForEach(appModel.activeResearchProjects) { project in
                Button {
                    toggleProject(project.id)
                } label: {
                    Label(project.name, systemImage: projectIDs.contains(project.id) ? "checkmark.circle.fill" : "circle")
                }
            }
            if !projectIDs.isEmpty {
                Divider()
                Button(appModel.localized("清除项目归属", "Clear Project")) { projectIDs = [] }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                Text(projectMenuTitle).font(.callout).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(projectIDs.isEmpty ? Color.secondary : Color.accentColor)
            .background(Capsule().fill(projectIDs.isEmpty ? SciStationDesign.subtleSurface : Color.accentColor.opacity(0.12)))
            .overlay(Capsule().stroke(projectIDs.isEmpty ? SciStationDesign.hairline : Color.clear, lineWidth: 0.7))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var paperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(appModel.localized("关联论文", "Linked Papers"), systemImage: "book")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isShowingPaperPicker = true
                } label: {
                    Label(appModel.localized("选择论文", "Select Papers"), systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if relatedPaperIDs.isEmpty {
                Text(appModel.localized("尚未选择论文", "No papers selected yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TaskFlowLayout(spacing: 6) {
                    ForEach(relatedPaperIDs, id: \.self) { id in
                        paperChip(id)
                    }
                }
            }
        }
        .padding(12)
        .background(SciStationDesign.groupedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func paperChip(_ id: String) -> some View {
        let title = appModel.papers.first(where: { $0.id == id })?.displayTitle ?? id
        return HStack(spacing: 5) {
            Image(systemName: "doc.text").font(.system(size: 10))
            Text(title).font(.caption).lineLimit(1)
            Button {
                relatedPaperIDs.removeAll { $0 == id }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
    }

    private var notesField: some View {
        TextField(appModel.localized("备注", "Notes"), text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(2...4)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack {
            if let reason = disabledReason {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(appModel.localized("取消", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                save()
            } label: {
                Label(editingTodo == nil ? appModel.localized("添加", "Add") : appModel.localized("保存", "Save"), systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(disabledReason != nil)
        }
    }

    // MARK: Logic

    private var defaultProjectID: String? {
        projectIDs.first ?? scope.projectID ?? appModel.currentProjectID
    }

    private var projectMenuTitle: String {
        if projectIDs.isEmpty {
            return appModel.localized("未分配", "Unassigned")
        }
        if projectIDs.count == 1 {
            return appModel.projectName(for: projectIDs[0])
        }
        return appModel.localized("\(projectIDs.count) 个项目", "\(projectIDs.count) Projects")
    }

    private var disabledReason: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appModel.localized("请输入任务标题", "Enter a task title")
        }
        return nil
    }

    private func toggleProject(_ id: String) {
        if let index = projectIDs.firstIndex(of: id) {
            projectIDs.remove(at: index)
        } else {
            projectIDs.append(id)
        }
    }

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        if let editingTodo {
            title = editingTodo.title
            kind = editingTodo.kind
            startDate = editingTodo.startDate
            dueDate = editingTodo.dueDate
            priority = editingTodo.priority
            selectedTags = editingTodo.tags
            projectIDs = editingTodo.projectIDs
            notes = editingTodo.notes ?? ""
            relatedPaperIDs = editingTodo.relatedPaperIDs
        } else {
            projectIDs = scope.projectID.map { [$0] } ?? appModel.currentProjectID.map { [$0] } ?? []
            if case .selectedDate(let date) = scope {
                dueDate = date
            }
        }
    }

    private func save() {
        guard disabledReason == nil else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingTodo {
            appModel.updateTodo(
                editingTodo,
                title: title,
                kind: kind,
                status: editingTodo.status,
                startDate: startDate,
                dueDate: dueDate,
                priority: priority,
                notes: kind == .general ? trimmedNotes : editingTodo.notes,
                projectIDs: projectIDs,
                tags: selectedTags,
                relatedPaperIDs: relatedPaperIDs
            )
        } else {
            appModel.addTodo(
                title: title,
                startDate: startDate,
                dueDate: dueDate,
                kind: kind,
                priority: priority,
                notes: kind == .general ? trimmedNotes : nil,
                projectIDs: projectIDs,
                tags: selectedTags,
                relatedPaperIDs: relatedPaperIDs
            )
        }
        dismiss()
    }
}

/// Scope used to seed composer defaults.
enum TodoComposerScope {
    case global
    case currentProject(String?)
    case selectedDate(Date)

    var projectID: String? {
        if case .currentProject(let id) = self { return id }
        return nil
    }
}

#if DEBUG
#Preview("Task Composer") {
    TaskComposerView(scope: .global)
        .environmentObject(AppViewModel())
}
#endif
