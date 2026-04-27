import SwiftUI
import UniformTypeIdentifiers

struct LibraryListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var isTargetedForDrop = false
    @State private var isShowingCollectionManager = false
    @State private var isShowingTagManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Import PDFs into raw/papers, edit meta.yaml fields, and keep the local paper library in sync.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search title, author, tag, or citekey", text: $appModel.librarySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)

                Button("Manage Collections") {
                    isShowingCollectionManager = true
                }
                .buttonStyle(.bordered)

                Button("Manage Tags") {
                    isShowingTagManager = true
                }
                .buttonStyle(.bordered)

                Button("Add by Identifier") {
                    appModel.beginIdentifierImport()
                }
                .buttonStyle(.bordered)

                Button("Import PDF", action: appModel.importPDF)
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                Text("\(appModel.filteredPapers.count) / \(appModel.papers.count) papers in \(workspace.displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(appModel.libraryScopeSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if appModel.selectedCollectionPath != nil || appModel.selectedTagName != nil {
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
                Table(appModel.filteredPapers, selection: selectionBinding) {
                    TableColumn("Title") { paper in
                        Text(paper.displayTitle)
                            .lineLimit(2)
                    }
                    .width(min: 280, ideal: 360)

                    TableColumn("Authors") { paper in
                        Text(paper.authorsDisplay)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 180, ideal: 220)

                    TableColumn("Year") { paper in
                        Text(paper.yearText)
                    }
                    .width(70)

                    TableColumn("Collection") { paper in
                        Text(paper.collectionPath ?? "-")
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Wiki") { paper in
                        Text(appModel.paperWikiStatusText(for: paper, in: workspace))
                            .foregroundStyle(appModel.paperHasWikiPage(paper, in: workspace) ? .primary : .secondary)
                    }
                    .width(90)

                    TableColumn("Tags") { paper in
                        TagChipGroupView(tags: paper.tags)
                    }
                    .width(min: 150, ideal: 220)

                    TableColumn("Status") { paper in
                        Text(paper.status.label)
                    }
                    .width(110)

                    TableColumn("Priority") { paper in
                        Text(paper.priority.label)
                    }
                    .width(90)

                    TableColumn("Rating") { paper in
                        Text(paper.ratingText)
                    }
                    .width(70)

                    TableColumn("Updated") { paper in
                        Text(paper.updatedText)
                    }
                    .width(120)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}

struct PaperInspectorView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let paper = appModel.selectedPaperDraft {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Metadata")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(paper.displayTitle)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Core") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Title", text: titleBinding)
                            TextField("Authors", text: authorsBinding, prompt: Text("Comma-separated authors"))
                            TextField("Year", text: yearBinding)
                            TextField("Venue", text: venueBinding)
                            TextField("Tags", text: tagsBinding, prompt: Text("Comma-separated tags"))
                            TextField("Use For", text: useForBinding, prompt: Text("Comma-separated usage hints"))
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 4)
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

                            TextField("Rating", text: ratingBinding, prompt: Text("1-5 or empty"))
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Files") {
                        VStack(alignment: .leading, spacing: 10) {
                            WorkspacePathRow(label: "Collection", value: paper.collectionPath ?? "Uncategorized")
                            WorkspacePathRow(label: "Paper Folder", value: paper.paperDirectoryRelativePath)
                            WorkspacePathRow(label: "PDF", value: paper.pdfRelativePath ?? "-")
                            WorkspacePathRow(label: "Last Page", value: paper.lastReadPage.map(String.init) ?? "-")
                            WorkspacePathRow(label: "Raw Markdown", value: "paper.md")
                            WorkspacePathRow(label: "Summary Target", value: paper.notesSummaryRelativePath ?? "-")
                            WorkspacePathRow(label: "Workspace Root", value: workspace.rootURL.path)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Embedded PDF Reader") {
                        if let pdfURL = appModel.selectedPaperPDFURL,
                           FileManager.default.fileExists(atPath: pdfURL.path) {
                            EmbeddedPDFReaderView(
                                pdfURL: pdfURL,
                                initialPage: paper.lastReadPage,
                                onPageChanged: appModel.saveSelectedPaperReadingState(lastPage:)
                            )
                            .frame(minHeight: 360)
                        } else {
                            Text("No local PDF available for the selected paper.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GroupBox("Organization") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Move selected paper into a collection folder under raw/papers/.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Menu("Move to Collection") {
                                Button("Uncategorized") {
                                    appModel.moveSelectedPaper(to: "Uncategorized")
                                }

                                ForEach(appModel.collections) { collection in
                                    Button(collection.relativePath) {
                                        appModel.moveSelectedPaper(to: collection.relativePath)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack {
                        Button("Discard", action: appModel.discardSelectedPaperChanges)
                        Button("Open in Default Viewer", action: appModel.openSelectedPaperPDF)
                            .disabled(!appModel.canOpenSelectedPaperPDF)
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

private struct LibraryEmptyStateView: View {
    let hasAnyPaper: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasAnyPaper ? "No papers match the current search." : "No papers imported yet.")
                .font(.title3)
                .fontWeight(.semibold)
            Text(hasAnyPaper ? "Change the search query or clear filters to see more results." : "Use Import PDF or drag a PDF into this view to create raw/papers/{paper-id}, paper.pdf, paper.md, meta.yaml, annotations.md, figures/, and a BibTeX stub.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}