import PDFKit
import SwiftUI

struct EmbeddedPDFReaderView: View {
    let pdfURL: URL
    let initialPage: Int?
    let onPageChanged: (Int) -> Void

    @StateObject private var viewModel: PDFReaderViewModel

    init(pdfURL: URL, initialPage: Int?, onPageChanged: @escaping (Int) -> Void) {
        self.pdfURL = pdfURL
        self.initialPage = initialPage
        self.onPageChanged = onPageChanged
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(initialPage: initialPage))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: viewModel.goToPreviousPage) {
                    Image(systemName: "chevron.left")
                }

                Button(action: viewModel.goToNextPage) {
                    Image(systemName: "chevron.right")
                }

                TextField("Page", text: $viewModel.pageInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onSubmit(viewModel.submitPageInput)

                Text("/ \(max(viewModel.totalPages, 1))")
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 22)

                TextField("Search PDF", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(viewModel.submitSearch)
                    .frame(minWidth: 180)

                Button("Find", action: viewModel.submitSearch)

                Divider()
                    .frame(height: 22)

                Button(action: viewModel.zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button(action: viewModel.zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
            }

            PDFKitViewRepresentable(
                pdfURL: pdfURL,
                viewModel: viewModel,
                onPageChanged: onPageChanged
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(pdfURL.path)
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
            case .zoomIn:
                pdfView.zoomIn(nil)
            case .zoomOut:
                pdfView.zoomOut(nil)
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