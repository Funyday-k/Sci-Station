import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var isTargetedForDrop = false
    @State private var isShowingCollectionManager = false
    @State private var isShowingTagManager = false
    @State private var isShowingQuickLinkImport = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("All papers live in the global library. Project ownership, core status, project folders, and pins are stored in the relationship layer.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("Search title, author, tag, identifier, abstract", text: $appModel.librarySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240, idealWidth: 360, maxWidth: 420)
                    .focused($isSearchFocused)

                Spacer(minLength: 0)

                Button("Manage Folders") {
                    isShowingCollectionManager = true
                }
                .buttonStyle(.bordered)
                .help("Create, rename, or delete Library folders")

                Button("Manage Tags") {
                    isShowingTagManager = true
                }
                .buttonStyle(.bordered)
                .help("Manage global paper tags")

                Button("Import PDF", action: appModel.importPDF)
                    .buttonStyle(.bordered)
                    .help("Import a local PDF")

                Button(isShowingQuickLinkImport ? "Hide Link Import" : "Add by Link") {
                    if isShowingQuickLinkImport {
                        appModel.resetIdentifierImportForm()
                        isShowingQuickLinkImport = false
                    } else {
                        appModel.prepareIdentifierImport()
                        isShowingQuickLinkImport = true
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .help("Import papers from DOI, arXiv, PDF URL, or web link")
            }

            if isShowingQuickLinkImport {
                QuickLinkImportPanel {
                    appModel.resetIdentifierImportForm()
                    isShowingQuickLinkImport = false
                }
            }

            HStack(spacing: 10) {
                Text("\(appModel.filteredPapers.count) / \(appModel.papers.count) papers in \(workspace.displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LibraryFilterChips()

                if appModel.selectedCollectionPath != nil || appModel.selectedTagName != nil || !appModel.librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Filters", action: appModel.clearLibraryFilters)
                        .buttonStyle(.link)
                }
            }

            if appModel.isImportingPDF {
                ProgressView("Importing PDF…")
            }

            if appModel.filteredPapers.isEmpty {
                LibraryEmptyStateView(hasAnyPaper: !appModel.papers.isEmpty)
            } else {
                LibraryPaperTableView(
                    workspace: workspace,
                    visibleColumnStorage: Binding(
                        get: { appModel.libraryVisibleColumnStorage },
                        set: appModel.updateLibraryVisibleColumns(storageValue:)
                    )
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDeleteCommand {
            appModel.requestDeleteSelectedPaper()
        }
        .alert("Delete Paper?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive, action: appModel.confirmDeletePendingPaper)
            Button("Cancel", role: .cancel, action: appModel.cancelPaperDeletion)
        } message: {
            Text("Delete \(appModel.deletePendingPaperTitle) from the workspace. This removes the paper directory at \(appModel.deletePendingPaperRelativePath).")
        }
        .overlay(alignment: .bottomTrailing) {
            if isTargetedForDrop {
                Text("Drop PDF to import")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(20)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetedForDrop) { providers in
            appModel.handlePDFDrop(providers: providers)
        }
        .onAppear {
            if appModel.librarySearchFocusRequest > 0 {
                isSearchFocused = true
            }
        }
        .onChange(of: appModel.librarySearchFocusRequest) { _, _ in
            isSearchFocused = true
        }
        .sheet(isPresented: $isShowingCollectionManager) {
            CollectionManagerView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $isShowingTagManager) {
            TagManagerView()
                .environmentObject(appModel)
        }
    }

    private var selectionBinding: Binding<Paper.ID?> {
        Binding(
            get: { appModel.selectedPaperID },
            set: { appModel.selectPaper(id: $0) }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { appModel.isShowingPaperDeleteConfirmation },
            set: { isShowing in
                if !isShowing {
                    appModel.cancelPaperDeletion()
                }
            }
        )
    }

    private func paper(for selection: Set<Paper.ID>) -> Paper? {
        if let selectedID = selection.first {
            return appModel.papers.first(where: { $0.id == selectedID })
        }

        return appModel.selectedPaperDraft
    }

    @ViewBuilder
    private func paperContextMenu(for selection: Set<Paper.ID>) -> some View {
        if let paper = paper(for: selection) {
            Button {
                appModel.openPaperReader(paper)
            } label: {
                Label("Read in App", systemImage: "doc.viewfinder")
            }
            .disabled(!appModel.canOpenPDF(for: paper))

            Button {
                appModel.openPaperPDF(paper)
            } label: {
                Label("Open PDF", systemImage: "arrow.up.right.square")
            }
            .disabled(!appModel.canOpenPDF(for: paper))

            Button {
                appModel.exportBibTeX(for: paper)
            } label: {
                Label("Export BibTeX", systemImage: "doc.on.doc")
            }

            Divider()

            PaperClassificationMenuItems(paper: paper)

            Divider()

            Button(role: .destructive) {
                appModel.requestDeletePaper(paper)
            } label: {
                Label("Delete Paper", systemImage: "trash")
            }
        }
    }
}

private struct LibraryFilterChips: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    private var chips: [String] {
        var values: [String] = []
        if let selectedLibraryProjectID = appModel.selectedLibraryProjectID {
            values.append("Project: \(appModel.projectName(for: selectedLibraryProjectID))")
        }
        if let selectedCollectionPath = appModel.selectedCollectionPath {
            values.append("Folder: \(selectedCollectionPath)")
        }
        if let selectedTagName = appModel.selectedTagName {
            values.append("Tag: \(selectedTagName)")
        }
        let query = appModel.librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            values.append("Search: \(query)")
        }
        return values.isEmpty ? ["All Papers"] : values
    }
}

private enum LibraryColumn: String, CaseIterable, Identifiable {
    case title
    case authors
    case year
    case projects
    case coreProjects
    case collection
    case publication
    case itemType
    case doi
    case arxiv
    case wiki
    case tags
    case status
    case priority
    case rating
    case updated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title:
            return "Title"
        case .authors:
            return "Authors"
        case .year:
            return "Year"
        case .projects:
            return "Projects"
        case .coreProjects:
            return "Core"
        case .collection:
            return "Folder"
        case .publication:
            return "Publication"
        case .itemType:
            return "Type"
        case .doi:
            return "DOI"
        case .arxiv:
            return "arXiv"
        case .wiki:
            return "Wiki"
        case .tags:
            return "Tags"
        case .status:
            return "Status"
        case .priority:
            return "Priority"
        case .rating:
            return "Rating"
        case .updated:
            return "Updated"
        }
    }

    static let defaultColumns: [LibraryColumn] = [.title, .authors, .year, .tags, .projects, .collection]
    static let defaultStorageValue = defaultColumns.map(\.rawValue).joined(separator: ",")

    static func columns(from storage: String) -> [LibraryColumn] {
        let decodedColumns = storage
            .split(separator: ",")
            .compactMap { LibraryColumn(rawValue: String($0)) }

        return decodedColumns.isEmpty ? defaultColumns : decodedColumns
    }
}

