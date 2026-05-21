import AppKit
import SwiftUI

struct ShellRightRailView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    @ViewBuilder
    var body: some View {
        if let workspace {
            Group {
                switch appModel.effectiveRightRailMode {
                case .inspector:
                    ContextInspectorRail(workspace: workspace)
                case .ai:
                    GlobalAISidePanel(workspace: workspace, context: appModel.currentWorkspaceContextSnapshot)
                case .hidden:
                    EmptyView()
                }
            }
            .background(ShellRailBackground())
        } else {
            EmptyRightRailView()
        }
    }
}

struct ContextInspectorRail: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        VStack(spacing: 0) {
            ShellRailHeader(
                title: inspectorTitle,
                subtitle: appModel.currentWorkspaceContextSnapshot.displayTitle
            )

            Divider()

            inspectorBody
        }
    }

    @ViewBuilder
    private var inspectorBody: some View {
        if shouldShowPaperInspector {
            PaperInspectorView(workspace: workspace)
        } else if shouldShowWikiInspector {
            WikiInspectorView(workspace: workspace)
        } else if appModel.selectedSection == .pdfReader || appModel.currentWorkspaceContextSnapshot.projectTabID == "pdf-reader" {
            PDFReaderContextRail(workspace: workspace)
        } else {
            ContextActionsRail(workspace: workspace)
        }
    }

    private var inspectorTitle: String {
        if shouldShowPaperInspector { return appModel.localized("论文检查器", "Paper Inspector") }
        if shouldShowWikiInspector { return appModel.localized("Wiki 检查器", "Wiki Inspector") }
        if appModel.selectedSection == .pdfReader || appModel.currentWorkspaceContextSnapshot.projectTabID == "pdf-reader" {
            return appModel.localized("PDF 上下文", "PDF Context")
        }
        return appModel.localized("上下文", "Context")
    }

    private var shouldShowPaperInspector: Bool {
        appModel.selectedSection == .library || appModel.currentWorkspaceContextSnapshot.projectTabID == "papers"
    }

    private var shouldShowWikiInspector: Bool {
        appModel.selectedSection == .wiki || appModel.currentWorkspaceContextSnapshot.projectTabID == "wiki"
    }
}

struct GlobalAISidePanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let context: WorkspaceContextSnapshot

    var body: some View {
        VStack(spacing: 0) {
            ShellRailHeader(
                title: "AI",
                subtitle: context.displayTitle
            )

            GlobalAIContextActionBar(context: context)

            AgentPanelView(workspace: workspace, isCompact: true)
        }
    }
}

private struct ShellRailHeader: View {
    let title: String
    let subtitle: String

    // The rail's open/close + AI affordances are owned by the window toolbar
    // (see `ContentView`'s Inspector / AI toolbar buttons, which toggle the
    // rail in place). Keeping a second set of buttons inside the rail header
    // produced two visually-identical collapse/AI controls — see Bug Bash 2026-05-17.
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ContextActionsRail: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                compactContextBlock

