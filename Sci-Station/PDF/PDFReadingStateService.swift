import Foundation

actor PDFReadingStateService {
    private let paperRepository: PaperRepository

    init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    func save(lastPage: Int, scaleFactor: Double?, for paper: Paper, in workspace: ResearchWorkspace) async throws -> Paper {
        var updatedPaper = paper
        updatedPaper.lastReadPage = lastPage
        if let scaleFactor, scaleFactor.isFinite, scaleFactor > 0 {
            updatedPaper.lastReadScale = scaleFactor
        }
        updatedPaper.lastReadAt = Date()
        return try await paperRepository.save(updatedPaper, in: workspace)
    }
}