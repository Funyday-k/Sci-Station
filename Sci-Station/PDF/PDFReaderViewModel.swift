import Combine
import Foundation

@MainActor
final class PDFReaderViewModel: ObservableObject {
    enum Command: Equatable {
        case next(UUID)
        case previous(UUID)
        case zoomIn(UUID)
        case zoomOut(UUID)
        case goToPage(Int, UUID)
        case search(String, UUID)
    }

    @Published var currentPage = 1
    @Published var totalPages = 0
    @Published var pageInput = "1"
    @Published var searchQuery = ""
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

    func zoomIn() {
        pendingCommand = .zoomIn(UUID())
    }

    func zoomOut() {
        pendingCommand = .zoomOut(UUID())
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
}