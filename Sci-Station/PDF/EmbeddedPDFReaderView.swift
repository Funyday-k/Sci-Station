import PDFKit
import SwiftUI

struct EmbeddedPDFReaderView: View {
    let pdfURL: URL
    let paper: Paper
    let initialPage: Int?
    let onPageChanged: (Int) -> Void
    let onBackToLibrary: () -> Void
    let onOpenExternal: () -> Void

    @StateObject private var viewModel: PDFReaderViewModel
    @State private var isShowingSearch = false
    @State private var activeSidebarPanel: PDFReaderSidebarPanel? = .metadata

    init(
        pdfURL: URL,
        paper: Paper,
        initialPage: Int?,
        onPageChanged: @escaping (Int) -> Void,
        onBackToLibrary: @escaping () -> Void,
        onOpenExternal: @escaping () -> Void
    ) {
        self.pdfURL = pdfURL
        self.paper = paper
        self.initialPage = initialPage
        self.onPageChanged = onPageChanged
        self.onBackToLibrary = onBackToLibrary
        self.onOpenExternal = onOpenExternal
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(initialPage: initialPage))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                readerToolbar

                if isShowingSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search PDF", text: $viewModel.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(viewModel.submitSearch)
                        Button("Find", action: viewModel.submitSearch)
                            .buttonStyle(.bordered)
                        Button {
                            isShowingSearch = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help("Close search")
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.06))
                }

                PDFKitViewRepresentable(
                    pdfURL: pdfURL,
                    viewModel: viewModel,
                    onPageChanged: onPageChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            if let activeSidebarPanel {
                PDFReaderMetadataPanel(paper: paper, panel: activeSidebarPanel)
                    .frame(width: 320)
                Divider()
            }

            PDFReaderSideRail(activePanel: $activeSidebarPanel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(pdfURL.path)
    }

    private var readerToolbar: some View {
        HStack(spacing: 10) {
            Button(action: onBackToLibrary) {
                Image(systemName: "chevron.left")
            }
            .help("Back to Library")

            Divider()
                .frame(height: 22)

            Button(action: viewModel.goToPreviousPage) {
                Image(systemName: "chevron.up")
            }
            .help("Previous page")

            Button(action: viewModel.goToNextPage) {
                Image(systemName: "chevron.down")
            }
            .help("Next page")

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

            Button(action: viewModel.goForward) {
                Image(systemName: "arrow.uturn.forward")
            }
            .help("Forward to next PDF location")

            Divider()
                .frame(height: 22)

            Button {
                isShowingSearch.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search PDF")

            Button(action: viewModel.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button(action: viewModel.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")

            Button(action: viewModel.fitToWidth) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit page")

            Spacer(minLength: 8)

            Button(action: onOpenExternal) {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open in default viewer")

            Button {
                activeSidebarPanel = activeSidebarPanel == nil ? .metadata : nil
            } label: {
                Image(systemName: activeSidebarPanel == nil ? "sidebar.right" : "sidebar.trailing")
            }
            .help("Toggle metadata sidebar")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private enum PDFReaderSidebarPanel: CaseIterable, Identifiable {
    case metadata
    case abstract
    case links
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .metadata:
            return "Metadata"
        case .abstract:
            return "Abstract"
        case .links:
            return "Links"
        case .files:
            return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .metadata:
            return "info.circle"
        case .abstract:
            return "doc.text"
        case .links:
            return "link"
        case .files:
            return "folder"
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
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 48)
        .background(Color.secondary.opacity(0.05))
    }
}

private struct PDFReaderMetadataPanel: View {
    let paper: Paper
    let panel: PDFReaderSidebarPanel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(panel.title)
                    .font(.headline)

                switch panel {
                case .metadata:
                    metadataRows
                case .abstract:
                    Text(paper.abstract ?? "No abstract saved.")
                        .font(.callout)
                        .foregroundStyle(paper.abstract == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                case .links:
                    metadataSection(rows: [
                        ("DOI", paper.doi),
                        ("arXiv", paper.arxiv),
                        ("INSPIRE", paper.inspireID),
                        ("URL", paper.url),
                        ("PDF URL", paper.pdfURL)
                    ])
                case .files:
                    metadataSection(rows: [
                        ("Folder", paper.paperDirectoryRelativePath),
                        ("PDF", paper.pdfRelativePath),
                        ("Markdown", "paper.md"),
                        ("Summary", paper.notesSummaryRelativePath),
                        ("Annotations", paper.annotationsRelativePath),
                        ("Last Page", paper.lastReadPage.map(String.init))
                    ])
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
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

private struct PDFKitViewRepresentable: NSViewRepresentable {
    let pdfURL: URL
    @ObservedObject var viewModel: PDFReaderViewModel
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onPageChanged: onPageChanged)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.delegate = context.coordinator
        context.coordinator.configure(pdfView: pdfView, pdfURL: pdfURL)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.configure(pdfView: pdfView, pdfURL: pdfURL)
        context.coordinator.handlePendingCommandIfNeeded(on: pdfView)
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        private let documentService = PDFDocumentService()
        private let viewModel: PDFReaderViewModel
        private let onPageChanged: (Int) -> Void
        private var loadedURL: URL?
        private var handledCommand: PDFReaderViewModel.Command?

        init(viewModel: PDFReaderViewModel, onPageChanged: @escaping (Int) -> Void) {
            self.viewModel = viewModel
            self.onPageChanged = onPageChanged
        }

        func configure(pdfView: PDFView, pdfURL: URL) {
            guard loadedURL != pdfURL else {
                return
            }

            loadedURL = pdfURL
            pdfView.document = try? documentService.loadDocument(from: pdfURL)
            viewModel.totalPages = pdfView.document?.pageCount ?? 0

            if let initialPage = viewModel.initialPage,
               let targetPage = pdfView.document?.page(at: max(initialPage - 1, 0)) {
                pdfView.go(to: targetPage)
                updatePageState(on: pdfView, notify: false)
            } else {
                updatePageState(on: pdfView, notify: false)
            }
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
                pdfView.zoomIn(nil)
            case .zoomOut:
                pdfView.zoomOut(nil)
            case .fit:
                pdfView.autoScales = true
            case let .goToPage(page, _):
                if let targetPage = pdfView.document?.page(at: max(page - 1, 0)) {
                    pdfView.go(to: targetPage)
                }
            case let .search(query, _):
                pdfView.document?.beginFindString(query, withOptions: .caseInsensitive)
            }

            updatePageState(on: pdfView, notify: true)
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
                onPageChanged(pageIndex)
            }
        }
    }
}