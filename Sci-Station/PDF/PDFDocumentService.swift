import Foundation
import PDFKit

enum PDFDocumentServiceError: LocalizedError {
    case failedToLoad(URL)

    var errorDescription: String? {
        switch self {
        case let .failedToLoad(url):
            return "Failed to load PDF document at \(url.path)."
        }
    }
}

struct PDFDocumentService {
    func loadDocument(from url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw PDFDocumentServiceError.failedToLoad(url)
        }

        return document
    }
}