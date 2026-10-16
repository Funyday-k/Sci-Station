import Foundation

public nonisolated enum PDFDownloadError: LocalizedError, Sendable, Equatable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case unexpectedMIMEType(String)
    case responseTooLarge(Int64)
    case downloadedFileTooLarge(Int64)
    case invalidPDFSignature

    public nonisolated var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "The PDF server did not return a valid HTTP response."
        case let .httpStatus(statusCode):
            return "The PDF server returned HTTP status \(statusCode)."
        case let .unexpectedMIMEType(mimeType):
            return "The downloaded resource is not a PDF (Content-Type: \(mimeType))."
        case let .responseTooLarge(byteCount), let .downloadedFileTooLarge(byteCount):
            return "The PDF exceeds the configured download limit (\(byteCount) bytes)."
        case .invalidPDFSignature:
            return "The downloaded resource does not contain a valid PDF header."
        }
    }
}

public actor DownloadService {
    private let session: URLSession
    private let fileManager: FileManager
    private let maximumDownloadBytes: Int64

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        maximumDownloadBytes: Int64 = 100 * 1_024 * 1_024
    ) {
        self.session = session
        self.fileManager = fileManager
        self.maximumDownloadBytes = maximumDownloadBytes
    }

    public func downloadPDF(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: url)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try Self.validate(response: response, maximumDownloadBytes: maximumDownloadBytes)
        try validateDownloadedFile(at: temporaryURL)

        let targetURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("pdf")

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: targetURL)
        return targetURL
    }

    nonisolated static func validate(
        response: URLResponse,
        maximumDownloadBytes: Int64
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PDFDownloadError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PDFDownloadError.httpStatus(httpResponse.statusCode)
        }
        if httpResponse.expectedContentLength > maximumDownloadBytes {
            throw PDFDownloadError.responseTooLarge(httpResponse.expectedContentLength)
        }

        if let mimeType = httpResponse.mimeType?.lowercased(),
           !mimeType.isEmpty,
           !acceptedMIMETypes.contains(mimeType) {
            throw PDFDownloadError.unexpectedMIMEType(mimeType)
        }
    }

    private func validateDownloadedFile(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= maximumDownloadBytes else {
            throw PDFDownloadError.downloadedFileTooLarge(byteCount)
        }
        guard try Self.hasPDFSignature(at: url) else {
            throw PDFDownloadError.invalidPDFSignature
        }
    }

    public nonisolated static func hasPDFSignature(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 1_024) ?? Data()
        return prefix.range(of: Data("%PDF-".utf8)) != nil
    }

    private nonisolated static let acceptedMIMETypes: Set<String> = [
        "application/pdf",
        "application/x-pdf",
        "application/octet-stream"
    ]
}