private struct LibraryPaperTableView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @Binding var visibleColumnStorage: String

    private var visibleColumns: [LibraryColumn] {
        LibraryColumn.columns(from: visibleColumnStorage)
    }

    private var displayColumns: [LibraryColumn] {
        visibleColumns
    }

    private var rows: [LibraryPaperTableRow] {
        appModel.filteredPapers.map { paper in
            LibraryPaperTableRow(
                paper: paper,
                projectNames: appModel.projectNames(for: paper).joined(separator: ", "),
                coreProjectNames: appModel.coreProjectNames(for: paper).joined(separator: ", "),
                wikiStatus: appModel.paperWikiStatusText(for: paper, in: workspace),
                hasWiki: appModel.paperHasWikiPage(paper, in: workspace)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(sortSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appModel.selectedLibraryPaperCount > 1 {
                    Text("\(appModel.selectedLibraryPaperCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if appModel.librarySortState.field != nil {
                    Button("Clear Sort", action: appModel.clearLibrarySort)
                        .buttonStyle(.link)
                }

                columnMenu
            }
            .padding(.horizontal, 2)

            sortableColumnHeader

            Table(
                of: LibraryPaperTableRow.self,
                selection: selectionBinding
            ) {
                TableColumnForEach(visibleColumns) { column in
                    TableColumn(column.label) { (row: LibraryPaperTableRow) in
                        valueView(column: column, row: row)
                    }
                }
            } rows: {
                ForEach(rows) { row in
                    TableRow(row)
                        .contextMenu {
                            paperContextMenu(for: row)
                        }
                }
            }
            .alternatingRowBackgrounds()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onKeyPress(.space) {
            appModel.previewLibrarySelection()
            return .handled
        }
    }

    private var selectionBinding: Binding<Set<Paper.ID>> {
        Binding(
            get: { appModel.selectedLibraryPaperIDs },
            set: appModel.updateLibrarySelection
        )
    }

    private var sortSummary: String {
        guard let field = appModel.librarySortState.field else {
            return "Original order"
        }

        return "Sorted by \(field.label) \(appModel.librarySortState.isAscending ? "ascending" : "descending")"
    }

    private var columnMenu: some View {
        Menu {
            Section("Sort") {
                ForEach(LibrarySortField.allCases, id: \.self) { field in
                    Button(sortMenuTitle(for: field)) {
                        toggleSort(field)
                    }
                }

                Button("Original Order", action: appModel.clearLibrarySort)
                    .disabled(appModel.librarySortState.field == nil)
            }

            Divider()

            Section("Columns") {
                ForEach(LibraryColumn.allCases) { column in
                    Toggle(isOn: binding(for: column)) {
                        Text(column.label)
                    }
                }
            }

            Divider()

            Section("Column Order") {
                ForEach(visibleColumns) { column in
                    Menu(column.label) {
                        Button("Move Earlier") {
                            moveColumn(column, offset: -1)
                        }
                        .disabled(isFirstVisibleColumn(column))

                        Button("Move Later") {
                            moveColumn(column, offset: 1)
                        }
                        .disabled(isLastVisibleColumn(column))
                    }
                }
            }

            Divider()

            Button("Reset Columns") {
                visibleColumnStorage = LibraryColumn.defaultStorageValue
            }
        } label: {
            Label("Columns", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .help("Choose visible columns and sorting")
    }

    private var sortableColumnHeader: some View {
        HStack(spacing: 12) {
            ForEach(displayColumns) { column in
                columnHeader(column)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func columnHeader(_ column: LibraryColumn) -> some View {
        Group {
            if let field = sortField(for: column) {
                Button {
                    toggleSort(field)
                } label: {
                    HStack(spacing: 4) {
                        Text(column.label)
                            .lineLimit(1)
                        if appModel.librarySortState.field == field {
                            Image(systemName: appModel.librarySortState.isAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Sort by \(field.label)")
            } else {
                Text(column.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sortMenuTitle(for field: LibrarySortField) -> String {
        guard appModel.librarySortState.field == field else {
            return field.label
        }

        return "\(field.label) \(appModel.librarySortState.isAscending ? "Ascending" : "Descending")"
    }

    private func sortField(for column: LibraryColumn) -> LibrarySortField? {
        LibrarySortField(rawValue: column.rawValue)
    }

    private func toggleSort(_ field: LibrarySortField) {
        if appModel.librarySortState.field == field {
            appModel.updateLibrarySort(field: field, isAscending: !appModel.librarySortState.isAscending)
        } else {
            appModel.updateLibrarySort(field: field, isAscending: true)
        }
    }

    private func valueView(column: LibraryColumn, row: LibraryPaperTableRow) -> some View {
        LibraryColumnValueView(column: column, row: row)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                appModel.openPaperReader(row.paper)
            }
    }

    private func binding(for column: LibraryColumn) -> Binding<Bool> {
        Binding(
            get: { visibleColumns.contains(column) },
            set: { isVisible in
                var nextColumns = visibleColumns
                if isVisible {
                    if !nextColumns.contains(column) {
                        nextColumns.append(column)
                    }
                } else if nextColumns.count > 1 {
                    nextColumns.removeAll { $0 == column }
                }

                visibleColumnStorage = nextColumns.map(\.rawValue).joined(separator: ",")
            }
        )
    }

    private func moveColumn(_ column: LibraryColumn, offset: Int) {
        var nextColumns = visibleColumns
        guard let currentIndex = nextColumns.firstIndex(of: column) else {
            return
        }

        let nextIndex = currentIndex + offset
        guard nextColumns.indices.contains(nextIndex) else {
            return
        }

        nextColumns.swapAt(currentIndex, nextIndex)
        visibleColumnStorage = nextColumns.map(\.rawValue).joined(separator: ",")
    }

    private func isFirstVisibleColumn(_ column: LibraryColumn) -> Bool {
        visibleColumns.first == column
    }

    private func isLastVisibleColumn(_ column: LibraryColumn) -> Bool {
        visibleColumns.last == column
    }

    @ViewBuilder
    private func paperContextMenu(for row: LibraryPaperTableRow) -> some View {
        let selectedIDs = appModel.selectedLibraryPaperIDs
        if selectedIDs.contains(row.id), selectedIDs.count > 1 {
            Button {
                appModel.previewLibrarySelection()
            } label: {
                Label("Preview PDF", systemImage: "eye")
            }
            .disabled(!appModel.canPreviewLibrarySelection)

            Divider()

            batchEditMenu

            Divider()

            Button {
                appModel.exportBibTeXForLibrarySelection()
            } label: {
                Label("Export BibTeX for Selection", systemImage: "doc.on.doc")
            }

            Button {
                appModel.copyBibTeXForLibrarySelection()
            } label: {
                Label("Copy BibTeX for Selection", systemImage: "doc.on.clipboard")
            }

            Button {
                appModel.copySelectedPaperCitation()
            } label: {
                Label("Copy Citation for Selection", systemImage: "quote.bubble")
            }

            Button {
                appModel.clearLibrarySelection()
            } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
        } else {
            singlePaperContextMenu(for: row.paper)
        }
    }

    private var batchEditMenu: some View {
        Group {
            Menu("Set Status") {
                ForEach(ReadingStatus.allCases, id: \.self) { status in
                    Button(status.label) {
                        appModel.setStatusForLibrarySelection(status)
                    }
                }
            }

            Menu("Set Priority") {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button(priority.label) {
                        appModel.setPriorityForLibrarySelection(priority)
                    }
                }
            }

            Menu("Set Rating") {
                Button("Clear Rating") {
                    appModel.setRatingForLibrarySelection(nil)
                }
                Divider()
                ForEach(1...5, id: \.self) { rating in
                    Button("\(rating)") {
                        appModel.setRatingForLibrarySelection(rating)
                    }
                }
            }

            Menu("Move to Folder") {
                Button {
                    appModel.moveLibrarySelection(to: "Uncategorized")
                } label: {
                    Label("Uncategorized", systemImage: "folder")
                }

                if !appModel.collections.isEmpty {
                    Divider()
                }

                ForEach(appModel.collections) { collection in
                    Button {
                        appModel.moveLibrarySelection(to: collection.relativePath)
                    } label: {
                        Label(collection.relativePath, systemImage: "folder")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func singlePaperContextMenu(for paper: Paper) -> some View {
        Button {
            appModel.previewPaper(paper)
        } label: {
            Label("Preview PDF", systemImage: "eye")
        }
        .disabled(!appModel.canOpenPDF(for: paper))

        Button {
            appModel.openPaperReader(paper)
        } label: {
            Label("Read in App", systemImage: "doc.viewfinder")
        }
        .disabled(!appModel.canOpenPDF(for: paper))

        Button {
            appModel.openPaperPDF(paper)
        } label: {
            Label("Open PDF", systemImage: "arrow.up.right.square")
        }
        .disabled(!appModel.canOpenPDF(for: paper))

        Button {
            appModel.copyCitation(for: paper)
        } label: {
            Label("Copy Citation", systemImage: "quote.bubble")
        }

        Button {
            appModel.copyBibTeX(for: paper)
        } label: {
            Label("Copy BibTeX", systemImage: "doc.on.clipboard")
        }

        Button {
            appModel.exportBibTeX(for: paper)
        } label: {
            Label("Export BibTeX", systemImage: "doc.on.doc")
        }

        Divider()

        PaperClassificationMenuItems(paper: paper)

        Divider()

        Button(role: .destructive) {
            appModel.requestDeletePaper(paper)
        } label: {
            Label("Delete Paper", systemImage: "trash")
        }
    }
}

private struct LibraryPaperTableRow: Identifiable, Hashable {
    let paper: Paper
    let projectNames: String
    let coreProjectNames: String
    let wikiStatus: String
    let hasWiki: Bool

    var id: Paper.ID { paper.id }
    var titleSortKey: String { paper.displayTitle }
    var authorsSortKey: String { paper.authorsDisplay }
    var yearSortKey: Int { paper.year ?? Int.max }
    var updatedSortKey: Date { paper.updatedAt }
    var ratingSortKey: Int { paper.rating ?? Int.max }
    var prioritySortKey: Int { Self.prioritySortValue(paper.priority) }
    var statusSortKey: Int { Self.statusSortValue(paper.status) }

    static func comparators(for state: LibrarySortState) -> [KeyPathComparator<LibraryPaperTableRow>] {
        guard let field = state.field else {
            return []
        }

        let order: SortOrder = state.isAscending ? .forward : .reverse
        switch field {
        case .title:
            return [KeyPathComparator(\.titleSortKey, order: order)]
        case .authors:
            return [KeyPathComparator(\.authorsSortKey, order: order)]
        case .year:
            return [KeyPathComparator(\.yearSortKey, order: order)]
        case .updated:
            return [KeyPathComparator(\.updatedSortKey, order: order)]
        case .rating:
            return [KeyPathComparator(\.ratingSortKey, order: order)]
        case .priority:
            return [KeyPathComparator(\.prioritySortKey, order: order)]
        case .status:
            return [KeyPathComparator(\.statusSortKey, order: order)]
        }
    }

    static func sortField(for comparator: KeyPathComparator<LibraryPaperTableRow>) -> LibrarySortField? {
        for (field, first, second) in sortProbes where comparator.compare(first, second) != .orderedSame {
            return field
        }

        return nil
    }

    private static var sortProbes: [(LibrarySortField, LibraryPaperTableRow, LibraryPaperTableRow)] {
        [
            (.title, probe(id: "title-a", title: "A"), probe(id: "title-b", title: "B")),
            (.authors, probe(id: "authors-a", authors: ["A"]), probe(id: "authors-b", authors: ["B"])),
            (.year, probe(id: "year-a", year: 2001), probe(id: "year-b", year: 2002)),
            (.updated, probe(id: "updated-a", updatedAt: Date(timeIntervalSince1970: 1)), probe(id: "updated-b", updatedAt: Date(timeIntervalSince1970: 2))),
            (.rating, probe(id: "rating-a", rating: 1), probe(id: "rating-b", rating: 2)),
            (.priority, probe(id: "priority-a", priority: .urgent), probe(id: "priority-b", priority: .low)),
            (.status, probe(id: "status-a", status: .unread), probe(id: "status-b", status: .used))
        ]
    }

    private static func probe(
        id: String,
        title: String = "Probe",
        authors: [String] = ["Probe Author"],
        year: Int? = 2024,
        updatedAt: Date = Date(timeIntervalSince1970: 1),
        rating: Int? = 3,
        priority: Priority = .medium,
        status: ReadingStatus = .unread
    ) -> LibraryPaperTableRow {
        LibraryPaperTableRow(
            paper: Paper(
                id: id,
                citekey: id,
                title: title,
                authors: authors,
                year: year,
                venue: nil,
                doi: nil,
                arxiv: nil,
                url: nil,
                pdfRelativePath: nil,
                tags: [],
                status: status,
                priority: priority,
                rating: rating,
                useFor: [],
                createdAt: updatedAt,
                updatedAt: updatedAt,
                paperDirectoryRelativePath: "library/papers/\(id)",
                notesSummaryRelativePath: nil,
                annotationsRelativePath: nil
            ),
            projectNames: "",
            coreProjectNames: "",
            wikiStatus: "Missing",
            hasWiki: false
        )
    }

    private static func prioritySortValue(_ priority: Priority) -> Int {
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

    private static func statusSortValue(_ status: ReadingStatus) -> Int {
        ReadingStatus.allCases.firstIndex(of: status) ?? ReadingStatus.allCases.count
    }
}

private struct PaperClassificationMenuItems: View {
    @EnvironmentObject private var appModel: AppViewModel

    let paper: Paper

    var body: some View {
        Menu("Project") {
            ForEach(appModel.activeResearchProjects) { project in
                Button {
                    appModel.togglePaperProject(paper, projectID: project.id)
                } label: {
                    Label(project.name, systemImage: appModel.projectPaperLink(for: paper, projectID: project.id) == nil ? "circle" : "checkmark.circle.fill")
                }
            }
        }

        Menu("Add to Folder") {
            Button {
                appModel.movePaper(paper, to: "Uncategorized")
            } label: {
                Label("Uncategorized", systemImage: paper.collectionPath == "Uncategorized" ? "checkmark.circle.fill" : "folder")
            }

            if !appModel.collections.isEmpty {
                Divider()
            }

            ForEach(appModel.collections) { collection in
                Button {
                    appModel.movePaper(paper, to: collection.relativePath)
                } label: {
                    Label(collection.relativePath, systemImage: paper.collectionPath == collection.relativePath ? "checkmark.circle.fill" : "folder")
                }
            }
        }

        Menu("Add to Core Paper") {
            let projectOptions = appModel.activeResearchProjects.filter { appModel.projectPaperLink(for: paper, projectID: $0.id) != nil }
            if projectOptions.isEmpty {
                Text("Add this paper to a project first")
            } else {
                ForEach(projectOptions) { project in
                    Button {
                        appModel.togglePaperCoreProject(paper, projectID: project.id)
                    } label: {
                        Label(project.name, systemImage: appModel.projectPaperLink(for: paper, projectID: project.id)?.isCore == true ? "star.fill" : "star")
                    }
                }
            }
        }
        .disabled(appModel.activeResearchProjects.allSatisfy { appModel.projectPaperLink(for: paper, projectID: $0.id) == nil })

        Menu("Pin in Project") {
            let projectOptions = appModel.activeResearchProjects.filter { appModel.projectPaperLink(for: paper, projectID: $0.id) != nil }
            if projectOptions.isEmpty {
                Text("Add this paper to a project first")
            } else {
                ForEach(projectOptions) { project in
                    let isPinned = appModel.projectPaperLink(for: paper, projectID: project.id)?.isPinned == true
                    Button {
                        appModel.setPaperProjectPinned(paper, projectID: project.id, isPinned: !isPinned)
                    } label: {
                        Label(project.name, systemImage: isPinned ? "pin.fill" : "pin")
                    }
                }
            }
        }
        .disabled(appModel.activeResearchProjects.allSatisfy { appModel.projectPaperLink(for: paper, projectID: $0.id) == nil })
    }
}

private struct PaperProjectRelationshipEditor: View {
    @EnvironmentObject private var appModel: AppViewModel

    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if projects.isEmpty {
                Text("No projects yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    PaperProjectRelationshipRow(paper: paper, project: project)
                    if project.id != projects.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var projects: [ResearchProject] {
        appModel.activeResearchProjects.sorted { first, second in
            let firstLinked = appModel.projectPaperLink(for: paper, projectID: first.id) != nil
            let secondLinked = appModel.projectPaperLink(for: paper, projectID: second.id) != nil
            if firstLinked != secondLinked {
                return firstLinked
            }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
}

private struct PaperProjectRelationshipRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let paper: Paper
    let project: ResearchProject

    @State private var useForText = ""
    @State private var folderPathText = ""

    private var link: ProjectPaperLink? {
        appModel.projectPaperLink(for: paper, projectID: project.id)
    }

    private var isLinked: Bool {
        link != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle(isOn: membershipBinding) {
                    Label(project.name, systemImage: project.iconName.isEmpty ? "folder" : project.iconName)
                        .fontWeight(.semibold)
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 0)

                Button {
                    appModel.setPaperProjectCore(paper, projectID: project.id, isCore: link?.isCore != true)
                } label: {
                    Image(systemName: link?.isCore == true ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .help("Core paper")
                .disabled(!isLinked)

                Button {
                    appModel.setPaperProjectPinned(paper, projectID: project.id, isPinned: link?.isPinned != true)
                } label: {
                    Image(systemName: link?.isPinned == true ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help("Pin in project")
                .disabled(!isLinked)
            }

            if isLinked {
                HStack(spacing: 10) {
                    TextField("Project Use", text: $useForText, prompt: Text("Comma-separated"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appModel.updatePaperProjectUseFor(paper, projectID: project.id, text: useForText)
                        }

                    TextField("Project Folder", text: $folderPathText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appModel.updatePaperProjectFolderPath(paper, projectID: project.id, folderPath: folderPathText)
                        }
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: link) { _, _ in
            syncDrafts()
        }
    }

    private var membershipBinding: Binding<Bool> {
        Binding(
            get: { isLinked },
            set: { isMember in
                appModel.setPaperProjectMembership(paper, projectID: project.id, isMember: isMember)
            }
        )
    }

    private func syncDrafts() {
        useForText = link?.useFor.joined(separator: ", ") ?? ""
        folderPathText = link?.folderPath ?? ""
    }
}

struct BibTeXExportView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BibTeX Export")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Copied to Clipboard")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(appModel.bibTeXExportText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(width: 620, height: 320)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Export .bib File", action: appModel.saveExportedBibTeXToFile)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Close", action: appModel.dismissBibTeXExport)
            }
        }
        .padding(22)
    }
}

private struct LibraryColumnValueView: View {
    let column: LibraryColumn
    let row: LibraryPaperTableRow

    private var paper: Paper {
        row.paper
    }

    var body: some View {
        Group {
            switch column {
            case .title:
                Text(paper.displayTitle)
                    .fontWeight(.medium)
                    .lineLimit(2)
            case .authors:
                secondaryText(paper.authorsDisplay, lineLimit: 2)
            case .year:
                Text(paper.yearText)
                    .lineLimit(1)
            case .projects:
                secondaryText(row.projectNames.isEmpty ? "-" : row.projectNames, lineLimit: 2)
            case .coreProjects:
                secondaryText(row.coreProjectNames.isEmpty ? "-" : row.coreProjectNames, lineLimit: 2)
            case .collection:
                secondaryText(paper.folderDisplay, lineLimit: 2)
            case .publication:
                secondaryText(paper.publicationDisplay, lineLimit: 2)
            case .itemType:
                secondaryText(paper.itemType ?? "-", lineLimit: 1)
            case .doi:
                secondaryText(paper.doi ?? "-", lineLimit: 1)
            case .arxiv:
                secondaryText(paper.arxiv ?? "-", lineLimit: 1)
            case .wiki:
                Text(row.wikiStatus)
                    .foregroundStyle(row.hasWiki ? .primary : .secondary)
                    .lineLimit(1)
            case .tags:
                TagChipGroupView(tags: paper.tags)
            case .status:
                Text(paper.status.label)
                    .lineLimit(1)
            case .priority:
                Text(paper.priority.label)
                    .lineLimit(1)
            case .rating:
                Text(paper.ratingText)
                    .lineLimit(1)
            case .updated:
                secondaryText(paper.updatedText, lineLimit: 1)
            }
        }
        .font(.callout)
        .truncationMode(.tail)
    }

    private func secondaryText(_ value: String, lineLimit: Int) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
    }
}

struct PDFReaderWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    var body: some View {
        Group {
            if let workspace,
               let paper = appModel.selectedPaperDraft,
               let pdfURL = appModel.selectedPaperPDFURL,
               FileManager.default.fileExists(atPath: pdfURL.path) {
                EmbeddedPDFReaderView(
                    pdfURL: pdfURL,
                    workspace: workspace,
                    paper: paper,
                    initialPage: paper.lastReadPage,
                    onPageChanged: appModel.saveSelectedPaperReadingState(lastPage:),
                    onBackToLibrary: { appModel.selectSection(.library) },
                    onOpenExternal: appModel.openSelectedPaperPDF
                )
                .padding(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background)
            } else if workspace != nil {
                PDFReaderEmptyStateView(
                    title: "No Readable PDF Selected",
                    message: "Select a paper with a local PDF in Library, then switch back to PDF Reader mode.",
                    actionTitle: "Back to Library"
                ) {
                    appModel.selectSection(.library)
                }
            } else {
                PDFReaderEmptyStateView(
                    title: "No Workspace Open",
                    message: "Open or create a workspace before entering PDF Reader mode.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }
}

struct PaperInspectorView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @FocusState private var isEditingMetadataField: Bool

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appModel.hasMultipleLibraryPaperSelection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Multiple Papers Selected")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(appModel.selectedLibraryPaperCount) papers are selected. Single-paper metadata editing is paused until the selection is narrowed.")
                            .foregroundStyle(.secondary)

                        GroupBox("Batch Actions") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Batch edits apply to \(appModel.selectedLibraryPaperCount) selected papers and keep the selection active.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Menu("Set Status") {
                                    ForEach(ReadingStatus.allCases, id: \.self) { status in
                                        Button(status.label) {
                                            appModel.setStatusForLibrarySelection(status)
                                        }
                                    }
                                }

                                Menu("Set Priority") {
                                    ForEach(Priority.allCases, id: \.self) { priority in
                                        Button(priority.label) {
                                            appModel.setPriorityForLibrarySelection(priority)
                                        }
                                    }
                                }

                                Menu("Set Rating") {
                                    Button("Clear Rating") {
                                        appModel.setRatingForLibrarySelection(nil)
                                    }
                                    Divider()
                                    ForEach(1...5, id: \.self) { rating in
                                        Button("\(rating)") {
                                            appModel.setRatingForLibrarySelection(rating)
                                        }
                                    }
                                }

                                Menu("Move Folder") {
                                    Button {
                                        appModel.moveLibrarySelection(to: "Uncategorized")
                                    } label: {
                                        Label("Uncategorized", systemImage: "folder")
                                    }

                                    if !appModel.collections.isEmpty {
                                        Divider()
                                    }

                                    ForEach(appModel.collections) { collection in
                                        Button {
                                            appModel.moveLibrarySelection(to: collection.relativePath)
                                        } label: {
                                            Label(collection.relativePath, systemImage: "folder")
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    TextField("Tags to add/remove", text: $appModel.libraryBatchTagText)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Add Tags") {
                                        appModel.addTagsToLibrarySelection()
                                    }
                                    Button("Remove Tags") {
                                        appModel.removeTagsFromLibrarySelection()
                                    }
                                }

                                if let message = appModel.libraryBatchStatusMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Button("Preview First PDF", action: appModel.previewLibrarySelection)
                                    .disabled(!appModel.canPreviewLibrarySelection)
                                Button("Copy Citation for Selection", action: appModel.copySelectedPaperCitation)
                                Button("Copy BibTeX for Selection", action: appModel.copyBibTeXForLibrarySelection)
                                Button("Export BibTeX for Selection", action: appModel.exportBibTeXForLibrarySelection)
                                    .buttonStyle(.borderedProminent)
                                Button("Clear Selection", action: appModel.clearLibrarySelection)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }

                        GroupBox("Selected Papers") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(appModel.selectedLibraryPapers.prefix(8)) { paper in
                                    Text(paper.displayTitle)
                                        .lineLimit(2)
                                }

                                if appModel.selectedLibraryPaperCount > 8 {
                                    Text("+ \(appModel.selectedLibraryPaperCount - 8) more")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                } else if let paper = appModel.selectedPaperDraft {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Metadata")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(paper.displayTitle)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Core") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataField("Citekey", text: citekeyBinding)
                            metadataField("Title", text: titleBinding)
                            metadataField("Title Translation", text: optionalBinding(\.titleTranslation))
                            metadataField("Short Title", text: optionalBinding(\.shortTitle))
                            metadataField("Authors", text: authorsBinding, prompt: Text("Comma-separated authors"))
                            metadataField("Year", text: yearBinding)
                            metadataField("Venue", text: venueBinding)
                            TagCompletionField(
                                title: "Tags",
                                text: tagsBinding,
                                prompt: Text("Comma-separated tags"),
                                onSubmit: saveMetadataAndClearFocus
                            )
                            metadataField("Use For", text: useForBinding, prompt: Text("Comma-separated usage hints"))
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
                    }

                    GroupBox("Bibliography") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataField("Item Type", text: optionalBinding(\.itemType))
                            metadataField("Publication Title", text: optionalBinding(\.publicationTitle))
                            metadataField("Publisher", text: optionalBinding(\.publisher))
                            metadataField("Publication Place", text: optionalBinding(\.publicationPlace))
                            metadataField("Published Date", text: optionalBinding(\.publishedDate))
                            metadataField("Volume", text: optionalBinding(\.volume))
                            metadataField("Issue", text: optionalBinding(\.issue))
                            metadataField("Pages", text: optionalBinding(\.pages))
                            metadataField("Series", text: optionalBinding(\.series))
                            metadataField("Series Title", text: optionalBinding(\.seriesTitle))
                            metadataField("Journal Abbreviation", text: optionalBinding(\.journalAbbreviation))
                            metadataField("ISSN", text: optionalBinding(\.issn))
                            metadataField("ISBN", text: optionalBinding(\.isbn))
                            metadataField("Language", text: optionalBinding(\.language))
                            metadataField("Library Catalog", text: optionalBinding(\.libraryCatalog))
                            metadataField("Call Number", text: optionalBinding(\.callNumber))
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
                    }

                    GroupBox("Identifiers") {
                        VStack(alignment: .leading, spacing: 12) {
                            metadataField("DOI", text: optionalBinding(\.doi))
                            metadataField("arXiv", text: optionalBinding(\.arxiv))
                            metadataField("INSPIRE", text: optionalBinding(\.inspireID))
                            metadataField("PMID", text: optionalBinding(\.pmid))
                            metadataField("PMCID", text: optionalBinding(\.pmcid))
                            metadataField("URL", text: optionalBinding(\.url))
                            metadataField("PDF URL", text: optionalBinding(\.pdfURL))
                            metadataField("Archive", text: optionalBinding(\.archive))
                            metadataField("Archive Location", text: optionalBinding(\.archiveLocation))
                            metadataField("Accessed At", text: optionalBinding(\.accessedAt))
                            metadataField("Categories", text: categoriesBinding, prompt: Text("Comma-separated categories"))
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
                    }

                    GroupBox("Abstract") {
                        TextEditor(text: optionalBinding(\.abstract))
                            .font(.body)
                            .focused($isEditingMetadataField)
                            .frame(minHeight: 90)
                            .padding(4)
                    }

                    GroupBox("Status") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Reading Status", selection: statusBinding) {
                                ForEach(ReadingStatus.allCases, id: \.self) { status in
                                    Text(status.label).tag(status)
                                }
                            }

                            Picker("Priority", selection: priorityBinding) {
                                ForEach(Priority.allCases, id: \.self) { priority in
                                    Text(priority.label).tag(priority)
                                }
                            }

                            metadataField("Rating", text: ratingBinding, prompt: Text("1-5 or empty"))
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Files") {
                        VStack(alignment: .leading, spacing: 10) {
                            WorkspacePathRow(label: "Folder", value: paper.folderDisplay)
                            WorkspacePathRow(label: "Projects", value: appModel.projectNames(for: paper).isEmpty ? "-" : appModel.projectNames(for: paper).joined(separator: ", "))
                            WorkspacePathRow(label: "Core In", value: appModel.coreProjectNames(for: paper).isEmpty ? "-" : appModel.coreProjectNames(for: paper).joined(separator: ", "))
                            WorkspacePathRow(label: "Paper Folder", value: paper.paperDirectoryRelativePath)
                            WorkspacePathRow(label: "PDF", value: paper.pdfRelativePath ?? "-")
                            WorkspacePathRow(label: "Last Page", value: paper.lastReadPage.map(String.init) ?? "-")
                            WorkspacePathRow(label: "Raw Markdown", value: "paper.md")
                            WorkspacePathRow(label: "Summary Target", value: paper.notesSummaryRelativePath ?? "-")
                            WorkspacePathRow(label: "Workspace Root", value: workspace.rootURL.path)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Organization") {
                        VStack(alignment: .leading, spacing: 12) {
                            PaperProjectRelationshipEditor(paper: paper)

                            Divider()

                            Menu("Move Library Folder") {
                                Button {
                                    appModel.movePaper(paper, to: "Uncategorized")
                                } label: {
                                    Label("Uncategorized", systemImage: paper.collectionPath == "Uncategorized" ? "checkmark.circle.fill" : "folder")
                                }

                                if !appModel.collections.isEmpty {
                                    Divider()
                                }

                                ForEach(appModel.collections) { collection in
                                    Button {
                                        appModel.movePaper(paper, to: collection.relativePath)
                                    } label: {
                                        Label(collection.relativePath, systemImage: paper.collectionPath == collection.relativePath ? "checkmark.circle.fill" : "folder")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack {
                        Button("Revert Edits", action: appModel.discardSelectedPaperChanges)
                            .disabled(!appModel.selectedPaperHasUnsavedChanges)
                            .help("Restore the selected paper metadata to the last saved meta.yaml state.")
                        Button("Summarize with LLM", action: appModel.generateSelectedPaperSummary)
                            .disabled(appModel.llmConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(appModel.selectedPaperWikiButtonTitle, action: appModel.openOrGenerateSelectedPaperWikiPage)
                        Button("Save Metadata", action: appModel.saveSelectedPaperChanges)
                            .buttonStyle(.borderedProminent)
                    }

                    if appModel.isSavingSelectedPaper {
                        ProgressView("Saving meta.yaml…")
                    }

                    if appModel.isGeneratingWikiPage {
                        ProgressView("Preparing wiki page…")
                    }

                    if appModel.isGeneratingSummary {
                        ProgressView("Calling LLM…")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadata")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Select a paper to edit tags, reading status, priority, rating, and core metadata.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditingMetadataField = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        )
    }

    @ViewBuilder
    private func metadataField(_ title: String, text: Binding<String>, prompt: Text? = nil) -> some View {
        if let prompt {
            TextField(title, text: text, prompt: prompt)
                .focused($isEditingMetadataField)
                .onSubmit(saveMetadataAndClearFocus)
        } else {
            TextField(title, text: text)
                .focused($isEditingMetadataField)
                .onSubmit(saveMetadataAndClearFocus)
        }
    }

    private func saveMetadataAndClearFocus() {
        appModel.saveSelectedPaperChanges()
        isEditingMetadataField = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var citekeyBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.citekey ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedValue.isEmpty {
                        paper.citekey = trimmedValue
                    }
                }
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.title ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { $0.title = newValue }
            }
        )
    }

    private var authorsBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.authors.joined(separator: ", ") ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.authors = commaSeparatedValues(from: newValue)
                }
            }
        )
    }

    private var yearBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.year.map(String.init) ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.year = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        )
    }

    private var venueBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.venue ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.venue = trimmedOrNil(newValue)
                }
            }
        )
    }

    private var categoriesBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.categories.joined(separator: ", ") ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.categories = commaSeparatedValues(from: newValue)
                }
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<Paper, String?>) -> Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper[keyPath: keyPath] = trimmedOrNil(newValue)
                }
            }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.tags.joined(separator: ", ") ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.tags = commaSeparatedValues(from: newValue)
                }
            }
        )
    }

    private var useForBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.useFor.joined(separator: ", ") ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.useFor = commaSeparatedValues(from: newValue)
                }
            }
        )
    }

    private var statusBinding: Binding<ReadingStatus> {
        Binding(
            get: { appModel.selectedPaperDraft?.status ?? .unread },
            set: { newValue in
                appModel.updateSelectedPaper { $0.status = newValue }
            }
        )
    }

    private var priorityBinding: Binding<Priority> {
        Binding(
            get: { appModel.selectedPaperDraft?.priority ?? .medium },
            set: { newValue in
                appModel.updateSelectedPaper { $0.priority = newValue }
            }
        )
    }

    private var ratingBinding: Binding<String> {
        Binding(
            get: { appModel.selectedPaperDraft?.rating.map(String.init) ?? "" },
            set: { newValue in
                appModel.updateSelectedPaper { paper in
                    paper.rating = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        )
    }

    private func commaSeparatedValues(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private struct QuickLinkImportPanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Link Import")
                        .font(.headline)
                    Text("Paste one or many DOI, arXiv, PDF URLs, or normal paper links, then preview the first item or import all parsed entries.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Full Import") {
                    appModel.beginIdentifierImport(with: appModel.identifierImportInput)
                }
                .buttonStyle(.bordered)

                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $appModel.identifierImportInput)
                        .font(.callout.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 76, maxHeight: 108)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    if appModel.identifierImportInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Paste one or many links, DOIs, or arXiv IDs")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                    }
                }

                Text(batchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    openIdentifierInputURL()
                } label: {
                    Label("Open Link", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .help("Open first link in browser")
                .disabled(identifierInputURL == nil)

                Spacer()
            }

            HStack(spacing: 12) {
                TextField("Folder", text: $appModel.identifierImportCollectionPath)
                    .textFieldStyle(.roundedBorder)
                TagCompletionField(title: "Tags", text: $appModel.identifierImportTagsText, prompt: Text("Comma-separated"))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button(appModel.identifierImportInputs.count > 1 ? "Preview First" : "Preview", action: appModel.previewIdentifierImport)
                    .buttonStyle(.bordered)
                    .disabled(appModel.identifierImportInputs.isEmpty)

                Button(importButtonTitle) {
                    appModel.performIdentifierImport {
                        onClose()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.identifierImportInputs.isEmpty)
            }

            if appModel.isResolvingIdentifierImport || appModel.isPerformingIdentifierImport {
                ProgressView(appModel.isPerformingIdentifierImport ? "Importing…" : "Resolving metadata…")
            }

            if let statusMessage = appModel.identifierImportStatusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let preview = appModel.identifierImportPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.title)
                        .fontWeight(.semibold)
                    Text([preview.doi, preview.arxiv, preview.sourceProvider]
                        .compactMap { $0 }
                        .joined(separator: "  ·  "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var identifierInputURL: URL? {
        guard let trimmedInput = appModel.identifierImportInputs.first else {
            return nil
        }
        if let url = URL(string: trimmedInput),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        if trimmedInput.contains("."),
           let url = URL(string: "https://\(trimmedInput)") {
            return url
        }

        return nil
    }

    private var batchSummary: String {
        let count = appModel.identifierImportInputs.count
        switch count {
        case 0:
            return "No import targets parsed yet."
        case 1:
            return "1 import target parsed."
        default:
            return "\(count) import targets parsed."
        }
    }

    private var importButtonTitle: String {
        let count = appModel.identifierImportInputs.count
        return count > 1 ? "Import All (\(count))" : "Import"
    }

    private func openIdentifierInputURL() {
        guard let identifierInputURL else {
            return
        }

        NSWorkspace.shared.open(identifierInputURL)
    }
}

private struct LibraryEmptyStateView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let hasAnyPaper: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasAnyPaper ? "No papers match the current search." : "No papers imported yet.")
                .font(.title3)
                .fontWeight(.semibold)
            Text(hasAnyPaper ? "Change the search query or clear filters to see more results." : "Use Import PDF, Add by Identifier, or drag a PDF here to create a normalized paper directory under library/papers.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Import PDF", action: appModel.importPDF)
                    .buttonStyle(.borderedProminent)
                Button("Add by Identifier") {
                    appModel.beginIdentifierImport()
                }
                .buttonStyle(.bordered)
                if hasAnyPaper {
                    Button("Clear Filters", action: appModel.clearLibraryFilters)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct PDFReaderEmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }
}