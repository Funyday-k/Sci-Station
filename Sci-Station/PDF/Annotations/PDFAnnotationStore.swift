import Foundation

public nonisolated struct PDFAnnotationBounds: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(pageIndex: Int, x: Double, y: Double, width: Double, height: Double) {
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public nonisolated struct PDFAnnotationRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case highlight
        case underline
        case note
    }

    public var id: String
    public var paperID: String
    public var pageIndex: Int
    public var kind: Kind
    public var bounds: [PDFAnnotationBounds]
    public var selectedTextPreview: String
    public var noteText: String?
    public var colorHex: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        paperID: String,
        pageIndex: Int,
        kind: Kind,
        bounds: [PDFAnnotationBounds],
        selectedTextPreview: String,
        noteText: String? = nil,
        colorHex: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.paperID = paperID
        self.pageIndex = pageIndex
        self.kind = kind
        self.bounds = bounds
        self.selectedTextPreview = selectedTextPreview
        self.noteText = noteText
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PDFAnnotationStoreError: LocalizedError, Equatable, Sendable {
    case invalidPaperDirectory(String)
    case annotationOutsidePaperFolder(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidPaperDirectory(path):
            return "Invalid paper directory: \(path)"
        case let .annotationOutsidePaperFolder(path):
            return "PDF annotation sidecar must stay inside the paper folder: \(path)"
        }
    }
}

public actor PDFAnnotationStore {
    public static let sidecarFileName = "pdf_annotations.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadAnnotations(for paper: Paper, in workspace: ResearchWorkspace) throws -> [PDFAnnotationRecord] {
        let sidecarURL = try self.sidecarURL(for: paper, in: workspace)
        guard fileManager.fileExists(atPath: sidecarURL.path) else {
            return []
        }

        let data = try Data(contentsOf: sidecarURL)
        return try decoder.decode(PDFAnnotationSidecar.self, from: data).annotations
            .filter { $0.paperID == paper.id }
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.pageIndex < rhs.pageIndex
            }
    }

    public func saveAnnotations(_ annotations: [PDFAnnotationRecord], for paper: Paper, in workspace: ResearchWorkspace) throws {
        let sidecarURL = try self.sidecarURL(for: paper, in: workspace)
        let records = annotations
            .filter { $0.paperID == paper.id }
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.pageIndex < rhs.pageIndex
            }
        let sidecar = PDFAnnotationSidecar(paperID: paper.id, annotations: records)
        let data = try encoder.encode(sidecar)

        try fileManager.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: sidecarURL, options: [.atomic])
    }

    public func upsertAnnotation(_ annotation: PDFAnnotationRecord, for paper: Paper, in workspace: ResearchWorkspace) throws -> [PDFAnnotationRecord] {
        var annotations = try loadAnnotations(for: paper, in: workspace)
        if let existingIndex = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[existingIndex] = annotation
        } else {
            annotations.append(annotation)
        }
        try saveAnnotations(annotations, for: paper, in: workspace)
        return annotations
    }

    public func deleteAnnotation(id: PDFAnnotationRecord.ID, for paper: Paper, in workspace: ResearchWorkspace) throws -> [PDFAnnotationRecord] {
        let annotations = try loadAnnotations(for: paper, in: workspace)
            .filter { $0.id != id }
        try saveAnnotations(annotations, for: paper, in: workspace)
        return annotations
    }

    public func sidecarRelativePath(for paper: Paper, in workspace: ResearchWorkspace) throws -> String {
        try workspace.relativePath(to: sidecarURL(for: paper, in: workspace))
    }

    private func sidecarURL(for paper: Paper, in workspace: ResearchWorkspace) throws -> URL {
        let paperDirectoryURL = try validatedPaperDirectoryURL(for: paper, in: workspace)
        let sidecarURL = paperDirectoryURL.appendingPathComponent(Self.sidecarFileName, isDirectory: false).standardizedFileURL
        let paperDirectoryPath = paperDirectoryURL.standardizedFileURL.path
        guard sidecarURL.path == paperDirectoryPath + "/" + Self.sidecarFileName else {
            throw PDFAnnotationStoreError.annotationOutsidePaperFolder(sidecarURL.path)
        }
        return sidecarURL
    }

    private func validatedPaperDirectoryURL(for paper: Paper, in workspace: ResearchWorkspace) throws -> URL {
        let relativePath = paper.paperDirectoryRelativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = relativePath.split(separator: "/").map(String.init)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("~"),
              !components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
            throw PDFAnnotationStoreError.invalidPaperDirectory(paper.paperDirectoryRelativePath)
        }

        let rootURL = workspace.rootURL.standardizedFileURL
        let paperDirectoryURL = workspace.directoryURL(for: relativePath).standardizedFileURL
        let rootPath = rootURL.path
        guard paperDirectoryURL.path == rootPath || paperDirectoryURL.path.hasPrefix(rootPath + "/") else {
            throw PDFAnnotationStoreError.invalidPaperDirectory(paper.paperDirectoryRelativePath)
        }
        return paperDirectoryURL
    }
}

private nonisolated struct PDFAnnotationSidecar: Codable, Sendable {
    var schemaVersion: Int
    var paperID: String
    var annotations: [PDFAnnotationRecord]

    init(schemaVersion: Int = 1, paperID: String, annotations: [PDFAnnotationRecord]) {
        self.schemaVersion = schemaVersion
        self.paperID = paperID
        self.annotations = annotations
    }
}