import Combine
import Foundation

@MainActor
final class PDFReaderViewModel: ObservableObject {
    enum Command: Equatable {
        case next(UUID)
        case previous(UUID)
        case back(UUID)
        case forward(UUID)
        case zoomIn(UUID)
        case zoomOut(UUID)
        case fit(UUID)
        case goToPage(Int, UUID)
        case search(String, UUID)
        case findNext(String, UUID)
        case findPrevious(String, UUID)
        case createAnnotation(PDFAnnotationRecord.Kind, String?, UUID)
    }

    @Published var currentPage = 1
    @Published var totalPages = 0
    @Published var pageInput = "1"
    @Published var searchQuery = ""
    @Published var searchStatusMessage: String?
    @Published var activeTextAnnotationMode: PDFAnnotationRecord.Kind?
    @Published private(set) var selectedTextPreview: String?
    @Published private(set) var selectedTextPageIndex: Int?
    @Published private(set) var pendingCommand: Command?

    let initialPage: Int?
    let initialScaleFactor: Double?

    init(initialPage: Int?, initialScaleFactor: Double?) {
        self.initialPage = initialPage
        self.initialScaleFactor = initialScaleFactor
        if let initialPage {
            currentPage = initialPage
            pageInput = String(initialPage)
        }
    }

    func goToNextPage() {
        pendingCommand = .next(UUID())
    }

    func goToPreviousPage() {
        pendingCommand = .previous(UUID())
    }

    func goBack() {
        pendingCommand = .back(UUID())
    }

    func goForward() {
        pendingCommand = .forward(UUID())
    }

    func zoomIn() {
        pendingCommand = .zoomIn(UUID())
    }

    func zoomOut() {
        pendingCommand = .zoomOut(UUID())
    }

    func fitToWidth() {
        pendingCommand = .fit(UUID())
    }

    func submitPageInput() {
        guard let page = Int(pageInput) else {
            pageInput = String(currentPage)
            return
        }

        goToPage(page)
    }

    func goToPage(_ page: Int) {
        pendingCommand = .goToPage(page, UUID())
    }

    func submitSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        pendingCommand = .search(trimmedQuery, UUID())
    }

    func findNext() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchStatusMessage = "Enter a search term first."
            return
        }

        pendingCommand = .findNext(trimmedQuery, UUID())
    }

    func findPrevious() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchStatusMessage = "Enter a search term first."
            return
        }

        pendingCommand = .findPrevious(trimmedQuery, UUID())
    }

    func toggleHighlightAnnotationMode() {
        toggleTextAnnotationMode(.highlight)
    }

    func toggleUnderlineAnnotationMode() {
        toggleTextAnnotationMode(.underline)
    }

    func createNoteAnnotation(noteText: String?) {
        pendingCommand = .createAnnotation(.note, noteText, UUID())
    }

    func updateSelection(preview: String?, pageIndex: Int?) {
        selectedTextPreview = preview
        selectedTextPageIndex = pageIndex
    }

    var hasTextSelection: Bool {
        selectedTextPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func toggleTextAnnotationMode(_ kind: PDFAnnotationRecord.Kind) {
        if activeTextAnnotationMode == kind {
            activeTextAnnotationMode = nil
            searchStatusMessage = nil
            return
        }

        activeTextAnnotationMode = kind
        if hasTextSelection {
            pendingCommand = .createAnnotation(kind, nil, UUID())
        } else {
            searchStatusMessage = "Select text to apply \(kind.rawValue)."
        }
    }
}