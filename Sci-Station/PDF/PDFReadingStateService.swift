import Foundation

actor PDFReadingStateService {
    private let paperRepository: PaperRepository

    init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    func save(lastPage: Int, for paper: Paper, in workspace: ResearchWorkspace) async throws -> Paper {
        var updatedPaper = paper
        updatedPaper.lastReadPage = lastPage
        updatedPaper.lastReadAt = Date()
        return try await paperRepository.save(updatedPaper, in: workspace)
    }
}