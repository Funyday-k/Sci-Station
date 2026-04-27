import AppKit
import Foundation

enum PDFOpeningError: LocalizedError {
    case failedToOpen(URL)
    case unsupportedReader(String)

    var errorDescription: String? {
        switch self {
        case let .failedToOpen(url):
            return "Failed to open PDF at \(url.path)."
        case let .unsupportedReader(name):
            return "\(name) integration is reserved but not configured yet."
        }
    }
}

@MainActor
protocol PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws
}

struct SystemPDFOpeningService: PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws {
        let didOpen = NSWorkspace.shared.open(url)
        if !didOpen {
            throw PDFOpeningError.failedToOpen(url)
        }
    }
}

struct SioyekPDFOpeningService: PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws {
        throw PDFOpeningError.unsupportedReader("Sioyek")
    }
}

struct SkimPDFOpeningService: PDFOpeningService {
    func openPDF(at url: URL, page: Int?) async throws {
        throw PDFOpeningError.unsupportedReader("Skim")
    }
}