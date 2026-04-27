import Foundation

public actor DownloadService {
    private let session: URLSession
    private let fileManager: FileManager

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    public func downloadPDF(from url: URL) async throws -> URL {
        let (temporaryURL, _) = try await session.download(from: url)
        let targetURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("pdf")

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: targetURL)
        return targetURL
    }
}