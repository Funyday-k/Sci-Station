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
    }

    @Published var currentPage = 1
    @Published var totalPages = 0
    @Published var pageInput = "1"
    @Published var searchQuery = ""
    @Published var searchStatusMessage: String?
    @Published private(set) var pendingCommand: Command?

    let initialPage: Int?

    init(initialPage: Int?) {
        self.initialPage = initialPage
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
}