                Button {
                    appModel.openGlobalAIPanel(source: "context_action")
                } label: {
                    Label(
                        appModel.localized("询问当前视图", "Ask About View"),
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.refreshCurrentWorkspaceView()
                } label: {
                    Label(appModel.t(.toolbarRefresh), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if appModel.selectedSection == .projects {
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                        Label(appModel.t(.toolbarNewProject), systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                if appModel.selectedSection == .calendar || appModel.selectedSection == .tasks {
                    Button {
                        appModel.selectGlobalTodos()
                    } label: {
                        Label(appModel.t(.toolbarAllTodos), systemImage: "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    appModel.revealCurrentWorkspaceInFinder()
                } label: {
                    Label(appModel.t(.toolbarRevealInFinder), systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appModel.currentWorkspaceContextSnapshot.topLevelSectionID)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(appModel.currentWorkspaceContextSnapshot.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(workspace.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum PDFContextPanel: String, CaseIterable, Identifiable {
    case paper
    case notes
    case tasks
    case citations
    case files
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "Paper"
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .citations: return "Citations"
        case .files: return "Files"
        case .ai: return "AI"
        }
    }
}

private struct PDFReaderContextRail: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var selectedPanel = PDFContextPanel.notes
    @State private var annotationSearchText = ""
    @State private var pendingDelete: PDFAnnotationRecord?
    @State private var newTaskTitle = ""
    @State private var newTaskHasDueDate = false
    @State private var newTaskDueDate = Calendar.current.startOfDay(for: Date())
    @State private var newTaskPriority = Priority.medium
    @State private var newTaskNotes = ""
    @State private var selectedCitationFormat = CitationFormat.bibTeX

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("PDF Context", selection: $selectedPanel) {
                    ForEach(PDFContextPanel.allCases) { panel in
                        Text(panel.title).tag(panel)
                    }
                }
                .pickerStyle(.segmented)

                if let paper = appModel.selectedPaperDraft {
                    switch selectedPanel {
                    case .paper:
                        paperPanel(paper)
                    case .notes:
                        notesPanel(paper)
                    case .tasks:
                        tasksPanel(paper)
                    case .citations:
                        citationsPanel(paper)
                    case .files:
                        filesPanel(paper)
                    case .ai:
                        aiPanel
                    }
                } else {
                    ContentUnavailableView("No PDF selected", systemImage: "doc.viewfinder", description: Text("Open a paper in the PDF reader to inspect notes, tasks, citations, and files."))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Delete PDF annotation?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    appModel.deletePDFAnnotation(id: pendingDelete.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sidecar record and in-memory PDF overlay will be removed.")
        }
    }

    private func paperPanel(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(paper.displayTitle, systemImage: "doc.richtext")
                .font(.headline)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button {
                    appModel.focusSearchForCurrentSection()
                } label: {
                    Label("Search PDF", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.openGlobalAIPanel(source: "pdf_context")
                } label: {
                    Label("Ask", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            metadataSection(rows: [
                ("Authors", paper.authorsDisplay),
                ("Publication", paper.publicationDisplay),
                ("Date", paper.publishedDate ?? paper.yearText),
                ("Status", paper.status.label),
                ("Priority", paper.priority.label),
                ("Tags", paper.tagsDisplay),
                ("DOI", paper.doi),
                ("arXiv", paper.arxiv),
                ("Citekey", paper.citekey)
            ])

            if let abstract = paper.abstract?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty {
                Divider()
                Text("Abstract")
                    .font(.subheadline.weight(.semibold))
                Text(abstract)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private func notesPanel(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selection = appModel.selectedPDFSelectionPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Selection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(selection)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            TextField("Search PDF marks", text: $annotationSearchText)
                .textFieldStyle(.roundedBorder)

            if filteredAnnotations.isEmpty {
                ContentUnavailableView("No PDF marks", systemImage: "highlighter", description: Text("Highlight text, underline a passage, or add a note from the PDF toolbar."))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredAnnotations) { annotation in
                        annotationRow(annotation)
                    }
                }
            }
        }
    }

    private func annotationRow(_ annotation: PDFAnnotationRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Page \(annotation.pageIndex + 1)", systemImage: systemImage(for: annotation.kind))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    appModel.requestPDFReaderGoToPage(annotation.pageIndex)
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .buttonStyle(.borderless)
                .help("Jump to mark")

                Button(role: .destructive) {
                    pendingDelete = annotation
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete mark")
            }

            if !annotation.selectedTextPreview.isEmpty {
                Text(annotation.selectedTextPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            TextField("Note", text: noteBinding(for: annotation))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.10), lineWidth: 0.6))
    }

    private func tasksPanel(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Task title", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReaderTask)

                HStack(spacing: 10) {
                    Toggle("Due date", isOn: $newTaskHasDueDate)
                        .toggleStyle(.checkbox)
                    if newTaskHasDueDate {
                        DatePicker("Due", selection: $newTaskDueDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Picker("Priority", selection: $newTaskPriority) {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 132)
                }
                .controlSize(.small)

                TextField("Notes", text: $newTaskNotes)
                    .textFieldStyle(.roundedBorder)

                Button(action: addReaderTask) {
                    Label("Add Task", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTaskTitleEmpty)

                if isTaskTitleEmpty {
                    Text("Enter a task title to add a reading task for this paper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Divider()

            if relatedTodos(for: paper).isEmpty {
                ContentUnavailableView("No linked tasks", systemImage: "checklist", description: Text("Create a task here to connect it to this paper."))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(relatedTodos(for: paper)) { todo in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(todo.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(2)
                            Text([todo.status.label, todo.priority.label, todo.dueDate?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " - "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func citationsPanel(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Format", selection: $selectedCitationFormat) {
                ForEach(CitationFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.menu)

            ScrollView {
                Text(BibTeXFormatter.citation(for: paper, format: selectedCitationFormat))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 220)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BibTeXFormatter.citation(for: paper, format: selectedCitationFormat), forType: .string)
                }
                    .buttonStyle(.bordered)
                Button("Export BibTeX") { appModel.exportBibTeX(for: paper) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCitationFormat != .bibTeX)
            }
        }
    }

    private func filesPanel(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataSection(rows: [
                ("Folder", paper.paperDirectoryRelativePath),
                ("PDF", paper.pdfRelativePath),
                ("Markdown", "paper.md"),
                ("Summary", paper.notesSummaryRelativePath),
                ("Annotations", paper.annotationsRelativePath),
                ("Last Page", paper.lastReadPage.map(String.init))
            ])

            ForEach(paperLinks(for: paper)) { link in
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    Label(link.label, systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlobalAIContextActionBar(context: appModel.currentWorkspaceContextSnapshot)
            AgentPanelView(workspace: workspace, isCompact: true)
                .frame(minHeight: 520)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredAnnotations: [PDFAnnotationRecord] {
        let query = annotationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.selectedPDFAnnotations
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.pageIndex < rhs.pageIndex
            }
            .filter { annotation in
                guard !query.isEmpty else { return true }
                return annotation.selectedTextPreview.lowercased().contains(query)
                    || annotation.noteText?.lowercased().contains(query) == true
                    || annotation.kind.rawValue.contains(query)
            }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    private var isTaskTitleEmpty: Bool {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func noteBinding(for annotation: PDFAnnotationRecord) -> Binding<String> {
        Binding(
            get: { appModel.selectedPDFAnnotations.first(where: { $0.id == annotation.id })?.noteText ?? "" },
            set: { appModel.updatePDFAnnotationNote(id: annotation.id, noteText: $0) }
        )
    }

    private func addReaderTask() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let noteText = newTaskNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        appModel.addTodo(
            title: trimmedTitle,
            dueDate: newTaskHasDueDate ? newTaskDueDate : nil,
            priority: newTaskPriority,
            notes: noteText.isEmpty ? "Created while reading \(appModel.selectedPaperDraft?.citekey ?? "the selected paper")." : noteText
        )
        newTaskTitle = ""
        newTaskNotes = ""
    }

    private func relatedTodos(for paper: Paper) -> [TodoItem] {
        appModel.todos.filter { $0.relatedPaperIDs.contains(paper.id) }
    }

    private func metadataSection(rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.filter { row in
                guard let text = row.1?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !text.isEmpty && text != "-"
            }, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value ?? "")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func systemImage(for kind: PDFAnnotationRecord.Kind) -> String {
        switch kind {
        case .highlight:
            return "highlighter"
        case .underline:
            return "underline"
        case .note:
            return "note.text"
        }
    }

    private func paperLinks(for paper: Paper) -> [PDFContextExternalLink] {
        [
            ("DOI", doiURL(for: paper)),
            ("arXiv", arxivURL(for: paper)),
            ("INSPIRE", inspireURL(for: paper)),
            ("URL", url(from: paper.url)),
            ("PDF URL", url(from: paper.pdfURL))
        ]
        .compactMap { label, url in
            guard let url else { return nil }
            return PDFContextExternalLink(label: label, url: url)
        }
    }

    private func doiURL(for paper: Paper) -> URL? {
        guard let doi = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty else {
            return nil
        }
        return url(from: doi) ?? URL(string: "https://doi.org/\(doi)")
    }

    private func arxivURL(for paper: Paper) -> URL? {
        guard let arxiv = paper.arxiv?.trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty else {
            return nil
        }
        return URL(string: "https://arxiv.org/abs/\(arxiv)")
    }

    private func inspireURL(for paper: Paper) -> URL? {
        guard let inspireID = paper.inspireID?.trimmingCharacters(in: .whitespacesAndNewlines), !inspireID.isEmpty else {
            return nil
        }
        return URL(string: "https://inspirehep.net/literature/\(inspireID)")
    }

    private func url(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }
        if value.contains("."), let url = URL(string: "https://\(value)") {
            return url
        }
        return nil
    }
}

private struct PDFContextExternalLink: Identifiable {
    let label: String
    let url: URL

    var id: String { label }
}

struct GlobalAIContextActionBar: View {
    @EnvironmentObject private var appModel: AppViewModel

    let context: WorkspaceContextSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedTextPreview = context.selectedTextPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected text from page \(context.pdfPageIndex.map(String.init) ?? "-")")
                        .font(.caption.weight(.semibold))
                    Text(selectedTextPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        appModel.agentGoal = "Ask about this view.\n\n\(promptContext)"
                    } label: {
                        Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                    }

                    Button {
                        appModel.agentGoal = "Summarize the current selection.\n\n\(promptContext)"
                    } label: {
                        Label("Summarize", systemImage: "text.quote")
                    }
                    .disabled(context.selectedTextPreview == nil)

                    Button {
                        appModel.agentGoal = "Draft a todo from the current selection. Do not write it yet.\n\n\(promptContext)"
                    } label: {
                        Label("Todo Draft", systemImage: "checklist")
                    }
                    .disabled(context.selectedTextPreview == nil)
                }
                .font(.caption)
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.68)
            Color.secondary.opacity(0.045)
        }
    }

    private var promptContext: String {
        var lines = ["Context: \(context.displayTitle)"]
        if let page = context.pdfPageIndex {
            lines.append("PDF page: \(page)")
        }
        if let path = context.selectedPaperMarkdownPath {
            lines.append("paper.md path: \(path)")
        }
        if let selectedText = context.selectedTextPreview {
            lines.append("Selected text preview:\n\(selectedText)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct EmptyRightRailView: View {
    var body: some View {
        ShellRailBackground()
    }
}

private struct ShellRailBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.secondary.opacity(0.055)
        }
    }
}