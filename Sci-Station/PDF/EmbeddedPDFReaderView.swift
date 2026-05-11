import PDFKit
import SwiftUI

struct EmbeddedPDFReaderView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let pdfURL: URL
    let workspace: ResearchWorkspace
    let paper: Paper
    let initialPage: Int?
    let initialScaleFactor: Double?
    let onReadingStateChanged: (Int, Double?) -> Void
    let onBackToLibrary: () -> Void
    let onOpenExternal: () -> Void

    @StateObject private var viewModel: PDFReaderViewModel
    @State private var isShowingSearch = false
    @State private var isShowingNoteDialog = false
    @State private var noteDraft = ""
    @FocusState private var focusedField: PDFReaderFocusedField?

    init(
        pdfURL: URL,
        workspace: ResearchWorkspace,
        paper: Paper,
        initialPage: Int?,
        initialScaleFactor: Double?,
        onReadingStateChanged: @escaping (Int, Double?) -> Void,
        onBackToLibrary: @escaping () -> Void,
        onOpenExternal: @escaping () -> Void
    ) {
        self.pdfURL = pdfURL
        self.workspace = workspace
        self.paper = paper
        self.initialPage = initialPage
        self.initialScaleFactor = initialScaleFactor
        self.onReadingStateChanged = onReadingStateChanged
        self.onBackToLibrary = onBackToLibrary
        self.onOpenExternal = onOpenExternal
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(initialPage: initialPage, initialScaleFactor: initialScaleFactor))
    }

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar

            if isShowingSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search PDF", text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(viewModel.submitSearch)
                        .focused($focusedField, equals: .search)
                    Button("Find", action: viewModel.findNext)
                        .buttonStyle(.bordered)
                    Button("Next", action: viewModel.findNext)
                        .buttonStyle(.bordered)
                    Button("Previous", action: viewModel.findPrevious)
                        .buttonStyle(.bordered)
                    Button {
                        isShowingSearch = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Close search")
                    .accessibilityLabel("Close PDF search")
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.06))

                if let searchStatusMessage = viewModel.searchStatusMessage {
                    Text(searchStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }

            PDFKitViewRepresentable(
                pdfURL: pdfURL,
                paperID: paper.id,
                annotations: appModel.selectedPDFAnnotations,
                viewModel: viewModel,
                onReadingStateChanged: onReadingStateChanged,
                onSelectionChanged: appModel.updatePDFSelection(preview:pageIndex:),
                onCreateAnnotation: appModel.createPDFAnnotation,
                onDeleteAnnotation: appModel.deletePDFAnnotation(id:),
                onMoveNoteAnnotation: appModel.movePDFAnnotationNote(id:pageIndex:x:y:)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(pdfURL.path)
        .onChange(of: appModel.pdfReaderSearchFocusRequest) { _, _ in
            showAndFocusSearch()
        }
        .onChange(of: appModel.pdfReaderFindNextRequest) { _, _ in
            showAndFocusSearch()
            viewModel.findNext()
        }
        .onChange(of: appModel.pdfReaderFindPreviousRequest) { _, _ in
            showAndFocusSearch()
            viewModel.findPrevious()
        }
        .onChange(of: appModel.pdfReaderGoToPageRequest) { _, _ in
            if let pageIndex = appModel.pdfReaderRequestedPageIndex {
                viewModel.goToPage(pageIndex + 1)
            }
        }
        .task(id: paper.id) {
            appModel.reloadSelectedPDFAnnotations()
            appModel.updatePDFSelection(preview: nil, pageIndex: paper.lastReadPage)
        }
        .sheet(isPresented: $isShowingNoteDialog) {
            PDFNoteDialog(noteText: $noteDraft) {
                viewModel.createNoteAnnotation(noteText: noteDraft)
                noteDraft = ""
                isShowingNoteDialog = false
            } cancel: {
                noteDraft = ""
                isShowingNoteDialog = false
            }
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 10) {
            Button(action: onBackToLibrary) {
                Image(systemName: "chevron.left")
            }
            .help("Back to Library")
            .accessibilityLabel("Back to Library")

            Divider()
                .frame(height: 22)

            Button(action: viewModel.goToPreviousPage) {
                Image(systemName: "chevron.up")
            }
            .help("Previous page")
            .accessibilityLabel("Previous PDF page")

            Button(action: viewModel.goToNextPage) {
                Image(systemName: "chevron.down")
            }
            .help("Next page")
            .accessibilityLabel("Next PDF page")

            TextField("Page", text: $viewModel.pageInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .onSubmit(viewModel.submitPageInput)

            Text("/ \(max(viewModel.totalPages, 1))")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 22)

            Button(action: viewModel.goBack) {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Back to previous PDF location")
            .accessibilityLabel("Back to previous PDF location")

            Button(action: viewModel.goForward) {
                Image(systemName: "arrow.uturn.forward")
            }
            .help("Forward to next PDF location")
            .accessibilityLabel("Forward to next PDF location")

            Divider()
                .frame(height: 22)

            Button {
                if isShowingSearch {
                    isShowingSearch = false
                } else {
                    showAndFocusSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search PDF")
            .keyboardShortcut("f", modifiers: [.command])
            .accessibilityLabel("Search PDF")

            Button(action: viewModel.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .accessibilityLabel("Zoom out")

            Button(action: viewModel.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .accessibilityLabel("Zoom in")

            Button(action: viewModel.fitToWidth) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit page")
            .accessibilityLabel("Fit page")

            Divider()
                .frame(height: 22)

            Button(action: viewModel.toggleHighlightAnnotationMode) {
                Image(systemName: "highlighter")
            }
            .foregroundStyle(viewModel.activeTextAnnotationMode == .highlight ? Color.accentColor : Color.primary)
            .help(viewModel.activeTextAnnotationMode == .highlight ? "Highlight mode active" : "Highlight selected text or enable highlight mode")
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .accessibilityLabel("Highlight PDF selection")

            Button(action: viewModel.toggleUnderlineAnnotationMode) {
                Image(systemName: "underline")
            }
            .foregroundStyle(viewModel.activeTextAnnotationMode == .underline ? Color.accentColor : Color.primary)
            .help(viewModel.activeTextAnnotationMode == .underline ? "Underline mode active" : "Underline selected text or enable underline mode")
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .accessibilityLabel("Underline PDF selection")

            Button {
                isShowingNoteDialog = true
            } label: {
                Image(systemName: "note.text.badge.plus")
            }
            .help("Add note")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel("Add PDF note")

            Spacer(minLength: 8)

            Button(action: onOpenExternal) {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open in default viewer")
            .accessibilityLabel("Open PDF in default viewer")

            Button {
                if appModel.effectiveRightRailMode == .inspector {
                    appModel.hideRightRail(source: "pdf_toolbar")
                } else {
                    appModel.showContextInspector(source: "pdf_toolbar")
                }
            } label: {
                Image(systemName: appModel.effectiveRightRailMode == .inspector ? "sidebar.trailing" : "sidebar.right")
            }
            .help("Toggle PDF inspector")
            .accessibilityLabel("Toggle PDF inspector")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func showAndFocusSearch() {
        isShowingSearch = true
        DispatchQueue.main.async {
            focusedField = .search
        }
    }
}

private enum PDFReaderFocusedField {
    case search
}

private struct PDFNoteDialog: View {
    @Binding var noteText: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PDF Note")
                .font(.headline)
            TextEditor(text: $noteText)
                .font(.body)
                .frame(width: 360, height: 140)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }
}

private enum PDFReaderSidebarPanel: CaseIterable, Identifiable {
    case metadata
    case notes
    case tasks
    case citations
    case links
    case abstract
    case files
    case ai

    var id: Self { self }

    var title: String {
        switch self {
        case .metadata:
            return "Metadata"
        case .notes:
            return "Notes"
        case .tasks:
            return "Tasks"
        case .citations:
            return "Citations"
        case .abstract:
            return "Abstract"
        case .links:
            return "Links"
        case .files:
            return "Files"
        case .ai:
            return "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .metadata:
            return "info.circle"
        case .notes:
            return "square.and.pencil"
        case .tasks:
            return "checklist"
        case .citations:
            return "quote.bubble"
        case .abstract:
            return "doc.text"
        case .links:
            return "link"
        case .files:
            return "folder"
        case .ai:
            return "sparkles"
        }
    }
}

private struct PDFReaderSideRail: View {
    @Binding var activePanel: PDFReaderSidebarPanel?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(PDFReaderSidebarPanel.allCases) { panel in
                Button {
                    activePanel = activePanel == panel ? nil : panel
                } label: {
                    Image(systemName: panel.systemImage)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(activePanel == panel ? Color.accentColor : Color.secondary)
                .help(panel.title)
                .accessibilityLabel(panel.title)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 48)
        .background(Color.secondary.opacity(0.05))
    }
}

private struct PDFReaderMetadataPanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let paper: Paper
    let panel: PDFReaderSidebarPanel
    @ObservedObject var viewModel: PDFReaderViewModel
    @State private var newTaskTitle = ""
    @State private var newTaskHasDueDate = false
    @State private var newTaskDueDate = Calendar.current.startOfDay(for: Date())
    @State private var newTaskPriority = Priority.medium
    @State private var activeNotesTab = PDFReaderNotesTab.pdfMarks
    @State private var annotationSearchQuery = ""
    @State private var pendingAnnotationDelete: PDFAnnotationRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(panel.title)
                    .font(.headline)

                switch panel {
                case .metadata:
                    metadataRows
                case .notes:
                    notesPanel
                case .tasks:
                    tasksPanel
                case .citations:
                    citationsPanel
                case .abstract:
                    Text(paper.abstract ?? "No abstract saved.")
                        .font(.callout)
                        .foregroundStyle(paper.abstract == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                case .links:
                    linksPanel
                case .files:
                    metadataSection(rows: [
                        ("Folder", paper.paperDirectoryRelativePath),
                        ("PDF", paper.pdfRelativePath),
                        ("Markdown", "paper.md"),
                        ("Summary", paper.notesSummaryRelativePath),
                        ("Annotations", paper.annotationsRelativePath),
                        ("Last Page", paper.lastReadPage.map(String.init))
                    ])
                case .ai:
                    aiPanel
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .confirmationDialog("Delete PDF annotation?", isPresented: annotationDeleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let pendingAnnotationDelete {
                    appModel.deletePDFAnnotation(id: pendingAnnotationDelete.id)
                }
                pendingAnnotationDelete = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sidecar record and in-memory PDF overlay will be removed.")
        }
    }

    private var metadataRows: some View {
        metadataSection(rows: [
            ("Title", paper.displayTitle),
            ("Title Translation", paper.titleTranslation),
            ("Short Title", paper.shortTitle),
            ("Authors", paper.authorsDisplay),
            ("Item Type", paper.itemType),
            ("Publication", paper.publicationDisplay),
            ("Publisher", paper.publisher),
            ("Place", paper.publicationPlace),
            ("Date", paper.publishedDate ?? paper.yearText),
            ("Volume", paper.volume),
            ("Issue", paper.issue),
            ("Pages", paper.pages),
            ("Journal Abbr.", paper.journalAbbreviation),
            ("ISSN", paper.issn),
            ("Archive", paper.archive),
            ("Archive Location", paper.archiveLocation),
            ("Language", paper.language),
            ("Catalog", paper.libraryCatalog),
            ("Call Number", paper.callNumber),
            ("Citekey", paper.citekey),
            ("Tags", paper.tagsDisplay),
            ("Status", paper.status.label),
            ("Priority", paper.priority.label),
            ("Rating", paper.ratingText)
        ])
    }

    private var annotationDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingAnnotationDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAnnotationDelete = nil
                }
            }
        )
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Notes", selection: $activeNotesTab) {
                ForEach(PDFReaderNotesTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch activeNotesTab {
            case .pdfMarks:
                pdfMarksPanel
            case .paperNotes:
                paperNotesPanel
            }
        }
    }

    private var paperNotesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $appModel.selectedPaperAnnotationsDraft)
                .font(.body)
                .frame(minHeight: 260)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Button("Save Notes", action: appModel.saveSelectedPaperAnnotations)
                    .buttonStyle(.borderedProminent)
                if appModel.isSavingSelectedPaperAnnotations {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var pdfMarksPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search PDF marks", text: $annotationSearchQuery)
                .textFieldStyle(.roundedBorder)

            if filteredPDFAnnotations.isEmpty {
                Text("No PDF marks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredPDFAnnotations) { annotation in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label("Page \(annotation.pageIndex + 1)", systemImage: annotation.kind.systemImage)
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 0)
                            Button {
                                viewModel.goToPage(annotation.pageIndex + 1)
                            } label: {
                                Image(systemName: "arrow.turn.down.right")
                            }
                            .buttonStyle(.borderless)
                            .help("Jump to page")

                            Button(role: .destructive) {
                                pendingAnnotationDelete = annotation
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete annotation")
                        }

                        if !annotation.selectedTextPreview.isEmpty {
                            Text(annotation.selectedTextPreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }

                        if let noteText = annotation.noteText, !noteText.isEmpty {
                            Text(noteText)
                                .font(.caption.weight(.medium))
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }

                        TextField("Note", text: noteBinding(for: annotation))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var filteredPDFAnnotations: [PDFAnnotationRecord] {
        let query = annotationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private func noteBinding(for annotation: PDFAnnotationRecord) -> Binding<String> {
        Binding(
            get: {
                appModel.selectedPDFAnnotations.first(where: { $0.id == annotation.id })?.noteText ?? ""
            },
            set: { appModel.updatePDFAnnotationNote(id: annotation.id, noteText: $0) }
        )
    }

    private var tasksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task title", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addReaderTask)

            HStack(spacing: 10) {
                Toggle("Due", isOn: $newTaskHasDueDate)
                    .toggleStyle(.checkbox)
                DatePicker("Due Date", selection: $newTaskDueDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!newTaskHasDueDate)
            }
            .controlSize(.small)

            Picker("Priority", selection: $newTaskPriority) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Text(priority.label).tag(priority)
                }
            }
            .pickerStyle(.segmented)

            Button("Add Task", action: addReaderTask)
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()

            if relatedTodos.isEmpty {
                Text("No tasks linked to this paper.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relatedTodos) { todo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todo.title)
                            .fontWeight(.medium)
                        Text([todo.status.label, todo.priority.label, todo.dueDate?.formatted(date: .abbreviated, time: .omitted)]
                            .compactMap { $0 }
                            .joined(separator: "  ·  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlobalAIContextActionBar(context: appModel.currentWorkspaceContextSnapshot)
            AgentPanelView(workspace: workspace)
                .frame(minHeight: 520)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var citationsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(bibTeXText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 220)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Button("Copy") {
                    appModel.copyBibTeX(for: paper)
                }
                .buttonStyle(.bordered)

                Button("Export") {
                    appModel.exportBibTeX(for: paper)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var linksPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if paperLinks.isEmpty {
                Text("No external links saved.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paperLinks) { link in
                    Button {
                        NSWorkspace.shared.open(link.url)
                    } label: {
                        Label(link.label, systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }

            metadataSection(rows: [
                ("Wiki", paper.notesSummaryRelativePath),
                ("Backlinks", emptyToNil(appModel.markdownDocuments.filter { document in
                    document.outgoingLinks.contains { link in
                        link.normalizedTarget == WikiLink.normalizePageKey(paper.citekey)
                    }
                }.map(\.title).joined(separator: ", ")))
            ])
        }
    }

    private var relatedTodos: [TodoItem] {
        appModel.todos.filter { $0.relatedPaperIDs.contains(paper.id) }
    }

    private var bibTeXText: String {
        BibTeXFormatter.bibTeX(for: paper)
    }

    private var paperLinks: [PDFReaderExternalLink] {
        [
            ("DOI", doiURL),
            ("arXiv", arxivURL),
            ("INSPIRE", inspireURL),
            ("URL", url(from: paper.url)),
            ("PDF URL", url(from: paper.pdfURL))
        ]
        .compactMap { label, url in
            guard let url else { return nil }
            return PDFReaderExternalLink(label: label, url: url)
        }
    }

    private var doiURL: URL? {
        guard let doi = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty else {
            return nil
        }
        return url(from: doi) ?? URL(string: "https://doi.org/\(doi)")
    }

    private var arxivURL: URL? {
        guard let arxiv = paper.arxiv?.trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty else {
            return nil
        }
        return URL(string: "https://arxiv.org/abs/\(arxiv)")
    }

    private var inspireURL: URL? {
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

    private func addReaderTask() {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        appModel.addTodo(
            title: trimmedTitle,
            dueDate: newTaskHasDueDate ? newTaskDueDate : nil,
            priority: newTaskPriority,
            notes: "Created while reading \(paper.citekey)."
        )
        newTaskTitle = ""
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func metadataSection(rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.filter { value in
                guard let text = value.1 else {
                    return false
                }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != "-"
            }, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value ?? "")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct PDFReaderExternalLink: Identifiable {
    let label: String
    let url: URL

    var id: String {
        label
    }
}

private enum PDFReaderNotesTab: String, CaseIterable, Identifiable {
    case pdfMarks
    case paperNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdfMarks:
            return "PDF Marks"
        case .paperNotes:
            return "Paper Notes"
        }
    }
}

private extension PDFAnnotationRecord.Kind {
    var systemImage: String {
        switch self {
        case .highlight:
            return "highlighter"
        case .underline:
            return "underline"
        case .note:
            return "note.text"
        }
    }
}

private final class SciStationPDFView: PDFView {
    var overlayContentsPrefix = "sci-station-pdf-mark:"
    var deleteAnnotationHandler: ((String) -> Void)?
    var moveNoteAnnotationHandler: ((String, Int, Double, Double) -> Void)?

    private var draggedNote: (annotation: PDFAnnotation, id: String, page: PDFPage, offset: CGPoint)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = overlayHit(for: event) else {
            return super.menu(for: event)
        }

        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "Delete PDF Mark", action: #selector(deletePDFMark(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = hit.metadata.id
        menu.addItem(deleteItem)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        if let hit = overlayHit(for: event), hit.metadata.kind == PDFAnnotationRecord.Kind.note.rawValue {
            let bounds = hit.annotation.bounds
            let offset = CGPoint(x: hit.pagePoint.x - bounds.minX, y: hit.pagePoint.y - bounds.minY)
            draggedNote = (hit.annotation, hit.metadata.id, hit.page, offset)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draggedNote,
              let pagePoint = pagePoint(for: event, page: draggedNote.page) else {
            super.mouseDragged(with: event)
            return
        }

        let size = draggedNote.annotation.bounds.size
        let origin = CGPoint(x: pagePoint.x - draggedNote.offset.x, y: pagePoint.y - draggedNote.offset.y)
        draggedNote.annotation.bounds = CGRect(origin: origin, size: size)
        draggedNote.page.removeAnnotation(draggedNote.annotation)
        draggedNote.page.addAnnotation(draggedNote.annotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let draggedNote else {
            super.mouseUp(with: event)
            return
        }

        let pageIndex = document?.index(for: draggedNote.page) ?? -1
        if pageIndex >= 0 {
            let origin = draggedNote.annotation.bounds.origin
            moveNoteAnnotationHandler?(draggedNote.id, pageIndex, Double(origin.x), Double(origin.y))
        }
        self.draggedNote = nil
    }

    @objc private func deletePDFMark(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        deleteAnnotationHandler?(id)
    }

    private func overlayHit(for event: NSEvent) -> (annotation: PDFAnnotation, page: PDFPage, pagePoint: CGPoint, metadata: (kind: String?, id: String))? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true),
              let pagePoint = pagePoint(for: event, page: page),
              let annotation = page.annotation(at: pagePoint),
              let metadata = overlayMetadata(for: annotation) else {
            return nil
        }
        return (annotation, page, pagePoint, metadata)
    }

    private func pagePoint(for event: NSEvent, page: PDFPage) -> CGPoint? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return convert(viewPoint, to: page)
    }

    private func overlayMetadata(for annotation: PDFAnnotation) -> (kind: String?, id: String)? {
        guard let userName = annotation.userName,
              userName.hasPrefix(overlayContentsPrefix) else {
            if let contents = annotation.contents, contents.hasPrefix(overlayContentsPrefix) {
                return (nil, String(contents.dropFirst(overlayContentsPrefix.count)))
            }
            return nil
        }

        let payload = String(userName.dropFirst(overlayContentsPrefix.count))
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (nil, payload)
    }
}

private struct PDFKitViewRepresentable: NSViewRepresentable {
    let pdfURL: URL
    let paperID: String
    let annotations: [PDFAnnotationRecord]
    @ObservedObject var viewModel: PDFReaderViewModel
    let onReadingStateChanged: (Int, Double?) -> Void
    let onSelectionChanged: (String?, Int?) -> Void
    let onCreateAnnotation: (PDFAnnotationRecord) -> Void
    let onDeleteAnnotation: (PDFAnnotationRecord.ID) -> Void
    let onMoveNoteAnnotation: (PDFAnnotationRecord.ID, Int, Double, Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            onReadingStateChanged: onReadingStateChanged,
            onSelectionChanged: onSelectionChanged,
            onCreateAnnotation: onCreateAnnotation,
            onDeleteAnnotation: onDeleteAnnotation,
            onMoveNoteAnnotation: onMoveNoteAnnotation
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = SciStationPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.delegate = context.coordinator
        pdfView.overlayContentsPrefix = context.coordinator.overlayContentsPrefix
        pdfView.deleteAnnotationHandler = onDeleteAnnotation
        pdfView.moveNoteAnnotationHandler = onMoveNoteAnnotation
        context.coordinator.configure(pdfView: pdfView, pdfURL: pdfURL, paperID: paperID, annotations: annotations)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let pdfView = pdfView as? SciStationPDFView {
            pdfView.deleteAnnotationHandler = onDeleteAnnotation
            pdfView.moveNoteAnnotationHandler = onMoveNoteAnnotation
        }
        context.coordinator.configure(pdfView: pdfView, pdfURL: pdfURL, paperID: paperID, annotations: annotations)
        context.coordinator.handlePendingCommandIfNeeded(on: pdfView)
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        private let documentService = PDFDocumentService()
        private let viewModel: PDFReaderViewModel
        private let onReadingStateChanged: (Int, Double?) -> Void
        private let onSelectionChanged: (String?, Int?) -> Void
        private let onCreateAnnotation: (PDFAnnotationRecord) -> Void
        private let onDeleteAnnotation: (PDFAnnotationRecord.ID) -> Void
        private let onMoveNoteAnnotation: (PDFAnnotationRecord.ID, Int, Double, Double) -> Void
        private var loadedURL: URL?
        private var loadedPaperID: String?
        private var handledCommand: PDFReaderViewModel.Command?
        private weak var observedPDFView: PDFView?
        private var renderedAnnotationSignature: [String] = []
        private var pendingSelectionPreview: String?
        private var pendingSelectionPageIndex: Int?
        private var isSelectionPublishScheduled = false
        private var lastAutoAnnotationSignature: String?
        private var pendingAutoAnnotationSignature: String?
        private var pendingAutoAnnotationGeneration = 0
        let overlayContentsPrefix = "sci-station-pdf-mark:"

        init(
            viewModel: PDFReaderViewModel,
            onReadingStateChanged: @escaping (Int, Double?) -> Void,
            onSelectionChanged: @escaping (String?, Int?) -> Void,
            onCreateAnnotation: @escaping (PDFAnnotationRecord) -> Void,
            onDeleteAnnotation: @escaping (PDFAnnotationRecord.ID) -> Void,
            onMoveNoteAnnotation: @escaping (PDFAnnotationRecord.ID, Int, Double, Double) -> Void
        ) {
            self.viewModel = viewModel
            self.onReadingStateChanged = onReadingStateChanged
            self.onSelectionChanged = onSelectionChanged
            self.onCreateAnnotation = onCreateAnnotation
            self.onDeleteAnnotation = onDeleteAnnotation
            self.onMoveNoteAnnotation = onMoveNoteAnnotation
        }

        deinit {
            if let observedPDFView {
                NotificationCenter.default.removeObserver(self, name: .PDFViewSelectionChanged, object: observedPDFView)
            }
        }

        func configure(pdfView: PDFView, pdfURL: URL, paperID: String, annotations: [PDFAnnotationRecord]) {
            observeSelectionChanges(on: pdfView)

            if loadedURL != pdfURL || loadedPaperID != paperID {
                loadedURL = pdfURL
                loadedPaperID = paperID
                renderedAnnotationSignature = []
                pdfView.document = try? documentService.loadDocument(from: pdfURL)
                viewModel.totalPages = pdfView.document?.pageCount ?? 0

                if let initialPage = viewModel.initialPage,
                   let targetPage = pdfView.document?.page(at: max(initialPage - 1, 0)) {
                    pdfView.go(to: targetPage)
                }

                if let initialScaleFactor = viewModel.initialScaleFactor,
                   initialScaleFactor.isFinite,
                   initialScaleFactor > 0 {
                    pdfView.autoScales = false
                    pdfView.scaleFactor = initialScaleFactor
                }

                updatePageState(on: pdfView, notify: false)

                publishSelection(from: pdfView)
            }

            renderAnnotations(annotations, on: pdfView)
        }

        func handlePendingCommandIfNeeded(on pdfView: PDFView) {
            guard let command = viewModel.pendingCommand, handledCommand != command else {
                return
            }

            handledCommand = command

            switch command {
            case .next:
                pdfView.goToNextPage(nil)
            case .previous:
                pdfView.goToPreviousPage(nil)
            case .back:
                pdfView.goBack(nil)
            case .forward:
                pdfView.goForward(nil)
            case .zoomIn:
                pdfView.autoScales = false
                pdfView.zoomIn(nil)
            case .zoomOut:
                pdfView.autoScales = false
                pdfView.zoomOut(nil)
            case .fit:
                pdfView.autoScales = true
            case let .goToPage(page, _):
                if let targetPage = pdfView.document?.page(at: max(page - 1, 0)) {
                    pdfView.go(to: targetPage)
                }
            case let .search(query, _):
                performSearch(query, backwards: false, on: pdfView)
            case let .findNext(query, _):
                performSearch(query, backwards: false, on: pdfView)
            case let .findPrevious(query, _):
                performSearch(query, backwards: true, on: pdfView)
            case let .createAnnotation(kind, noteText, _):
                createAnnotation(kind: kind, noteText: noteText, on: pdfView)
            }

            updatePageState(on: pdfView, notify: true)
        }

        private func performSearch(_ query: String, backwards: Bool, on pdfView: PDFView) {
            var options: NSString.CompareOptions = [.caseInsensitive]
            if backwards {
                options.insert(.backwards)
            }

            guard let selection = pdfView.document?.findString(
                query,
                fromSelection: pdfView.currentSelection,
                withOptions: options
            ) else {
                viewModel.searchStatusMessage = "No matches for \"\(query)\"."
                return
            }

            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.scrollSelectionToVisible(nil)
            viewModel.searchStatusMessage = "Match found."
            publishSelection(from: pdfView)
        }

        @objc private func pdfSelectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else {
                return
            }
            publishSelection(from: pdfView)
        }

        private func observeSelectionChanges(on pdfView: PDFView) {
            guard observedPDFView !== pdfView else {
                return
            }
            if let observedPDFView {
                NotificationCenter.default.removeObserver(self, name: .PDFViewSelectionChanged, object: observedPDFView)
            }
            observedPDFView = pdfView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfSelectionChanged(_:)),
                name: .PDFViewSelectionChanged,
                object: pdfView
            )
        }

        private func publishSelection(from pdfView: PDFView) {
            let selectionText = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = selectionText?.isEmpty == false ? Self.limitedText(selectionText ?? "", maxCharacters: 800) : nil
            let pageIndex: Int?
            if let page = pdfView.currentSelection?.pages.first, let document = pdfView.document {
                pageIndex = document.index(for: page) + 1
            } else if let page = pdfView.currentPage, let document = pdfView.document {
                pageIndex = document.index(for: page) + 1
            } else {
                pageIndex = nil
            }

            pendingSelectionPreview = preview
            pendingSelectionPageIndex = pageIndex
            scheduleAutoCreateAnnotationIfNeeded(on: pdfView)
            guard !isSelectionPublishScheduled else {
                return
            }

            isSelectionPublishScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSelectionPublishScheduled = false
                let preview = self.pendingSelectionPreview
                let pageIndex = self.pendingSelectionPageIndex
                self.viewModel.updateSelection(preview: preview, pageIndex: pageIndex)
                self.onSelectionChanged(preview, pageIndex)
            }
        }

        private func createAnnotation(kind: PDFAnnotationRecord.Kind, noteText: String?, on pdfView: PDFView) {
            guard let annotation = annotationRecord(kind: kind, noteText: noteText, on: pdfView) else {
                viewModel.searchStatusMessage = "Select text before marking the PDF."
                return
            }

            lastAutoAnnotationSignature = selectionSignature(on: pdfView)
            onCreateAnnotation(annotation)
            publishSelection(from: pdfView)
        }

        private func scheduleAutoCreateAnnotationIfNeeded(on pdfView: PDFView) {
            guard let kind = viewModel.activeTextAnnotationMode,
                  kind == .highlight || kind == .underline,
                  let signature = selectionSignature(on: pdfView),
                  signature != lastAutoAnnotationSignature else {
                pendingAutoAnnotationSignature = nil
                return
            }

            pendingAutoAnnotationSignature = signature
            pendingAutoAnnotationGeneration += 1
            let generation = pendingAutoAnnotationGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self, weak pdfView] in
                guard let self,
                      let pdfView,
                      self.pendingAutoAnnotationGeneration == generation,
                      self.pendingAutoAnnotationSignature == signature,
                      self.selectionSignature(on: pdfView) == signature,
                      signature != self.lastAutoAnnotationSignature,
                      let annotation = self.annotationRecord(kind: kind, noteText: nil, on: pdfView) else {
                    return
                }

                self.lastAutoAnnotationSignature = signature
                self.pendingAutoAnnotationSignature = nil
                self.viewModel.searchStatusMessage = "Applied \(kind.rawValue)."
                self.onCreateAnnotation(annotation)
            }
        }

        private func selectionSignature(on pdfView: PDFView) -> String? {
            guard let selection = pdfView.currentSelection,
                  let document = pdfView.document,
                  let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !selectedText.isEmpty else {
                return nil
            }

            let bounds = selection.pages.compactMap { page -> String? in
                let pageIndex = document.index(for: page)
                let rect = selection.bounds(for: page)
                guard pageIndex >= 0, !rect.isNull, !rect.isEmpty else {
                    return nil
                }
                return "\(pageIndex):\(rect.integral.debugDescription)"
            }
            guard !bounds.isEmpty else {
                return nil
            }
            return ([selectedText] + bounds).joined(separator: "|")
        }

        private func annotationRecord(kind: PDFAnnotationRecord.Kind, noteText: String?, on pdfView: PDFView) -> PDFAnnotationRecord? {
            guard let paperID = loadedPaperID, let document = pdfView.document else {
                return nil
            }

            let selectedText = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var bounds: [PDFAnnotationBounds] = []
            if let selection = pdfView.currentSelection, !selectedText.isEmpty {
                let lineSelections = selection.selectionsByLine()
                let selections = lineSelections.isEmpty ? [selection] : lineSelections
                var seenBounds = Set<String>()
                for lineSelection in selections {
                    for page in lineSelection.pages {
                        let pageIndex = document.index(for: page)
                        let rect = lineSelection.bounds(for: page).standardized
                        guard pageIndex >= 0, !rect.isNull, !rect.isEmpty, rect.width > 1, rect.height > 1 else {
                            continue
                        }
                        let bound = normalizedBound(pageIndex: pageIndex, rect: rect)
                        guard !seenBounds.contains(bound.fingerprintComponent) else {
                            continue
                        }
                        seenBounds.insert(bound.fingerprintComponent)
                        bounds.append(bound)
                    }
                }
            }

            if kind != .note, bounds.isEmpty {
                return nil
            }

            if kind == .note, bounds.isEmpty,
               let currentPage = pdfView.currentPage {
                let pageIndex = document.index(for: currentPage)
                let pageBounds = currentPage.bounds(for: .cropBox)
                bounds.append(PDFAnnotationBounds(
                    pageIndex: max(pageIndex, 0),
                    x: 36,
                    y: max(pageBounds.maxY - 72, 36),
                    width: 180,
                    height: 48
                ))
            }

            guard let firstBound = bounds.first else {
                return nil
            }

            return PDFAnnotationRecord(
                paperID: paperID,
                pageIndex: firstBound.pageIndex,
                kind: kind,
                bounds: bounds,
                selectedTextPreview: Self.limitedText(selectedText, maxCharacters: 800),
                noteText: noteText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                colorHex: kind.defaultColorHex,
                opacity: kind.defaultOpacity,
                selectionFingerprint: selectionSignature(on: pdfView)
            )
        }

        private func normalizedBound(pageIndex: Int, rect: CGRect) -> PDFAnnotationBounds {
            PDFAnnotationBounds(
                pageIndex: pageIndex,
                x: normalizedCoordinate(rect.origin.x),
                y: normalizedCoordinate(rect.origin.y),
                width: normalizedCoordinate(rect.width),
                height: normalizedCoordinate(rect.height)
            )
        }

        private func normalizedCoordinate(_ value: CGFloat) -> Double {
            (Double(value) * 10).rounded() / 10
        }

        private func renderAnnotations(_ annotations: [PDFAnnotationRecord], on pdfView: PDFView) {
            let signature = annotations.map { Self.renderSignature(for: $0) }.sorted()
            guard signature != renderedAnnotationSignature else {
                return
            }
            renderedAnnotationSignature = signature

            removeRenderedAnnotations(from: pdfView)
            var renderedFingerprints = Set<String>()
            for annotation in annotations {
                if annotation.kind != .note {
                    guard renderedFingerprints.insert(annotation.duplicateFingerprint).inserted else {
                        continue
                    }
                }
                addRenderedAnnotation(annotation, to: pdfView)
            }
        }

        private static func renderSignature(for annotation: PDFAnnotationRecord) -> String {
            let opacityComponent = annotation.opacity.map { String($0) } ?? ""
            let updatedAtComponent = String(annotation.updatedAt.timeIntervalSince1970)
            let boundsComponent = annotation.bounds.map { $0.fingerprintComponent }.joined(separator: ",")
            let noteComponent = annotation.noteText ?? ""
            let components: [String] = [
                annotation.id,
                annotation.kind.rawValue,
                annotation.colorHex,
                opacityComponent,
                updatedAtComponent,
                boundsComponent,
                noteComponent,
                annotation.duplicateFingerprint
            ]
            return components.joined(separator: "|")
        }

        private func removeRenderedAnnotations(from pdfView: PDFView) {
            guard let document = pdfView.document else {
                return
            }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in page.annotations where annotation.userName?.hasPrefix(overlayContentsPrefix) == true || annotation.contents?.hasPrefix(overlayContentsPrefix) == true {
                    page.removeAnnotation(annotation)
                }
            }
        }

        private func addRenderedAnnotation(_ record: PDFAnnotationRecord, to pdfView: PDFView) {
            guard let document = pdfView.document else {
                return
            }
            for bound in record.bounds {
                guard bound.pageIndex >= 0,
                      bound.pageIndex < document.pageCount,
                      let page = document.page(at: bound.pageIndex) else {
                    continue
                }
                let rect = CGRect(x: bound.x, y: bound.y, width: bound.width, height: bound.height)
                guard !rect.isEmpty, !rect.isNull else {
                    continue
                }
                let pdfAnnotation: PDFAnnotation
                switch record.kind {
                case .highlight:
                    pdfAnnotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                case .underline:
                    pdfAnnotation = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                case .note:
                    let noteRect = CGRect(x: rect.minX, y: rect.maxY - 24, width: 24, height: 24)
                    pdfAnnotation = PDFAnnotation(bounds: noteRect, forType: .text, withProperties: nil)
                }
                pdfAnnotation.color = NSColor(hexString: record.colorHex, alpha: record.opacity ?? record.kind.defaultOpacity) ?? record.kind.defaultColor
                pdfAnnotation.userName = overlayUserName(for: record)
                pdfAnnotation.contents = record.noteText?.nilIfEmpty ?? record.selectedTextPreview.nilIfEmpty ?? "PDF note"
                page.addAnnotation(pdfAnnotation)
            }
        }

        private func overlayUserName(for record: PDFAnnotationRecord) -> String {
            overlayContentsPrefix + record.kind.rawValue + ":" + record.id
        }

        func pdfViewPageChanged(_ sender: Notification) {
            guard let pdfView = sender.object as? PDFView else {
                return
            }

            updatePageState(on: pdfView, notify: true)
        }

        private func updatePageState(on pdfView: PDFView, notify: Bool) {
            guard let currentPage = pdfView.currentPage,
                  let document = pdfView.document else {
                viewModel.currentPage = 1
                viewModel.pageInput = "1"
                viewModel.totalPages = 0
                return
            }

            let pageIndex = document.index(for: currentPage) + 1
            viewModel.currentPage = pageIndex
            viewModel.pageInput = String(pageIndex)
            viewModel.totalPages = document.pageCount

            if notify {
                onReadingStateChanged(pageIndex, pdfView.scaleFactor.isFinite ? pdfView.scaleFactor : nil)
            }
            publishSelection(from: pdfView)
        }

        private static func limitedText(_ text: String, maxCharacters: Int) -> String {
            guard text.count > maxCharacters else {
                return text
            }
            return String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
    }
}

private extension PDFAnnotationRecord.Kind {
    var defaultColorHex: String {
        switch self {
        case .highlight:
            return "#F7D154"
        case .underline:
            return "#4C8DFF"
        case .note:
            return "#FFB36A"
        }
    }

    var defaultColor: NSColor {
        switch self {
        case .highlight:
            return NSColor.systemYellow.withAlphaComponent(0.45)
        case .underline:
            return NSColor.systemBlue.withAlphaComponent(0.85)
        case .note:
            return NSColor.systemOrange.withAlphaComponent(0.9)
        }
    }

    var defaultOpacity: Double {
        switch self {
        case .highlight:
            return 0.35
        case .underline:
            return 0.85
        case .note:
            return 0.9
        }
    }
}

private extension NSColor {
    convenience init?(hexString: String, alpha: Double = 0.85) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: min(max(CGFloat(alpha), 0), 1))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}